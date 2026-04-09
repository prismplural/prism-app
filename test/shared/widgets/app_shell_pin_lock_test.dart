import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/utils/pin_lock_decision.dart';

void main() {
  // ── initialLockDecision ────────────────────────────────────────────────

  group('initialLockDecision', () {
    test('not resolved when settings still loading', () {
      final result = initialLockDecision(
        settingsLoading: true,
        isPinSetLoading: false,
        pinLockEnabled: true,
        isPinSet: true,
      );
      expect(result.resolved, isFalse);
    });

    test('not resolved when isPinSet still loading', () {
      final result = initialLockDecision(
        settingsLoading: false,
        isPinSetLoading: true,
        pinLockEnabled: true,
        isPinSet: null,
      );
      expect(result.resolved, isFalse);
    });

    test('no lock when settings errored (pinLockEnabled is null)', () {
      final result = initialLockDecision(
        settingsLoading: false,
        isPinSetLoading: false,
        pinLockEnabled: null,
        isPinSet: null,
      );
      expect(result.resolved, isTrue);
      expect(result.locked, isFalse);
    });

    test('no lock when pinLockEnabled is false', () {
      final result = initialLockDecision(
        settingsLoading: false,
        isPinSetLoading: false,
        pinLockEnabled: false,
        isPinSet: true,
      );
      expect(result.resolved, isTrue);
      expect(result.locked, isFalse);
    });

    test('locked when pinLockEnabled is true and isPinSet is true', () {
      final result = initialLockDecision(
        settingsLoading: false,
        isPinSetLoading: false,
        pinLockEnabled: true,
        isPinSet: true,
      );
      expect(result.resolved, isTrue);
      expect(result.locked, isTrue);
    });

    test('locked when pinLockEnabled is true and isPinSet is null (error — fail closed)', () {
      final result = initialLockDecision(
        settingsLoading: false,
        isPinSetLoading: false,
        pinLockEnabled: true,
        isPinSet: null,
      );
      expect(result.resolved, isTrue);
      expect(result.locked, isTrue);
    });

    test('no lock when pinLockEnabled is true but isPinSet is false', () {
      final result = initialLockDecision(
        settingsLoading: false,
        isPinSetLoading: false,
        pinLockEnabled: true,
        isPinSet: false,
      );
      expect(result.resolved, isTrue);
      expect(result.locked, isFalse);
    });
  });

  // ── resumeLockDecision ─────────────────────────────────────────────────

  group('resumeLockDecision', () {
    test('returns false when already locked', () {
      final result = resumeLockDecision(
        alreadyLocked: true,
        pinLockEnabled: true,
        isPinSet: true,
        backgroundedAt: DateTime(2026, 1, 1),
        autoLockDelaySeconds: 0,
      );
      expect(result, isFalse);
    });

    test('returns false when pinLockEnabled is null', () {
      final result = resumeLockDecision(
        alreadyLocked: false,
        pinLockEnabled: null,
        isPinSet: true,
        backgroundedAt: DateTime(2026, 1, 1),
        autoLockDelaySeconds: 0,
      );
      expect(result, isFalse);
    });

    test('returns false when pinLockEnabled is false', () {
      final result = resumeLockDecision(
        alreadyLocked: false,
        pinLockEnabled: false,
        isPinSet: true,
        backgroundedAt: DateTime(2026, 1, 1),
        autoLockDelaySeconds: 0,
      );
      expect(result, isFalse);
    });

    test('returns true when isPinSet is null (error — fail closed)', () {
      final result = resumeLockDecision(
        alreadyLocked: false,
        pinLockEnabled: true,
        isPinSet: null,
        backgroundedAt: null,
        autoLockDelaySeconds: 0,
      );
      expect(result, isTrue);
    });

    test('returns false when isPinSet is false', () {
      final result = resumeLockDecision(
        alreadyLocked: false,
        pinLockEnabled: true,
        isPinSet: false,
        backgroundedAt: DateTime(2026, 1, 1),
        autoLockDelaySeconds: 0,
      );
      expect(result, isFalse);
    });

    test('returns true when backgroundedAt is null', () {
      final result = resumeLockDecision(
        alreadyLocked: false,
        pinLockEnabled: true,
        isPinSet: true,
        backgroundedAt: null,
        autoLockDelaySeconds: 60,
      );
      expect(result, isTrue);
    });

    test('returns true when elapsed time exceeds autoLockDelaySeconds', () {
      final result = resumeLockDecision(
        alreadyLocked: false,
        pinLockEnabled: true,
        isPinSet: true,
        backgroundedAt: DateTime.now().subtract(const Duration(seconds: 120)),
        autoLockDelaySeconds: 60,
      );
      expect(result, isTrue);
    });

    test('returns false when elapsed time is below autoLockDelaySeconds', () {
      final result = resumeLockDecision(
        alreadyLocked: false,
        pinLockEnabled: true,
        isPinSet: true,
        backgroundedAt: DateTime.now(),
        autoLockDelaySeconds: 60,
      );
      expect(result, isFalse);
    });

    test('returns true with autoLockDelaySeconds of 0 (immediate lock)', () {
      final result = resumeLockDecision(
        alreadyLocked: false,
        pinLockEnabled: true,
        isPinSet: true,
        backgroundedAt: DateTime.now().subtract(const Duration(milliseconds: 1)),
        autoLockDelaySeconds: 0,
      );
      expect(result, isTrue);
    });
  });
}
