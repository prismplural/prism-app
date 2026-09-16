import 'dart:math' as math;

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/data/repositories/drift_media_attachment_repository.dart';

/// Feature-flag gate for the startup bio-media orphan reconcile. Flip to
/// `false` in a hotfix if the sweep turns out to be too aggressive — keeps
/// the wiring in place without requiring a revert.
const bool kEnableBioMediaReconcile = true;

/// Number of distinct member ids resolved per paged sweep query.
///
/// The sweep is driven by the attachment side (see [_selectBioMediaMemberPage]),
/// so this bounds the number of member ids bound into the follow-up
/// `member_id IN (...)` batch query. Kept well under SQLite's default
/// `SQLITE_MAX_VARIABLE_NUMBER` (999 on older builds) so the batch predicate
/// never overflows a variable slot.
const int kBioMediaReconcileMemberPageSize = 256;

/// Maximum orphan candidates revalidated and tombstoned between cooperative
/// yields.
///
/// Each slice re-reads its owning members' bios before issuing individual
/// repository writes (one data write + one sync emission per tombstone).
/// Yielding every N candidates keeps the startup caller responsive without
/// splitting or reordering the emissions.
const int kBioMediaReconcileMutationBatchSize = 128;

/// Matches a `prism-media://<mediaId>` reference in a member's `bio` markdown.
///
/// The captured group is the *maximal* run of id characters, which is the exact
/// reference semantics this sweep has always used. Do NOT relax this to a bare
/// `bio LIKE '%<media_id>%'` substring test: the id charset is a strict subset
/// of the surrounding markdown, so a substring test would (a) spare an
/// attachment whose id is merely a prefix of a longer `prism-media://` run, and
/// (b) spare an attachment whose id appears in the bio as plain text outside any
/// `prism-media://` URI. Both cases are orphans today and must stay orphans.
final RegExp _prismMediaUriPattern = RegExp(r'prism-media://([a-zA-Z0-9-]+)');

/// Scans `media_attachments` for bio-media rows whose `media_id` is no longer
/// referenced by the owning member's `bio` text, and soft-deletes the orphans.
///
/// This sweep is a safety net for the on-save hook in `_reconcileBioImageOrphans`
/// (add_edit_member_sheet.dart): it catches anything the hook missed — e.g. if
/// the app crashed before the hook ran, or a concurrent remote edit left orphans.
///
/// **Logic**
/// 1. Page over the distinct `member_id` values that own at least one live
///    (`is_deleted = 0`) bio-media row, ascending by `member_id`, resolving each
///    page's `bio` text in the same query (`_selectBioMediaMemberPage`).
/// 2. For each page, fetch every live bio-media attachment row for those member
///    ids in ONE batch query (`_selectLiveBioMediaAttachmentsForMembers`).
/// 3. Parse all `prism-media://<mediaId>` URIs from each member's bio text,
///    per member, and soft-delete any attachment of that member whose `media_id`
///    is not in the member's referenced set.
/// 4. Cooperatively yield between mutation slices ([mutationBatchSize]) and at
///    each page boundary so a large sweep never monopolizes the isolate.
///
/// **Query shape.** The expensive media scan stays bounded at
/// `2 * ceil(members / [memberPageSize]) + 1` statements:
///
/// * the member page query pages distinct member ids with a `LEFT JOIN` on
///   `members` so bio text comes back with the page (one query per page, not
///   one per member),
/// * the attachment query resolves every live bio-media row for a whole page of
///   members with a single `member_id IN (...)` predicate.
///
/// Each orphan candidate also performs one indexed member-primary-key bio lookup
/// inside the same transaction as its tombstone. That closes the concurrent-edit
/// race without reintroducing per-member attachment scans or blob projection.
///
/// The previous implementation issued `2M + 1` queries for `M` members (all
/// distinct ids, then a bio lookup and an attachment lookup per member), which
/// dominated startup on large systems and produced Android ANRs. Both queries
/// project only the columns the sweep needs (`member_id`, `bio`, `id`,
/// `media_id`) — no attachment metadata, blob, waveform, or key columns are
/// materialized.
///
/// Only the *scan* is batched: each orphan is still tombstoned through
/// `repository.softDeleteBioMedia`, so tombstones and their sync emissions stay
/// one-per-attachment and byte-identical to before.
///
/// Returns the number of attachments soft-deleted.
///
/// Best-effort: all DB operations are wrapped in try/catch. A failure for one
/// page never prevents reconciliation for the other pages.
///
/// **Idempotence**: safe to call repeatedly. Already-deleted rows are excluded
/// by both queries, so a second run finds no orphans, soft-deletes nothing, and
/// emits no sync ops.
Future<int> reconcileBioMediaOrphans({
  required AppDatabase db,
  required DriftMediaAttachmentRepository repository,
  void Function(String message)? log,
  int memberPageSize = kBioMediaReconcileMemberPageSize,
  int mutationBatchSize = kBioMediaReconcileMutationBatchSize,
  Future<void> Function()? yieldControl,
}) async {
  final logFn = log ?? _defaultLog;

  if (!kEnableBioMediaReconcile) {
    logFn('Bio media reconcile disabled by feature flag');
    return 0;
  }

  // Guard the paging/tombstone strides against a non-positive override: a zero
  // page size would return an empty page and silently end the sweep, and a zero
  // batch size would make the yield stride undefined.
  final pageSize = memberPageSize < 1 ? 1 : memberPageSize;
  final batchSize = mutationBatchSize < 1 ? 1 : mutationBatchSize;
  final yieldFn = yieldControl ?? _cooperativeYield;

  var totalDeleted = 0;

  try {
    var lastMemberId = '';

    while (true) {
      final List<_BioMediaMember> page;
      try {
        page = await _selectBioMediaMemberPage(
          db,
          afterMemberId: lastMemberId,
          limit: pageSize,
        );
      } catch (e) {
        // Cannot advance the cursor safely without a page, and re-querying the
        // same range would spin — stop the sweep and keep the deletions already
        // committed.
        logFn(
          'Bio media reconcile: failed to page members after '
          '${lastMemberId.isEmpty ? '<start>' : lastMemberId} '
          '(non-fatal): $e',
        );
        break;
      }

      if (page.isEmpty) break;

      // Advance the cursor before doing page work so a per-page failure can
      // never re-process (or skip past) the same range.
      lastMemberId = page.last.memberId;

      try {
        final memberIds = [for (final member in page) member.memberId];

        // Batch 1: every live bio-media attachment row for this whole page of
        // members, in one set-based query.
        final attachments = await _selectLiveBioMediaAttachmentsForMembers(
          db,
          memberIds: memberIds,
        );

        // Per-member referenced set, parsed with the exact `prism-media://`
        // regex. Kept per member (not unioned globally): an attachment is an
        // orphan when ITS OWNING member's bio does not reference it, even if
        // some other member's bio does.
        final referencedByMember = <String, Set<String>>{
          for (final member in page)
            member.memberId: _parseReferencedMediaIds(member.bio),
        };

        final orphanCandidates = [
          for (final attachment in attachments)
            if (!(referencedByMember[attachment.memberId]?.contains(
                  attachment.mediaId,
                ) ??
                true))
              attachment,
        ];

        for (
          var offset = 0;
          offset < orphanCandidates.length;
          offset += batchSize
        ) {
          final end = math.min(offset + batchSize, orphanCandidates.length);
          final batch = orphanCandidates.sublist(offset, end);

          for (final attachment in batch) {
            try {
              final deleted = await db.transaction(() async {
                // Keep the current-bio read and tombstone in one transaction so
                // no local save or remote delivery can restore the reference in
                // the await between validation and mutation.
                final currentReferences = await _selectCurrentBioReferences(
                  db,
                  memberIds: {attachment.memberId},
                );
                if (currentReferences[attachment.memberId]?.contains(
                      attachment.mediaId,
                    ) ??
                    false) {
                  return false;
                }
                await repository.softDeleteBioMedia(attachment.id);
                return true;
              });
              if (deleted) totalDeleted += 1;
            } catch (e) {
              logFn(
                'Bio media reconcile: failed to soft-delete attachment '
                '${attachment.id} (non-fatal): $e',
              );
            }
          }

          // Cooperative yield between mutation slices: the sweep runs during
          // startup on the UI isolate, so a large sweep must hand the event loop
          // back regularly.
          await yieldFn();
        }
      } catch (e) {
        logFn(
          'Bio media reconcile: error processing member page ending at '
          '$lastMemberId (non-fatal, continuing): $e',
        );
      }

      // Page-boundary yield: guarantees a hand-back per page even when the page
      // had no orphans to tombstone.
      await yieldFn();
    }

    if (totalDeleted > 0) {
      logFn(
        'Bio media reconcile: soft-deleted $totalDeleted orphaned '
        'bio-media attachment(s)',
      );
    }
    return totalDeleted;
  } catch (e) {
    logFn('Bio media reconcile failed (non-fatal): $e');
    return 0;
  }
}

/// Default cooperative yield: hands the event loop back for one turn so pending
/// frames, input, and other startup work get a chance to run between mutation
/// slices. Matches the `Future<void>.delayed(Duration.zero)` convention used
/// elsewhere on long startup paths (see `database_encryption.dart`).
Future<void> _cooperativeYield() => Future<void>.delayed(Duration.zero);

/// Extracts the `media_id` values referenced by `prism-media://<mediaId>` URIs
/// in [bio]. A null/empty bio references nothing.
Set<String> _parseReferencedMediaIds(String? bio) {
  if (bio == null || bio.isEmpty) return const <String>{};
  final referenced = <String>{};
  for (final match in _prismMediaUriPattern.allMatches(bio)) {
    final mediaId = match.group(1);
    if (mediaId != null) referenced.add(mediaId);
  }
  return referenced;
}

/// Re-reads the current live bios for a bounded mutation slice.
///
/// Every requested id is present in the result. Missing or soft-deleted members
/// map to an empty set, preserving the sweep's "all attachments are orphaned"
/// behavior for those owners.
Future<Map<String, Set<String>>> _selectCurrentBioReferences(
  AppDatabase db, {
  required Set<String> memberIds,
}) async {
  if (memberIds.isEmpty) return const <String, Set<String>>{};

  final placeholders = List.filled(memberIds.length, '?').join(', ');
  final rows = await db
      .customSelect(
        '''
        SELECT id, bio
        FROM members
        WHERE is_deleted = 0
          AND id IN ($placeholders)
        ''',
        variables: [
          for (final memberId in memberIds) Variable.withString(memberId),
        ],
        readsFrom: {db.members},
      )
      .get();

  final result = <String, Set<String>>{
    for (final memberId in memberIds) memberId: const <String>{},
  };
  for (final row in rows) {
    result[row.read<String>('id')] = _parseReferencedMediaIds(
      row.read<String?>('bio'),
    );
  }
  return result;
}

/// One page of distinct bio-media member ids with the owning member's current
/// `bio` text, ordered ascending by `member_id`.
///
/// Driven by the attachment side so the sweep visits exactly the members that
/// have live bio-media rows, and `LEFT JOIN`ed so the old member-existence
/// semantics survive: a member row that is absent OR soft-deleted yields a
/// `null` bio, which makes every one of that member's bio-media attachments an
/// orphan (the previous implementation's `SELECT bio FROM members WHERE id = ?
/// AND is_deleted = 0` returned no row in exactly those two cases).
///
/// `GROUP BY a.member_id` with the aggregate `MAX(...)` bio projection makes the
/// per-group scalar deterministic instead of relying on SQLite's bare-column
/// pick-any-row rule.
Future<List<_BioMediaMember>> _selectBioMediaMemberPage(
  AppDatabase db, {
  required String afterMemberId,
  required int limit,
}) async {
  final rows = await db
      .customSelect(
        '''
        SELECT a.member_id AS member_id,
               MAX(
                 CASE WHEN m.id IS NOT NULL AND m.is_deleted = 0
                 THEN m.bio END
               ) AS bio
        FROM media_attachments AS a
        LEFT JOIN members AS m
          ON m.id = a.member_id
        WHERE a.member_id != ''
          AND a.is_deleted = 0
          AND a.member_id > ?
        GROUP BY a.member_id
        ORDER BY a.member_id
        LIMIT ?
        ''',
        variables: [
          Variable.withString(afterMemberId),
          Variable.withInt(limit),
        ],
        readsFrom: {db.mediaAttachments, db.members},
      )
      .get();

  return [
    for (final row in rows)
      _BioMediaMember(
        memberId: row.read<String>('member_id'),
        bio: row.read<String?>('bio'),
      ),
  ];
}

/// Every live bio-media attachment row belonging to any of [memberIds], in one
/// set-based query. Projects only `id`, `member_id`, and `media_id` — the sweep
/// never needs attachment metadata, blob, waveform, or crypto columns.
Future<List<_BioMediaAttachmentRef>> _selectLiveBioMediaAttachmentsForMembers(
  AppDatabase db, {
  required List<String> memberIds,
}) async {
  if (memberIds.isEmpty) return const <_BioMediaAttachmentRef>[];

  final placeholders = List.filled(memberIds.length, '?').join(', ');
  final rows = await db
      .customSelect(
        '''
        SELECT a.id AS id, a.member_id AS member_id, a.media_id AS media_id
        FROM media_attachments AS a
        WHERE a.member_id != ''
          AND a.is_deleted = 0
          AND a.member_id IN ($placeholders)
        ORDER BY a.id
        ''',
        variables: [
          for (final memberId in memberIds) Variable.withString(memberId),
        ],
        readsFrom: {db.mediaAttachments},
      )
      .get();

  return [
    for (final row in rows)
      _BioMediaAttachmentRef(
        id: row.read<String>('id'),
        memberId: row.read<String>('member_id'),
        mediaId: row.read<String>('media_id'),
      ),
  ];
}

/// A distinct bio-media member id plus that member's current `bio` (`null` when
/// the member row is absent or soft-deleted).
class _BioMediaMember {
  const _BioMediaMember({required this.memberId, required this.bio});

  final String memberId;
  final String? bio;
}

/// The narrow attachment projection the sweep tombstones against.
class _BioMediaAttachmentRef {
  const _BioMediaAttachmentRef({
    required this.id,
    required this.memberId,
    required this.mediaId,
  });

  final String id;
  final String memberId;
  final String mediaId;
}

void _defaultLog(String message) {
  ErrorReportingService.instance.report(message, severity: ErrorSeverity.info);
}

/// Convenience wrapper that resolves [AppDatabase] from a [WidgetRef] and
/// runs [reconcileBioMediaOrphans]. Called from app startup once after the
/// Riverpod tree is up. Accepts [WidgetRef] (the type that [ConsumerState]
/// exposes via its `ref` field) rather than the provider-only [Ref] so the
/// startup hook in `app.dart` can wire this without an extra adapter.
Future<int> runBioMediaReconcileFromRef(WidgetRef ref) async {
  if (!kEnableBioMediaReconcile) return 0;
  try {
    final db = ref.read(databaseProvider);
    final repo =
        ref.read(mediaAttachmentRepositoryProvider)
            as DriftMediaAttachmentRepository;
    return await reconcileBioMediaOrphans(db: db, repository: repo);
  } catch (e) {
    ErrorReportingService.instance.report(
      'Bio media reconcile failed to resolve dependencies (non-fatal): $e',
      severity: ErrorSeverity.info,
    );
    return 0;
  }
}
