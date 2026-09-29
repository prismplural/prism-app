import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Main-isolate stall logger. Debug/profile only — compiled out in release via
/// `kReleaseMode` short-circuit. On iOS the main isolate runs on the platform
/// main thread, so a long synchronous stretch risks a system watchdog kill; a
/// periodic timer that fires late reveals how long the isolate was blocked.
class MainIsolateStalls {
  MainIsolateStalls._();

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
  static void mark(String label) {
    if (kReleaseMode) return;
    _sampler.mark(label);
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
    required Iterable<String> marks,
  }) {
    final blockedMicros = gapMicros - _interval.inMicroseconds;
    if (blockedMicros < _threshold.inMicroseconds) return null;
    final after = marks.isEmpty ? '' : ' after ${marks.join(', ')}';
    return '[stall] main isolate blocked ~${blockedMicros ~/ 1000}ms$after';
  }
}

/// Tick bookkeeping for [MainIsolateStalls], driven by explicit timestamps so
/// tests need no real timers. A suspended app's timer fires late on return,
/// so leaving the foreground stops sampling and returning restarts it from a
/// fresh baseline.
@visibleForTesting
class StallSampler {
  int? _lastTickMicros;
  final Set<String> _marks = <String>{};

  bool get isRunning => _lastTickMicros != null;

  void lifecycleChanged(AppLifecycleState state, int nowMicros) {
    switch (state) {
      case AppLifecycleState.resumed || AppLifecycleState.inactive:
        if (isRunning) return;
        _lastTickMicros = nowMicros;
        _marks.clear();
      case AppLifecycleState.hidden ||
          AppLifecycleState.paused ||
          AppLifecycleState.detached:
        _lastTickMicros = null;
    }
  }

  void mark(String label) {
    if (isRunning) _marks.add(label);
  }

  String? tick(int nowMicros) {
    final last = _lastTickMicros;
    if (last == null) return null;
    final report = MainIsolateStalls.stallReport(
      gapMicros: nowMicros - last,
      marks: _marks,
    );
    _lastTickMicros = nowMicros;
    _marks.clear();
    return report;
  }
}
