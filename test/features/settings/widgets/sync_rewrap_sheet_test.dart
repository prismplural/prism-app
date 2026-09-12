import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/settings/providers/reset_data_provider.dart';
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

class _FakeResetDataNotifier extends ResetDataNotifier {
  ResetCategory? lastCategory;

  @override
  Future<void> reset(ResetCategory category) async {
    lastCategory = category;
  }
}

const _validMnemonic =
    'abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon about';
const _replacementMnemonic =
    'legal winner thank year wave sausage worth useful legal winner thank yellow';

Widget _buildSheet({
  SyncHealthNotifier? healthNotifier,
  ResetDataNotifier? resetNotifier,
}) {
  return ProviderScope(
    overrides: [
      syncHealthProvider.overrideWith(
        () => healthNotifier ?? _FakeSyncHealthNotifier(),
      ),
      if (resetNotifier != null)
        resetDataNotifierProvider.overrideWith(() => resetNotifier),
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
  setUp(() {
    SyncRewrapSheet.debugGenerateSecretKeyOverride = null;
  });

  tearDown(() {
    SyncRewrapSheet.debugGenerateSecretKeyOverride = null;
  });

  group('SyncRewrapSheet', () {
    testWidgets('shows recovery title on mnemonic step', (tester) async {
      _useTallViewport(tester);

      await tester.pumpWidget(_buildSheet());
      await tester.pumpAndSettle();

      expect(find.text('Restore your pairing key'), findsOneWidget);
      expect(find.byType(SecureScope), findsOneWidget);
    });

    testWidgets('can disconnect stale sync state while keeping local data', (
      tester,
    ) async {
      _useTallViewport(tester);
      final resetNotifier = _FakeResetDataNotifier();

      await tester.pumpWidget(_buildSheet(resetNotifier: resetNotifier));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Disconnect Sync, Keep Data'));
      await tester.pumpAndSettle();

      expect(find.text('Disconnect sync from this device?'), findsOneWidget);
      expect(
        find.textContaining('keep all local data on this device'),
        findsOneWidget,
      );

      await tester.tap(find.text('Disconnect Sync, Keep Data').last);
      await tester.pumpAndSettle();

      expect(resetNotifier.lastCategory, ResetCategory.sync);
      expect(find.byType(SyncRewrapSheet), findsNothing);
    });

    testWidgets('cancel keeps recovery open without resetting sync', (
      tester,
    ) async {
      _useTallViewport(tester);
      final resetNotifier = _FakeResetDataNotifier();

      await tester.pumpWidget(_buildSheet(resetNotifier: resetNotifier));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Disconnect Sync, Keep Data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(resetNotifier.lastCategory, isNull);
      expect(find.byType(SyncRewrapSheet), findsOneWidget);
    });

    testWidgets(
      'lost phrase generates, saves, and rewraps with a replacement',
      (tester) async {
        _useTallViewport(tester);
        final notifier = _FakeSyncHealthNotifier(rewrapResult: true);
        SyncRewrapSheet.debugGenerateSecretKeyOverride = () async =>
            _replacementMnemonic;

        await tester.pumpWidget(_buildSheet(healthNotifier: notifier));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Lost your phrase?'));
        await tester.pumpAndSettle();

        expect(find.text('Save your recovery phrase'), findsOneWidget);
        expect(find.text('1. legal'), findsOneWidget);
        expect(find.text('12. yellow'), findsOneWidget);

        final showQr = find.text('Show QR Code');
        await tester.ensureVisible(showQr);
        await tester.tap(showQr);
        await tester.pumpAndSettle();

        final savedCheckbox = find.text('I have saved my Secret Key');
        await tester.ensureVisible(savedCheckbox);
        await tester.tap(savedCheckbox);
        await tester.pumpAndSettle();

        final continueButton = find.widgetWithText(PrismButton, 'Continue');
        await tester.ensureVisible(continueButton);
        await tester.tap(continueButton);
        await tester.pumpAndSettle();
        await _tapPin(tester, '123456');
        await tester.pumpAndSettle();

        expect(find.text('Confirm PIN'), findsOneWidget);
        expect(notifier.lastPin, isNull);

        await _tapPin(tester, '123456');
        await tester.pumpAndSettle();

        expect(notifier.lastPin, '123456');
        expect(notifier.lastMnemonic, _replacementMnemonic);
        expect(find.byType(SyncRewrapSheet), findsNothing);
      },
    );

    testWidgets('advances to PIN step after valid mnemonic', (tester) async {
      _useTallViewport(tester);

      await tester.pumpWidget(_buildSheet());
      await tester.pumpAndSettle();

      await _advancePastMnemonicStep(tester);

      // Step 2: PIN subtitle should be visible.
      expect(
        find.textContaining('Enter your PIN to finish restoring'),
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

        expect(find.text('Confirm PIN'), findsOneWidget);
        expect(notifier.lastPin, isNull);

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

        expect(find.text('Confirm PIN'), findsOneWidget);
        expect(notifier.lastPin, isNull);

        await _tapPin(tester, '000000');
        await tester.pumpAndSettle();

        expect(notifier.lastPin, '000000');
        expect(
          find.text(
            "Couldn't save the restored pairing key. Please try again.",
          ),
          findsOneWidget,
        );
        // Sheet still present.
        expect(find.byType(SyncRewrapSheet), findsOneWidget);
      },
    );

    testWidgets('mismatched confirmation never attempts a rewrap', (
      tester,
    ) async {
      _useTallViewport(tester);
      final notifier = _FakeSyncHealthNotifier(rewrapResult: true);

      await tester.pumpWidget(_buildSheet(healthNotifier: notifier));
      await tester.pumpAndSettle();

      await _advancePastMnemonicStep(tester);
      await _tapPin(tester, '123456');
      await tester.pumpAndSettle();
      await _tapPin(tester, '123457');
      await tester.pumpAndSettle();

      expect(notifier.lastPin, isNull);
      expect(find.text("PINs don't match."), findsOneWidget);
      expect(find.byType(SyncRewrapSheet), findsOneWidget);

      await _tapPin(tester, '654321');
      await tester.pumpAndSettle();
      expect(find.text('Confirm PIN'), findsOneWidget);
      expect(notifier.lastPin, isNull);
    });
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
