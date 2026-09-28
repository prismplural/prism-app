import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// UI-isolate stall logger. Debug/profile only — compiled out in release via
/// `kReleaseMode` short-circuit. On iOS the UI isolate is the platform main
/// thread, so a long synchronous stretch risks a system watchdog kill; a
/// periodic timer that fires late reveals how long the isolate was blocked.
class MainThreadStalls {
  MainThreadStalls._();

  static const _interval = Duration(milliseconds: 50);
  static const _threshold = Duration(milliseconds: 100);

  static Timer? _timer;
  static AppLifecycleListener? _lifecycle;
  static final Stopwatch _sw = Stopwatch();
  static final _sampler = StallSampler();

  static void start() {
    if (kReleaseMode || _lifecycle != null) return;
    _sw.start();
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycleChange);
    // Launch reports detached until the first view appears, so only a known
    // background state keeps the monitor off.
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != AppLifecycleState.hidden &&
        state != AppLifecycleState.paused) {
      _onLifecycleChange(AppLifecycleState.resumed);
    }
  }

  /// Leaves a breadcrumb, so the next stall report names what ran before it.
  static void phase(String label) {
    if (kReleaseMode) return;
    _sampler.phase(label);
  }

  static void _onLifecycleChange(AppLifecycleState state) {
    _sampler.lifecycleChanged(state, _sw.elapsedMicroseconds);
    if (_sampler.isRunning) {
      _timer ??= Timer.periodic(_interval, (_) => _tick());
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  static void _tick() {
    final report = _sampler.tick(_sw.elapsedMicroseconds);
    if (report != null) debugPrint(report);
  }

  @visibleForTesting
  static String? stallReport({
    required int gapMicros,
    required Iterable<String> phases,
  }) {
    final blockedMicros = gapMicros - _interval.inMicroseconds;
    if (blockedMicros < _threshold.inMicroseconds) return null;
    final after = phases.isEmpty ? '' : ' after ${phases.join(', ')}';
    return '[stall] UI isolate blocked ~${blockedMicros ~/ 1000}ms$after';
  }
}

/// Tick bookkeeping for [MainThreadStalls], driven by explicit timestamps so
/// tests need no real timers. A suspended app's timer fires late on return,
/// so leaving the foreground stops sampling and returning restarts it from a
/// fresh baseline.
@visibleForTesting
class StallSampler {
  int? _lastTickMicros;
  final Set<String> _phases = <String>{};

  bool get isRunning => _lastTickMicros != null;

  void lifecycleChanged(AppLifecycleState state, int nowMicros) {
    switch (state) {
      case AppLifecycleState.resumed || AppLifecycleState.inactive:
        if (isRunning) return;
        _lastTickMicros = nowMicros;
        _phases.clear();
      case AppLifecycleState.hidden ||
          AppLifecycleState.paused ||
          AppLifecycleState.detached:
        _lastTickMicros = null;
    }
  }

  void phase(String label) {
    if (isRunning) _phases.add(label);
  }

  String? tick(int nowMicros) {
    final last = _lastTickMicros;
    if (last == null) return null;
    final report = MainThreadStalls.stallReport(
      gapMicros: nowMicros - last,
      phases: _phases,
    );
    _lastTickMicros = nowMicros;
    _phases.clear();
    return report;
  }
}
