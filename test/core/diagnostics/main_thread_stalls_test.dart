import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/diagnostics/main_thread_stalls.dart';

void main() {
  group('MainThreadStalls.stallReport', () {
    test('stays quiet when the timer fires roughly on time', () {
      expect(
        MainThreadStalls.stallReport(gapMicros: 120000, phases: const []),
        isNull,
      );
    });

    test('reports how long the isolate was blocked past the tick', () {
      expect(
        MainThreadStalls.stallReport(gapMicros: 450000, phases: const []),
        '[stall] UI isolate blocked ~400ms',
      );
    });

    test('names the phases recorded before the late tick', () {
      expect(
        MainThreadStalls.stallReport(
          gapMicros: 1050000,
          phases: const ['sync apply', 'media hydration walk'],
        ),
        '[stall] UI isolate blocked ~1000ms after sync apply, '
        'media hydration walk',
      );
    });
  });

  group('StallSampler', () {
    const tick = 50000;

    StallSampler running({int at = 0}) =>
        StallSampler()..lifecycleChanged(AppLifecycleState.resumed, at);

    test('reports a late tick with the breadcrumbs left since the last', () {
      final sampler = running()..phase('resume');

      expect(sampler.tick(tick), isNull);
      sampler.phase('sync apply');
      expect(
        sampler.tick(tick + 650000),
        '[stall] UI isolate blocked ~600ms after sync apply',
      );
    });

    test('a return to the foreground drops the suspension gap', () {
      final sampler = running();
      expect(sampler.tick(tick), isNull);

      sampler
        ..phase('before background')
        ..lifecycleChanged(AppLifecycleState.inactive, tick + 1000)
        ..lifecycleChanged(AppLifecycleState.hidden, tick + 2000)
        ..lifecycleChanged(AppLifecycleState.paused, tick + 3000);
      expect(sampler.isRunning, isFalse);
      expect(sampler.tick(30000000), isNull);

      const back = 45000000;
      sampler
        ..lifecycleChanged(AppLifecycleState.hidden, back)
        ..lifecycleChanged(AppLifecycleState.inactive, back)
        ..phase('resume')
        ..lifecycleChanged(AppLifecycleState.resumed, back + 1000);
      expect(sampler.isRunning, isTrue);
      expect(sampler.tick(back + tick), isNull);
    });

    test('without the reset the same gap would read as a stall', () {
      final sampler = running();
      expect(sampler.tick(tick), isNull);
      expect(sampler.tick(45000000 + tick), isNotNull);
    });

    test('a stall right after resume still reports', () {
      final sampler = running()
        ..lifecycleChanged(AppLifecycleState.paused, tick)
        ..lifecycleChanged(AppLifecycleState.resumed, 45000000)
        ..phase('resume');

      expect(
        sampler.tick(45000000 + tick + 800000),
        '[stall] UI isolate blocked ~800ms after resume',
      );
    });

    test('ignores breadcrumbs while backgrounded', () {
      final sampler = running()
        ..lifecycleChanged(AppLifecycleState.paused, tick)
        ..phase('while paused')
        ..lifecycleChanged(AppLifecycleState.resumed, 1000000);

      expect(
        sampler.tick(1000000 + tick + 300000),
        '[stall] UI isolate blocked ~300ms',
      );
    });
  });
}
