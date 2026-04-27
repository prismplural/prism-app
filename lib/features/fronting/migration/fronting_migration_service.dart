/// Phase 5B of the per-member fronting refactor — the user-driven
/// app-layer migration transaction.
///
/// Spec: `docs/plans/fronting-per-member-sessions.md` §4.1 (steps 1-10),
/// §4.2 (sync state reset, primary vs secondary).
///
/// One entry point: [FrontingMigrationService.runMigration]. Called by
/// the upgrade modal (Phase 5C) after the user picks a mode + role.
///
/// File-IO and FFI calls (PRISM1 export, share-sheet, Rust
/// `resetSyncState`) run OUTSIDE the Drift transaction.  The Drift
/// transaction wraps steps 3-10 atomically; on failure inside that
/// block, the local DB rolls back and `pending_fronting_migration_mode`
/// stays at `'notStarted'` so the user can retry.  The PRISM1 file from
/// step 2 is preserved on disk regardless.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    hide FrontingSession, Member;
import 'package:prism_plurality/domain/models/front_session_comment.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/repositories/front_session_comments_repository.dart';
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/data_management/services/data_export_service.dart';

/// User-selected migration mode from the upgrade modal (5C).
enum MigrationMode {
  /// Preserve SP/native rows in place; fan out multi-member native rows
  /// per spec §4.1 step 4; PK rows go into the PRISM1 rescue file and
  /// then get deleted (re-imported via the new diff-sweep importer).
  upgradeAndKeep,

  /// Delete every fronting row (still produces a PRISM1 backup of the
  /// full local state first).  Skips per-row migration; relies on PK
  /// API + SP re-imports to rebuild the timeline post-migration.
  startFresh,

  /// Defer the migration.  Writes `'deferred'` to settings; no other
  /// side effects.  The upgrade modal will surface a banner reminding
  /// the user; sync stays degraded until they pick a real mode.
  notNow,
}

/// Device's role in the sync group, chosen by the upgrade modal (5C).
///
/// Solo and primary share the full per-row migration path; secondaries
/// skip per-row work and rely on re-pairing with the migrated primary
/// to resync fronting data in the new shape (see spec §4.2).
enum DeviceRole { solo, primary, secondary }

enum MigrationOutcome { success, failed, deferred }

/// Result returned from [FrontingMigrationService.runMigration].
@immutable
class MigrationResult {
  const MigrationResult({
    required this.outcome,
    this.exportFile,
    this.spRowsMigrated = 0,
    this.nativeRowsMigrated = 0,
    this.nativeRowsExpanded = 0,
    this.pkRowsDeleted = 0,
    this.commentsMigrated = 0,
    this.commentsDeleted = 0,
    this.orphanRowsAssignedToSentinel = 0,
    this.unknownSentinelCreated = false,
    this.corruptCoFronterRowIds = const [],
    this.errorMessage,
  });

  final MigrationOutcome outcome;
  final File? exportFile;
  final int spRowsMigrated;
  final int nativeRowsMigrated;

  /// Number of additional per-member rows created by fanning out
  /// multi-member native sessions (spec §4.1 step 4).  Excludes the
  /// primary row (which keeps the legacy id) — this is the count of
  /// NEW rows from the fan-out only.
  final int nativeRowsExpanded;

  final int pkRowsDeleted;
  final int commentsMigrated;
  final int commentsDeleted;
  final int orphanRowsAssignedToSentinel;
  final bool unknownSentinelCreated;

  /// Native row ids whose `co_fronter_ids` JSON failed to parse — fell
  /// back to single-member migration per §6 edge cases.  Surfaced for
  /// user review.
  final List<String> corruptCoFronterRowIds;

  final String? errorMessage;
}

/// Internal: classification bucket for a fronting session row.
enum _SessionKind { pkImported, spImported, nativeNormal, nativeSleep }

class _ClassifiedSession {
  const _ClassifiedSession(this.row, this.kind);
  final FrontingSessionRow row;
  final _SessionKind kind;
}

/// Drift `FrontingSession` row with the legacy v7 columns we still
/// need to read for the migration.  Drift's generated row class is
/// fine, but we copy the relevant fields out so the rest of the file
/// doesn't need to import the generated type explicitly.
class FrontingSessionRow {
  const FrontingSessionRow({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.memberId,
    required this.notes,
    required this.confidence,
    required this.pluralkitUuid,
    required this.coFronterIdsRaw,
    required this.sessionType,
    required this.quality,
    required this.isHealthKitImport,
  });

  final String id;
  final DateTime startTime;
  final DateTime? endTime;
  final String? memberId;
  final String? notes;
  final int? confidence;
  final String? pluralkitUuid;
  final String coFronterIdsRaw; // JSON list, possibly malformed
  final int sessionType; // 0 = normal, 1 = sleep
  final int? quality;
  final bool isHealthKitImport;
}

class FrontingMigrationService {
  FrontingMigrationService({
    required this.db,
    required this.memberRepository,
    required this.frontingSessionRepository,
    required this.frontSessionCommentsRepository,
    required this.dataExportService,
    required this.syncHandle,
    Future<void> Function(ffi.PrismSyncHandle handle)? resetSyncState,
  }) : _resetSyncState = resetSyncState ??
            ((handle) => ffi.resetSyncState(handle: handle));

  final AppDatabase db;
  final MemberRepository memberRepository;
  final FrontingSessionRepository frontingSessionRepository;
  final FrontSessionCommentsRepository frontSessionCommentsRepository;
  final DataExportService dataExportService;

  /// Opaque Rust handle.  Nullable so unit tests can run without
  /// initializing an FFI handle — when null we skip the engine reset
  /// step but still wipe `sync_quarantine` (host-side table).
  final ffi.PrismSyncHandle? syncHandle;

  /// Indirection so tests can inject a fake.  In production this is the
  /// generated `ffi.resetSyncState(handle: handle)`.  Must be passed
  /// `handle` as a positional arg by the wrapper.
  final Future<void> Function(ffi.PrismSyncHandle handle) _resetSyncState;

  static const _uuid = Uuid();

  /// Sentinel string written to `system_settings.pending_fronting_migration_mode`.
  static const String modeNotStarted = 'notStarted';
  static const String modeDeferred = 'deferred';
  static const String modeUpgradeAndKeep = 'upgradeAndKeep';
  static const String modeStartFresh = 'startFresh';
  static const String modeComplete = 'complete';

  /// Entry point.
  ///
  /// [shareFile] is the share-sheet callback (5C provides
  /// `Share.shareXFiles` analogue).  It runs OUTSIDE the Drift
  /// transaction; if it throws or returns null when the user cancels,
  /// migration aborts and `pending_fronting_migration_mode` stays at
  /// `'notStarted'`.  The PRISM1 file is preserved either way so the
  /// user can manually share it later.
  Future<MigrationResult> runMigration({
    required MigrationMode mode,
    required DeviceRole role,
    required Future<Uri?> Function(File file) shareFile,
    String password = '',
  }) async {
    if (mode == MigrationMode.notNow) {
      // No destructive work — just write the deferred marker.
      await db.systemSettingsDao
          .writePendingFrontingMigrationMode(modeDeferred);
      return const MigrationResult(outcome: MigrationOutcome.deferred);
    }

    // Step 1 + 2: classify rows, build PRISM1 export, share with user.
    // Outside the transaction so file IO can't roll back.
    File exportFile;
    try {
      exportFile = await dataExportService.exportEncryptedData(
        password: password,
        includeLegacyFields: true,
      );
    } catch (e) {
      // Export failed before any destructive step ran; settings
      // unchanged, no rollback needed.
      return MigrationResult(
        outcome: MigrationOutcome.failed,
        errorMessage: 'PRISM1 export failed: $e',
      );
    }

    try {
      await shareFile(exportFile);
    } catch (e) {
      return MigrationResult(
        outcome: MigrationOutcome.failed,
        exportFile: exportFile,
        errorMessage: 'Share-sheet failed: $e',
      );
    }

    // Steps 3-10: wrap in a single Drift transaction.  Repository
    // writes inside this block emit v2 entity ops via the SyncRecord
    // mixin; those ops are then blown away by step 8's wipe and
    // re-emitted from the migrated rows on first sync after re-pair.
    _MigrationCounters counters;
    try {
      counters = await db.transaction<_MigrationCounters>(() async {
        // Mark the chosen mode early so a mid-transaction crash leaves
        // a breadcrumb the next launch can surface ("looks like the
        // last attempt didn't finish").  On rollback Drift undoes this
        // write too — settings stays at the prior `'notStarted'`.
        await db.systemSettingsDao.writePendingFrontingMigrationMode(
          mode == MigrationMode.upgradeAndKeep
              ? modeUpgradeAndKeep
              : modeStartFresh,
        );

        switch (role) {
          case DeviceRole.secondary:
            // Spec §4.1 final paragraph: secondaries skip per-row work
            // and just truncate.  Re-pairing with the migrated primary
            // resyncs the data in new shape.
            return _runSecondary();
          case DeviceRole.solo:
          case DeviceRole.primary:
            return _runPrimaryOrSolo(mode);
        }
      });
    } catch (e, st) {
      debugPrint('[FrontingMigration] Drift transaction failed: $e\n$st');
      // Drift rolled back; settings is still at whatever it was before
      // the transaction (typically `'notStarted'`).
      return MigrationResult(
        outcome: MigrationOutcome.failed,
        exportFile: exportFile,
        errorMessage: 'Migration transaction failed: $e',
      );
    }

    // Step 8: reset sync state.  Runs OUTSIDE the Drift transaction
    // because the Rust engine commits to its own SQLite store, not
    // ours.  Failure here leaves the migration committed locally but
    // the device potentially still paired with stale credentials —
    // surface as a soft failure so the user can retry the reset
    // separately.
    if (syncHandle != null) {
      try {
        await _resetSyncState(syncHandle!);
      } catch (e) {
        return MigrationResult(
          outcome: MigrationOutcome.failed,
          exportFile: exportFile,
          spRowsMigrated: counters.spRowsMigrated,
          nativeRowsMigrated: counters.nativeRowsMigrated,
          nativeRowsExpanded: counters.nativeRowsExpanded,
          pkRowsDeleted: counters.pkRowsDeleted,
          commentsMigrated: counters.commentsMigrated,
          commentsDeleted: counters.commentsDeleted,
          orphanRowsAssignedToSentinel:
              counters.orphanRowsAssignedToSentinel,
          unknownSentinelCreated: counters.unknownSentinelCreated,
          corruptCoFronterRowIds: counters.corruptCoFronterRowIds,
          errorMessage:
              'Migration succeeded locally but Rust engine reset failed: $e. '
              'Please re-pair from settings.',
        );
      }
    }

    // Truncate `sync_quarantine` AFTER engine reset so any quarantine
    // entries the reset itself produces (none today, defensive) also
    // get cleaned up.  Lives in the host's Drift schema, not Rust's,
    // which is why it isn't covered by `reset_sync_state`.
    await db.syncQuarantineDao.clearAll();

    // Step 10: mark complete.
    await db.systemSettingsDao
        .writePendingFrontingMigrationMode(modeComplete);

    return MigrationResult(
      outcome: MigrationOutcome.success,
      exportFile: exportFile,
      spRowsMigrated: counters.spRowsMigrated,
      nativeRowsMigrated: counters.nativeRowsMigrated,
      nativeRowsExpanded: counters.nativeRowsExpanded,
      pkRowsDeleted: counters.pkRowsDeleted,
      commentsMigrated: counters.commentsMigrated,
      commentsDeleted: counters.commentsDeleted,
      orphanRowsAssignedToSentinel: counters.orphanRowsAssignedToSentinel,
      unknownSentinelCreated: counters.unknownSentinelCreated,
      corruptCoFronterRowIds: counters.corruptCoFronterRowIds,
    );
  }

  // -------------------------------------------------------------------
  // Primary / solo path (full §4.1 steps 3-7 + 9)
  // -------------------------------------------------------------------

  Future<_MigrationCounters> _runPrimaryOrSolo(MigrationMode mode) async {
    // Step 1: read + classify all rows.
    final allRows = await _readAllSessions();
    final spSessionIds = await _readSpSessionIds();
    final classified = _classify(allRows, spSessionIds);

    // Step 5 setup: read all comment rows BEFORE deletes so we can
    // join them back to their (about-to-be-deleted) parents.  We need
    // `session_id`, `body`, `timestamp`, `created_at`.
    final allComments = await _readAllComments();

    if (mode == MigrationMode.startFresh) {
      // Step 6: delete every fronting row + every comment.  We still
      // need to read the rows first to issue per-row `syncRecordDelete`
      // so tombstones emit (the wipe at step 8 nukes those tombstones,
      // but the local Drift `is_deleted` flips correctly).
      var commentsDeleted = 0;
      for (final c in allComments) {
        await frontSessionCommentsRepository.deleteComment(c.id);
        commentsDeleted++;
      }
      var pkRowsDeleted = 0;
      for (final r in allRows) {
        await frontingSessionRepository.deleteSession(r.id);
        pkRowsDeleted++;
      }
      return _MigrationCounters(pkRowsDeleted: pkRowsDeleted)
        ..commentsDeleted = commentsDeleted;
    }

    // upgradeAndKeep path -------------------------------------------
    final counters = _MigrationCounters();

    // Step 3: SP-imported rows.  Already 1:1 per-member; just emit a
    // v2 entity op so the new-shape sync schema picks them up.
    for (final c in classified) {
      if (c.kind != _SessionKind.spImported) continue;
      await frontingSessionRepository
          .updateSession(_rowToDomain(c.row));
      counters.spRowsMigrated++;
    }

    // Step 4: native rows (normal + sleep).  Sleep keeps nullable
    // member_id and migrates 1:1.  Normal single-member migrates 1:1.
    // Normal multi-member: primary keeps legacy id; co-fronters get
    // deterministic v5 ids from migrationFrontingNamespace.
    final orphans = <FrontingSessionRow>[];
    for (final c in classified) {
      switch (c.kind) {
        case _SessionKind.pkImported:
        case _SessionKind.spImported:
          continue;
        case _SessionKind.nativeSleep:
          await frontingSessionRepository
              .updateSession(_rowToDomain(c.row));
          counters.nativeRowsMigrated++;
          continue;
        case _SessionKind.nativeNormal:
          break;
      }

      final row = c.row;
      // Parse co-fronter list, falling back to single-member on
      // corrupt JSON (§6 edge case).
      List<String> coFronters;
      var corrupt = false;
      try {
        final decoded = jsonDecode(row.coFronterIdsRaw);
        coFronters = decoded is List
            ? decoded.whereType<String>().toList()
            : const <String>[];
      } catch (_) {
        corrupt = true;
        coFronters = const <String>[];
        counters.corruptCoFronterRowIds.add(row.id);
      }

      // Detect orphans (member_id NULL on a normal row): handle
      // separately at step 7 so we only create the sentinel when
      // there's at least one orphan.
      if (row.memberId == null) {
        orphans.add(row);
        continue;
      }

      // Migrate the primary row in place.
      await frontingSessionRepository.updateSession(_rowToDomain(row));
      counters.nativeRowsMigrated++;

      // Skip fan-out on corrupt JSON (we already counted the row).
      if (corrupt) continue;

      // Fan out additional co-fronters into new per-member rows.
      for (final coId in coFronters) {
        if (coId == row.memberId) continue; // sanity guard
        final derivedId = _uuid.v5(
          migrationFrontingNamespace,
          '${row.id}:$coId',
        );
        // Use createSession so a v2 op emits.  CRDT field-LWW + the
        // composite (pluralkit_uuid, member_id) index are bug
        // protection; deterministic ids are correctness on concurrent
        // migrations across paired devices (§4.5 + §4.1 step 4).
        await frontingSessionRepository.createSession(
          FrontingSession(
            id: derivedId,
            startTime: row.startTime,
            endTime: row.endTime,
            memberId: coId,
            notes: row.notes,
            confidence: _intToConfidence(row.confidence),
            pluralkitUuid: null, // native rows never carry one
            sessionType: SessionType.normal,
          ),
        );
        counters.nativeRowsExpanded++;
      }
    }

    // Step 5: comments.  Walk every comment, look up its parent
    // session by legacy `session_id`, decide preserve-or-delete.
    //
    // Preserved comments use `updateComment` (NOT create) so the row
    // id stays stable and the comments DAO's plain `insert` doesn't
    // collide.  The update emits a v2 entity op carrying the new
    // `target_time` + `author_member_id` fields; the legacy
    // `session_id` column on disk stays in place (the v8 schema
    // rebuild drops it later — until then the comments mapper writes
    // the empty-string sentinel on every new insert anyway).
    final byParent = <String, FrontingSessionRow>{
      for (final r in allRows) r.id: r,
    };
    final pkParentIds = <String>{
      for (final c in classified)
        if (c.kind == _SessionKind.pkImported) c.row.id,
    };
    for (final cmt in allComments) {
      final parent = byParent[cmt.sessionId];
      final parentIsPk = parent != null && pkParentIds.contains(parent.id);
      if (parent == null || parentIsPk) {
        // Parent missing or wiped — drop the comment.  `parent ==
        // null` covers comments whose legacy session_id was empty
        // (e.g., already-migrated rows from a failed earlier attempt)
        // or pointed at a deleted session.
        await frontSessionCommentsRepository.deleteComment(cmt.id);
        counters.commentsDeleted++;
        continue;
      }

      // Migrate comment in place to new shape, anchored at the LEGACY
      // `timestamp` column (NOT createdAt — see spec warning §4.1
      // step 5).  Author is the parent session's member_id (may be
      // null for orphan/sleep parents — comments tolerate that).
      await frontSessionCommentsRepository.updateComment(
        FrontSessionComment(
          id: cmt.id,
          body: cmt.body,
          timestamp: cmt.timestamp,
          createdAt: cmt.createdAt,
          targetTime: cmt.timestamp,
          authorMemberId: parent.memberId,
        ),
      );
      counters.commentsMigrated++;
    }

    // Step 7: orphan handling.  Create the Unknown sentinel only if
    // there's at least one orphan to assign.
    if (orphans.isNotEmpty) {
      final sentinelId = _uuid.v5(
        spFrontingNamespace,
        'unknown-member-sentinel',
      );
      // Idempotency: if a prior failed attempt already created the
      // sentinel, don't re-create.
      final existing = await memberRepository.getMemberById(sentinelId);
      if (existing == null) {
        await memberRepository.createMember(
          Member(
            id: sentinelId,
            name: 'Unknown',
            emoji: '❔',
            isActive: true,
            createdAt: DateTime.now().toUtc(),
          ),
        );
        counters.unknownSentinelCreated = true;
      }
      for (final r in orphans) {
        await frontingSessionRepository.updateSession(
          FrontingSession(
            id: r.id,
            startTime: r.startTime,
            endTime: r.endTime,
            memberId: sentinelId,
            notes: r.notes,
            confidence: _intToConfidence(r.confidence),
            pluralkitUuid: r.pluralkitUuid,
            sessionType: SessionType.normal,
          ),
        );
        counters.orphanRowsAssignedToSentinel++;
      }
    }

    // Step 6: delete PK-imported rows.  Done LAST among the per-row
    // steps so the comment join above could still find PK parents.
    for (final c in classified) {
      if (c.kind != _SessionKind.pkImported) continue;
      await frontingSessionRepository.deleteSession(c.row.id);
      counters.pkRowsDeleted++;
    }

    // Step 9: explicitly DO NOT clear `sp_id_map` rows with
    // entityType='session'.  The SP re-importer needs the lookup.

    return counters;
  }

  // -------------------------------------------------------------------
  // Secondary path (no per-row migration; just truncate)
  // -------------------------------------------------------------------

  Future<_MigrationCounters> _runSecondary() async {
    // Truncate `fronting_sessions` and `front_session_comments`.
    // Direct SQL because we want the entire table gone, not soft-
    // delete tombstones (those would re-emit via sync ops on next
    // pair, defeating the purpose).  The sync state wipe (step 8)
    // happens after the transaction commits.
    await db.customStatement('DELETE FROM fronting_sessions');
    await db.customStatement('DELETE FROM front_session_comments');
    return _MigrationCounters();
  }

  // -------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------

  Future<List<FrontingSessionRow>> _readAllSessions() async {
    // Use customSelect to read the legacy `co_fronter_ids` column —
    // the freezed FrontingSession model no longer exposes it.
    final rows = await db
        .customSelect(
          'SELECT id, start_time, end_time, member_id, notes, confidence, '
          'pluralkit_uuid, co_fronter_ids, session_type, quality, '
          'is_health_kit_import '
          'FROM fronting_sessions WHERE is_deleted = 0',
        )
        .get();
    return rows.map((r) {
      return FrontingSessionRow(
        id: r.read<String>('id'),
        startTime: r.read<DateTime>('start_time'),
        endTime: r.read<DateTime?>('end_time'),
        memberId: r.read<String?>('member_id'),
        notes: r.read<String?>('notes'),
        confidence: r.read<int?>('confidence'),
        pluralkitUuid: r.read<String?>('pluralkit_uuid'),
        coFronterIdsRaw: r.read<String?>('co_fronter_ids') ?? '[]',
        sessionType: r.read<int>('session_type'),
        quality: r.read<int?>('quality'),
        isHealthKitImport: r.read<bool>('is_health_kit_import'),
      );
    }).toList();
  }

  Future<List<_LegacyComment>> _readAllComments() async {
    final rows = await db
        .customSelect(
          'SELECT id, session_id, body, timestamp, created_at '
          'FROM front_session_comments WHERE is_deleted = 0',
        )
        .get();
    return rows
        .map((r) => _LegacyComment(
              id: r.read<String>('id'),
              sessionId: r.read<String?>('session_id') ?? '',
              body: r.read<String>('body'),
              timestamp: r.read<DateTime>('timestamp'),
              createdAt: r.read<DateTime>('created_at'),
            ))
        .toList();
  }

  Future<Set<String>> _readSpSessionIds() async {
    final rows = await db
        .customSelect(
          "SELECT prism_id FROM sp_id_map WHERE entity_type = 'session'",
        )
        .get();
    return rows.map((r) => r.read<String>('prism_id')).toSet();
  }

  List<_ClassifiedSession> _classify(
    List<FrontingSessionRow> rows,
    Set<String> spSessionIds,
  ) {
    return [
      for (final r in rows)
        _ClassifiedSession(
          r,
          _classifyOne(r, spSessionIds),
        ),
    ];
  }

  _SessionKind _classifyOne(
    FrontingSessionRow r,
    Set<String> spSessionIds,
  ) {
    if (r.pluralkitUuid != null && r.pluralkitUuid!.isNotEmpty) {
      return _SessionKind.pkImported;
    }
    if (spSessionIds.contains(r.id)) return _SessionKind.spImported;
    if (r.sessionType == SessionType.sleep.index) {
      return _SessionKind.nativeSleep;
    }
    return _SessionKind.nativeNormal;
  }

  FrontingSession _rowToDomain(FrontingSessionRow r) {
    return FrontingSession(
      id: r.id,
      startTime: r.startTime,
      endTime: r.endTime,
      memberId: r.memberId,
      notes: r.notes,
      confidence: _intToConfidence(r.confidence),
      pluralkitUuid: r.pluralkitUuid,
      sessionType: r.sessionType == SessionType.sleep.index
          ? SessionType.sleep
          : SessionType.normal,
      quality: r.quality != null &&
              r.quality! >= 0 &&
              r.quality! < SleepQuality.values.length
          ? SleepQuality.values[r.quality!]
          : null,
      isHealthKitImport: r.isHealthKitImport,
    );
  }

  FrontConfidence? _intToConfidence(int? v) {
    if (v == null) return null;
    if (v < 0 || v >= FrontConfidence.values.length) return null;
    return FrontConfidence.values[v];
  }
}

class _LegacyComment {
  const _LegacyComment({
    required this.id,
    required this.sessionId,
    required this.body,
    required this.timestamp,
    required this.createdAt,
  });

  final String id;
  final String sessionId; // legacy FK; may be empty for already-migrated rows
  final String body;
  final DateTime timestamp;
  final DateTime createdAt;
}

class _MigrationCounters {
  _MigrationCounters({
    this.pkRowsDeleted = 0,
  });

  int spRowsMigrated = 0;
  int nativeRowsMigrated = 0;
  int nativeRowsExpanded = 0;
  int pkRowsDeleted;
  int commentsMigrated = 0;
  int commentsDeleted = 0;
  int orphanRowsAssignedToSentinel = 0;
  bool unknownSentinelCreated = false;
  final List<String> corruptCoFronterRowIds = <String>[];
}
