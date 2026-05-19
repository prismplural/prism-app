/// Persisted state machine for the sync DB pairing/re-pairing flow.
///
/// Why this exists: when the sync DB key slot is unreadable, the recovery
/// path is to wipe `prism_sync.db` and re-pair. That wipe is a multi-step
/// local operation. If the user goes offline AFTER wipe but BEFORE pair,
/// we must NOT recreate the broken state on next launch — instead we
/// surface "complete the pair you started".
///
/// The phase is persisted to SharedPreferences, so it survives offline
/// restart and reboots.
///
/// See `docs/0.9.2-secure-storage-remediation.md` §5.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key for the persisted phase string.
const String kSyncPairingPhaseKey = 'prism.sync.pairing_phase';

/// Lifecycle phase of the sync DB pairing flow.
///
/// Default is [unread] — sync is healthy and no pending wipe is in flight.
enum SyncPairingPhase {
  /// Sync is healthy, no pending wipe.
  unread,

  /// Atomic transition: wipe of `prism_sync.db` + sync keychain slots is in
  /// progress. Survives offline restart and resumes via
  /// [wipeSyncDatabaseForRepair] re-invocation.
  wipeInProgress,

  /// Sync DB wiped, ready for fresh pair. Pairing UI should offer
  /// "complete the pair you started" rather than "set up sync from scratch".
  pendingPair,

  /// Active sync handle. Set on successful pair.
  paired,
}

/// Service: read / write / transition the persisted phase.
///
/// All transitions log via `debugPrint('[SYNC_PAIRING_PHASE] ...')` so the
/// lines can be grepped from user-submitted logs.
class SyncPairingPhaseService {
  SyncPairingPhaseService({SharedPreferences? prefs}) : _prefs = prefs;

  final SharedPreferences? _prefs;

  Future<SharedPreferences> _resolvePrefs() async {
    return _prefs ?? await SharedPreferences.getInstance();
  }

  /// Returns the persisted phase, or [SyncPairingPhase.unread] when no save
  /// exists or the saved value is not a recognized enum name.
  Future<SyncPairingPhase> read() async {
    final prefs = await _resolvePrefs();
    final raw = prefs.getString(kSyncPairingPhaseKey);
    if (raw == null || raw.isEmpty) {
      return SyncPairingPhase.unread;
    }
    for (final phase in SyncPairingPhase.values) {
      if (phase.name == raw) return phase;
    }
    debugPrint(
      '[SYNC_PAIRING_PHASE] unrecognized saved value "$raw" — defaulting to unread',
    );
    return SyncPairingPhase.unread;
  }

  /// Overwrite the persisted phase. Logs the write.
  ///
  /// Prefer [transition] when changing phase — it enforces the allowed
  /// transition graph. Direct [write] is exposed for tests and for the
  /// `phase == unread` reset path (which is also allowed via [transition]).
  Future<void> write(SyncPairingPhase phase) async {
    final prefs = await _resolvePrefs();
    debugPrint('[SYNC_PAIRING_PHASE] write: ${phase.name}');
    await prefs.setString(kSyncPairingPhaseKey, phase.name);
  }

  /// Transition from [from] to [to], enforcing the allowed transition graph.
  ///
  /// Allowed:
  ///   * `unread → wipeInProgress`
  ///   * `wipeInProgress → pendingPair`
  ///   * `pendingPair → paired`
  ///   * `paired → unread`
  ///   * `* → unread` (reset path, logged as `reset`)
  ///   * identity transition (`from == to`) — no-op, no log
  ///
  /// Throws [StateError] on any other transition. The current saved phase
  /// must match [from], else [StateError] is thrown with a precondition
  /// message — callers that don't know the current phase should `read()`
  /// first.
  Future<void> transition({
    required SyncPairingPhase from,
    required SyncPairingPhase to,
  }) async {
    final current = await read();
    if (current != from) {
      throw StateError(
        'SyncPairingPhase precondition mismatch: expected $from, saw $current',
      );
    }
    if (from == to) {
      // Identity — silent no-op.
      return;
    }
    if (!_isAllowedTransition(from, to)) {
      throw StateError(
        'Invalid SyncPairingPhase transition: ${from.name} → ${to.name}',
      );
    }

    final isResetPath = to == SyncPairingPhase.unread &&
        from != SyncPairingPhase.paired;
    debugPrint(
      '[SYNC_PAIRING_PHASE] transition: ${from.name} → ${to.name}'
      '${isResetPath ? ' (reset)' : ''}',
    );
    await write(to);
  }

  bool _isAllowedTransition(SyncPairingPhase from, SyncPairingPhase to) {
    // Reset path: any → unread is allowed.
    if (to == SyncPairingPhase.unread) return true;
    switch (from) {
      case SyncPairingPhase.unread:
        return to == SyncPairingPhase.wipeInProgress;
      case SyncPairingPhase.wipeInProgress:
        return to == SyncPairingPhase.pendingPair;
      case SyncPairingPhase.pendingPair:
        return to == SyncPairingPhase.paired;
      case SyncPairingPhase.paired:
        // `paired → unread` is handled by the `to == unread` short-circuit
        // above; no other transitions from `paired` are allowed.
        return false;
    }
  }
}

/// Riverpod provider for the service.
///
/// Constructs the service lazily without injecting a [SharedPreferences]
/// instance — the service resolves one on first call via
/// `SharedPreferences.getInstance()`. Tests inject directly via the
/// constructor instead of overriding this provider.
final syncPairingPhaseProvider = Provider<SyncPairingPhaseService>((ref) {
  return SyncPairingPhaseService();
});
