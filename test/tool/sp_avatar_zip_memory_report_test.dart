import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/sp_avatar_zip_memory_report.dart';

void main() {
  test('parses samples and accepts bounded memory and heartbeat data', () {
    final report = evaluateSpAvatarZipMemoryGate(
      samples: parseSpAvatarZipMemorySamples(_samples()),
      events: parseSpAvatarZipBenchmarkEvents(_log()),
      log: _log(),
      scaleBaseline: <String, Object?>{
        'metrics': <String, Object?>{'peakPssKb': 145000},
      },
    );

    expect(report['valid'], isTrue);
    expect(
      (report['metrics']! as Map<String, Object?>)['peakPssDeltaKb'],
      50000,
    );
    expect(
      (report['metrics']! as Map<String, Object?>)['repeatedIdleGrowthKb'],
      2000,
    );
  });

  test('rejects excess PSS, heartbeat stalls, and fatal process signals', () {
    final report = evaluateSpAvatarZipMemoryGate(
      samples: parseSpAvatarZipMemorySamples(
        _samples(importPssKb: 400000, cleanupPssKb: 140000),
      ),
      events: parseSpAvatarZipBenchmarkEvents(
        _log(maximumHeartbeatGapMicros: 500001),
      ),
      log:
          '${_log(maximumHeartbeatGapMicros: 500001)}\n'
          'ANR in com.prismplural.prism\n'
          'java.lang.OutOfMemoryError\n',
    );

    expect(report['valid'], isFalse);
    final failures = report['failures']! as List<Object?>;
    expect(failures, hasLength(greaterThanOrEqualTo(5)));
  });

  test('fails closed for malformed or incomplete evidence', () {
    expect(
      () => parseSpAvatarZipMemorySamples(
        'elapsed_ms,phase,total_pss_kb,rss_kb\n2,before,100,200\n1,import-1,101,201\n',
      ),
      throwsFormatException,
    );
    expect(
      () => evaluateSpAvatarZipMemoryGate(
        samples: parseSpAvatarZipMemorySamples(_samples()),
        events: const <Map<String, Object?>>[],
        log: '',
      ),
      throwsFormatException,
    );
  });
}

String _samples({int importPssKb = 150000, int cleanupPssKb = 102000}) =>
    'elapsed_ms,phase,total_pss_kb,rss_kb\n'
    '0,before,100000,150000\n'
    '1000,before,100000,150000\n'
    '2000,import-1,$importPssKb,220000\n'
    '3000,after-1,101000,151000\n'
    '4000,import-2,$importPssKb,220000\n'
    '5000,after-2,102000,152000\n'
    '6000,import-3,$importPssKb,220000\n'
    '7000,after-3,103000,153000\n'
    '8000,cleanup,$cleanupPssKb,152000\n';

String _log({int maximumHeartbeatGapMicros = 499999}) {
  final event = <String, Object?>{
    'event': 'benchmark_complete',
    'case': 'repeat-5000',
    'profile': 'scale-small',
    'count': 5000,
    'repetitions': 3,
    'maximumHeartbeatGapMicros': maximumHeartbeatGapMicros,
    'cacheCleaned': true,
    'fixtureZipSha256': 'abc',
  };
  return 'noise\nSP_AVATAR_ZIP_BENCHMARK ${jsonEncode(event)}\n';
}
