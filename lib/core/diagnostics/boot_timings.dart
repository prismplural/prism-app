import 'package:flutter/foundation.dart';

/// Lightweight startup profiling. Debug/profile only — compiled out in
/// release via `kReleaseMode` short-circuit.
class BootTimings {
  static final Stopwatch _sw = Stopwatch()..start();
  static void mark(String label) {
    if (kReleaseMode) return;
    debugPrint('[boot] +${_sw.elapsedMilliseconds}ms $label');
  }
}
