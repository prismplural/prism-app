import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

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
    ref.listen(pkSyncModeProvider, (_, _) => _reschedule());
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
    final bus = ref.read(pkSyncEventBusProvider);
    try {
      if (!_foreground) {
        bus.emit(
          const PkAutoPollTick(outcome: 'skipped', reason: 'not_foregrounded'),
        );
        return;
      }
      final suppressUntil = _suppressUntil;
      if (suppressUntil != null && DateTime.now().isBefore(suppressUntil)) {
        bus.emit(
          const PkAutoPollTick(outcome: 'skipped', reason: 'recent_push'),
        );
        return;
      }
      final pkState = ref.read(pluralKitSyncProvider);
      final tokenPresent = await _hasStoredTokenForLog();
      if (!ref.mounted) return;
      final gate = _autoSyncGateSnapshot(pkState, tokenPresent: tokenPresent);
      if (!pkState.canAutoSync) {
        bus.emit(
          PkAutoPollTick(
            outcome: 'skipped',
            reason: 'cannot_auto_sync',
            gate: gate,
          ),
        );
        return;
      }
      if (tokenPresent == false) {
        bus.emit(
          PkAutoPollTick(
            outcome: 'skipped',
            reason: 'token_missing',
            gate: gate,
          ),
        );
        return;
      }
      if (pkState.isSyncing) {
        bus.emit(const PkAutoPollTick(outcome: 'skipped', reason: 'busy'));
        return;
      }

      await ref.read(pkSyncModeProvider.notifier).load();
      await ref.read(pkSyncDirectionProvider.notifier).load();
      if (!ref.mounted) return;

      final mode = ref.read(pkSyncModeProvider);
      if (mode == PkSyncMode.liveFrontsOnly) {
        final direction = ref.read(pkSyncDirectionProvider);
        if (!direction.pullEnabled) {
          bus.emit(
            const PkAutoPollTick(outcome: 'skipped', reason: 'pull_disabled'),
          );
          return;
        }
        await ref
            .read(pluralKitSyncProvider.notifier)
            .syncLiveFrontersOnly(isManual: false, direction: direction);
      } else {
        await ref.read(pluralKitSyncServiceProvider).pollFrontersOnly();
      }
      bus.emit(const PkAutoPollTick(outcome: 'ok'));
    } catch (e) {
      // PK sync services swallow most errors; anything that escapes here is
      // unexpected. Back off one cycle to avoid hammering.
      //
      // We DO NOT attach `e.toString()` to the emitted event. The auto-poll
      // notifier doesn't have a captured token to redact against, and routing
      // the raw exception string through `PkSyncEvent.redact(..., null)` is a
      // no-op — so any token embedded in the exception text would leak into
      // the sync log. The operational signal ("auto-poll failed") is
      // sufficient for the log; the full stack trace is still available via
      // `debugPrint` above for developers attached to the device.
      debugPrint('[PK auto-poll] tick failed: $e');
      bus.emit(const PkAutoPollTick(outcome: 'failed'));
      _overrideNext = _kMinBackoffOn429;
    } finally {
      // Guard against dispose racing a tick — ref.read on a disposed
      // provider throws.
      if (ref.mounted) _reschedule();
    }
  }

  Future<bool?> _hasStoredTokenForLog() async {
    try {
      return await ref.read(pluralKitSyncServiceProvider).hasStoredToken();
    } catch (e) {
      debugPrint('[PK auto-poll] token-state read failed: $e');
      return null;
    }
  }

  Map<String, Object?> _autoSyncGateSnapshot(
    PluralKitSyncState state, {
    required bool? tokenPresent,
  }) {
    return {
      'is_connected': state.isConnected,
      'direction_confirmed': state.directionConfirmed,
      'mapping_acknowledged': state.mappingAcknowledged,
      'can_auto_sync': state.canAutoSync,
      'is_syncing': state.isSyncing,
      'token_present': ?tokenPresent,
    };
  }
}

final pkAutoPollProvider = NotifierProvider<PkAutoPollNotifier, void>(
  PkAutoPollNotifier.new,
);
