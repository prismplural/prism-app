import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/database/database_encryption.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/fronting/migration/providers/fronting_migration_providers.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';
import 'package:prism_plurality/features/pluralkit/views/pluralkit_setup_screen.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

import '../../../helpers/fake_repositories.dart';

class _StaticPluralKitSyncNotifier extends PluralKitSyncNotifier {
  _StaticPluralKitSyncNotifier(
    this._state, {
    this.syncRecentDataCompleter,
    this.syncStateAfterManualSync,
    this.deleteRiskPreview = const PkDeleteRiskPreview(),
    this.deleteRiskPreviewError,
    this.setTokenSyncError,
  });

  final PluralKitSyncState _state;
  final Completer<PkSyncSummary?>? syncRecentDataCompleter;
  final PluralKitSyncState? syncStateAfterManualSync;
  final PkDeleteRiskPreview deleteRiskPreview;
  final Object? deleteRiskPreviewError;

  /// When non-null, setToken mimics the real service's failure contract:
  /// it leaves the connection state alone and surfaces this via
  /// `state.syncError` (the real service NEVER throws from setToken).
  final String? setTokenSyncError;
  int syncRecentDataCallCount = 0;
  int syncLiveFrontersOnlyCallCount = 0;
  int previewPendingDestructivePushCallCount = 0;
  int setTokenCallCount = 0;
  int fetchSystemProfileCallCount = 0;
  int adoptSystemProfileCallCount = 0;
  bool? lastManualSyncFlag;
  PkSyncDirection? lastSyncDirection;
  String? lastSetTokenArg;

  @override
  PluralKitSyncState build() => _state;

  @override
  Future<void> performFullImport() async {}

  @override
  Future<void> setToken(String token) async {
    setTokenCallCount += 1;
    lastSetTokenArg = token;
    final error = setTokenSyncError;
    if (error != null) {
      state = PluralKitSyncState(syncError: error);
      return;
    }
    state = const PluralKitSyncState(
      isConnected: true,
      directionConfirmed: true,
      mappingAcknowledged: true,
    );
  }

  @override
  Future<PKSystem?> fetchSystemProfile() async {
    fetchSystemProfileCallCount += 1;
    return const PKSystem(id: 'sys-1', name: 'PK System');
  }

  @override
  Future<void> adoptSystemProfile({
    required PKSystem pk,
    required Set<PkProfileField> accepted,
  }) async {
    adoptSystemProfileCallCount += 1;
  }

  @override
  Future<PkDeleteRiskPreview> previewPendingDestructivePush() async {
    previewPendingDestructivePushCallCount += 1;
    final error = deleteRiskPreviewError;
    if (error != null) throw error;
    return deleteRiskPreview;
  }

  @override
  Future<PkSyncSummary?> syncRecentData({
    bool isManual = false,
    PkSyncDirection direction = PkSyncDirection.pullOnly,
  }) {
    syncRecentDataCallCount += 1;
    lastManualSyncFlag = isManual;
    lastSyncDirection = direction;
    final completer = syncRecentDataCompleter;
    final nextState = syncStateAfterManualSync;
    if (completer != null) {
      return completer.future.then((summary) {
        if (nextState != null) state = nextState;
        return summary;
      });
    }
    if (nextState != null) state = nextState;
    return Future.value(null);
  }

  @override
  Future<PkSyncSummary?> syncLiveFrontersOnly({
    bool isManual = false,
    PkSyncDirection direction = PkSyncDirection.pullOnly,
    PKSwitch? knownCurrentFronters,
  }) async {
    syncLiveFrontersOnlyCallCount += 1;
    lastManualSyncFlag = isManual;
    lastSyncDirection = direction;
    final nextState = syncStateAfterManualSync;
    if (nextState != null) state = nextState;
    return null;
  }
}

class _StaticPkSyncDirectionNotifier extends PkSyncDirectionNotifier {
  _StaticPkSyncDirectionNotifier(this._initial);

  final PkSyncDirection _initial;

  @override
  PkSyncDirection build() => _initial;

  @override
  Future<void> load() async {
    state = _initial;
  }
}

class _StaticPkSyncModeNotifier extends PkSyncModeNotifier {
  _StaticPkSyncModeNotifier(this._initial);

  final PkSyncMode _initial;

  @override
  PkSyncMode build() => _initial;

  @override
  Future<void> load() async {
    state = _initial;
  }

  @override
  Future<void> setMode(PkSyncMode mode) async {
    state = mode;
  }
}

Widget _buildScreen({
  required FakeSystemSettingsRepository settingsRepository,
  required Stream<SystemSettings> settingsStream,
  PluralKitSyncState syncState = const PluralKitSyncState(),
  _StaticPluralKitSyncNotifier? syncNotifier,
  PkSyncMode syncMode = PkSyncMode.fullSync,
  PkSyncEventBus? bus,
  GoRouter? router,
  PkSyncDirection syncDirection = PkSyncDirection.pullOnly,
}) {
  final overrides = [
    // §4/§5 boot providers throw by default. Widget tests don't run the
    // boot probe, so we inject a fake 64-char hex key so any provider
    // chain that touches `databaseProvider` can mount.
    verifiedStartupKeyProvider.overrideWithValue('aa' * 32),
    systemSettingsRepositoryProvider.overrideWithValue(settingsRepository),
    systemSettingsProvider.overrideWith((ref) => settingsStream),
    pluralKitSyncProvider.overrideWith(
      () => syncNotifier ?? _StaticPluralKitSyncNotifier(syncState),
    ),
    pkSyncDirectionProvider.overrideWith(
      () => _StaticPkSyncDirectionNotifier(syncDirection),
    ),
    pkSyncModeProvider.overrideWith(() => _StaticPkSyncModeNotifier(syncMode)),
    if (bus != null) pkSyncEventBusProvider.overrideWithValue(bus),
    // Override the migration gate so the screen doesn't try to open a
    // Drift database stream (which leaks a pending timer in tests).
    frontingMigrationWritesBlockedProvider.overrideWithValue(false),
  ];

  if (router != null) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        routerConfig: router,
        builder: (context, child) =>
            PrismToastHost(child: child ?? const SizedBox.shrink()),
      ),
    );
  }

  return ProviderScope(
    overrides: overrides,
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: [Locale('en')],
      home: PrismToastHost(child: PluralKitSetupScreen()),
    ),
  );
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required FakeSystemSettingsRepository settingsRepository,
  required Stream<SystemSettings> settingsStream,
  PluralKitSyncState syncState = const PluralKitSyncState(),
  _StaticPluralKitSyncNotifier? syncNotifier,
  PkSyncMode syncMode = PkSyncMode.fullSync,
  PkSyncEventBus? bus,
  GoRouter? router,
  PkSyncDirection syncDirection = PkSyncDirection.pullOnly,
}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    _buildScreen(
      settingsRepository: settingsRepository,
      settingsStream: settingsStream,
      syncState: syncState,
      syncNotifier: syncNotifier,
      syncMode: syncMode,
      bus: bus,
      router: router,
      syncDirection: syncDirection,
    ),
  );
  await tester.pump();
}

void main() {
  setUp(markPkBusMainIsolate);
  tearDown(() {
    PrismToast.resetForTest();
    resetPkBusMainIsolateForTest();
  });

  group('PluralKitSetupScreen sync lifecycle', () {
    testWidgets('shows sync mode control and can switch modes', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final settingsRepository = FakeSystemSettingsRepository();
      await _pumpScreen(
        tester,
        settingsRepository: settingsRepository,
        settingsStream: Stream.value(settingsRepository.settings),
        syncState: const PluralKitSyncState(
          isConnected: true,
          directionConfirmed: true,
          mappingAcknowledged: true,
        ),
      );

      expect(find.text('Full Sync'), findsOneWidget);
      expect(find.text('Live Fronts Only'), findsOneWidget);
      expect(
        find.textContaining('Import and pk;export recovery still run'),
        findsOneWidget,
      );
      expect(find.text('PluralKit Group Repair'), findsNothing);
      expect(find.text('Enable PK group sync'), findsNothing);

      await tester.tap(find.text('Live Fronts Only'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text(
          'Records new PluralKit front changes while Prism is open. Older '
          'history, profile, group, and system data are left untouched.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('manual sync uses recent sync in full mode', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final settingsRepository = FakeSystemSettingsRepository();
      final syncNotifier = _StaticPluralKitSyncNotifier(
        const PluralKitSyncState(
          isConnected: true,
          directionConfirmed: true,
          mappingAcknowledged: true,
        ),
      );

      await _pumpScreen(
        tester,
        settingsRepository: settingsRepository,
        settingsStream: Stream.value(settingsRepository.settings),
        syncNotifier: syncNotifier,
      );

      await tester.tap(find.text('Sync Recent Changes'));
      await tester.pump();

      expect(syncNotifier.syncRecentDataCallCount, 1);
      expect(syncNotifier.syncLiveFrontersOnlyCallCount, 0);
      expect(syncNotifier.lastManualSyncFlag, isTrue);
      expect(syncNotifier.lastSyncDirection, PkSyncDirection.pullOnly);
    });

    testWidgets('manual sync uses live fronts method in live mode', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final settingsRepository = FakeSystemSettingsRepository();
      final syncNotifier = _StaticPluralKitSyncNotifier(
        const PluralKitSyncState(
          isConnected: true,
          directionConfirmed: true,
          mappingAcknowledged: true,
        ),
      );

      await _pumpScreen(
        tester,
        settingsRepository: settingsRepository,
        settingsStream: Stream.value(settingsRepository.settings),
        syncNotifier: syncNotifier,
        syncMode: PkSyncMode.liveFrontsOnly,
      );

      await tester.tap(find.text('Sync Recent Changes'));
      await tester.pump();

      expect(syncNotifier.syncLiveFrontersOnlyCallCount, 1);
      expect(syncNotifier.syncRecentDataCallCount, 0);
      expect(syncNotifier.lastManualSyncFlag, isTrue);
      expect(syncNotifier.lastSyncDirection, PkSyncDirection.pullOnly);
    });

    testWidgets(
      'bidirectional manual sync warns about significant pending deletes',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 2400));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final settingsRepository = FakeSystemSettingsRepository();
        final syncNotifier = _StaticPluralKitSyncNotifier(
          PluralKitSyncState(
            isConnected: true,
            directionConfirmed: true,
            mappingAcknowledged: true,
            lastSyncDate: DateTime(2024, 1, 1),
          ),
          deleteRiskPreview: const PkDeleteRiskPreview(membersToDelete: 1),
        );

        await _pumpScreen(
          tester,
          settingsRepository: settingsRepository,
          settingsStream: Stream.value(settingsRepository.settings),
          syncNotifier: syncNotifier,
          syncDirection: PkSyncDirection.bidirectional,
        );

        await tester.tap(find.text('Sync Recent Changes'));
        await tester.pumpAndSettle();

        expect(syncNotifier.previewPendingDestructivePushCallCount, 1);
        expect(find.text('Sync may delete PluralKit data'), findsOneWidget);

        await tester.tap(find.text('Cancel Sync'));
        await tester.pumpAndSettle();

        expect(syncNotifier.syncRecentDataCallCount, 0);
      },
    );

    testWidgets('confirmed delete-risk warning allows manual sync', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final settingsRepository = FakeSystemSettingsRepository();
      final syncNotifier = _StaticPluralKitSyncNotifier(
        PluralKitSyncState(
          isConnected: true,
          directionConfirmed: true,
          mappingAcknowledged: true,
          lastSyncDate: DateTime(2024, 1, 1),
        ),
        deleteRiskPreview: const PkDeleteRiskPreview(switchesToDelete: 10),
      );

      await _pumpScreen(
        tester,
        settingsRepository: settingsRepository,
        settingsStream: Stream.value(settingsRepository.settings),
        syncNotifier: syncNotifier,
        syncDirection: PkSyncDirection.bidirectional,
      );

      await tester.tap(find.text('Sync Recent Changes'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sync Anyway'));
      await tester.pumpAndSettle();

      expect(syncNotifier.previewPendingDestructivePushCallCount, 1);
      expect(syncNotifier.syncRecentDataCallCount, 1);
      expect(syncNotifier.lastSyncDirection, PkSyncDirection.bidirectional);
    });

    testWidgets('first bidirectional full sync does not preview deletes', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final settingsRepository = FakeSystemSettingsRepository();
      final syncNotifier = _StaticPluralKitSyncNotifier(
        const PluralKitSyncState(
          isConnected: true,
          directionConfirmed: true,
          mappingAcknowledged: true,
        ),
        deleteRiskPreview: const PkDeleteRiskPreview(membersToDelete: 1),
      );

      await _pumpScreen(
        tester,
        settingsRepository: settingsRepository,
        settingsStream: Stream.value(settingsRepository.settings),
        syncNotifier: syncNotifier,
        syncDirection: PkSyncDirection.bidirectional,
      );

      await tester.tap(find.text('Sync Recent Changes'));
      await tester.pumpAndSettle();

      expect(syncNotifier.previewPendingDestructivePushCallCount, 0);
      expect(syncNotifier.syncRecentDataCallCount, 1);
    });

    testWidgets('push-only full sync previews deletes before first sync', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final settingsRepository = FakeSystemSettingsRepository();
      final syncNotifier = _StaticPluralKitSyncNotifier(
        const PluralKitSyncState(
          isConnected: true,
          directionConfirmed: true,
          mappingAcknowledged: true,
        ),
        deleteRiskPreview: const PkDeleteRiskPreview(switchesToDelete: 1),
      );

      await _pumpScreen(
        tester,
        settingsRepository: settingsRepository,
        settingsStream: Stream.value(settingsRepository.settings),
        syncNotifier: syncNotifier,
        syncDirection: PkSyncDirection.pushOnly,
      );

      await tester.tap(find.text('Sync Recent Changes'));
      await tester.pumpAndSettle();

      expect(syncNotifier.previewPendingDestructivePushCallCount, 1);
      expect(find.text('Sync may delete PluralKit data'), findsNothing);
      expect(syncNotifier.syncRecentDataCallCount, 1);
      expect(syncNotifier.lastSyncDirection, PkSyncDirection.pushOnly);
    });

    testWidgets('live-fronts-only manual sync does not preview deletes', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final settingsRepository = FakeSystemSettingsRepository();
      final syncNotifier = _StaticPluralKitSyncNotifier(
        const PluralKitSyncState(
          isConnected: true,
          directionConfirmed: true,
          mappingAcknowledged: true,
        ),
        deleteRiskPreview: const PkDeleteRiskPreview(membersToDelete: 1),
      );

      await _pumpScreen(
        tester,
        settingsRepository: settingsRepository,
        settingsStream: Stream.value(settingsRepository.settings),
        syncNotifier: syncNotifier,
        syncMode: PkSyncMode.liveFrontsOnly,
        syncDirection: PkSyncDirection.pushOnly,
      );

      await tester.tap(find.text('Sync Recent Changes'));
      await tester.pumpAndSettle();

      expect(syncNotifier.previewPendingDestructivePushCallCount, 0);
      expect(syncNotifier.syncLiveFrontersOnlyCallCount, 1);
      expect(syncNotifier.syncRecentDataCallCount, 0);
    });

    testWidgets('delete-risk preview failure stops manual sync', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final settingsRepository = FakeSystemSettingsRepository();
      final syncNotifier = _StaticPluralKitSyncNotifier(
        PluralKitSyncState(
          isConnected: true,
          directionConfirmed: true,
          mappingAcknowledged: true,
          lastSyncDate: DateTime(2024, 1, 1),
        ),
        deleteRiskPreviewError: StateError('preview failed'),
      );

      await _pumpScreen(
        tester,
        settingsRepository: settingsRepository,
        settingsStream: Stream.value(settingsRepository.settings),
        syncNotifier: syncNotifier,
        syncDirection: PkSyncDirection.bidirectional,
      );

      await tester.tap(find.text('Sync Recent Changes'));
      await tester.pumpAndSettle();

      expect(syncNotifier.previewPendingDestructivePushCallCount, 1);
      expect(syncNotifier.syncRecentDataCallCount, 0);
      expect(
        find.textContaining("couldn't check whether this sync would delete"),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('live-fronts-only mode hides the full import action', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final settingsRepository = FakeSystemSettingsRepository();

      await _pumpScreen(
        tester,
        settingsRepository: settingsRepository,
        settingsStream: Stream.value(settingsRepository.settings),
        syncState: const PluralKitSyncState(
          isConnected: true,
          directionConfirmed: true,
          mappingAcknowledged: true,
        ),
        syncMode: PkSyncMode.liveFrontsOnly,
      );

      expect(find.text('Import from PluralKit'), findsNothing);
      expect(find.text('Sync Recent Changes'), findsOneWidget);
    });

    testWidgets('push-only connection does not offer profile import', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final settingsRepository = FakeSystemSettingsRepository();
      final syncNotifier = _StaticPluralKitSyncNotifier(
        const PluralKitSyncState(),
      );

      await _pumpScreen(
        tester,
        settingsRepository: settingsRepository,
        settingsStream: Stream.value(settingsRepository.settings),
        syncNotifier: syncNotifier,
        syncDirection: PkSyncDirection.pushOnly,
      );

      await tester.enterText(find.byType(TextField), 'pk-token');
      await tester.tap(find.text('Connect'));
      await tester.pump();
      await tester.pump();

      expect(syncNotifier.setTokenCallCount, 1);
      expect(syncNotifier.fetchSystemProfileCallCount, 0);
      expect(syncNotifier.adoptSystemProfileCallCount, 0);
    });

    testWidgets('does not throw when screen is disposed mid-syncRecent', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final settingsRepository = FakeSystemSettingsRepository();
      final syncCompleter = Completer<PkSyncSummary?>();
      final syncNotifier = _StaticPluralKitSyncNotifier(
        const PluralKitSyncState(
          isConnected: true,
          directionConfirmed: true,
          mappingAcknowledged: true,
        ),
        syncRecentDataCompleter: syncCompleter,
      );

      await _pumpScreen(
        tester,
        settingsRepository: settingsRepository,
        settingsStream: Stream.value(settingsRepository.settings),
        syncNotifier: syncNotifier,
      );
      await tester.pump();
      await tester.pump();

      final syncButton = find.text('Sync Recent Changes');
      expect(syncButton, findsOneWidget);
      await tester.tap(syncButton);
      await tester.pump();

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump();

      syncCompleter.complete(null);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'does not throw when disposed while sync cooldown timer is active',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 2400));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final settingsRepository = FakeSystemSettingsRepository();
        final syncNotifier = _StaticPluralKitSyncNotifier(
          const PluralKitSyncState(
          isConnected: true,
          directionConfirmed: true,
          mappingAcknowledged: true,
        ),
          syncStateAfterManualSync: PluralKitSyncState(
            isConnected: true,
            directionConfirmed: true,
            mappingAcknowledged: true,
            lastManualSyncDate: DateTime.now(),
          ),
        );

        await _pumpScreen(
          tester,
          settingsRepository: settingsRepository,
          settingsStream: Stream.value(settingsRepository.settings),
          syncNotifier: syncNotifier,
        );
        await tester.pump();
        await tester.pump();

        final syncButton = find.text('Sync Recent Changes');
        expect(syncButton, findsOneWidget);
        await tester.tap(syncButton);
        await tester.pump();
        await tester.pump();

        expect(find.textContaining('Sync Recent Changes ('), findsOneWidget);

        await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(tester.takeException(), isNull);
      },
    );
  });

  group('PluralKitSetupScreen sync activity log tile', () {
    testWidgets(
      'shows disabled tile with empty-state subtitle when log is empty',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 2400));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final settingsRepository = FakeSystemSettingsRepository();
        final capture = PkSyncEventBusCapture();

        await _pumpScreen(
          tester,
          settingsRepository: settingsRepository,
          settingsStream: Stream.value(settingsRepository.settings),
          syncState: const PluralKitSyncState(
          isConnected: true,
          directionConfirmed: true,
          mappingAcknowledged: true,
        ),
          bus: capture.bus,
        );

        await tester.scrollUntilVisible(
          find.text('Sync activity log'),
          300,
          scrollable: find.byType(Scrollable).first,
        );

        expect(find.text('Sync activity log'), findsOneWidget);
        expect(find.text('No events recorded yet'), findsOneWidget);
        expect(find.text('View recent PluralKit sync activity'), findsNothing);

        // Tile is disabled — tapping the title text should NOT navigate.
        await tester.tap(find.text('Sync activity log'));
        await tester.pump();

        // Still on the same screen — the PK sync debug screen would have a
        // top-bar title that doesn't appear yet.
        expect(find.text('Sync activity log'), findsOneWidget);
      },
    );

    testWidgets(
      'shows enabled tile with active subtitle when log has events; tap navigates',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 2400));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final settingsRepository = FakeSystemSettingsRepository();
        final bus = PkSyncEventBus();
        addTearDown(bus.dispose);

        // Router that mounts the PK setup screen at the same path the real
        // router uses ('/settings/pluralkit'), with the sync-debug subroute
        // registered. This lets us assert that tapping the tile navigates to
        // AppRoutePaths.settingsPluralkitSyncDebug.
        final router = GoRouter(
          initialLocation: '/settings/pluralkit',
          routes: [
            GoRoute(
              path: '/settings/pluralkit',
              builder: (_, _) => const PluralKitSetupScreen(),
              routes: [
                GoRoute(
                  path: 'sync-debug',
                  builder: (_, _) =>
                      const Scaffold(body: Text('pk-sync-debug-route')),
                ),
              ],
            ),
          ],
        );

        await _pumpScreen(
          tester,
          settingsRepository: settingsRepository,
          settingsStream: Stream.value(settingsRepository.settings),
          syncState: const PluralKitSyncState(
          isConnected: true,
          directionConfirmed: true,
          mappingAcknowledged: true,
        ),
          bus: bus,
          router: router,
        );
        // Emit one event so the log is non-empty and the tile flips to
        // enabled. We have to do this AFTER the screen mounts so the
        // notifier (kept alive by ref.watch in the tile) has a subscription.
        bus.emit(const PkTokenCleared());
        await tester.pump();
        await tester.pump();

        await tester.scrollUntilVisible(
          find.text('Sync activity log'),
          300,
          scrollable: find.byType(Scrollable).first,
        );

        expect(find.text('Sync activity log'), findsOneWidget);
        expect(
          find.text('View recent PluralKit sync activity'),
          findsOneWidget,
        );
        expect(find.text('No events recorded yet'), findsNothing);

        // Verify the route exists by tapping the tile.
        await tester.tap(find.text('Sync activity log'));
        await tester.pumpAndSettle();

        // We should have navigated to the sync-debug subroute. We assert on
        // the destination's rendered text rather than the router's currentUri:
        // go_router represents the matched URI as the parent route when the
        // subroute builder renders a child page, so the URI check is brittle.
        // The rendered text is the user-facing invariant we actually care
        // about.
        expect(find.text('pk-sync-debug-route'), findsOneWidget);
        expect(
          AppRoutePaths.settingsPluralkitSyncDebug,
          '/settings/pluralkit/sync-debug',
          reason: 'Route path constant should match the registered subroute.',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // 2026-06 PK audit low (wave 4): token paste robustness — strip ALL
  // whitespace (PDF/email copies inject internal newlines), soft-warn on
  // implausible length without blocking submit, and never clear the field
  // before the auth result is known (a 401 used to force a full re-paste).
  // ---------------------------------------------------------------------------

  group('PluralKitSetupScreen token paste robustness', () {
    testWidgets(
      'strips internal whitespace and newlines before setToken',
      (tester) async {
        final settingsRepository = FakeSystemSettingsRepository();
        final syncNotifier = _StaticPluralKitSyncNotifier(
          const PluralKitSyncState(),
        );

        await _pumpScreen(
          tester,
          settingsRepository: settingsRepository,
          settingsStream: Stream.value(settingsRepository.settings),
          syncNotifier: syncNotifier,
        );

        // A real-shaped 64-char token mangled the way PDF viewers and email
        // clients mangle copies: leading/trailing space, internal newlines,
        // tabs, and a CRLF.
        final core = 'a' * 64;
        final pasted =
            '  ${core.substring(0, 20)}\n${core.substring(20, 40)}\t\r\n'
            '${core.substring(40)}  ';
        await tester.enterText(find.byType(TextField), pasted);
        await tester.pump();
        await tester.tap(find.text('Connect'));
        await tester.pump();
        await tester.pump();

        expect(syncNotifier.setTokenCallCount, 1);
        expect(syncNotifier.lastSetTokenArg, core);
      },
    );

    testWidgets(
      'keeps the pasted token in the field when connect fails',
      (tester) async {
        final settingsRepository = FakeSystemSettingsRepository();
        final syncNotifier = _StaticPluralKitSyncNotifier(
          const PluralKitSyncState(),
          setTokenSyncError: 'Invalid token — please check and try again.',
        );

        await _pumpScreen(
          tester,
          settingsRepository: settingsRepository,
          settingsStream: Stream.value(settingsRepository.settings),
          syncNotifier: syncNotifier,
        );

        const pasted = 'not-the-right-token';
        await tester.enterText(find.byType(TextField), pasted);
        await tester.pump();
        await tester.tap(find.text('Connect'));
        await tester.pump();
        await tester.pump();

        expect(syncNotifier.setTokenCallCount, 1);
        // The field must NOT be wiped on failure — the user can fix a typo
        // instead of re-pasting from scratch.
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.controller!.text, pasted);
      },
    );

    testWidgets(
      'soft-warns on implausible token length but still allows submit',
      (tester) async {
        final settingsRepository = FakeSystemSettingsRepository();
        final syncNotifier = _StaticPluralKitSyncNotifier(
          const PluralKitSyncState(),
          setTokenSyncError: 'Invalid token — please check and try again.',
        );

        await _pumpScreen(
          tester,
          settingsRepository: settingsRepository,
          settingsStream: Stream.value(settingsRepository.settings),
          syncNotifier: syncNotifier,
        );

        // 11 chars (after stripping) → warning appears.
        await tester.enterText(find.byType(TextField), 'short-token');
        await tester.pump();
        expect(find.textContaining('expected 64'), findsOneWidget);

        // Warning is soft: Connect still submits.
        await tester.tap(find.text('Connect'));
        await tester.pump();
        await tester.pump();
        expect(syncNotifier.setTokenCallCount, 1);

        // A plausible 64-char token (even whitespace-mangled) clears the
        // warning — the check runs on the stripped form.
        await tester.enterText(
          find.byType(TextField),
          '${'b' * 32}\n${'b' * 32}',
        );
        await tester.pump();
        expect(find.textContaining('expected 64'), findsNothing);
      },
    );
  });
}
