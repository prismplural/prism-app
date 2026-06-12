import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/pluralkit_sync_dao.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/features/fronting/migration/fronting_migration_service.dart';
import 'package:prism_plurality/features/fronting/migration/providers/fronting_migration_providers.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_file_parser.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_push_service.dart';
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
      final decoded = jsonDecode(row.fieldSyncConfig!) as Map<String, dynamic>;
      final global = PkFieldSyncConfig.fromJson(
        decoded['__global__'] as Map<String, dynamic>,
      );
      expect(
        global,
        isNotNull,
        reason: 'setDirection must persist a __global__ config entry',
      );

      // Every field — including displayName and birthday — must reflect the
      // user's chosen direction. Before the fix both silently fell back to
      // `bidirectional`.
      expect(global.name, PkSyncDirection.pushOnly);
      expect(global.displayName, PkSyncDirection.pushOnly);
      expect(global.pronouns, PkSyncDirection.pushOnly);
      expect(global.description, PkSyncDirection.pushOnly);
      expect(global.color, PkSyncDirection.pushOnly);
      expect(global.birthday, PkSyncDirection.pushOnly);
      expect(global.proxyTags, PkSyncDirection.pushOnly);
    },
  );

  group('PkSyncModeNotifier', () {
    Future<({ProviderContainer container, PluralKitSyncDao dao})>
    modeContainer({String? fieldSyncConfig}) async {
      _installSecureStorageStub();
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final dao = PluralKitSyncDao(db);
      await dao.getSyncState();
      if (fieldSyncConfig != null) {
        await dao.upsertSyncState(
          PluralKitSyncStateCompanion(
            id: const drift.Value('pk_config'),
            fieldSyncConfig: drift.Value(fieldSyncConfig),
          ),
        );
      }
      final container = ProviderContainer(
        overrides: [pluralKitSyncDaoProvider.overrideWithValue(dao)],
      );
      addTearDown(container.dispose);
      return (container: container, dao: dao);
    }

    Future<void> settle() async {
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    }

    test('defaults to fullSync with no persisted mode', () async {
      final ctx = await modeContainer();

      expect(ctx.container.read(pkSyncModeProvider), PkSyncMode.fullSync);
      await settle();
      expect(ctx.container.read(pkSyncModeProvider), PkSyncMode.fullSync);
    });

    test('malformed persisted mode defaults to fullSync', () async {
      final ctx = await modeContainer(
        fieldSyncConfig: jsonEncode({
          '__mode__': {'bad': true},
        }),
      );

      expect(ctx.container.read(pkSyncModeProvider), PkSyncMode.fullSync);
      await settle();
      expect(ctx.container.read(pkSyncModeProvider), PkSyncMode.fullSync);
    });

    test('loads and persists liveFrontsOnly under __mode__', () async {
      final ctx = await modeContainer();

      await ctx.container
          .read(pkSyncModeProvider.notifier)
          .setMode(PkSyncMode.liveFrontsOnly);

      final row = await ctx.dao.getSyncState();
      final decoded = jsonDecode(row.fieldSyncConfig!) as Map<String, dynamic>;
      expect(decoded['__mode__'], 'liveFrontsOnly');
      expect(parsePkSyncMode(row.fieldSyncConfig), PkSyncMode.liveFrontsOnly);
      expect(ctx.container.read(pkSyncModeProvider), PkSyncMode.liveFrontsOnly);
    });

    test('setMode preserves existing global direction', () async {
      final ctx = await modeContainer(
        fieldSyncConfig: serializeFieldSyncConfigWithGlobalDirection(
          null,
          PkSyncDirection.pushOnly,
        ),
      );

      await ctx.container
          .read(pkSyncModeProvider.notifier)
          .setMode(PkSyncMode.liveFrontsOnly);

      final row = await ctx.dao.getSyncState();
      expect(parsePkSyncMode(row.fieldSyncConfig), PkSyncMode.liveFrontsOnly);
      expect(
        parseGlobalSyncDirection(row.fieldSyncConfig),
        PkSyncDirection.pushOnly,
      );
    });

    test('setDirection preserves existing mode', () async {
      final ctx = await modeContainer(
        fieldSyncConfig: serializeFieldSyncConfigWithMode(
          null,
          PkSyncMode.liveFrontsOnly,
        ),
      );
      ctx.container.read(pkSyncDirectionProvider);

      await ctx.container
          .read(pkSyncDirectionProvider.notifier)
          .setDirection(PkSyncDirection.bidirectional);

      final row = await ctx.dao.getSyncState();
      expect(parsePkSyncMode(row.fieldSyncConfig), PkSyncMode.liveFrontsOnly);
      expect(
        parseGlobalSyncDirection(row.fieldSyncConfig),
        PkSyncDirection.bidirectional,
      );
    });
  });

  group('PkSleepSyncBehaviorNotifier', () {
    Future<({ProviderContainer container, PluralKitSyncDao dao})>
    sleepContainer({String? fieldSyncConfig}) async {
      _installSecureStorageStub();
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final dao = PluralKitSyncDao(db);
      await dao.getSyncState();
      if (fieldSyncConfig != null) {
        await dao.upsertSyncState(
          PluralKitSyncStateCompanion(
            id: const drift.Value('pk_config'),
            fieldSyncConfig: drift.Value(fieldSyncConfig),
          ),
        );
      }
      final container = ProviderContainer(
        overrides: [pluralKitSyncDaoProvider.overrideWithValue(dao)],
      );
      addTearDown(container.dispose);
      return (container: container, dao: dao);
    }

    Future<void> settle() async {
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    }

    test('defaults to clearFronters with no persisted behavior', () async {
      final ctx = await sleepContainer();

      expect(
        ctx.container.read(pkSleepSyncBehaviorProvider),
        PkSleepSyncBehavior.clearFronters,
      );
      await settle();
      expect(
        ctx.container.read(pkSleepSyncBehaviorProvider),
        PkSleepSyncBehavior.clearFronters,
      );
    });

    test('loads and persists leaveUnchanged under reserved metadata', () async {
      final ctx = await sleepContainer();

      await ctx.container
          .read(pkSleepSyncBehaviorProvider.notifier)
          .setBehavior(PkSleepSyncBehavior.leaveUnchanged);

      final row = await ctx.dao.getSyncState();
      final decoded = jsonDecode(row.fieldSyncConfig!) as Map<String, dynamic>;
      expect(decoded['__sleep_sync_behavior__'], 'leaveUnchanged');
      expect(
        parsePkSleepSyncBehavior(row.fieldSyncConfig),
        PkSleepSyncBehavior.leaveUnchanged,
      );
      expect(
        ctx.container.read(pkSleepSyncBehaviorProvider),
        PkSleepSyncBehavior.leaveUnchanged,
      );
    });

    test('setBehavior preserves direction and mode', () async {
      final withDirection = serializeFieldSyncConfigWithGlobalDirection(
        null,
        PkSyncDirection.pushOnly,
      );
      final withMode = serializeFieldSyncConfigWithMode(
        withDirection,
        PkSyncMode.liveFrontsOnly,
      );
      final ctx = await sleepContainer(fieldSyncConfig: withMode);

      await ctx.container
          .read(pkSleepSyncBehaviorProvider.notifier)
          .setBehavior(PkSleepSyncBehavior.leaveUnchanged);

      final row = await ctx.dao.getSyncState();
      expect(
        parsePkSleepSyncBehavior(row.fieldSyncConfig),
        PkSleepSyncBehavior.leaveUnchanged,
      );
      expect(parsePkSyncMode(row.fieldSyncConfig), PkSyncMode.liveFrontsOnly);
      expect(
        parseGlobalSyncDirection(row.fieldSyncConfig),
        PkSyncDirection.pushOnly,
      );
    });
  });

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
      PkSyncMode? syncMode,
      PkSyncDirection? syncDirection,
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
          if (syncMode != null)
            pkSyncModeProvider.overrideWith(
              () => _StaticPkSyncModeNotifier(syncMode),
            ),
          pkSyncDirectionProvider.overrideWith(
            () => _StaticPkSyncDirectionNotifier(
              syncDirection ?? PkSyncDirection.bidirectional,
            ),
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

    test('pushPendingSwitches returns 0 in pullOnly direction', () async {
      final ctx = await primedContainer(
        FrontingMigrationService.modeComplete,
        initialServiceState: const PluralKitSyncState(isConnected: true),
        syncDirection: PkSyncDirection.pullOnly,
      );
      final notifier = ctx.container.read(pluralKitSyncProvider.notifier);
      final pushed = await notifier.pushPendingSwitches();
      expect(pushed, 0);
      expect(ctx.service.pushPendingCalls, 0);
    });

    test('pushPendingSwitches returns 0 when sync is disabled', () async {
      final ctx = await primedContainer(
        FrontingMigrationService.modeComplete,
        initialServiceState: const PluralKitSyncState(isConnected: true),
        syncDirection: PkSyncDirection.disabled,
      );
      final notifier = ctx.container.read(pluralKitSyncProvider.notifier);
      final pushed = await notifier.pushPendingSwitches();
      expect(pushed, 0);
      expect(ctx.service.pushPendingCalls, 0);
    });

    test('pushPendingSwitches delegates in pushOnly direction', () async {
      final ctx = await primedContainer(
        FrontingMigrationService.modeComplete,
        initialServiceState: const PluralKitSyncState(
          isConnected: true,
          directionConfirmed: true,
          mappingAcknowledged: true,
        ),
        syncDirection: PkSyncDirection.pushOnly,
      );
      ctx.service.pushReturn = 3;
      final notifier = ctx.container.read(pluralKitSyncProvider.notifier);
      final pushed = await notifier.pushPendingSwitches();
      expect(pushed, 3);
      expect(ctx.service.pushPendingCalls, 1);
    });

    test('previewPendingDestructivePush returns empty while blocked without '
        'touching the service', () async {
      final ctx = await primedContainer(
        FrontingMigrationService.modeBlocked,
        initialServiceState: const PluralKitSyncState(isConnected: true),
      );
      final notifier = ctx.container.read(pluralKitSyncProvider.notifier);
      final preview = await notifier.previewPendingDestructivePush();
      expect(preview.totalToRemove, 0);
      expect(preview.totalSkipped, 0);
      expect(ctx.service.previewCalls, 0);
    });

    test(
      'previewPendingDestructivePush returns empty while disconnected',
      () async {
        final ctx = await primedContainer(
          FrontingMigrationService.modeComplete,
          initialServiceState: const PluralKitSyncState(isConnected: false),
        );
        final notifier = ctx.container.read(pluralKitSyncProvider.notifier);
        final preview = await notifier.previewPendingDestructivePush();
        expect(preview.totalToRemove, 0);
        expect(preview.totalSkipped, 0);
        expect(ctx.service.previewCalls, 0);
      },
    );

    test(
      'previewPendingDestructivePush returns empty while mapping is pending',
      () async {
        // needsMapping = isConnected && directionConfirmed && !mappingAcknowledged
        final ctx = await primedContainer(
          FrontingMigrationService.modeComplete,
          initialServiceState: const PluralKitSyncState(
            isConnected: true,
            directionConfirmed: true,
            mappingAcknowledged: false,
          ),
        );
        final notifier = ctx.container.read(pluralKitSyncProvider.notifier);
        final preview = await notifier.previewPendingDestructivePush();
        expect(preview.totalToRemove, 0);
        expect(preview.totalSkipped, 0);
        expect(ctx.service.previewCalls, 0);
      },
    );

    test(
      'previewPendingDestructivePush delegates and preserves errors',
      () async {
        final ctx = await primedContainer(
          FrontingMigrationService.modeComplete,
          initialServiceState: const PluralKitSyncState(
            isConnected: true,
            directionConfirmed: true,
            mappingAcknowledged: true,
          ),
        );
        ctx.service.previewError = StateError('preview failed');
        final notifier = ctx.container.read(pluralKitSyncProvider.notifier);

        await expectLater(
          notifier.previewPendingDestructivePush(),
          throwsA(isA<StateError>()),
        );
        expect(ctx.service.previewCalls, 1);
      },
    );

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

    test('pushMemberUpdate is a no-op in liveFrontsOnly mode', () async {
      final ctx = await primedContainer(
        FrontingMigrationService.modeComplete,
        initialServiceState: const PluralKitSyncState(isConnected: true),
        syncMode: PkSyncMode.liveFrontsOnly,
        syncDirection: PkSyncDirection.pushOnly,
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

    test('pushMemberUpdate is a no-op in pullOnly direction (2026-06 PK '
        'audit M11)', () async {
      final ctx = await primedContainer(
        FrontingMigrationService.modeComplete,
        initialServiceState: const PluralKitSyncState(
          isConnected: true,
          directionConfirmed: true,
          mappingAcknowledged: true,
        ),
        syncMode: PkSyncMode.fullSync,
        syncDirection: PkSyncDirection.pullOnly,
      );
      final notifier = ctx.container.read(pluralKitSyncProvider.notifier);
      final member = domain.Member(
        id: 'm-1',
        name: 'Ada',
        createdAt: DateTime.utc(2026, 4, 30),
        pluralkitId: 'abcde',
      );
      await notifier.pushMemberUpdate(member);
      expect(ctx.service.pushMemberCalls, 0);
    });

    test('pushMemberUpdate delegates to the service in a push-enabled '
        'direction (2026-06 PK audit M11)', () async {
      final ctx = await primedContainer(
        FrontingMigrationService.modeComplete,
        initialServiceState: const PluralKitSyncState(
          isConnected: true,
          directionConfirmed: true,
          mappingAcknowledged: true,
        ),
        syncMode: PkSyncMode.fullSync,
        syncDirection: PkSyncDirection.pushOnly,
      );
      final notifier = ctx.container.read(pluralKitSyncProvider.notifier);
      final member = domain.Member(
        id: 'm-1',
        name: 'Ada',
        createdAt: DateTime.utc(2026, 4, 30),
        pluralkitId: 'abcde',
      );
      await notifier.pushMemberUpdate(member);
      expect(ctx.service.pushMemberCalls, 1);
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
        initialServiceState: const PluralKitSyncState(
          isConnected: true,
          directionConfirmed: true,
          mappingAcknowledged: true,
        ),
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

  // ──────────────────────────────────────────────────────────────────────────
  // H10: `pluralKitSyncServiceProvider` must yield a STABLE service instance
  // across `prismSyncHandleProvider` transitions — the old `ref.watch` wiring
  // rebuilt the service mid-import (state reset, double delivery). New wiring
  // builds once and rebinds via `updateVolatileDependencies`.
  // ──────────────────────────────────────────────────────────────────────────
  group('H10: pluralKitSyncServiceProvider — handle-transition stability', () {
    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    ({ProviderContainer container, AppDatabase db}) makeContainer({
      ffi.PrismSyncHandle? initialHandle,
    }) {
      _installSecureStorageStub();
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          prismSyncHandleProvider.overrideWith(
            () => _StubSyncHandleNotifier(initialHandle),
          ),
        ],
      );
      addTearDown(container.dispose);
      return (container: container, db: db);
    }

    _StubSyncHandleNotifier stubOf(ProviderContainer container) =>
        container.read(prismSyncHandleProvider.notifier)
            as _StubSyncHandleNotifier;

    test(
        'service identity and an in-flight isSyncing claim survive a '
        'data→data handle transition (reqs a + b)', () async {
      final handleA = _FakeRustHandle();
      final h = makeContainer(initialHandle: handleA);
      await h.container.read(prismSyncHandleProvider.future);

      final service1 = h.container.read(pluralKitSyncServiceProvider);

      // Start a real file import. Its synchronous prefix claims isSyncing
      // BEFORE the first await suspends it (at the H8 linked-system DAO
      // read), so the claim is observable without any timing games.
      const export = PkFileExport(
        system: PKSystem(id: 'sysaa', name: 'Import System'),
        members: [
          PKMember(
            id: 'memaa',
            uuid: 'cccccccc-0000-0000-0000-000000000001',
            name: 'File Member',
          ),
        ],
        groups: [],
        switches: [],
      );
      final importFuture = service1.importFromFile(export);
      expect(service1.state.isSyncing, isTrue);

      // data→data transition mid-flight (handleA → null handle). The import
      // resumes AFTER the listener has rebound the repositories, so the
      // member writes go through the null-handle repos (no FFI in tests).
      // With the old ref.watch wiring this transition rebuilt the service
      // and wiped the claim while the old instance kept running.
      stubOf(h.container).emitHandle(null);

      final service2 = h.container.read(pluralKitSyncServiceProvider);
      expect(
        identical(service1, service2),
        isTrue,
        reason: 'H10 (a): the service instance must survive the transition',
      );
      expect(
        service2.state.isSyncing,
        isTrue,
        reason:
            'H10 (b): the in-flight isSyncing claim must not be wiped — the '
            'old rebuild let a second import start concurrently',
      );

      final result = await importFuture;
      expect(result.membersImported, 1);
      expect(service2.state.isSyncing, isFalse,
          reason: 'the import completed on the same instance');
    });

    test(
        'groups importer rebinds to the NEW handle without a service rebuild '
        '(req c)', () async {
      final handleA = _FakeRustHandle();
      final handleB = _FakeRustHandle();
      final h = makeContainer(initialHandle: handleA);
      await h.container.read(prismSyncHandleProvider.future);

      final service = h.container.read(pluralKitSyncServiceProvider);
      final importer1 = service.groupsImporterForTesting;
      expect(importer1, isNotNull);
      expect(importer1!.syncHandle, same(handleA),
          reason: 'initial importer bound to the boot handle');

      stubOf(h.container).emitHandle(handleB);

      expect(
        identical(h.container.read(pluralKitSyncServiceProvider), service),
        isTrue,
      );
      final importer2 = service.groupsImporterForTesting;
      expect(importer2, isNotNull);
      expect(
        identical(importer1, importer2),
        isFalse,
        reason: 'H10 (c): the importer must be rebuilt on transition',
      );
      expect(
        importer2!.syncHandle,
        same(handleB),
        reason:
            'H10 (c): group import after a reconfigure must use the NEW '
            'handle — a stale importer would emit ops into a dead session',
      );
    });

    test(
        'exactly one notifier delivery per service emit after a transition '
        '(req d)', () async {
      final h = makeContainer(initialHandle: null);
      await h.container.read(prismSyncHandleProvider.future);

      final deliveries = <PluralKitSyncState>[];
      h.container.listen(
        pluralKitSyncProvider,
        (prev, next) => deliveries.add(next),
      );
      // Build the notifier and let loadState's async emit settle.
      h.container.read(pluralKitSyncProvider);
      await settle();

      // A handle transition. Old code: this rebuilt the service while the
      // orphaned instance's onStateChanged closure stayed live — both
      // instances then emitted into the same notifier.
      stubOf(h.container).emitHandle(_FakeRustHandle());
      await settle();

      deliveries.clear();
      // One service emit: the empty-token path is a single synchronous
      // _emit with no I/O.
      await h.container.read(pluralKitSyncProvider.notifier).setToken('');
      await settle();

      expect(
        deliveries,
        hasLength(1),
        reason:
            'H10 (d): one emit must produce exactly one delivery — no '
            'double emission from an orphaned service instance',
      );
      expect(deliveries.single.syncError, contains('Token cannot be empty'));
    });
  });
}

class _StaticPkSyncModeNotifier extends PkSyncModeNotifier {
  _StaticPkSyncModeNotifier(this._mode);

  final PkSyncMode _mode;

  @override
  PkSyncMode build() => _mode;
}

class _StaticPkSyncDirectionNotifier extends PkSyncDirectionNotifier {
  _StaticPkSyncDirectionNotifier(this._direction);

  final PkSyncDirection _direction;

  @override
  PkSyncDirection build() => _direction;

  @override
  Future<void> load() async {
    state = _direction;
  }
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
  int previewCalls = 0;
  int pushReturn = 0;
  PkDeleteRiskPreview previewReturn = const PkDeleteRiskPreview();
  Object? previewError;

  @override
  PluralKitSyncState get state => fakeState;

  @override
  set onStateChanged(SyncStateCallback? cb) {}

  @override
  Future<void> loadState() async {}

  @override
  Future<PkPushSwitchesResult> pushPendingSwitches({
    PkPushService? pushService,
    void Function(String message)? onStaleLink,
    bool allowDuringSync = false,
    PKSwitch? knownCurrentFronters,
    bool refreshMembersOnStaleLink = true,
  }) async {
    pushPendingCalls++;
    return PkPushSwitchesResult(pushed: pushReturn);
  }

  @override
  Future<PkDeleteRiskPreview> previewPendingDestructivePush() async {
    previewCalls++;
    final error = previewError;
    if (error != null) throw error;
    return previewReturn;
  }

  @override
  Future<bool> pushMemberUpdate(
    domain.Member member, {
    PkPushService? pushService,
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

/// Distinguishable stand-in for the Rust FFI sync handle (H10 tests).
///
/// `ffi.PrismSyncHandle` is an empty opaque interface (`implements
/// RustOpaqueInterface`), so a fake only needs the dispose surface. No FFI
/// method ever runs against it in these tests: the repositories/importer
/// merely STORE the handle, and the one test that performs DB writes
/// transitions to a null handle before the writes resume.
class _FakeRustHandle implements ffi.PrismSyncHandle {
  bool _disposed = false;

  @override
  void dispose() => _disposed = true;

  @override
  bool get isDisposed => _disposed;
}

/// Drives `prismSyncHandleProvider` state transitions from tests without the
/// real notifier's secure-storage reads / handle construction.
class _StubSyncHandleNotifier extends PrismSyncHandleNotifier {
  _StubSyncHandleNotifier(this._initial);

  final ffi.PrismSyncHandle? _initial;

  @override
  Future<ffi.PrismSyncHandle?> build() async => _initial;

  /// Emit a new handle value — an AsyncData→AsyncData transition once the
  /// initial build has settled, exactly like a sync reconfigure in
  /// production.
  void emitHandle(ffi.PrismSyncHandle? handle) {
    state = AsyncData(handle);
  }
}
