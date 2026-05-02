import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/sync/pairing_ceremony_api.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/settings/widgets/sync_pin_sheet.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/secure_scope.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

// ---------------------------------------------------------------------------
// Fake SyncHealthNotifier
// ---------------------------------------------------------------------------

class _FakeSyncHealthNotifier extends SyncHealthNotifier {
  bool unlockResult;
  String? lastPin;
  String? lastMnemonic;
  _FakeSyncHealthNotifier({this.unlockResult = false});

  @override
  SyncHealthState build() => SyncHealthState.needsPassword;

  @override
  Future<bool> attemptUnlock({
    required String pin,
    required String mnemonic,
  }) async {
    lastPin = pin;
    lastMnemonic = mnemonic;
    return unlockResult;
  }
}

// ---------------------------------------------------------------------------
// Fake PairingCeremonyApi — makes the mnemonic gate pass without FFI.
// ---------------------------------------------------------------------------

class _AcceptMnemonicApi extends PairingCeremonyApi {
  const _AcceptMnemonicApi();

  @override
  Future<String> startJoinerCeremony({required ffi.PrismSyncHandle handle}) =>
      throw UnimplementedError();

  @override
  Future<String> getJoinerSas({required ffi.PrismSyncHandle handle}) =>
      throw UnimplementedError();

  @override
  Future<void> cancelPairingCeremony({required ffi.PrismSyncHandle handle}) =>
      Future.value();

  @override
  Future<String> completeJoinerCeremony({
    required ffi.PrismSyncHandle handle,
    required List<int> password,
  }) => throw UnimplementedError();

  @override
  Future<String> startInitiatorCeremony({
    required ffi.PrismSyncHandle handle,
    required Uint8List tokenBytes,
  }) => throw UnimplementedError();

  @override
  Future<String> completeInitiatorCeremony({
    required ffi.PrismSyncHandle handle,
    required List<int> password,
    required List<int> mnemonic,
  }) => throw UnimplementedError();
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

const _prefsKeyAttempts = 'prism.sync_pin_failed_attempts';
const _prefsKeyLockedUntil = 'prism.sync_pin_locked_until_ms';

// A canonical BIP39 12-word mnemonic with a valid checksum.
const _validMnemonic =
    'abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon about';

Widget _buildSheet({SyncHealthNotifier? healthNotifier}) {
  return ProviderScope(
    overrides: [
      syncHealthProvider.overrideWith(
        () => healthNotifier ?? _FakeSyncHealthNotifier(unlockResult: false),
      ),
      pairingCeremonyApiProvider.overrideWith(
        (ref) => const _AcceptMnemonicApi(),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Navigator(
          onGenerateRoute: (_) =>
              MaterialPageRoute(builder: (_) => const SyncPinSheet()),
        ),
      ),
    ),
  );
}

/// Sets a phone-like viewport so the sheet's content all renders inside
/// the physical window. The default 800x600 test window is too short to
/// accommodate both the mnemonic chip grid and the numpad.
void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Drives the sheet past the mnemonic step: types a valid phrase word-by-word,
/// taps Continue, and settles.
Future<void> _advancePastMnemonicStep(WidgetTester tester) async {
  final words = _validMnemonic.split(' ');
  for (var i = 0; i < 12; i++) {
    await tester.enterText(find.byType(TextField).at(i), words[i]);
    await tester.pump();
  }
  await tester.pumpAndSettle();
  // The "Continue" button enables once 12 valid words are entered.
  // The sheet content can overflow a standard 800x600 test viewport,
  // so make sure the button is scrolled into view before tapping.
  final continueButton = find.widgetWithText(PrismButton, 'Continue');
  await tester.ensureVisible(continueButton);
  await tester.pumpAndSettle();
  await tester.tap(continueButton);
  await tester.pumpAndSettle();
}

/// Taps the numpad buttons for each digit to enter a 6-digit PIN.
Future<void> _tapPin(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.tap(find.text(digit).first);
    await tester.pump();
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SyncPinSheet lockout persistence', () {
    // ── No pre-existing lockout ─────────────────────────────────────────────

    testWidgets('no lockout subtitle on the mnemonic step', (tester) async {
      _useTallViewport(tester);
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(_buildSheet());
      await tester.pumpAndSettle();

      // Step 1 (mnemonic) — lockout subtitle belongs to step 2.
      expect(find.textContaining('Too many attempts'), findsNothing);
    });

    testWidgets('wraps recovery phrase and PIN entry in SecureScope', (
      tester,
    ) async {
      _useTallViewport(tester);
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(_buildSheet());
      await tester.pumpAndSettle();

      expect(find.byType(SecureScope), findsOneWidget);

      await _advancePastMnemonicStep(tester);

      expect(find.byType(SecureScope), findsOneWidget);
      expect(find.text('Enter your PIN'), findsOneWidget);
    });

    // ── Pre-existing lockout loaded from prefs ──────────────────────────────

    testWidgets(
      'shows locked subtitle on step 2 when SharedPreferences has a future locked_until',
      (tester) async {
        _useTallViewport(tester);
        final futureMs = DateTime.now()
            .add(const Duration(seconds: 120))
            .millisecondsSinceEpoch;

        SharedPreferences.setMockInitialValues({
          _prefsKeyAttempts: 5,
          _prefsKeyLockedUntil: futureMs,
        });

        await tester.pumpWidget(_buildSheet());
        await tester.pumpAndSettle();

        await _advancePastMnemonicStep(tester);

        expect(find.textContaining('Too many attempts'), findsOneWidget);
      },
    );

    testWidgets('expired lockout from prefs shows no lockout subtitle', (
      tester,
    ) async {
      _useTallViewport(tester);
      // Lock that expired 1 minute ago
      final pastMs = DateTime.now()
          .subtract(const Duration(minutes: 1))
          .millisecondsSinceEpoch;

      SharedPreferences.setMockInitialValues({
        _prefsKeyAttempts: 5,
        _prefsKeyLockedUntil: pastMs,
      });

      await tester.pumpWidget(_buildSheet());
      await tester.pumpAndSettle();

      await _advancePastMnemonicStep(tester);

      // Expired lockout should not show the lockout subtitle
      expect(find.textContaining('Too many attempts'), findsNothing);
    });

    // ── Failed attempts persist to prefs ───────────────────────────────────

    testWidgets(
      'failed attempt writes incremented count to SharedPreferences',
      (tester) async {
        _useTallViewport(tester);
        SharedPreferences.setMockInitialValues({
          _prefsKeyAttempts: 3, // prior failures already recorded
        });

        await tester.pumpWidget(
          _buildSheet(
            healthNotifier: _FakeSyncHealthNotifier(
              unlockResult: false,
            ), // wrong PIN
          ),
        );
        await tester.pumpAndSettle();

        await _advancePastMnemonicStep(tester);

        await _tapPin(tester, '123456');
        await tester.pumpAndSettle();

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt(_prefsKeyAttempts), equals(4)); // 3 → 4
      },
    );

    testWidgets('5th failed attempt writes a future locked_until to prefs', (
      tester,
    ) async {
      _useTallViewport(tester);
      SharedPreferences.setMockInitialValues({
        _prefsKeyAttempts: 4, // one more wrong attempt triggers lockout
      });

      final beforeMs = DateTime.now().millisecondsSinceEpoch;

      await tester.pumpWidget(
        _buildSheet(
          healthNotifier: _FakeSyncHealthNotifier(unlockResult: false),
        ),
      );
      await tester.pumpAndSettle();

      await _advancePastMnemonicStep(tester);

      await _tapPin(tester, '654321');
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      final lockedUntilMs = prefs.getInt(_prefsKeyLockedUntil);
      expect(lockedUntilMs, isNotNull);
      // The lockout must be in the future (30 s lock, so at least 29 s from now)
      expect(lockedUntilMs!, greaterThan(beforeMs + 25000));
    });

    // ── Successful unlock clears lockout state ──────────────────────────────

    testWidgets('successful unlock clears lockout prefs keys', (tester) async {
      _useTallViewport(tester);
      SharedPreferences.setMockInitialValues({_prefsKeyAttempts: 3});

      final notifier = _FakeSyncHealthNotifier(unlockResult: true);
      await tester.pumpWidget(_buildSheet(healthNotifier: notifier));
      await tester.pumpAndSettle();

      await _advancePastMnemonicStep(tester);

      await _tapPin(tester, '000000');
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(_prefsKeyAttempts), isNull);
      expect(prefs.getInt(_prefsKeyLockedUntil), isNull);
      // Both inputs should have been forwarded to attemptUnlock.
      expect(notifier.lastPin, '000000');
      expect(notifier.lastMnemonic, _validMnemonic);
    });
  });
}
