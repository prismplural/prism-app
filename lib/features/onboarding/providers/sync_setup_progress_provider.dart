import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_event_loop.dart';

enum PairingProgressPhase { connecting, downloading, restoring, finishing }

@immutable
class SyncSetupProgressState {
  final PairingProgressPhase phase;
  final Map<String, int> liveCounts;
  final DateTime phaseStartedAt;
  final bool timedOut;
  final bool wsConnected;

  const SyncSetupProgressState({
    required this.phase,
    required this.liveCounts,
    required this.phaseStartedAt,
    required this.timedOut,
    required this.wsConnected,
  });

  factory SyncSetupProgressState.initial(DateTime now) =>
      SyncSetupProgressState(
        phase: PairingProgressPhase.connecting,
        liveCounts: const {},
        phaseStartedAt: now,
        timedOut: false,
        wsConnected: false,
      );

  SyncSetupProgressState copyWith({
    PairingProgressPhase? phase,
    Map<String, int>? liveCounts,
    DateTime? phaseStartedAt,
    bool? timedOut,
    bool? wsConnected,
  }) {
    return SyncSetupProgressState(
      phase: phase ?? this.phase,
      liveCounts: liveCounts ?? this.liveCounts,
      phaseStartedAt: phaseStartedAt ?? this.phaseStartedAt,
      timedOut: timedOut ?? this.timedOut,
      wsConnected: wsConnected ?? this.wsConnected,
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
    Object.hashAll(liveCounts.entries.map((e) => Object.hash(e.key, e.value))),
  );
}

class SyncSetupProgressNotifier extends Notifier<SyncSetupProgressState> {
  Timer? _flushTimer;
  final Map<String, int> _pendingTally = {};

  @override
  SyncSetupProgressState build() {
    ref.onDispose(() {
      _flushTimer?.cancel();
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
    state = state.copyWith(phase: next, phaseStartedAt: DateTime.now());
  }

  void markTimedOut() {
    state = state.copyWith(timedOut: true);
  }

  void reset() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _pendingTally.clear();
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

  void _flushPendingTally() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_pendingTally.isEmpty) return;
    final merged = Map<String, int>.from(state.liveCounts);
    _pendingTally.forEach((k, v) => merged[k] = (merged[k] ?? 0) + v);
    _pendingTally.clear();
    state = state.copyWith(liveCounts: Map.unmodifiable(merged));
  }
}

final syncSetupProgressProvider =
    NotifierProvider<SyncSetupProgressNotifier, SyncSetupProgressState>(
      SyncSetupProgressNotifier.new,
    );
