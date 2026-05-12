import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/settings/widgets/sync_rewrap_sheet.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/secure_scope.dart';

// ---------------------------------------------------------------------------
// Fake SyncHealthNotifier that records rewrap calls.
// ---------------------------------------------------------------------------

class _FakeSyncHealthNotifier extends SyncHealthNotifier {
  bool rewrapResult;
  String? lastPin;
  String? lastMnemonic;
  _FakeSyncHealthNotifier({this.rewrapResult = true});

  @override
  SyncHealthState build() => SyncHealthState.needsRewrap;

  @override
  Future<bool> attemptRewrap({
    required String pin,
    required String mnemonic,
  }) async {
    lastPin = pin;
    lastMnemonic = mnemonic;
    return rewrapResult;
  }
}

const _validMnemonic =
    'abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon about';

Widget _buildSheet({SyncHealthNotifier? healthNotifier}) {
  return ProviderScope(
    overrides: [
      syncHealthProvider.overrideWith(
        () => healthNotifier ?? _FakeSyncHealthNotifier(),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Navigator(
          onGenerateRoute: (_) =>
              MaterialPageRoute(builder: (_) => const SyncRewrapSheet()),
        ),
      ),
    ),
  );
}

void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _advancePastMnemonicStep(WidgetTester tester) async {
  final words = _validMnemonic.split(' ');
  for (var i = 0; i < 12; i++) {
    await tester.enterText(find.byType(TextField).at(i), words[i]);
    await tester.pump();
  }
  await tester.pumpAndSettle();
  final continueButton = find.widgetWithText(PrismButton, 'Continue');
  await tester.ensureVisible(continueButton);
  await tester.pumpAndSettle();
  await tester.tap(continueButton);
  await tester.pumpAndSettle();
}

Future<void> _tapPin(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.tap(find.text(digit).first);
    await tester.pump();
  }
}

void main() {
  group('SyncRewrapSheet', () {
    testWidgets('shows recovery title on mnemonic step', (tester) async {
      _useTallViewport(tester);

      await tester.pumpWidget(_buildSheet());
      await tester.pumpAndSettle();

      expect(find.text('Restore your pairing key'), findsOneWidget);
      expect(find.byType(SecureScope), findsOneWidget);
    });

    testWidgets('advances to PIN step after valid mnemonic', (tester) async {
      _useTallViewport(tester);

      await tester.pumpWidget(_buildSheet());
      await tester.pumpAndSettle();

      await _advancePastMnemonicStep(tester);

      // Step 2: PIN subtitle should be visible.
      expect(
        find.textContaining(
          'Enter your PIN to finish restoring',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'success path: calls attemptRewrap with pin+mnemonic and dismisses',
      (tester) async {
        _useTallViewport(tester);
        final notifier = _FakeSyncHealthNotifier(rewrapResult: true);

        await tester.pumpWidget(_buildSheet(healthNotifier: notifier));
        await tester.pumpAndSettle();

        await _advancePastMnemonicStep(tester);
        await _tapPin(tester, '123456');
        await tester.pumpAndSettle();

        expect(notifier.lastPin, '123456');
        expect(notifier.lastMnemonic, _validMnemonic);
        // Sheet should be popped — no SyncRewrapSheet on the tree anymore.
        expect(find.byType(SyncRewrapSheet), findsNothing);
      },
    );

    testWidgets(
      'failure path: shows generic error message and stays on PIN step',
      (tester) async {
        _useTallViewport(tester);
        final notifier = _FakeSyncHealthNotifier(rewrapResult: false);

        await tester.pumpWidget(_buildSheet(healthNotifier: notifier));
        await tester.pumpAndSettle();

        await _advancePastMnemonicStep(tester);
        await _tapPin(tester, '000000');
        await tester.pumpAndSettle();

        expect(notifier.lastPin, '000000');
        expect(find.text('Incorrect PIN or recovery phrase.'), findsOneWidget);
        // Sheet still present.
        expect(find.byType(SyncRewrapSheet), findsOneWidget);
      },
    );
  });

  group('AppShell listener pattern', () {
    test('syncRewrapSheetVisibleProvider starts false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(syncRewrapSheetVisibleProvider), isFalse);
    });

    test('syncRewrapSheetVisibleProvider tracks setValue updates', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(syncRewrapSheetVisibleProvider.notifier).setValue(true);
      expect(container.read(syncRewrapSheetVisibleProvider), isTrue);

      container.read(syncRewrapSheetVisibleProvider.notifier).setValue(false);
      expect(container.read(syncRewrapSheetVisibleProvider), isFalse);
    });
  });
}
