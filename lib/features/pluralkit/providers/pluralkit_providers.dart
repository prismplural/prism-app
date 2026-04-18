import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart' as domain;
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_push_service.dart';
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
      pronouns: direction,
      description: direction,
      color: direction,
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

// ---------------------------------------------------------------------------
// Auto-push provider — watches fronting sessions and pushes new switches
// ---------------------------------------------------------------------------

/// Watches active fronting sessions and automatically pushes new switches
/// to PluralKit when the direction is pushOnly or bidirectional.
///
/// Debounced by 30 seconds to avoid spamming the PK API during rapid
/// front changes.
final pkAutoPushProvider = Provider<void>((ref) {
  final syncState = ref.watch(pluralKitSyncProvider);
  final direction = ref.watch(pkSyncDirectionProvider);

  // Only activate when PK is fully connected (mapping done) and push enabled.
  if (!syncState.canAutoSync || !direction.pushEnabled) return;

  Timer? debounce;
  ref.onDispose(() => debounce?.cancel());

  // Watch active sessions for changes
  ref.listen(activeSessionsProvider, (previous, next) {
    final prevSessions = previous?.value ?? [];
    final nextSessions = next.value ?? [];

    // Only push when sessions actually change
    if (_sessionListEquals(prevSessions, nextSessions)) return;

    debounce?.cancel();
    debounce = Timer(const Duration(seconds: 30), () async {
      try {
        final service = ref.read(pluralKitSyncServiceProvider);
        final client = await service.buildClientIfConnected();
        if (client == null) return;

        final memberRepo = ref.read(memberRepositoryProvider);
        final sessions = next.value ?? [];

        // Batch-fetch all members to avoid N+1 queries
        final allMembers = await memberRepo.getAllMembers();
        final memberById = {for (final m in allMembers) m.id: m};

        // Collect PK member IDs for current fronters
        final pkMemberIds = <String>[];
        for (final session in sessions) {
          if (session.memberId == null) continue;
          final member = memberById[session.memberId!];
          if (member?.pluralkitId != null) {
            pkMemberIds.add(member!.pluralkitId!);
          }
        }

        if (pkMemberIds.isNotEmpty) {
          final pushService = PkPushService();
          await pushService.pushSwitch(pkMemberIds, client);
        }

        client.dispose();
      } catch (_) {
        // Auto-push failures are silent — manual sync will surface errors
      }
    });
  });
});

bool _sessionListEquals(
  List<domain.FrontingSession> a,
  List<domain.FrontingSession> b,
) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].id != b[i].id) return false;
    if (a[i].memberId != b[i].memberId) return false;
  }
  return true;
}
