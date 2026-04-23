import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_group_repair_provider.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_group_reset_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_group_repair_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/pluralkit/views/pluralkit_setup_screen.dart';
import 'package:prism_plurality/features/pluralkit/widgets/pk_group_repair_card.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

import '../../../helpers/fake_repositories.dart';

class _StaticPluralKitSyncNotifier extends PluralKitSyncNotifier {
  _StaticPluralKitSyncNotifier(this._state);

  final PluralKitSyncState _state;

  @override
  PluralKitSyncState build() => _state;

  @override
  Future<void> performFullImport() async {}
}

class _StaticPkGroupRepairController extends PkGroupRepairController {
  _StaticPkGroupRepairController(this._state);

  final PkGroupRepairState _state;

  @override
  Future<PkGroupRepairState> build() async => _state;
}

class _StaticPkSyncDirectionNotifier extends PkSyncDirectionNotifier {
  @override
  PkSyncDirection build() => PkSyncDirection.pullOnly;
}

class _TrackingSystemSettingsRepository extends FakeSystemSettingsRepository {
  int updatePkGroupSyncV2EnabledCallCount = 0;
  Object? enableError;

  @override
  Future<void> updatePkGroupSyncV2Enabled(bool value) async {
    updatePkGroupSyncV2EnabledCallCount += 1;
    final error = enableError;
    if (error != null) {
      throw error;
    }
    await super.updatePkGroupSyncV2Enabled(value);
  }
}

class _TrackingPkGroupResetService implements PkGroupResetService {
  int resetCallCount = 0;
  Object? resetError;
  PkGroupResetResult result = const PkGroupResetResult(groupsReset: 2);

  @override
  Future<PkGroupResetResult> resetPkGroupsOnly() async {
    resetCallCount += 1;
    final error = resetError;
    if (error != null) {
      throw error;
    }
    return result;
  }
}

const _completedRepairReport = PkGroupRepairReport(
  referenceMode: PkGroupRepairReferenceMode.storedToken,
  backfilledEntries: 0,
  canonicalizedEntryIds: 0,
  revivedTombstonesDuringCanonicalization: 0,
  legacyEntriesSoftDeletedDuringCanonicalization: 0,
  duplicateSetsMerged: 0,
  duplicateGroupsSoftDeleted: 0,
  parentReferencesRehomed: 0,
  entriesRehomed: 0,
  entryConflictsSoftDeleted: 0,
  aliasesRecorded: 0,
  ambiguousGroupsSuppressed: 0,
  pendingReviewCount: 0,
);

Widget _buildScreen({
  required _TrackingSystemSettingsRepository settingsRepository,
  required PkGroupRepairState repairState,
  required Stream<SystemSettings> settingsStream,
  _TrackingPkGroupResetService? resetService,
  bool hasStoredToken = true,
  PluralKitSyncState syncState = const PluralKitSyncState(),
}) {
  return ProviderScope(
    overrides: [
      systemSettingsRepositoryProvider.overrideWithValue(settingsRepository),
      systemSettingsProvider.overrideWith((ref) => settingsStream),
      pluralKitSyncProvider.overrideWith(
        () => _StaticPluralKitSyncNotifier(syncState),
      ),
      pkSyncDirectionProvider.overrideWith(_StaticPkSyncDirectionNotifier.new),
      pkGroupRepairControllerProvider.overrideWith(
        () => _StaticPkGroupRepairController(repairState),
      ),
      pkGroupRepairHasStoredTokenProvider.overrideWith(
        (ref) async => hasStoredToken,
      ),
      pkGroupRepairBootstrapProvider.overrideWith((ref) => null),
      pkGroupResetServiceProvider.overrideWithValue(
        resetService ?? _TrackingPkGroupResetService(),
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
  required _TrackingSystemSettingsRepository settingsRepository,
  required PkGroupRepairState repairState,
  required Stream<SystemSettings> settingsStream,
  _TrackingPkGroupResetService? resetService,
  bool hasStoredToken = true,
  PluralKitSyncState syncState = const PluralKitSyncState(),
}) async {
  await tester.pumpWidget(
    _buildScreen(
      settingsRepository: settingsRepository,
      repairState: repairState,
      settingsStream: settingsStream,
      resetService: resetService,
      hasStoredToken: hasStoredToken,
      syncState: syncState,
    ),
  );
  await tester.pump();
}

Future<void> _invokeEnableCallback(WidgetTester tester) async {
  final card = tester.widget<PkGroupRepairCard>(find.byType(PkGroupRepairCard));
  await card.onEnablePkGroupSyncV2();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _invokeResetCallback(WidgetTester tester) async {
  final card = tester.widget<PkGroupRepairCard>(find.byType(PkGroupRepairCard));
  await card.onResetPkGroupsOnly();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _dismissToast(WidgetTester tester) async {
  PrismToast.dismiss();
  await tester.pump();
}

void main() {
  tearDown(PrismToast.resetForTest);

  group('PluralKitSetupScreen PK group sync v2 cutover', () {
    testWidgets('shows an error when shared settings are still loading', (
      tester,
    ) async {
      final settingsRepository = _TrackingSystemSettingsRepository();
      final settingsController = StreamController<SystemSettings>();
      addTearDown(settingsController.close);

      await _pumpScreen(
        tester,
        settingsRepository: settingsRepository,
        repairState: const PkGroupRepairState(
          lastReport: _completedRepairReport,
        ),
        settingsStream: settingsController.stream,
      );

      await _invokeEnableCallback(tester);

      expect(
        find.text(
          'Could not verify the shared cutover setting yet. Wait for repair '
          'status to finish loading and try again.',
        ),
        findsOneWidget,
      );
      expect(settingsRepository.updatePkGroupSyncV2EnabledCallCount, 0);
      await _dismissToast(tester);
    });

    testWidgets('requires a repair run before enabling PK group sync v2', (
      tester,
    ) async {
      final settingsRepository = _TrackingSystemSettingsRepository()
        ..settings = const SystemSettings(pkGroupSyncV2Enabled: false);

      await _pumpScreen(
        tester,
        settingsRepository: settingsRepository,
        repairState: const PkGroupRepairState(),
        settingsStream: Stream.value(settingsRepository.settings),
      );

      await _invokeEnableCallback(tester);

      expect(
        find.text(
          'Run PluralKit group repair first. PK group sync v2 stays off until '
          'this client completes a repair pass.',
        ),
        findsOneWidget,
      );
      expect(settingsRepository.updatePkGroupSyncV2EnabledCallCount, 0);
      await _dismissToast(tester);
    });

    testWidgets('blocks cutover while pending review items remain', (
      tester,
    ) async {
      final settingsRepository = _TrackingSystemSettingsRepository()
        ..settings = const SystemSettings(pkGroupSyncV2Enabled: false);

      await _pumpScreen(
        tester,
        settingsRepository: settingsRepository,
        repairState: const PkGroupRepairState(
          pendingReviewCount: 2,
          lastReport: _completedRepairReport,
        ),
        settingsStream: Stream.value(settingsRepository.settings),
      );

      await _invokeEnableCallback(tester);

      expect(
        find.text(
          'Resolve or keep local-only the 2 pending review items before '
          'enabling PK group sync v2.',
        ),
        findsOneWidget,
      );
      expect(settingsRepository.updatePkGroupSyncV2EnabledCallCount, 0);
      await _dismissToast(tester);
    });

    testWidgets('reports when PK group sync v2 is already enabled', (
      tester,
    ) async {
      final settingsRepository = _TrackingSystemSettingsRepository()
        ..settings = const SystemSettings(pkGroupSyncV2Enabled: true);

      await _pumpScreen(
        tester,
        settingsRepository: settingsRepository,
        repairState: const PkGroupRepairState(
          lastReport: _completedRepairReport,
        ),
        settingsStream: Stream.value(settingsRepository.settings),
      );

      await _invokeEnableCallback(tester);

      expect(
        find.text('PK group sync v2 is already enabled for this sync group.'),
        findsOneWidget,
      );
      expect(settingsRepository.updatePkGroupSyncV2EnabledCallCount, 0);
      await _dismissToast(tester);
    });

    testWidgets('enables PK group sync v2 after explicit confirmation', (
      tester,
    ) async {
      final settingsRepository = _TrackingSystemSettingsRepository()
        ..settings = const SystemSettings(pkGroupSyncV2Enabled: false);

      await _pumpScreen(
        tester,
        settingsRepository: settingsRepository,
        repairState: const PkGroupRepairState(
          lastReport: _completedRepairReport,
        ),
        settingsStream: Stream.value(settingsRepository.settings),
      );

      await tester.ensureVisible(find.text('Enable PK group sync'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enable PK group sync'));
      await tester.pumpAndSettle();

      expect(find.text('Enable PK sync v2?'), findsOneWidget);

      await tester.tap(find.text('Enable PK sync v2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(settingsRepository.updatePkGroupSyncV2EnabledCallCount, 1);
      expect(settingsRepository.settings.pkGroupSyncV2Enabled, isTrue);
      expect(
        find.text(
          'PK group sync v2 enabled for this sync group. Manual/local-only '
          'groups are unchanged.',
        ),
        findsOneWidget,
      );
      await _dismissToast(tester);
    });

    testWidgets('shows an error toast when enabling PK group sync v2 fails', (
      tester,
    ) async {
      final settingsRepository = _TrackingSystemSettingsRepository()
        ..settings = const SystemSettings(pkGroupSyncV2Enabled: false)
        ..enableError = Exception('write failed');

      await _pumpScreen(
        tester,
        settingsRepository: settingsRepository,
        repairState: const PkGroupRepairState(
          lastReport: _completedRepairReport,
        ),
        settingsStream: Stream.value(settingsRepository.settings),
      );

      await tester.ensureVisible(find.text('Enable PK group sync'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enable PK group sync'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enable PK sync v2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(settingsRepository.updatePkGroupSyncV2EnabledCallCount, 1);
      expect(settingsRepository.settings.pkGroupSyncV2Enabled, isFalse);
      expect(
        find.text('Could not enable PK group sync v2: write failed'),
        findsOneWidget,
      );
      await _dismissToast(tester);
    });

    testWidgets('resets PK groups and re-imports when still connected', (
      tester,
    ) async {
      final settingsRepository = _TrackingSystemSettingsRepository();
      final resetService = _TrackingPkGroupResetService()
        ..result = const PkGroupResetResult(
          groupsReset: 2,
          promotedChildGroups: 1,
          deferredOpsCleared: 3,
        );

      await _pumpScreen(
        tester,
        settingsRepository: settingsRepository,
        repairState: const PkGroupRepairState(
          pendingReviewCount: 1,
          pendingReviewItems: [
            PkGroupReviewItem(
              groupId: 'group-1',
              name: 'Suppressed Copy',
              suspectedPkGroupUuid: 'pk-group-1',
              syncSuppressed: true,
            ),
          ],
          lastReport: _completedRepairReport,
        ),
        settingsStream: Stream.value(settingsRepository.settings),
        resetService: resetService,
        syncState: const PluralKitSyncState(isConnected: true),
      );

      await _invokeResetCallback(tester);

      expect(resetService.resetCallCount, 1);
      expect(
        find.text(
          'PK group reset finished. Removed 2 PK-backed or suppressed '
          'groups, promoted 1 local child group to root, and cleared 3 '
          'deferred PK membership ops. Current PK groups were re-imported.',
        ),
        findsOneWidget,
      );
      await _dismissToast(tester);
    });

    testWidgets('shows an error toast when PK group reset fails', (
      tester,
    ) async {
      final settingsRepository = _TrackingSystemSettingsRepository();
      final resetService = _TrackingPkGroupResetService()
        ..resetError = Exception('reset failed');

      await _pumpScreen(
        tester,
        settingsRepository: settingsRepository,
        repairState: const PkGroupRepairState(
          pendingReviewCount: 1,
          pendingReviewItems: [
            PkGroupReviewItem(
              groupId: 'group-1',
              name: 'Suppressed Copy',
              suspectedPkGroupUuid: 'pk-group-1',
              syncSuppressed: true,
            ),
          ],
        ),
        settingsStream: Stream.value(settingsRepository.settings),
        resetService: resetService,
      );

      await _invokeResetCallback(tester);

      expect(resetService.resetCallCount, 1);
      expect(
        find.text('Could not reset PK groups: reset failed'),
        findsOneWidget,
      );
      await _dismissToast(tester);
    });
  });
}
