import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/app_database.dart' hide Member;
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_file_parser.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_group_reset_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_groups_importer.dart';
import 'package:prism_plurality/features/fronting/migration/providers/fronting_migration_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

/// Thrown by [PluralKitSyncNotifier] surfaces when the per-member
/// fronting migration is `blocked` or `inProgress` and the requested
/// pull/push would write fronting rows in a transitional shape. UI
/// callers should treat this as "tell the user the migration modal is
/// the recovery surface" rather than a hard failure.
///
/// Push surfaces (e.g. `pushPendingSwitches`) opt to return 0 instead
/// of throwing because they're called fire-and-forget from listeners
/// and aren't user-initiated; pull surfaces throw because they're
/// always invoked from explicit user actions where a no-op would be
/// confusing.
class PkSyncMigrationGatedException implements Exception {
  const PkSyncMigrationGatedException();

  @override
  String toString() =>
      'PkSyncMigrationGatedException: PluralKit sync is paused while the '
      'per-member fronting migration is in progress or blocked.';
}

// ---------------------------------------------------------------------------
// Sync service provider (singleton)
// ---------------------------------------------------------------------------

final pluralKitSyncServiceProvider = Provider<PluralKitSyncService>((ref) {
  final db = ref.watch(databaseProvider);
  return PluralKitSyncService(
    memberRepository: ref.watch(memberRepositoryProvider),
    frontingSessionRepository: ref.watch(frontingSessionRepositoryProvider),
    syncDao: ref.watch(pluralKitSyncDaoProvider),
    settingsRepository: ref.watch(systemSettingsRepositoryProvider),
    groupsImporter: PkGroupsImporter(
      db: db,
      memberRepository: ref.watch(memberRepositoryProvider),
      syncHandle: ref.watch(prismSyncHandleProvider).value,
    ),
  );
});

final pkGroupResetServiceProvider = Provider<PkGroupResetService>((ref) {
  return PkGroupResetService(
    db: ref.watch(databaseProvider),
    memberGroupsRepository: ref.watch(memberGroupsRepositoryProvider),
  );
});

// ---------------------------------------------------------------------------
// Sync direction state
// ---------------------------------------------------------------------------

/// Persisted sync direction. Defaults to pullOnly for backward compatibility.
class PkSyncDirectionNotifier extends Notifier<PkSyncDirection> {
  @override
  PkSyncDirection build() {
    _loadDirection();
    return PkSyncDirection.pullOnly;
  }

  Future<void> _loadDirection() async {
    final syncDao = ref.read(pluralKitSyncDaoProvider);
    final row = await syncDao.getSyncState();
    final config = parseFieldSyncConfig(row.fieldSyncConfig);
    // The overall direction is stored under the '__global__' key
    final globalConfig = config['__global__'];
    if (globalConfig != null) {
      state =
          globalConfig.name; // We reuse the 'name' field for global direction
    }
  }

  Future<void> setDirection(PkSyncDirection direction) async {
    state = direction;
    // Persist to the fieldSyncConfig column
    final syncDao = ref.read(pluralKitSyncDaoProvider);
    final row = await syncDao.getSyncState();
    final config = parseFieldSyncConfig(row.fieldSyncConfig);
    config['__global__'] = PkFieldSyncConfig(
      name: direction,
      displayName: direction,
      pronouns: direction,
      description: direction,
      color: direction,
      birthday: direction,
      proxyTags: direction,
    );
    await syncDao.upsertSyncState(
      PluralKitSyncStateCompanion(
        id: const drift.Value('pk_config'),
        fieldSyncConfig: drift.Value(serializeFieldSyncConfig(config)),
      ),
    );
  }
}

final pkSyncDirectionProvider =
    NotifierProvider<PkSyncDirectionNotifier, PkSyncDirection>(
      PkSyncDirectionNotifier.new,
    );

// ---------------------------------------------------------------------------
// Last sync summary
// ---------------------------------------------------------------------------

class _PkLastSyncSummaryNotifier extends Notifier<PkSyncSummary?> {
  @override
  PkSyncSummary? build() => null;
  void set(PkSyncSummary? value) => state = value;
}

final pkLastSyncSummaryProvider =
    NotifierProvider<_PkLastSyncSummaryNotifier, PkSyncSummary?>(
      _PkLastSyncSummaryNotifier.new,
    );

// ---------------------------------------------------------------------------
// Sync state notifier
// ---------------------------------------------------------------------------

class PluralKitSyncNotifier extends Notifier<PluralKitSyncState> {
  late PluralKitSyncService _service;

  @override
  PluralKitSyncState build() {
    _service = ref.watch(pluralKitSyncServiceProvider);
    _service.onStateChanged = (newState) {
      state = newState;
    };
    // Kick off async load without blocking build
    _service.loadState();
    return _service.state;
  }

  Future<void> setToken(String token) => _service.setToken(token);
  Future<void> clearToken() => _service.clearToken();
  Future<bool> testConnection() => _service.testConnection();

  Future<(String? systemName, List<PKMember> pkMembers)> importMembersOnly() =>
      _service.importMembersOnly();

  Future<void> performFullImport() async {
    if (ref.read(frontingMigrationWritesBlockedProvider)) {
      // Pull writes new fronting rows; defer until the migration is
      // resolved. Same rationale as `pushPendingSwitches`.
      throw const PkSyncMigrationGatedException();
    }
    await _service.performFullImport();
  }

  Future<PkTokenImportResult> performOneTimeFullImport({String? token}) async {
    if (ref.read(frontingMigrationWritesBlockedProvider)) {
      throw const PkSyncMigrationGatedException();
    }
    return _service.performOneTimeFullImport(token: token);
  }

  Future<PkTokenImportResult> importFromTokenOnce(String token) async {
    if (ref.read(frontingMigrationWritesBlockedProvider)) {
      throw const PkSyncMigrationGatedException();
    }
    return _service.importFromTokenOnce(token);
  }

  Future<void> acknowledgeMapping() => _service.acknowledgeMapping();

  Future<bool> hasRepairToken({String? token}) =>
      _service.hasRepairToken(token: token);

  Future<PkFileImportResult> importFromFile(
    PkFileExport export, {
    void Function(double progress, String status)? onProgress,
  }) async {
    if (ref.read(frontingMigrationWritesBlockedProvider)) {
      throw const PkSyncMigrationGatedException();
    }
    return _service.importFromFile(export, onProgress: onProgress);
  }

  Future<PkFileTokenFrontingImportResult> importFromFileWithToken(
    PkFileExport export, {
    required String token,
    void Function(double progress, String status)? onProgress,
  }) async {
    if (ref.read(frontingMigrationWritesBlockedProvider)) {
      throw const PkSyncMigrationGatedException();
    }
    return _service.importFromFileWithToken(
      export,
      token: token,
      onProgress: onProgress,
    );
  }

  /// Push any locally-created fronting sessions to PluralKit. Safe to call
  /// on every front change: it no-ops when the service isn't connected /
  /// is mid-mapping, and deduplicates already-pushed sessions via
  /// `pluralkitUuid`.
  ///
  /// Hard-gated on the per-member fronting migration: while the migration
  /// is `blocked` or `inProgress`, fronting rows on disk may be in an
  /// intermediate shape (composite unique index missing, or new-shape
  /// rows without the post-tx sync state cutover). Pushing in that
  /// window risks creating PK switches that don't match the local truth
  /// after the migration finishes. Returns 0 silently — the upgrade
  /// modal is the user's recovery surface.
  Future<int> pushPendingSwitches() async {
    if (ref.read(frontingMigrationWritesBlockedProvider)) return 0;
    if (!state.isConnected || state.needsMapping) return 0;
    try {
      return await _service.pushPendingSwitches();
    } catch (_) {
      return 0;
    }
  }

  /// Push a single linked member's edits to PK. No-op when disconnected,
  /// mid-mapping, when the sync direction is pull-only, or when the member
  /// isn't linked. Safe to call from UI listeners — errors are swallowed.
  ///
  /// Migration-gated for the same reason as [pushPendingSwitches]: a
  /// member edit pushed while the migration is mid-flight could fix a
  /// PK row that the migration is about to delete (corrective import
  /// path) or that the user is about to re-classify.
  Future<void> pushMemberUpdate(Member member) async {
    if (ref.read(frontingMigrationWritesBlockedProvider)) return;
    if (!state.canAutoSync) return;
    if (!ref.read(pkSyncDirectionProvider).pushEnabled) return;
    if (member.pluralkitId == null || member.pluralkitId!.isEmpty) return;
    try {
      await _service.pushMemberUpdate(member);
    } catch (_) {}
  }

  Future<PkSyncSummary?> syncRecentData({
    bool isManual = false,
    PkSyncDirection direction = PkSyncDirection.pullOnly,
  }) {
    if (ref.read(frontingMigrationWritesBlockedProvider)) {
      // Polling for new switches while the local fronting tables are in
      // a transitional shape would write rows the migration intends to
      // overwrite. Skip silently and let the modal drive recovery.
      return Future.value(null);
    }
    return _service.syncRecentData(isManual: isManual, direction: direction);
  }

  Future<PKSystem?> fetchSystemProfile() => _service.fetchSystemProfile();

  Future<void> adoptSystemProfile({
    required PKSystem pk,
    required Set<PkProfileField> accepted,
  }) => _service.adoptSystemProfile(pk: pk, accepted: accepted);
}

final pluralKitSyncProvider =
    NotifierProvider<PluralKitSyncNotifier, PluralKitSyncState>(
      PluralKitSyncNotifier.new,
    );

// Auto-push-current-front-as-switch was removed in Phase 3 — it created
// duplicate PK switches on every session change because the returned PK
// switch ID was never stored. Phase 4's scoped switch push replaces it
// (post-link-date sessions only, with endTime-aware switch-out).
