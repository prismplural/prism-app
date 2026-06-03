import 'package:flutter/foundation.dart';

/// Lightweight startup profiling. Debug/profile only — compiled out in
/// release via `kReleaseMode` short-circuit.
class BootTimings {
  static final Stopwatch _sw = Stopwatch()..start();
  static final Set<String> _seenOnce = <String>{};

  static void mark(String label) {
    if (kReleaseMode) return;
    debugPrint('[boot] +${_sw.elapsedMilliseconds}ms $label');
  }

  static void markOnce(String label, [String? detail]) {
    if (kReleaseMode) return;
    if (!_seenOnce.add(label)) return;
    mark(detail == null ? label : '$label $detail');
  }
}
