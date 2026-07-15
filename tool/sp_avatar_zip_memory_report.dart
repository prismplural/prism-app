import 'dart:convert';
import 'dart:io';

const spAvatarZipMaxPeakPssDeltaKb = 192 * 1024;
const spAvatarZipMaxPlateauGrowthKb = 24 * 1024;
const spAvatarZipMaxHeartbeatGapMicros = 500 * 1000;

class SpAvatarZipMemorySample {
  const SpAvatarZipMemorySample({
    required this.elapsedMs,
    required this.phase,
    required this.totalPssKb,
    required this.rssKb,
  });

  final int elapsedMs;
  final String phase;
  final int totalPssKb;
  final int rssKb;
}

List<SpAvatarZipMemorySample> parseSpAvatarZipMemorySamples(String csv) {
  final lines = const LineSplitter().convert(csv);
  if (lines.isEmpty || lines.first != 'elapsed_ms,phase,total_pss_kb,rss_kb') {
    throw const FormatException('Unexpected memory sample CSV header.');
  }

  final samples = <SpAvatarZipMemorySample>[];
  var priorElapsedMs = -1;
  for (final line in lines.skip(1)) {
    if (line.trim().isEmpty) continue;
    final fields = line.split(',');
    if (fields.length != 4) {
      throw FormatException('Malformed memory sample row: $line');
    }
    final elapsedMs = int.tryParse(fields[0]);
    final totalPssKb = int.tryParse(fields[2]);
    final rssKb = int.tryParse(fields[3]);
    if (elapsedMs == null || elapsedMs < priorElapsedMs) {
      throw FormatException('Invalid elapsed time in memory sample: $line');
    }
    if (fields[1].isEmpty || totalPssKb == null || totalPssKb <= 0) {
      throw FormatException('Invalid PSS sample: $line');
    }
    if (rssKb == null || rssKb <= 0) {
      throw FormatException('Invalid RSS sample: $line');
    }
    priorElapsedMs = elapsedMs;
    samples.add(
      SpAvatarZipMemorySample(
        elapsedMs: elapsedMs,
        phase: fields[1],
        totalPssKb: totalPssKb,
        rssKb: rssKb,
      ),
    );
  }
  if (samples.isEmpty) {
    throw const FormatException('Memory sample CSV contains no samples.');
  }
  return samples;
}

List<Map<String, Object?>> parseSpAvatarZipBenchmarkEvents(String log) {
  const prefix = 'SP_AVATAR_ZIP_BENCHMARK ';
  final events = <Map<String, Object?>>[];
  for (final line in const LineSplitter().convert(log)) {
    final prefixIndex = line.indexOf(prefix);
    if (prefixIndex < 0) continue;
    final raw = line.substring(prefixIndex + prefix.length).trim();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Benchmark event is not a JSON object.');
    }
    events.add(decoded);
  }
  if (events.isEmpty) {
    throw const FormatException('Benchmark log contains no structured events.');
  }
  return events;
}

Map<String, Object?> evaluateSpAvatarZipMemoryGate({
  required List<SpAvatarZipMemorySample> samples,
  required List<Map<String, Object?>> events,
  required String log,
  Map<String, Object?>? scaleBaseline,
}) {
  final completionEvents = events
      .where((event) => event['event'] == 'benchmark_complete')
      .toList();
  if (completionEvents.length != 1) {
    throw const FormatException(
      'Expected exactly one benchmark_complete event.',
    );
  }
  final completion = completionEvents.single;
  final count = _positiveInt(completion['count'], 'count');
  final repetitions = _positiveInt(completion['repetitions'], 'repetitions');
  final maximumHeartbeatGapMicros = _nonNegativeInt(
    completion['maximumHeartbeatGapMicros'],
    'maximumHeartbeatGapMicros',
  );
  if (completion['cacheCleaned'] != true) {
    throw const FormatException('Benchmark did not prove cache cleanup.');
  }

  final before = _samplesFor(samples, (phase) => phase == 'before');
  final importing = _samplesFor(
    samples,
    (phase) => phase.startsWith('import-'),
  );
  final cleanup = _samplesFor(samples, (phase) => phase == 'cleanup');
  final baselinePssKb = _median(before.map((sample) => sample.totalPssKb));
  final baselineRssKb = _median(before.map((sample) => sample.rssKb));
  final peakPssKb = importing
      .map((sample) => sample.totalPssKb)
      .reduce((a, b) => a > b ? a : b);
  final peakRssKb = importing
      .map((sample) => sample.rssKb)
      .reduce((a, b) => a > b ? a : b);
  final postCleanupPssKb = _median(cleanup.map((sample) => sample.totalPssKb));
  final postCleanupRssKb = _median(cleanup.map((sample) => sample.rssKb));
  final peakPssDeltaKb = peakPssKb - baselinePssKb;
  final postCleanupPssDeltaKb = postCleanupPssKb - baselinePssKb;

  final failures = <String>[];
  if (peakPssDeltaKb > spAvatarZipMaxPeakPssDeltaKb) {
    failures.add(
      'Peak total PSS delta $peakPssDeltaKb KiB exceeds '
      '$spAvatarZipMaxPeakPssDeltaKb KiB.',
    );
  }
  if (postCleanupPssDeltaKb > spAvatarZipMaxPlateauGrowthKb) {
    failures.add(
      'Post-cleanup total PSS delta $postCleanupPssDeltaKb KiB exceeds '
      '$spAvatarZipMaxPlateauGrowthKb KiB.',
    );
  }
  if (maximumHeartbeatGapMicros > spAvatarZipMaxHeartbeatGapMicros) {
    failures.add(
      'Main-isolate heartbeat gap $maximumHeartbeatGapMicros us exceeds '
      '$spAvatarZipMaxHeartbeatGapMicros us.',
    );
  }

  final fatalSignals = <String, RegExp>{
    'anr': RegExp(r'ANR in com\.prismplural\.prism', caseSensitive: false),
    'oom': RegExp(r'OutOfMemoryError|lowmemorykiller', caseSensitive: false),
  };
  // A valid run requires both completion markers; ANR/OOM scans are separate.
  final fatalCounts = <String, int>{'processDeath': 0};
  for (final entry in fatalSignals.entries) {
    final count = entry.value.allMatches(log).length;
    fatalCounts[entry.key] = count;
    if (count > 0) failures.add('${entry.key} signal count was $count.');
  }

  int? scalePlateauGrowthKb;
  if (scaleBaseline != null) {
    final baselineMetrics = scaleBaseline['metrics'];
    if (baselineMetrics is! Map<String, Object?>) {
      throw const FormatException('Scale baseline has no metrics object.');
    }
    // Fresh-process baselines require absolute peak comparisons.
    final scalePeakPssKb = _int(
      baselineMetrics['peakPssKb'],
      'scale baseline peakPssKb',
    );
    scalePlateauGrowthKb = peakPssKb - scalePeakPssKb;
    if (scalePlateauGrowthKb > spAvatarZipMaxPlateauGrowthKb) {
      failures.add(
        'Count-scale PSS growth $scalePlateauGrowthKb KiB exceeds '
        '$spAvatarZipMaxPlateauGrowthKb KiB.',
      );
    }
  }

  int? repeatedIdleGrowthKb;
  if (repetitions >= 3) {
    final firstIdle = _samplesFor(samples, (phase) => phase == 'after-1');
    final thirdIdle = _samplesFor(samples, (phase) => phase == 'after-3');
    repeatedIdleGrowthKb =
        _median(thirdIdle.map((sample) => sample.totalPssKb)) -
        _median(firstIdle.map((sample) => sample.totalPssKb));
    if (repeatedIdleGrowthKb > spAvatarZipMaxPlateauGrowthKb) {
      failures.add(
        'Third-import idle PSS growth $repeatedIdleGrowthKb KiB exceeds '
        '$spAvatarZipMaxPlateauGrowthKb KiB.',
      );
    }
  }

  return <String, Object?>{
    'schemaVersion': 1,
    'valid': failures.isEmpty,
    'case': completion['case'],
    'profile': completion['profile'],
    'count': count,
    'repetitions': repetitions,
    'fixtureZipSha256': completion['fixtureZipSha256'],
    'metrics': <String, Object?>{
      'baselinePssKb': baselinePssKb,
      'peakPssKb': peakPssKb,
      'peakPssDeltaKb': peakPssDeltaKb,
      'postCleanupPssKb': postCleanupPssKb,
      'postCleanupPssDeltaKb': postCleanupPssDeltaKb,
      'baselineRssKb': baselineRssKb,
      'peakRssKb': peakRssKb,
      'peakRssDeltaKb': peakRssKb - baselineRssKb,
      'postCleanupRssKb': postCleanupRssKb,
      'postCleanupRssDeltaKb': postCleanupRssKb - baselineRssKb,
      'maximumHeartbeatGapMicros': maximumHeartbeatGapMicros,
      'scalePlateauGrowthKb': scalePlateauGrowthKb,
      'repeatedIdleGrowthKb': repeatedIdleGrowthKb,
      'sampleCount': samples.length,
    },
    'limits': <String, int>{
      'peakPssDeltaKb': spAvatarZipMaxPeakPssDeltaKb,
      'plateauGrowthKb': spAvatarZipMaxPlateauGrowthKb,
      'heartbeatGapMicros': spAvatarZipMaxHeartbeatGapMicros,
    },
    'fatalSignals': fatalCounts,
    'failures': failures,
  };
}

List<SpAvatarZipMemorySample> _samplesFor(
  List<SpAvatarZipMemorySample> samples,
  bool Function(String phase) predicate,
) {
  final selected = samples.where((sample) => predicate(sample.phase)).toList();
  if (selected.isEmpty) {
    throw const FormatException('A required memory sampling window is empty.');
  }
  return selected;
}

int _median(Iterable<int> values) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) throw const FormatException('Cannot take empty median.');
  return sorted[sorted.length ~/ 2];
}

int _int(Object? value, String label) {
  if (value is! int || value is bool) {
    throw FormatException('$label is not an integer.');
  }
  return value;
}

int _positiveInt(Object? value, String label) {
  final parsed = _int(value, label);
  if (parsed <= 0) throw FormatException('$label is not positive.');
  return parsed;
}

int _nonNegativeInt(Object? value, String label) {
  final parsed = _int(value, label);
  if (parsed < 0) throw FormatException('$label is negative.');
  return parsed;
}

Future<void> main(List<String> args) async {
  final options = <String, String>{};
  for (var index = 0; index < args.length; index += 2) {
    if (index + 1 >= args.length || !args[index].startsWith('--')) {
      stderr.writeln(
        'Usage: dart run tool/sp_avatar_zip_memory_report.dart '
        '--samples <csv> --log <log> --out <json> '
        '[--scale-baseline <json>]',
      );
      exitCode = 64;
      return;
    }
    options[args[index].substring(2)] = args[index + 1];
  }
  final samplesPath = options['samples'];
  final logPath = options['log'];
  final outputPath = options['out'];
  if (samplesPath == null || logPath == null || outputPath == null) {
    stderr.writeln('--samples, --log, and --out are required.');
    exitCode = 64;
    return;
  }

  try {
    final log = await File(logPath).readAsString();
    Map<String, Object?>? scaleBaseline;
    final scaleBaselinePath = options['scale-baseline'];
    if (scaleBaselinePath != null) {
      final decoded = jsonDecode(await File(scaleBaselinePath).readAsString());
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('Scale baseline is not a JSON object.');
      }
      scaleBaseline = decoded;
    }
    final report = evaluateSpAvatarZipMemoryGate(
      samples: parseSpAvatarZipMemorySamples(
        await File(samplesPath).readAsString(),
      ),
      events: parseSpAvatarZipBenchmarkEvents(log),
      log: log,
      scaleBaseline: scaleBaseline,
    );
    final output = File(outputPath);
    if (await output.exists()) {
      throw FileSystemException(
        'Refusing to replace an existing report.',
        outputPath,
      );
    }
    await output.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    );
    if (report['valid'] != true) exitCode = 1;
  } on Object catch (error) {
    stderr.writeln('Memory report failed: $error');
    exitCode = 65;
  }
}
