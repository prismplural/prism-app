import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

/// Measures how long the main isolate goes without servicing event messages.
///
/// A helper isolate emits pulses at [interval]. Receiving and timestamping each
/// pulse happens on the main isolate, so a long gap indicates that the app's
/// event loop could not service frames, input, platform messages, or this port.
/// This is profile/development test instrumentation, not production telemetry.
final class MainIsolatePulseMonitor {
  MainIsolatePulseMonitor._({
    required this.interval,
    required ReceivePort receivePort,
    required StreamSubscription<Object?> subscription,
    required SendPort controlPort,
    required Stopwatch clock,
    required int Function() readPulseCount,
    required int Function() readMaximumGapMicros,
    required Completer<void> stopped,
  }) : _receivePort = receivePort,
       _subscription = subscription,
       _controlPort = controlPort,
       _clock = clock,
       _readPulseCount = readPulseCount,
       _readMaximumGapMicros = readMaximumGapMicros,
       _stopped = stopped;

  final Duration interval;
  final ReceivePort _receivePort;
  final StreamSubscription<Object?> _subscription;
  final SendPort _controlPort;
  final Stopwatch _clock;
  final int Function() _readPulseCount;
  final int Function() _readMaximumGapMicros;
  final Completer<void> _stopped;
  bool _isStopped = false;

  static Future<MainIsolatePulseMonitor> start({
    Duration interval = const Duration(milliseconds: 16),
  }) async {
    if (interval <= Duration.zero) {
      throw ArgumentError.value(interval, 'interval', 'must be positive');
    }

    final receivePort = ReceivePort();
    final ready = Completer<SendPort>();
    final firstPulse = Completer<void>();
    final stopped = Completer<void>();
    final clock = Stopwatch()..start();
    var lastPulseMicros = 0;
    var pulseCount = 0;
    var maximumGapMicros = 0;

    // The returned monitor owns and cancels this subscription in [stop].
    // ignore: cancel_subscriptions
    late final StreamSubscription<Object?> subscription;
    subscription = receivePort.listen((message) {
      if (message is SendPort) {
        lastPulseMicros = clock.elapsedMicroseconds;
        ready.complete(message);
        return;
      }
      if (message == _finalPulse) {
        final nowMicros = clock.elapsedMicroseconds;
        maximumGapMicros = math.max(
          maximumGapMicros,
          nowMicros - lastPulseMicros,
        );
        stopped.complete();
        return;
      }

      final nowMicros = clock.elapsedMicroseconds;
      maximumGapMicros = math.max(
        maximumGapMicros,
        nowMicros - lastPulseMicros,
      );
      lastPulseMicros = nowMicros;
      pulseCount++;
      if (!firstPulse.isCompleted) firstPulse.complete();
    });

    Isolate? worker;
    final spawnFuture = Isolate.spawn(_emitPulses, (
      receivePort.sendPort,
      interval,
    ));
    try {
      worker = await spawnFuture.timeout(const Duration(seconds: 5));
      final controlPort = await ready.future.timeout(
        const Duration(seconds: 5),
      );
      await firstPulse.future.timeout(const Duration(seconds: 5));
      return MainIsolatePulseMonitor._(
        interval: interval,
        receivePort: receivePort,
        subscription: subscription,
        controlPort: controlPort,
        clock: clock,
        readPulseCount: () => pulseCount,
        readMaximumGapMicros: () => maximumGapMicros,
        stopped: stopped,
      );
    } catch (_) {
      if (worker != null) {
        worker.kill(priority: Isolate.immediate);
      } else {
        // If the timeout won before spawn completed, kill the eventual isolate
        // result rather than dropping the only handle to its periodic timer.
        unawaited(
          spawnFuture.then<void>(
            (isolate) => isolate.kill(priority: Isolate.immediate),
            onError: (Object _, StackTrace _) {},
          ),
        );
      }
      await subscription.cancel();
      receivePort.close();
      clock.stop();
      rethrow;
    }
  }

  /// Stops the emitter and returns a summary including the final tail gap.
  ///
  /// The worker sends [_finalPulse] only after cancelling its timer. Messages
  /// from its send port are ordered, so observing that marker proves all earlier
  /// pulses have reached the main isolate and prevents a stall immediately
  /// before [stop] from escaping measurement.
  Future<MainIsolatePulseSummary> stop() async {
    if (_isStopped) {
      throw StateError('MainIsolatePulseMonitor.stop called more than once');
    }
    _isStopped = true;
    _controlPort.send(null);
    try {
      await _stopped.future.timeout(const Duration(seconds: 5));
      return MainIsolatePulseSummary(
        intervalMicros: interval.inMicroseconds,
        pulseCount: _readPulseCount(),
        maximumGapMicros: _readMaximumGapMicros(),
      );
    } finally {
      await _subscription.cancel();
      _receivePort.close();
      _clock.stop();
    }
  }
}

final class MainIsolatePulseSummary {
  const MainIsolatePulseSummary({
    required this.intervalMicros,
    required this.pulseCount,
    required this.maximumGapMicros,
  });

  final int intervalMicros;
  final int pulseCount;
  final int maximumGapMicros;

  Map<String, Object> toJson({int thresholdMicros = 500000}) => {
    'intervalMicros': intervalMicros,
    'pulseCount': pulseCount,
    'maximumGapMicros': maximumGapMicros,
    'thresholdMicros': thresholdMicros,
    'passed': maximumGapMicros <= thresholdMicros,
  };
}

const String _finalPulse = 'main-isolate-pulse-final';

void _emitPulses((SendPort, Duration) input) {
  final (output, interval) = input;
  final control = ReceivePort();
  output.send(control.sendPort);
  final timer = Timer.periodic(interval, (_) => output.send(0));
  control.first.whenComplete(() {
    timer.cancel();
    output.send(_finalPulse);
    control.close();
  });
}
