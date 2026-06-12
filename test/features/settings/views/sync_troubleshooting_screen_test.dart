import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/settings/providers/reset_data_provider.dart';
import 'package:prism_plurality/features/settings/views/sync_troubleshooting_screen.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

void main() {
  Widget buildScreen({
    Locale locale = const Locale('en'),
    int quarantinedBatchCount = 0,
    int pendingOps = 0,
    bool resetThrows = false,
  }) {
    return ProviderScope(
      overrides: [
        relayUrlProvider.overrideWithValue(
          const AsyncValue<String?>.data('https://relay.example.com'),
        ),
        syncIdProvider.overrideWithValue(
          const AsyncValue<String?>.data('sync-123'),
        ),
        syncDeviceIdProvider.overrideWithValue(
          const AsyncValue<String?>.data('device-123'),
        ),
        syncDeviceSecretPresentProvider.overrideWithValue(
          const AsyncValue<bool>.data(true),
        ),
        syncStatusProvider.overrideWith(
          () => _StubSyncStatusNotifier(
            quarantinedBatchCount: quarantinedBatchCount,
            pendingOps: pendingOps,
          ),
        ),
        if (resetThrows)
          resetDataNotifierProvider.overrideWith(
            _ThrowingResetDataNotifier.new,
          ),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) =>
            PrismToastHost(child: child ?? const SizedBox.shrink()),
        home: const SyncTroubleshootingScreen(),
      ),
    );
  }

  testWidgets('reset sync failure shows an error toast', (tester) async {
    addTearDown(PrismToast.resetForTest);

    await tester.pumpWidget(buildScreen(resetThrows: true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reset sync').first);
    await tester.pumpAndSettle();

    expect(find.text('Reset sync setup?'), findsOneWidget);
    expect(find.text('Back up first'), findsOneWidget);

    await tester.tap(find.widgetWithText(PrismButton, 'Reset sync').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Prism sync failed:'), findsOneWidget);

    PrismToast.dismiss();
    await tester.pump();
  });

  testWidgets('renders activity items as compact detail rows', (tester) async {
    await tester.pumpWidget(buildScreen(pendingOps: 3));
    await tester.pumpAndSettle();

    await _scrollUntilVisible(tester, find.text('Activity'));

    expect(find.byType(Table), findsNothing);
    expect(find.text('Last successful sync'), findsOneWidget);
    expect(find.text('Never synced'), findsOneWidget);
    expect(find.text('Current sync state'), findsOneWidget);
    expect(find.text('Idle'), findsOneWidget);
    expect(find.text('Pending operations'), findsOneWidget);
    expect(find.text('3 ops waiting to sync'), findsOneWidget);
  });

  // ── Phase 1B: push-quarantine banner ──

  testWidgets('hides quarantine banner when count is zero', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    // Banner copy must not appear when nothing is quarantined.
    expect(find.textContaining('too large to sync'), findsNothing);
    expect(find.text('Repair stuck sync'), findsNothing);
  });

  testWidgets('shows quarantine banner with singular copy when count is 1', (
    tester,
  ) async {
    await tester.pumpWidget(buildScreen(quarantinedBatchCount: 1));
    await tester.pumpAndSettle();

    expect(find.text('1 item is too large to sync'), findsOneWidget);
    // Phase 1C banner body now points the user at the Repair button.
    expect(find.textContaining('Tap Repair stuck sync below'), findsOneWidget);
  });

  testWidgets('shows quarantine banner with plural copy when count > 1', (
    tester,
  ) async {
    await tester.pumpWidget(buildScreen(quarantinedBatchCount: 3));
    await tester.pumpAndSettle();

    expect(find.text('3 items are too large to sync'), findsOneWidget);
  });

  // ── Phase 1C: repair stuck sync ──

  testWidgets(
    'renders Repair stuck sync button when quarantinedBatchCount > 0',
    (tester) async {
      await tester.pumpWidget(buildScreen(quarantinedBatchCount: 2));
      await tester.pumpAndSettle();

      // Button label and description copy must be visible.
      expect(find.text('Repair stuck sync'), findsOneWidget);
      expect(
        find.textContaining('Splits the affected items into smaller chunks'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'tapping Repair stuck sync runs the repair function and shows success snackbar',
    (tester) async {
      // Inject a fake repair function that just returns a known count
      // without exercising the FFI.
      addTearDown(() {
        debugRepairQuarantinedBatchesOverride = null;
        PrismToast.resetForTest();
      });
      debugRepairQuarantinedBatchesOverride = () async => 7;

      await tester.pumpWidget(buildScreen(quarantinedBatchCount: 7));
      await tester.pumpAndSettle();

      final repairButton = find.widgetWithText(
        PrismButton,
        'Repair stuck sync',
      );
      await _scrollUntilVisible(tester, repairButton);
      await tester.tap(repairButton);
      // Pump enough frames for the override future to complete and the
      // snackbar to mount. Don't `pumpAndSettle` because the toast has
      // a 3-second auto-dismiss timer that would block forever; pump a
      // few short frames and assert the text is up.
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Repaired 7 items — sync resuming…'), findsOneWidget);

      // Dismiss the toast so the auto-dismiss timer doesn't outlive the
      // test and trip the binding's timersPending invariant.
      PrismToast.dismiss();
      await tester.pump();
    },
  );

  testWidgets(
    'tapping Repair stuck sync shows failure snackbar when the override throws',
    (tester) async {
      addTearDown(() {
        debugRepairQuarantinedBatchesOverride = null;
        PrismToast.resetForTest();
      });
      debugRepairQuarantinedBatchesOverride = () async {
        throw Exception('boom');
      };

      await tester.pumpWidget(buildScreen(quarantinedBatchCount: 1));
      await tester.pumpAndSettle();

      final repairButton = find.widgetWithText(
        PrismButton,
        'Repair stuck sync',
      );
      await _scrollUntilVisible(tester, repairButton);
      await tester.tap(repairButton);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('Repair failed:'), findsOneWidget);

      PrismToast.dismiss();
      await tester.pump();
    },
  );
}

Future<void> _scrollUntilVisible(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.drag(find.byType(Scrollable).first, const Offset(0, -160));
  await tester.pumpAndSettle();
}

class _StubSyncStatusNotifier extends SyncStatusNotifier {
  _StubSyncStatusNotifier({
    required this.quarantinedBatchCount,
    required this.pendingOps,
  });

  final int quarantinedBatchCount;
  final int pendingOps;

  @override
  SyncStatus build() {
    return SyncStatus(
      pendingOps: pendingOps,
      quarantinedBatchCount: quarantinedBatchCount,
    );
  }

  @override
  Future<void> refreshQuarantinedBatchCount() async {
    // No-op in tests: the override returns its own synthetic count.
  }
}

class _ThrowingResetDataNotifier extends ResetDataNotifier {
  @override
  Future<void> reset(ResetCategory category) async {
    throw StateError('reset failed');
  }
}
