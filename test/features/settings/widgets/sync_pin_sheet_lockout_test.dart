import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/settings/widgets/sync_pin_sheet.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

// ---------------------------------------------------------------------------
// Fake SyncHealthNotifier
// ---------------------------------------------------------------------------

class _FakeSyncHealthNotifier extends SyncHealthNotifier {
  bool unlockResult;
  _FakeSyncHealthNotifier({this.unlockResult = false});

  @override
  SyncHealthState build() => SyncHealthState.needsPassword;

  @override
  Future<bool> attemptUnlock(String pin) async => unlockResult;
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

const _prefsKeyAttempts = 'prism.sync_pin_failed_attempts';
const _prefsKeyLockedUntil = 'prism.sync_pin_locked_until_ms';

Widget _buildSheet({SyncHealthNotifier? healthNotifier}) {
  return ProviderScope(
    overrides: [
      syncHealthProvider.overrideWith(
        () => healthNotifier ?? _FakeSyncHealthNotifier(unlockResult: false),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute(
            builder: (_) => const SyncPinSheet(),
          ),
        ),
      ),
    ),
  );
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

    testWidgets('no lockout subtitle when SharedPreferences is empty', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(_buildSheet());
      await tester.pumpAndSettle();

      expect(find.textContaining('Too many attempts'), findsNothing);
    });

    // ── Pre-existing lockout loaded from prefs ──────────────────────────────

    testWidgets(
        'shows locked subtitle when SharedPreferences has a future locked_until',
        (tester) async {
      final futureMs = DateTime.now()
          .add(const Duration(seconds: 120))
          .millisecondsSinceEpoch;

      SharedPreferences.setMockInitialValues({
        _prefsKeyAttempts: 5,
        _prefsKeyLockedUntil: futureMs,
      });

      await tester.pumpWidget(_buildSheet());
      // Allow initState + _loadLockoutState() async call to complete
      await tester.pumpAndSettle();

      expect(find.textContaining('Too many attempts'), findsOneWidget);
    });

    testWidgets('expired lockout from prefs shows no lockout subtitle', (
      tester,
    ) async {
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

      // Expired lockout should not show the lockout subtitle
      expect(find.textContaining('Too many attempts'), findsNothing);
    });

    // ── Failed attempts persist to prefs ───────────────────────────────────

    testWidgets('failed attempt writes incremented count to SharedPreferences',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        _prefsKeyAttempts: 3, // prior failures already recorded
      });

      await tester.pumpWidget(
        _buildSheet(
          healthNotifier:
              _FakeSyncHealthNotifier(unlockResult: false), // wrong PIN
        ),
      );
      await tester.pumpAndSettle();

      await _tapPin(tester, '123456');
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(_prefsKeyAttempts), equals(4)); // 3 → 4
    });

    testWidgets('5th failed attempt writes a future locked_until to prefs', (
      tester,
    ) async {
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
      SharedPreferences.setMockInitialValues({
        _prefsKeyAttempts: 3,
      });

      await tester.pumpWidget(
        _buildSheet(
          healthNotifier: _FakeSyncHealthNotifier(unlockResult: true),
        ),
      );
      await tester.pumpAndSettle();

      await _tapPin(tester, '000000');
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(_prefsKeyAttempts), isNull);
      expect(prefs.getInt(_prefsKeyLockedUntil), isNull);
    });
  });
}
