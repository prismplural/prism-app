import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

// ---------------------------------------------------------------------------
// Sync service provider (singleton)
// ---------------------------------------------------------------------------

final pluralKitSyncServiceProvider = Provider<PluralKitSyncService>((ref) {
  return PluralKitSyncService(
    memberRepository: ref.watch(memberRepositoryProvider),
    frontingSessionRepository: ref.watch(frontingSessionRepositoryProvider),
    syncDao: ref.watch(pluralKitSyncDaoProvider),
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
      state = globalConfig.name; // We reuse the 'name' field for global direction
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

  Future<void> performFullImport() => _service.performFullImport();

  Future<PkSyncSummary?> syncRecentData({
    bool isManual = false,
    PkSyncDirection direction = PkSyncDirection.pullOnly,
  }) =>
      _service.syncRecentData(isManual: isManual, direction: direction);
}

final pluralKitSyncProvider =
    NotifierProvider<PluralKitSyncNotifier, PluralKitSyncState>(
  PluralKitSyncNotifier.new,
);

// Auto-push-current-front-as-switch was removed in Phase 3 — it created
// duplicate PK switches on every session change because the returned PK
// switch ID was never stored. Phase 4's scoped switch push replaces it
// (post-link-date sessions only, with endTime-aware switch-out).
