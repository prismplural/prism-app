import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted brute-force lockout state for a PIN entry surface.
///
/// Tracks failed attempts and enforces an exponentially growing lockout
/// window. State is stored in [SharedPreferences] under keys derived from
/// [prefsScope] so lockout survives sheet dismissal and app restarts.
///
/// A 6-digit PIN has only 10^6 entropy — always rate-limit at the call site.
/// Argon2id alone does not make brute force infeasible against a recovered
/// wrapped_dek + salt.
class PinLockoutState {
  PinLockoutState({required String prefsScope})
    : _prefsKeyAttempts = '$prefsScope.failed_attempts',
      _prefsKeyLockedUntil = '$prefsScope.locked_until_ms';

  static const _maxAttempts = 5;
  static const _baseLockoutSeconds = 30;

  final String _prefsKeyAttempts;
  final String _prefsKeyLockedUntil;

  int _failedAttempts = 0;
  DateTime? _lockedUntil;

  @visibleForTesting
  int get failedAttempts => _failedAttempts;

  bool get isLockedOut {
    if (_lockedUntil == null) return false;
    if (DateTime.now().isAfter(_lockedUntil!)) {
      _lockedUntil = null;
      return false;
    }
    return true;
  }

  int get secondsRemaining {
    if (_lockedUntil == null) return 0;
    return _lockedUntil!.difference(DateTime.now()).inSeconds.clamp(0, 9999);
  }

  /// Loads persisted lockout state. Call from [initState] before reading
  /// [isLockedOut] or [secondsRemaining]. Idempotent.
  Future<void> load() async {
    await _migrateLegacyKeys();

    final prefs = await SharedPreferences.getInstance();
    final attempts = prefs.getInt(_prefsKeyAttempts) ?? 0;
    final lockedUntilMs = prefs.getInt(_prefsKeyLockedUntil);
    final lockedUntil = lockedUntilMs != null
        ? DateTime.fromMillisecondsSinceEpoch(lockedUntilMs)
        : null;
    _failedAttempts = attempts;
    _lockedUntil = lockedUntil;
  }

  /// Records a failed attempt. May open a new lockout window using exponential
  /// backoff (5-attempt threshold, 30 s × multiplier). Persisted.
  Future<void> recordFailure() async {
    _failedAttempts++;
    if (_failedAttempts >= _maxAttempts) {
      final multiplier = _failedAttempts ~/ _maxAttempts;
      _lockedUntil = DateTime.now().add(
        Duration(seconds: _baseLockoutSeconds * multiplier),
      );
    }
    await _save();
  }

  /// Clears persisted state. Call on successful unlock.
  Future<void> clear() async {
    _failedAttempts = 0;
    _lockedUntil = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyAttempts);
    await prefs.remove(_prefsKeyLockedUntil);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKeyAttempts, _failedAttempts);
    if (_lockedUntil != null) {
      await prefs.setInt(
        _prefsKeyLockedUntil,
        _lockedUntil!.millisecondsSinceEpoch,
      );
    } else {
      await prefs.remove(_prefsKeyLockedUntil);
    }
  }

  /// Migrates legacy SyncPinSheet prefs keys (underscore-separated) to the
  /// dot-separated form. Runs only for the original `prism.sync_pin` scope;
  /// other scopes never had legacy state.
  Future<void> _migrateLegacyKeys() async {
    if (_prefsKeyAttempts != 'prism.sync_pin.failed_attempts') return;

    const legacyKeyAttempts = 'prism.sync_pin_failed_attempts';
    const legacyKeyLockedUntil = 'prism.sync_pin_locked_until_ms';

    final prefs = await SharedPreferences.getInstance();
    final hasLegacyAttempts = prefs.containsKey(legacyKeyAttempts);
    final hasLegacyLockedUntil = prefs.containsKey(legacyKeyLockedUntil);

    if (!hasLegacyAttempts && !hasLegacyLockedUntil) return;

    if (hasLegacyAttempts) {
      final attempts = prefs.getInt(legacyKeyAttempts)!;
      await prefs.setInt(_prefsKeyAttempts, attempts);
      await prefs.remove(legacyKeyAttempts);
    }

    if (hasLegacyLockedUntil) {
      final lockedUntilMs = prefs.getInt(legacyKeyLockedUntil)!;
      await prefs.setInt(_prefsKeyLockedUntil, lockedUntilMs);
      await prefs.remove(legacyKeyLockedUntil);
    }
  }
}
