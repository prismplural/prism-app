import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/main_isolate_pulse_monitor.dart';

void main() {
  test('records pulses while the main event loop remains responsive', () async {
    final monitor = await MainIsolatePulseMonitor.start(
      interval: const Duration(milliseconds: 5),
    );

    await Future<void>.delayed(const Duration(milliseconds: 40));
    final summary = await monitor.stop();

    expect(summary.pulseCount, greaterThan(0));
    expect(summary.maximumGapMicros, greaterThan(0));
    expect(summary.toJson(thresholdMicros: 500000)['passed'], isTrue);
  });

  test('detects a synchronous main-isolate stall including the tail', () async {
    final monitor = await MainIsolatePulseMonitor.start(
      interval: const Duration(milliseconds: 5),
    );

    final stall = Stopwatch()..start();
    while (stall.elapsed < const Duration(milliseconds: 80)) {
      // Intentionally occupy this isolate. The pulse worker keeps sending, but
      // this isolate cannot receive those messages until the loop ends.
    }
    stall.stop();

    final summary = await monitor.stop();

    expect(summary.pulseCount, greaterThan(0));
    expect(summary.maximumGapMicros, greaterThanOrEqualTo(60000));
    expect(summary.toJson(thresholdMicros: 50000)['passed'], isFalse);
  });

  test('rejects a non-positive interval', () async {
    await expectLater(
      MainIsolatePulseMonitor.start(interval: Duration.zero),
      throwsArgumentError,
    );
  });

  test('cannot be stopped twice', () async {
    final monitor = await MainIsolatePulseMonitor.start(
      interval: const Duration(milliseconds: 5),
    );
    await monitor.stop();

    await expectLater(monitor.stop(), throwsStateError);
  });
}
