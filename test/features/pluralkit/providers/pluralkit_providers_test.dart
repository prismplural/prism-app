import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/pluralkit_sync_dao.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/features/fronting/migration/fronting_migration_service.dart';
import 'package:prism_plurality/features/fronting/migration/providers/fronting_migration_providers.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_file_parser.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

void _installSecureStorageStub() {
  final store = <String, String?>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (MethodCall call) async {
          switch (call.method) {
            case 'write':
              store[call.arguments['key'] as String] =
                  call.arguments['value'] as String?;
              return null;
            case 'read':
              return store[call.arguments['key'] as String];
            case 'delete':
              store.remove(call.arguments['key'] as String);
              return null;
            case 'containsKey':
              return store.containsKey(call.arguments['key'] as String);
            default:
              return null;
          }
        },
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'pkSyncDirectionNotifier.setDirection includes every member field',
    () async {
      _installSecureStorageStub();
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final dao = PluralKitSyncDao(db);

      final container = ProviderContainer(
        overrides: [pluralKitSyncDaoProvider.overrideWithValue(dao)],
      );
      addTearDown(container.dispose);

      // Trigger build (which async-loads existing state), then wait for the
      // load to finish by hitting the DAO ourselves first. getSyncState
      // inserts the default row, so calling it up front dodges the race
      // between build's `_loadDirection` and our `setDirection` both trying
      // to insert the seed row concurrently.
      await dao.getSyncState();
      container.read(pkSyncDirectionProvider);

      await container
          .read(pkSyncDirectionProvider.notifier)
          .setDirection(PkSyncDirection.pushOnly);

      final row = await dao.getSyncState();
      final config = parseFieldSyncConfig(row.fieldSyncConfig);
      final global = config['__global__'];
      expect(
        global,
        isNotNull,
        reason: 'setDirection must persist a __global__ config entry',
      );

      // Every field — including displayName and birthday — must reflect the
      // user's chosen direction. Before the fix both silently fell back to
      // `bidirectional`.
      expect(global!.name, PkSyncDirection.pushOnly);
      expect(global.displayName, PkSyncDirection.pushOnly);
      expect(global.pronouns, PkSyncDirection.pushOnly);
      expect(global.description, PkSyncDirection.pushOnly);
      expect(global.color, PkSyncDirection.pushOnly);
      expect(global.birthday, PkSyncDirection.pushOnly);
      expect(global.proxyTags, PkSyncDirection.pushOnly);
    },
  );

  // ──────────────────────────────────────────────────────────────────────────
  // WS1 step 4 + 5: PluralKitSyncNotifier consumes
  // `frontingMigrationWritesBlockedProvider`. While the per-member fronting
  // migration is `blocked` or `inProgress`, every fronting-shape pull/push
  // surface must short-circuit before the underlying service runs.
  //
  // Push surfaces return 0 (fire-and-forget callers); pull surfaces throw
  // a typed [PkSyncMigrationGatedException] (always user-initiated).
  // ──────────────────────────────────────────────────────────────────────────
  group('PluralKitSyncNotifier — fronting migration gate', () {
    Future<void> settle() async {
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    }

    Future<({ProviderContainer container, _ThrowingPkSyncService service})>
    primedContainer(
      String mode, {
      PluralKitSyncState initialServiceState = const PluralKitSyncState(),
    }) async {
      final controller = StreamController<String>.broadcast();
      addTearDown(controller.close);
      final service = _ThrowingPkSyncService()..fakeState = initialServiceState;
      final container = ProviderContainer(
        overrides: [
          pluralKitSyncServiceProvider.overrideWithValue(service),
          frontingMigrationModeProvider.overrideWith(
            (ref) => controller.stream,
          ),
        ],
      );
      addTearDown(container.dispose);
      // Subscribe so the stream actually emits — see the
      // `FrontingMigrationGateProvider` group in upgrade_modal_test for why
      // a bare `read` won't deliver the first event.
      final sub = container.listen(frontingMigrationModeProvider, (_, _) {});
      addTearDown(sub.close);
      controller.add(mode);
      await settle();
      return (container: container, service: service);
    }

    test('pushPendingSwitches returns 0 while blocked without touching the '
        'service', () async {
      // Drive the notifier into "would otherwise push" — connected + no
      // pending mapping. If the gate doesn't fire, the service stub will
      // throw and surface a UnimplementedError.
      final ctx = await primedContainer(
        FrontingMigrationService.modeBlocked,
        initialServiceState: const PluralKitSyncState(isConnected: true),
      );
      final notifier = ctx.container.read(pluralKitSyncProvider.notifier);
      final pushed = await notifier.pushPendingSwitches();
      expect(pushed, 0);
      expect(
        ctx.service.pushPendingCalls,
        0,
        reason: 'gate must short-circuit before _service is called',
      );
    });

    test('pushPendingSwitches returns 0 while inProgress', () async {
      final ctx = await primedContainer(
        FrontingMigrationService.modeInProgress,
        initialServiceState: const PluralKitSyncState(isConnected: true),
      );
      final notifier = ctx.container.read(pluralKitSyncProvider.notifier);
      final pushed = await notifier.pushPendingSwitches();
      expect(pushed, 0);
      expect(ctx.service.pushPendingCalls, 0);
    });

    test('syncRecentData returns null while blocked', () async {
      final ctx = await primedContainer(FrontingMigrationService.modeBlocked);
      final notifier = ctx.container.read(pluralKitSyncProvider.notifier);
      final summary = await notifier.syncRecentData();
      expect(summary, isNull);
      expect(ctx.service.syncRecentCalls, 0);
    });

    test('pushMemberUpdate is a no-op while blocked', () async {
      final ctx = await primedContainer(
        FrontingMigrationService.modeBlocked,
        initialServiceState: const PluralKitSyncState(isConnected: true),
      );
      final notifier = ctx.container.read(pluralKitSyncProvider.notifier);
      final member = domain.Member(
        id: 'm-1',
        name: 'Ada',
        emoji: '✨',
        isActive: true,
        createdAt: DateTime.utc(2026, 4, 30),
        displayOrder: 0,
        isAdmin: false,
        customColorEnabled: false,
        pluralkitId: 'abcde',
      );
      await notifier.pushMemberUpdate(member);
      expect(ctx.service.pushMemberCalls, 0);
    });

    test('performFullImport throws PkSyncMigrationGatedException while '
        'blocked', () async {
      final ctx = await primedContainer(FrontingMigrationService.modeBlocked);
      final notifier = ctx.container.read(pluralKitSyncProvider.notifier);
      await expectLater(
        notifier.performFullImport(),
        throwsA(isA<PkSyncMigrationGatedException>()),
      );
      expect(ctx.service.fullImportCalls, 0);
    });

    test('performOneTimeFullImport throws PkSyncMigrationGatedException '
        'while inProgress', () async {
      final ctx = await primedContainer(
        FrontingMigrationService.modeInProgress,
      );
      final notifier = ctx.container.read(pluralKitSyncProvider.notifier);
      await expectLater(
        notifier.performOneTimeFullImport(token: 'tok'),
        throwsA(isA<PkSyncMigrationGatedException>()),
      );
      expect(ctx.service.oneTimeImportCalls, 0);
    });

    test('performOneTimeFullImport with explicit token throws '
        'PkSyncMigrationGatedException while blocked', () async {
      final ctx = await primedContainer(FrontingMigrationService.modeBlocked);
      final notifier = ctx.container.read(pluralKitSyncProvider.notifier);
      await expectLater(
        notifier.performOneTimeFullImport(token: 'tok'),
        throwsA(isA<PkSyncMigrationGatedException>()),
      );
      expect(ctx.service.oneTimeImportCalls, 0);
    });

    test('importFromFile throws PkSyncMigrationGatedException while '
        'blocked', () async {
      final ctx = await primedContainer(FrontingMigrationService.modeBlocked);
      final notifier = ctx.container.read(pluralKitSyncProvider.notifier);
      const fakeExport = PkFileExport(
        system: PKSystem(id: 'sys-1'),
        members: [],
        groups: [],
        switches: [],
      );
      await expectLater(
        notifier.importFromFile(fakeExport),
        throwsA(isA<PkSyncMigrationGatedException>()),
      );
      expect(ctx.service.fileImportCalls, 0);
    });

    test('complete mode does not gate (control)', () async {
      final ctx = await primedContainer(
        FrontingMigrationService.modeComplete,
        initialServiceState: const PluralKitSyncState(isConnected: true),
      );
      // pushPendingSwitches reaches `_service.pushPendingSwitches`; the
      // stub returns 7 deliberately so we can distinguish "gate fired"
      // (returns 0) from "gate cleared, service ran" (returns 7).
      ctx.service.pushReturn = 7;
      final notifier = ctx.container.read(pluralKitSyncProvider.notifier);
      final pushed = await notifier.pushPendingSwitches();
      expect(pushed, 7);
      expect(ctx.service.pushPendingCalls, 1);
    });
  });
}

/// Minimal PluralKitSyncService stand-in. Only counts calls and returns
/// pre-seeded values; everything else throws via [noSuchMethod] so any
/// untested path fails loudly. The notifier's `build()` calls
/// `loadState()` which we make a no-op.
class _ThrowingPkSyncService implements PluralKitSyncService {
  PluralKitSyncState fakeState = const PluralKitSyncState();
  int pushPendingCalls = 0;
  int pushMemberCalls = 0;
  int syncRecentCalls = 0;
  int fullImportCalls = 0;
  int oneTimeImportCalls = 0;
  int fileImportCalls = 0;
  int pushReturn = 0;

  @override
  PluralKitSyncState get state => fakeState;

  @override
  set onStateChanged(SyncStateCallback? cb) {}

  @override
  Future<void> loadState() async {}

  @override
  Future<PkPushSwitchesResult> pushPendingSwitches({
    Object? pushService,
    void Function(String message)? onStaleLink,
  }) async {
    pushPendingCalls++;
    return PkPushSwitchesResult(pushed: pushReturn);
  }

  @override
  Future<bool> pushMemberUpdate(
    domain.Member member, {
    Object? pushService,
  }) async {
    pushMemberCalls++;
    return false;
  }

  @override
  Future<PkSyncSummary?> syncRecentData({
    bool isManual = false,
    PkSyncDirection direction = PkSyncDirection.pullOnly,
  }) async {
    syncRecentCalls++;
    return null;
  }

  @override
  Future<void> performFullImport() async {
    fullImportCalls++;
  }

  @override
  Future<PkTokenImportResult> performOneTimeFullImport({String? token}) async {
    oneTimeImportCalls++;
    throw UnimplementedError('not used in gate tests');
  }

  @override
  Future<PkFileImportResult> importFromFile(
    PkFileExport export, {
    void Function(double progress, String status)? onProgress,
  }) async {
    fileImportCalls++;
    throw UnimplementedError('not used in gate tests');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unexpected call to ${invocation.memberName}');
}
