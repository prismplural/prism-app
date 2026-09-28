import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/main_isolate_pulse_monitor.dart';

/// Expects [offMain] to keep the main isolate responsive, measured against
/// [inline]: the same work run synchronously, which is the stall a regression
/// back onto the main isolate would cause. Retrying keeps a loaded host's
/// scheduling hiccups from failing correct code; a regression stalls every try.
Future<void> expectStaysResponsive({
  required Future<void> Function() offMain,
  required void Function() inline,
  Duration pulseInterval = const Duration(milliseconds: 5),
  int attempts = 3,
}) async {
  var smallestGapMicros = 1 << 62;
  var fastestInlineMicros = 1 << 62;
  for (var attempt = 0; attempt < attempts; attempt++) {
    final monitor = await MainIsolatePulseMonitor.start(
      interval: pulseInterval,
    );
    await offMain();
    final summary = await monitor.stop();
    smallestGapMicros = min(smallestGapMicros, summary.maximumGapMicros);

    // Timed second, so it runs code the off-main pass already JIT-compiled.
    final stopwatch = Stopwatch()..start();
    inline();
    fastestInlineMicros = min(
      fastestInlineMicros,
      stopwatch.elapsedMicroseconds,
    );

    if (smallestGapMicros < fastestInlineMicros ~/ 3) return;
  }
  fail(
    'main isolate blocked ${smallestGapMicros}us during the off-main run; '
    'the same work inline takes ${fastestInlineMicros}us',
  );
}
