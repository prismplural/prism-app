import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_event_loop.dart';

enum PairingProgressPhase { connecting, downloading, restoring, finishing }

const Object _copyWithUnset = Object();
const Duration _restoreProgressFlushDelay = Duration(milliseconds: 100);

class _RestoreApplyProgress {
  const _RestoreApplyProgress({required this.applied, required this.total});

  final int applied;
  final int total;
}

@immutable
class SyncSetupProgressState {
  final PairingProgressPhase phase;
  final Map<String, int> liveCounts;
  final DateTime phaseStartedAt;
  final bool timedOut;
  final bool wsConnected;
  final int? restoreApplied;
  final int? restoreTotal;

  const SyncSetupProgressState({
    required this.phase,
    required this.liveCounts,
    required this.phaseStartedAt,
    required this.timedOut,
    required this.wsConnected,
    this.restoreApplied,
    this.restoreTotal,
  });

  factory SyncSetupProgressState.initial(DateTime now) =>
      SyncSetupProgressState(
        phase: PairingProgressPhase.connecting,
        liveCounts: const {},
        phaseStartedAt: now,
        timedOut: false,
        wsConnected: false,
      );

  bool get hasRestoreProgress =>
      restoreApplied != null && restoreTotal != null && restoreTotal! > 0;

  double? get restoreProgressFraction {
    final applied = restoreApplied;
    final total = restoreTotal;
    if (applied == null || total == null || total <= 0) return null;
    return (applied / total).clamp(0.0, 1.0);
  }

  SyncSetupProgressState copyWith({
    PairingProgressPhase? phase,
    Map<String, int>? liveCounts,
    DateTime? phaseStartedAt,
    bool? timedOut,
    bool? wsConnected,
    Object? restoreApplied = _copyWithUnset,
    Object? restoreTotal = _copyWithUnset,
  }) {
    return SyncSetupProgressState(
      phase: phase ?? this.phase,
      liveCounts: liveCounts ?? this.liveCounts,
      phaseStartedAt: phaseStartedAt ?? this.phaseStartedAt,
      timedOut: timedOut ?? this.timedOut,
      wsConnected: wsConnected ?? this.wsConnected,
      restoreApplied: identical(restoreApplied, _copyWithUnset)
          ? this.restoreApplied
          : restoreApplied as int?,
      restoreTotal: identical(restoreTotal, _copyWithUnset)
          ? this.restoreTotal
          : restoreTotal as int?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SyncSetupProgressState) return false;
    if (phase != other.phase) return false;
    if (phaseStartedAt != other.phaseStartedAt) return false;
    if (timedOut != other.timedOut) return false;
    if (wsConnected != other.wsConnected) return false;
    if (restoreApplied != other.restoreApplied) return false;
    if (restoreTotal != other.restoreTotal) return false;
    if (liveCounts.length != other.liveCounts.length) return false;
    for (final entry in liveCounts.entries) {
      if (other.liveCounts[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    phase,
    phaseStartedAt,
    timedOut,
    wsConnected,
    restoreApplied,
    restoreTotal,
    Object.hashAll(liveCounts.entries.map((e) => Object.hash(e.key, e.value))),
  );
}

class SyncSetupProgressNotifier extends Notifier<SyncSetupProgressState> {
  Timer? _flushTimer;
  Timer? _restoreProgressTimer;
  final Map<String, int> _pendingTally = {};
  _RestoreApplyProgress? _pendingRestoreProgress;

  @override
  SyncSetupProgressState build() {
    ref.onDispose(() {
      _flushTimer?.cancel();
      _restoreProgressTimer?.cancel();
    });

    final strictCoordinator = ref.watch(strictApplyCoordinatorProvider);
    final progressSubscription = strictCoordinator.progressStream.listen(
      _onStrictApplyProgress,
    );
    ref.onDispose(() {
      unawaited(progressSubscription.cancel());
    });

    ref.listen<AsyncValue<SyncEvent>>(syncEventStreamProvider, (_, next) {
      final event = next.value;
      if (event != null) _onEvent(event);
    });

    return SyncSetupProgressState.initial(DateTime.now());
  }

  void setPhase(PairingProgressPhase next) {
    // Why: monotonic invariant — progress phases cannot rewind.
    if (next.index <= state.phase.index) return;
    // Why: flush pending tally before phase change so counts from the outgoing
    // phase are committed before the UI re-renders for the new phase.
    _flushPendingTally();
    _flushPendingRestoreProgress();
    state = state.copyWith(phase: next, phaseStartedAt: DateTime.now());
  }

  void markTimedOut() {
    state = state.copyWith(timedOut: true);
  }

  void setRestoreApplyProgress({required int applied, required int total}) {
    if (total <= 0) return;
    final normalizedApplied = applied < 0
        ? 0
        : applied > total
        ? total
        : applied;
    if (state.restoreApplied == normalizedApplied &&
        state.restoreTotal == total) {
      return;
    }
    state = state.copyWith(
      restoreApplied: normalizedApplied,
      restoreTotal: total,
    );
  }

  void reset() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _restoreProgressTimer?.cancel();
    _restoreProgressTimer = null;
    _pendingTally.clear();
    _pendingRestoreProgress = null;
    state = SyncSetupProgressState.initial(DateTime.now());
  }

  void _onEvent(SyncEvent e) {
    if (e.isWebSocketStateChanged) {
      final connected = e.data['connected'] as bool? ?? false;
      state = state.copyWith(wsConnected: connected);
    }
    // Why: drop RemoteChanges in finishing phase so displayed counts freeze.
    if (e.isRemoteChanges && state.phase != PairingProgressPhase.finishing) {
      for (final change in e.changes) {
        final table = change['table'] as String?;
        if (table == null) continue;
        _pendingTally[table] = (_pendingTally[table] ?? 0) + 1;
      }
      _flushTimer ??= Timer(
        const Duration(milliseconds: 300),
        _flushPendingTally,
      );
    }
  }

  void _onStrictApplyProgress(StrictApplyProgress progress) {
    if (!progress.hasTotal) return;
    _pendingRestoreProgress = _RestoreApplyProgress(
      applied: progress.applied!,
      total: progress.total!,
    );
    if (!state.hasRestoreProgress) {
      _flushPendingRestoreProgress();
      return;
    }
    _restoreProgressTimer ??= Timer(
      _restoreProgressFlushDelay,
      _flushPendingRestoreProgress,
    );
  }

  void _flushPendingTally() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_pendingTally.isEmpty) return;
    final merged = Map<String, int>.from(state.liveCounts);
    _pendingTally.forEach((k, v) => merged[k] = (merged[k] ?? 0) + v);
    _pendingTally.clear();
    state = state.copyWith(liveCounts: Map.unmodifiable(merged));
  }

  void _flushPendingRestoreProgress() {
    _restoreProgressTimer?.cancel();
    _restoreProgressTimer = null;
    final progress = _pendingRestoreProgress;
    _pendingRestoreProgress = null;
    if (progress == null) return;
    setRestoreApplyProgress(applied: progress.applied, total: progress.total);
  }
}

final syncSetupProgressProvider =
    NotifierProvider<SyncSetupProgressNotifier, SyncSetupProgressState>(
      SyncSetupProgressNotifier.new,
    );
