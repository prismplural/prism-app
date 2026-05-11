import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
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
  });

  final PluralKitSyncState _state;
  final Completer<PkSyncSummary?>? syncRecentDataCompleter;
  final PluralKitSyncState? syncStateAfterManualSync;
  final PkDeleteRiskPreview deleteRiskPreview;
  final Object? deleteRiskPreviewError;
  int syncRecentDataCallCount = 0;
  int syncLiveFrontersOnlyCallCount = 0;
  int previewPendingDestructivePushCallCount = 0;
  int setTokenCallCount = 0;
  int fetchSystemProfileCallCount = 0;
  int adoptSystemProfileCallCount = 0;
  bool? lastManualSyncFlag;
  PkSyncDirection? lastSyncDirection;

  @override
  PluralKitSyncState build() => _state;

  @override
  Future<void> performFullImport() async {}

  @override
  Future<void> setToken(String token) async {
    setTokenCallCount += 1;
    state = const PluralKitSyncState(isConnected: true);
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
  PkSyncDirection syncDirection = PkSyncDirection.pullOnly,
}) {
  return ProviderScope(
    overrides: [
      systemSettingsRepositoryProvider.overrideWithValue(settingsRepository),
      systemSettingsProvider.overrideWith((ref) => settingsStream),
      pluralKitSyncProvider.overrideWith(
        () => syncNotifier ?? _StaticPluralKitSyncNotifier(syncState),
      ),
      pkSyncDirectionProvider.overrideWith(
        () => _StaticPkSyncDirectionNotifier(syncDirection),
      ),
      pkSyncModeProvider.overrideWith(
        () => _StaticPkSyncModeNotifier(syncMode),
      ),
    ],
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
      syncDirection: syncDirection,
    ),
  );
  await tester.pump();
}

void main() {
  tearDown(PrismToast.resetForTest);

  group('PluralKitSetupScreen sync lifecycle', () {
    testWidgets('shows sync mode control and can switch modes', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final settingsRepository = FakeSystemSettingsRepository();
      await _pumpScreen(
        tester,
        settingsRepository: settingsRepository,
        settingsStream: Stream.value(settingsRepository.settings),
        syncState: const PluralKitSyncState(isConnected: true),
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
        const PluralKitSyncState(isConnected: true),
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
        const PluralKitSyncState(isConnected: true),
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
        const PluralKitSyncState(isConnected: true),
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
        const PluralKitSyncState(isConnected: true),
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
        const PluralKitSyncState(isConnected: true),
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
        syncState: const PluralKitSyncState(isConnected: true),
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
        const PluralKitSyncState(isConnected: true),
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
          const PluralKitSyncState(isConnected: true),
          syncStateAfterManualSync: PluralKitSyncState(
            isConnected: true,
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
}
