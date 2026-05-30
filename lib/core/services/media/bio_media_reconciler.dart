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

/// Scans `media_attachments` for bio-media rows whose `media_id` is no longer
/// referenced by the owning member's `bio` text, and soft-deletes the orphans.
///
/// This sweep is a safety net for the on-save hook in `_reconcileBioImageOrphans`
/// (add_edit_member_sheet.dart): it catches anything the hook missed — e.g. if
/// the app crashed before the hook ran, or a concurrent remote edit left orphans.
///
/// **Logic**
/// 1. Query all distinct `member_id` values from non-deleted `media_attachments`
///    rows that have a non-empty `member_id` (bio-media rows have a member_id;
///    message-media rows have an empty one).
/// 2. For each such member, fetch the member's current `bio` text from the DB.
/// 3. Parse all `prism-media://<mediaId>` URIs from the bio text.
/// 4. Soft-delete any attachment whose `media_id` is not in the referenced set.
///
/// Returns the number of attachments soft-deleted.
///
/// Best-effort: all DB operations are wrapped in try/catch. A failure for one
/// member never prevents reconciliation for the others.
///
/// **Idempotence**: safe to call repeatedly. Already-deleted rows are excluded
/// by the initial query; running twice produces the same outcome as once.
Future<int> reconcileBioMediaOrphans({
  required AppDatabase db,
  required DriftMediaAttachmentRepository repository,
  void Function(String message)? log,
}) async {
  final logFn = log ?? _defaultLog;

  if (!kEnableBioMediaReconcile) {
    logFn('Bio media reconcile disabled by feature flag');
    return 0;
  }

  var totalDeleted = 0;

  try {
    // 1. Find all distinct member_ids that have non-deleted bio-media rows.
    //    Bio-media attachments are distinguished by having a non-empty
    //    member_id (message media always has an empty member_id).
    final memberIdRows = await db
        .customSelect(
          'SELECT DISTINCT member_id FROM media_attachments '
          'WHERE member_id != \'\' AND is_deleted = 0',
        )
        .get();

    if (memberIdRows.isEmpty) return 0;

    final prismMediaPattern = RegExp(r'prism-media://([a-zA-Z0-9-]+)');

    for (final memberIdRow in memberIdRows) {
      final memberId = memberIdRow.read<String>('member_id');
      if (memberId.isEmpty) continue;

      try {
        // 2. Fetch the member's current bio from the DB.
        final memberRows = await db
            .customSelect(
              'SELECT bio FROM members WHERE id = ? AND is_deleted = 0',
              variables: [Variable.withString(memberId)],
            )
            .get();

        // Member may have been deleted since the attachment was written.
        // In that case all bio-media for this member are orphans.
        final bioText = memberRows.isEmpty
            ? null
            : memberRows.first.read<String?>('bio');

        // 3. Parse referenced media IDs from the bio.
        final referenced = <String>{};
        if (bioText != null && bioText.isNotEmpty) {
          for (final match in prismMediaPattern.allMatches(bioText)) {
            final mediaId = match.group(1);
            if (mediaId != null) referenced.add(mediaId);
          }
        }

        // 4. Fetch all non-deleted bio-media attachments for this member
        //    and soft-delete any that are not referenced.
        final attachmentRows = await db
            .customSelect(
              'SELECT id, media_id FROM media_attachments '
              'WHERE member_id = ? AND is_deleted = 0',
              variables: [Variable.withString(memberId)],
            )
            .get();

        for (final row in attachmentRows) {
          final attachmentId = row.read<String>('id');
          final mediaId = row.read<String>('media_id');

          if (!referenced.contains(mediaId)) {
            try {
              await repository.softDeleteBioMedia(attachmentId);
              totalDeleted += 1;
            } catch (e) {
              logFn(
                'Bio media reconcile: failed to soft-delete attachment '
                '$attachmentId (non-fatal): $e',
              );
            }
          }
        }
      } catch (e) {
        logFn(
          'Bio media reconcile: error processing member $memberId '
          '(non-fatal, continuing): $e',
        );
      }
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

void _defaultLog(String message) {
  ErrorReportingService.instance.report(
    message,
    severity: ErrorSeverity.info,
  );
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
    final repo = ref.read(mediaAttachmentRepositoryProvider)
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
