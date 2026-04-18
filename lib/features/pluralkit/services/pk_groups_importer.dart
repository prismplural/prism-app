import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/member_groups_dao.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';

/// Result of a single PK-groups import pass.
class PkGroupsImportResult {
  final int groupsInserted;
  final int groupsUpdated;
  final int groupsObserved;
  final int entriesInserted;
  final int entriesRemoved;
  final int entriesDeferred;

  /// Count of groups whose `memberIds` came back as null (privacy / partial
  /// fetch). Surfaces flapping — a high number here means membership reconcile
  /// was intentionally skipped for those groups.
  final int groupsWithUnknownMembership;

  const PkGroupsImportResult({
    this.groupsInserted = 0,
    this.groupsUpdated = 0,
    this.groupsObserved = 0,
    this.entriesInserted = 0,
    this.entriesRemoved = 0,
    this.entriesDeferred = 0,
    this.groupsWithUnknownMembership = 0,
  });

  PkGroupsImportResult copyWith({
    int? groupsInserted,
    int? groupsUpdated,
    int? groupsObserved,
    int? entriesInserted,
    int? entriesRemoved,
    int? entriesDeferred,
    int? groupsWithUnknownMembership,
  }) =>
      PkGroupsImportResult(
        groupsInserted: groupsInserted ?? this.groupsInserted,
        groupsUpdated: groupsUpdated ?? this.groupsUpdated,
        groupsObserved: groupsObserved ?? this.groupsObserved,
        entriesInserted: entriesInserted ?? this.entriesInserted,
        entriesRemoved: entriesRemoved ?? this.entriesRemoved,
        entriesDeferred: entriesDeferred ?? this.entriesDeferred,
        groupsWithUnknownMembership:
            groupsWithUnknownMembership ?? this.groupsWithUnknownMembership,
      );
}

/// Imports PluralKit groups and memberships into Prism.
///
/// Phase 1 (pull only). Follows the codex-reviewed revisions in
/// `docs/plans/pk-sp-gaps/03-pk-groups.md`:
///
/// - R1: Authoritative-set diff — membership removals are driven by the PK
///   member UUID set, not by locally-resolved IDs. Unresolved members are
///   deferred, never treated as "missing on PK".
/// - R2: `memberIds == null` means "unknown" → skip removals entirely.
/// - R3: `reattribute(...)` insert-only pass for members that weren't linked
///   at first import.
/// - R5: `overwriteMetadata` — background sync reconciles membership only;
///   metadata (name/description/color/displayName) is only overwritten on
///   explicit user action.
/// - R6: Deterministic entry IDs `sha256(groupUuid\0memberPkUuid)[:16]`.
/// - R7: Identity matching is UUID-only.
/// - R8: Local emoji is never touched on PK pull.
/// - R9: `last_seen_from_pk_at` refreshed for every observed group.
class PkGroupsImporter {
  final AppDatabase _db;
  final MemberGroupsDao _dao;
  final MemberRepository _memberRepository;
  final Uuid _uuid;

  PkGroupsImporter({
    required AppDatabase db,
    required MemberRepository memberRepository,
    Uuid? uuid,
  })  : _db = db,
        _dao = db.memberGroupsDao,
        _memberRepository = memberRepository,
        _uuid = uuid ?? const Uuid();

  /// Derive a deterministic `member_group_entries.id` from PK identifiers so
  /// two offline devices produce the same row (see R6).
  static String deriveEntryId(String groupUuid, String memberPkUuid) {
    final digest =
        sha256.convert(utf8.encode('$groupUuid\u0000$memberPkUuid'));
    // Hex → first 16 chars = 64 bits of entropy.
    return digest.toString().substring(0, 16);
  }

  /// Import a batch of PK groups.
  ///
  /// When [overwriteMetadata] is false (default for background sync),
  /// existing rows keep their local name/description/color/displayOrder and
  /// only membership is reconciled. When true (explicit re-import / user
  /// action), metadata is replaced with PK's values.
  Future<PkGroupsImportResult> importGroups(
    PluralKitClient client,
    List<PKGroup> pkGroups, {
    bool overwriteMetadata = false,
  }) async {
    var result = const PkGroupsImportResult();
    if (pkGroups.isEmpty) return result;

    // Resolve members once up front so we know which PK UUIDs are locally
    // available *right now*. The authoritative set (R1) is the PK list, not
    // this map — the map only tells us which PK UUIDs map to a local row.
    final allMembers = await _memberRepository.getAllMembers();
    final pkUuidToLocalMemberId = <String, String>{};
    for (final m in allMembers) {
      if (m.pluralkitUuid != null && m.pluralkitUuid!.isNotEmpty) {
        pkUuidToLocalMemberId[m.pluralkitUuid!] = m.id;
      }
    }

    final now = DateTime.now();

    for (final pk in pkGroups) {
      result = result.copyWith(groupsObserved: result.groupsObserved + 1);

      final existing = await _dao.findByPluralkitUuid(pk.uuid);
      final groupLocalId = existing?.id ?? _uuid.v4();

      if (existing == null) {
        // Insert new row. Always writes metadata — there is nothing local to
        // preserve. Local emoji stays null (R8): PK's `icon` is a URL, not an
        // emoji.
        final displayOrder = await _dao.nextDisplayOrder();
        await _dao.upsertGroup(
          MemberGroupsCompanion.insert(
            id: groupLocalId,
            name: pk.displayName ?? pk.name,
            description: Value(pk.description),
            colorHex: Value(pk.color == null ? null : '#${pk.color}'),
            emoji: const Value(null),
            displayOrder: Value(displayOrder),
            createdAt: now,
            pluralkitId: Value(pk.id),
            pluralkitUuid: Value(pk.uuid),
            lastSeenFromPkAt: Value(now),
          ),
        );
        result = result.copyWith(
          groupsInserted: result.groupsInserted + 1,
        );
      } else {
        // Existing row. Refresh last_seen_from_pk_at always; only update
        // metadata when the caller asked us to (R5). Never touch emoji (R8).
        final updates = MemberGroupsCompanion(
          id: Value(existing.id),
          lastSeenFromPkAt: Value(now),
          pluralkitId: Value(pk.id),
          pluralkitUuid: Value(pk.uuid),
          name: overwriteMetadata
              ? Value(pk.displayName ?? pk.name)
              : const Value.absent(),
          description: overwriteMetadata
              ? Value(pk.description)
              : const Value.absent(),
          colorHex: overwriteMetadata
              ? Value(pk.color == null ? null : '#${pk.color}')
              : const Value.absent(),
        );
        await (_db.update(_db.memberGroups)
              ..where((g) => g.id.equals(existing.id)))
            .write(updates);
        if (overwriteMetadata) {
          result = result.copyWith(
            groupsUpdated: result.groupsUpdated + 1,
          );
        }
      }

      // Membership reconciliation — R1 + R2.
      if (pk.memberIds == null) {
        // Unknown → don't touch entries at all.
        result = result.copyWith(
          groupsWithUnknownMembership:
              result.groupsWithUnknownMembership + 1,
        );
        debugPrint(
          '[PK groups] unknown membership for group ${pk.uuid}; skipping '
          'reconciliation.',
        );
        continue;
      }

      final delta = await _reconcileMembership(
        groupLocalId: groupLocalId,
        groupPkUuid: pk.uuid,
        authoritativePkMemberUuids: pk.memberIds!,
        allMembers: allMembers,
        pkUuidToLocalMemberId: pkUuidToLocalMemberId,
        insertOnly: false,
      );
      result = result.copyWith(
        entriesInserted: result.entriesInserted + delta.entriesInserted,
        entriesRemoved: result.entriesRemoved + delta.entriesRemoved,
        entriesDeferred: result.entriesDeferred + delta.entriesDeferred,
      );
    }

    return result;
  }

  /// R3 — insert-only re-attribution pass. Called after member mapping has
  /// applied so PK UUIDs that were previously unknown can now be resolved.
  /// Never removes entries.
  Future<PkGroupsImportResult> reattribute(
    PluralKitClient client,
  ) async {
    final pkGroups = await client.getGroups(withMembers: true);
    if (pkGroups.isEmpty) return const PkGroupsImportResult();

    final allMembers = await _memberRepository.getAllMembers();
    final pkUuidToLocalMemberId = <String, String>{};
    for (final m in allMembers) {
      if (m.pluralkitUuid != null && m.pluralkitUuid!.isNotEmpty) {
        pkUuidToLocalMemberId[m.pluralkitUuid!] = m.id;
      }
    }

    var result = const PkGroupsImportResult();
    for (final pk in pkGroups) {
      if (pk.memberIds == null) continue;
      final existing = await _dao.findByPluralkitUuid(pk.uuid);
      if (existing == null) continue; // Reattribute only touches known groups.
      final delta = await _reconcileMembership(
        groupLocalId: existing.id,
        groupPkUuid: pk.uuid,
        authoritativePkMemberUuids: pk.memberIds!,
        allMembers: allMembers,
        pkUuidToLocalMemberId: pkUuidToLocalMemberId,
        insertOnly: true,
      );
      result = result.copyWith(
        groupsObserved: result.groupsObserved + 1,
        entriesInserted: result.entriesInserted + delta.entriesInserted,
      );
    }
    return result;
  }

  Future<_ReconcileDelta> _reconcileMembership({
    required String groupLocalId,
    required String groupPkUuid,
    required List<String> authoritativePkMemberUuids,
    required List<domain.Member> allMembers,
    required Map<String, String> pkUuidToLocalMemberId,
    required bool insertOnly,
  }) async {
    final memberById = <String, domain.Member>{
      for (final m in allMembers) m.id: m,
    };

    final authoritativeSet = authoritativePkMemberUuids.toSet();
    final entries = await _dao.entriesForGroup(groupLocalId);

    int inserted = 0;
    int removed = 0;
    int deferred = 0;

    await _db.transaction(() async {
      if (!insertOnly) {
        for (final entry in entries) {
          final member = memberById[entry.memberId];
          if (member == null) continue; // orphan row — leave alone.
          final pkUuid = member.pluralkitUuid;
          if (pkUuid == null || pkUuid.isEmpty) {
            // Local-only member — preserve.
            continue;
          }
          if (authoritativeSet.contains(pkUuid)) continue; // preserve.
          // PK-linked member, not in authoritative set → soft-delete.
          await _dao.softDeleteEntry(entry.id);
          removed++;
        }
      }

      // Insert path — for every PK UUID in authoritative set, add an entry if
      // we can resolve it locally. Unresolved UUIDs count as deferred (R3).
      final existingActiveMemberIds = <String>{
        for (final e in entries) if (!e.isDeleted) e.memberId,
      };

      for (final pkMemberUuid in authoritativePkMemberUuids) {
        final localMemberId = pkUuidToLocalMemberId[pkMemberUuid];
        if (localMemberId == null) {
          deferred++;
          continue;
        }
        if (existingActiveMemberIds.contains(localMemberId)) continue;

        final entryId = deriveEntryId(groupPkUuid, pkMemberUuid);
        await _dao.upsertEntry(
          MemberGroupEntriesCompanion.insert(
            id: entryId,
            groupId: groupLocalId,
            memberId: localMemberId,
            isDeleted: const Value(false),
          ),
        );
        inserted++;
      }
    });

    return _ReconcileDelta(
      entriesInserted: inserted,
      entriesRemoved: removed,
      entriesDeferred: deferred,
    );
  }
}

class _ReconcileDelta {
  final int entriesInserted;
  final int entriesRemoved;
  final int entriesDeferred;
  const _ReconcileDelta({
    required this.entriesInserted,
    required this.entriesRemoved,
    required this.entriesDeferred,
  });
}
