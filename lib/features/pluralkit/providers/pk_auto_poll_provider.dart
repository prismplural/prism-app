import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';

// ---------------------------------------------------------------------------
// Preferences (per-device, not synced — polling cadence is a device concern)
// ---------------------------------------------------------------------------

const _kPkAutoPollEnabledKey = 'pk_auto_poll_enabled';
const _kPkAutoPollIntervalKey = 'pk_auto_poll_interval_seconds';

/// Default cadence when the toggle is enabled for the first time. 30s matches
/// the foreground-friendly floor we settled on — well under PK's 10/s GET
/// budget, and responsive enough for Discord `pk;s` switches.
const _kDefaultIntervalSeconds = 30;

/// Choices surfaced in the settings UI (value in seconds). 0 acts as a
/// sentinel for "off" but the toggle handles that separately — every entry
/// here is a valid live cadence.
const pkAutoPollIntervalChoices = <int>[30, 60, 120, 300];

/// Minimum delay between end of one tick and the next, to keep us from
/// re-firing during a long-running `syncRecentData`.
const _kMinBackoffOn429 = Duration(minutes: 2);

/// Cool-down window after a local push lands, so the poll doesn't re-ingest
/// a switch we just authored.
const _kPostPushSuppression = Duration(seconds: 10);

class PkAutoPollSettings {
  final bool enabled;
  final int intervalSeconds;

  const PkAutoPollSettings({
    required this.enabled,
    required this.intervalSeconds,
  });

  PkAutoPollSettings copyWith({bool? enabled, int? intervalSeconds}) =>
      PkAutoPollSettings(
        enabled: enabled ?? this.enabled,
        intervalSeconds: intervalSeconds ?? this.intervalSeconds,
      );
}

class PkAutoPollSettingsNotifier extends AsyncNotifier<PkAutoPollSettings> {
  @override
  Future<PkAutoPollSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    return PkAutoPollSettings(
      enabled: prefs.getBool(_kPkAutoPollEnabledKey) ?? false,
      intervalSeconds:
          prefs.getInt(_kPkAutoPollIntervalKey) ?? _kDefaultIntervalSeconds,
    );
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPkAutoPollEnabledKey, value);
    state = AsyncValue.data(
      (state.value ??
              const PkAutoPollSettings(
                enabled: false,
                intervalSeconds: _kDefaultIntervalSeconds,
              ))
          .copyWith(enabled: value),
    );
  }

  Future<void> setIntervalSeconds(int seconds) async {
    if (!pkAutoPollIntervalChoices.contains(seconds)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPkAutoPollIntervalKey, seconds);
    state = AsyncValue.data(
      (state.value ??
              const PkAutoPollSettings(
                enabled: false,
                intervalSeconds: _kDefaultIntervalSeconds,
              ))
          .copyWith(intervalSeconds: seconds),
    );
  }
}

final pkAutoPollSettingsProvider =
    AsyncNotifierProvider<PkAutoPollSettingsNotifier, PkAutoPollSettings>(
      PkAutoPollSettingsNotifier.new,
    );

// ---------------------------------------------------------------------------
// Runtime notifier — owns the Timer
// ---------------------------------------------------------------------------

/// Drives the foreground PK poll loop.
///
/// - Only runs while [markForegrounded] is true AND settings.enabled is true
///   AND the PK sync state is `canAutoSync`.
/// - Jitters each tick by ±5s so a user running Prism on several devices
///   doesn't align their requests.
/// - Honors 429 by backing off one cycle to 2 min before returning to the
///   configured cadence.
/// - Suppresses the tick for 10s after a local switch push lands (caller
///   invokes [noteLocalPush]) so we don't re-pull what we just wrote.
class PkAutoPollNotifier extends Notifier<void> {
  Timer? _timer;
  bool _foreground = false;
  DateTime? _suppressUntil;
  Duration? _overrideNext; // one-shot longer delay after 429
  final _rng = Random();

  @override
  void build() {
    ref.listen(pkAutoPollSettingsProvider, (_, _) => _reschedule());
    ref.listen(pluralKitSyncProvider, (_, _) => _reschedule());
    ref.onDispose(_cancel);
    _reschedule();
  }

  void markForegrounded(bool value) {
    if (_foreground == value) return;
    _foreground = value;
    _reschedule();
    if (value) {
      // Immediate catch-up on resume — mirrors Rust sync's onResume pattern.
      _tickOnce();
    }
  }

  /// Suppress the next tick for ~10s after a local push. Call from sites
  /// that write to PK (e.g. after `pushPendingSwitches`).
  void noteLocalPush() {
    _suppressUntil = DateTime.now().add(_kPostPushSuppression);
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void _reschedule() {
    _cancel();
    if (!_foreground) return;
    final settings = ref.read(pkAutoPollSettingsProvider).value;
    if (settings == null || !settings.enabled) return;
    final pkState = ref.read(pluralKitSyncProvider);
    if (!pkState.canAutoSync) return;

    final base = _overrideNext ?? Duration(seconds: settings.intervalSeconds);
    _overrideNext = null;
    final jitterMs = _rng.nextInt(10000) - 5000; // ±5s
    final delay = base + Duration(milliseconds: jitterMs);
    _timer = Timer(
      delay.isNegative ? const Duration(seconds: 10) : delay,
      _tickOnce,
    );
  }

  Future<void> _tickOnce() async {
    try {
      if (!_foreground) return;
      final suppressUntil = _suppressUntil;
      if (suppressUntil != null && DateTime.now().isBefore(suppressUntil)) {
        return;
      }
      final pkState = ref.read(pluralKitSyncProvider);
      if (!pkState.canAutoSync) return;
      if (pkState.isSyncing) return;

      await ref.read(pluralKitSyncServiceProvider).pollFrontersOnly();
    } catch (e) {
      // pollFrontersOnly swallows most errors; anything that escapes here
      // is unexpected. Back off one cycle to avoid hammering.
      debugPrint('[PK auto-poll] tick failed: $e');
      _overrideNext = _kMinBackoffOn429;
    } finally {
      // Guard against dispose racing a tick — ref.read on a disposed
      // provider throws.
      if (ref.mounted) _reschedule();
    }
  }
}

final pkAutoPollProvider = NotifierProvider<PkAutoPollNotifier, void>(
  PkAutoPollNotifier.new,
);
