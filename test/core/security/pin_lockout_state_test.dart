import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/security/pin_lockout_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('initial state: not locked, 0 seconds remaining', () async {
    final state = PinLockoutState(prefsScope: 'test.scope');
    await state.load();

    expect(state.isLockedOut, isFalse);
    expect(state.secondsRemaining, equals(0));
  });

  test('one failure: not locked, attempt count = 1', () async {
    final state = PinLockoutState(prefsScope: 'test.scope');
    await state.load();
    await state.recordFailure();

    expect(state.isLockedOut, isFalse);
    expect(state.secondsRemaining, equals(0));
  });

  test('four failures: still not locked', () async {
    final state = PinLockoutState(prefsScope: 'test.scope');
    await state.load();
    for (var i = 0; i < 4; i++) {
      await state.recordFailure();
    }

    expect(state.isLockedOut, isFalse);
  });

  test('5th failure triggers lockout with secondsRemaining > 0', () async {
    final state = PinLockoutState(prefsScope: 'test.scope');
    await state.load();
    for (var i = 0; i < 5; i++) {
      await state.recordFailure();
    }

    expect(state.isLockedOut, isTrue);
    expect(state.secondsRemaining, greaterThan(0));
  });

  test('5 failures: lockout window is approximately 30 s (1× base)', () async {
    final state = PinLockoutState(prefsScope: 'test.scope');
    await state.load();
    for (var i = 0; i < 5; i++) {
      await state.recordFailure();
    }

    // multiplier = 5 ~/ 5 = 1 → 30 s
    expect(state.secondsRemaining, greaterThanOrEqualTo(29));
    expect(state.secondsRemaining, lessThanOrEqualTo(31));
  });

  test('10 failures: lockout window doubled (60 s, 2× base)', () async {
    final state = PinLockoutState(prefsScope: 'test.scope');
    await state.load();
    for (var i = 0; i < 10; i++) {
      await state.recordFailure();
    }

    // multiplier = 10 ~/ 5 = 2 → 60 s
    expect(state.isLockedOut, isTrue);
    expect(state.secondsRemaining, greaterThanOrEqualTo(59));
    expect(state.secondsRemaining, lessThanOrEqualTo(61));
  });

  test('clear() resets state and removes prefs keys', () async {
    final state = PinLockoutState(prefsScope: 'test.scope');
    await state.load();
    for (var i = 0; i < 5; i++) {
      await state.recordFailure();
    }
    expect(state.isLockedOut, isTrue);

    await state.clear();

    expect(state.isLockedOut, isFalse);
    expect(state.secondsRemaining, equals(0));

    // Verify prefs were actually cleared.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('test.scope.failed_attempts'), isNull);
    expect(prefs.getInt('test.scope.locked_until_ms'), isNull);
  });

  test('isLockedOut flips to false once lockedUntil timestamp is in the past',
      () async {
    // Seed prefs with a lockout that expired 1 second ago.
    final pastMs =
        DateTime.now().subtract(const Duration(seconds: 1)).millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      'test.scope.failed_attempts': 5,
      'test.scope.locked_until_ms': pastMs,
    });

    final state = PinLockoutState(prefsScope: 'test.scope');
    await state.load();

    expect(state.isLockedOut, isFalse);
    expect(state.secondsRemaining, equals(0));
  });

  test('different prefsScope instances do not share state', () async {
    final a = PinLockoutState(prefsScope: 'test.scope_a');
    final b = PinLockoutState(prefsScope: 'test.scope_b');
    await a.load();
    await b.load();

    for (var i = 0; i < 5; i++) {
      await a.recordFailure();
    }

    expect(a.isLockedOut, isTrue);
    expect(b.isLockedOut, isFalse);
  });

  test('two instances with same scope share persisted state after load()',
      () async {
    final first = PinLockoutState(prefsScope: 'test.shared');
    await first.load();
    for (var i = 0; i < 5; i++) {
      await first.recordFailure();
    }
    expect(first.isLockedOut, isTrue);

    // Second instance created fresh — must load() to see persisted state.
    final second = PinLockoutState(prefsScope: 'test.shared');
    await second.load();

    expect(second.isLockedOut, isTrue);
    expect(second.secondsRemaining, greaterThan(0));
  });

  test(
      'load() migrates legacy underscore-keyed prefs for prism.sync_pin scope',
      () async {
    // Seed legacy keys (underscore-separated, as used by old SyncPinSheet).
    final futureMs =
        DateTime.now().add(const Duration(seconds: 60)).millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      'prism.sync_pin_failed_attempts': 3,
      'prism.sync_pin_locked_until_ms': futureMs,
    });

    final state = PinLockoutState(prefsScope: 'prism.sync_pin');
    await state.load();

    // State is preserved.
    expect(state.failedAttempts, equals(3));
    expect(state.isLockedOut, isTrue);
    expect(state.secondsRemaining, greaterThan(0));

    // New keys hold the values.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('prism.sync_pin.failed_attempts'), equals(3));
    expect(prefs.getInt('prism.sync_pin.locked_until_ms'), equals(futureMs));

    // Legacy keys are gone.
    expect(prefs.containsKey('prism.sync_pin_failed_attempts'), isFalse);
    expect(prefs.containsKey('prism.sync_pin_locked_until_ms'), isFalse);
  });

  test(
      'migration does NOT run for other scopes — legacy keys remain untouched',
      () async {
    final futureMs =
        DateTime.now().add(const Duration(seconds: 60)).millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      'prism.sync_pin_failed_attempts': 3,
      'prism.sync_pin_locked_until_ms': futureMs,
    });

    // A different scope should not touch the sync_pin legacy keys.
    final preflight = PinLockoutState(prefsScope: 'prism.preflight');
    await preflight.load();

    expect(preflight.isLockedOut, isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('prism.sync_pin_failed_attempts'), isTrue);
    expect(prefs.containsKey('prism.sync_pin_locked_until_ms'), isTrue);
  });

  test(
      'migration does NOT run for verify_backup scope — legacy keys remain',
      () async {
    final futureMs =
        DateTime.now().add(const Duration(seconds: 60)).millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      'prism.sync_pin_failed_attempts': 3,
      'prism.sync_pin_locked_until_ms': futureMs,
    });

    final verifyBackup = PinLockoutState(prefsScope: 'prism.verify_backup');
    await verifyBackup.load();

    expect(verifyBackup.isLockedOut, isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('prism.sync_pin_failed_attempts'), isTrue);
    expect(prefs.containsKey('prism.sync_pin_locked_until_ms'), isTrue);
  });
}
