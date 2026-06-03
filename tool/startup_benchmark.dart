import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

const _usage = '''
Usage:
  dart run tool/startup_benchmark.dart --device <device-id> [options]

Runs Flutter's built-in --trace-startup benchmark repeatedly, then reports
per-run and median startup timings. This preserves the app data already on the
device/simulator; seed stress data separately before running.

Options:
  --device, -d <id>     Required Flutter device id.
  --runs, -n <count>    Number of cold process launches. Default: 3.
  --mode <mode>         debug, profile, or release. Default: debug.
  --target, -t <path>   Dart entrypoint. Default: lib/main.dart.
  --out <dir>           Output directory. Default: build/startup-benchmark.
  --dart-define <k=v>   Forwarded to flutter run. Repeatable.
  --help, -h            Show this help.

Notes:
  - Debug/simulator numbers are useful for local comparisons, not release truth.
  - Prefer --mode profile on a real Android/iOS device for decision-making.
''';

void main(List<String> args) async {
  final _Options options;
  try {
    options = _parseArgs(args);
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n');
    stderr.write(_usage);
    exitCode = 64;
    return;
  }
  if (options.help) {
    stdout.write(_usage);
    return;
  }
  if (options.deviceId == null || options.deviceId!.isEmpty) {
    stderr.writeln('Missing required --device <device-id>.\n');
    stderr.write(_usage);
    exitCode = 64;
    return;
  }
  if (options.runs < 1) {
    stderr.writeln('--runs must be at least 1.');
    exitCode = 64;
    return;
  }
  if (!{'debug', 'profile', 'release'}.contains(options.mode)) {
    stderr.writeln('--mode must be debug, profile, or release.');
    exitCode = 64;
    return;
  }

  final stamp = DateTime.now()
      .toIso8601String()
      .replaceAll(':', '-')
      .replaceAll('.', '-');
  final rootDir = Directory('${options.outDir}/$stamp');
  await rootDir.create(recursive: true);

  stdout.writeln('Startup benchmark');
  stdout.writeln('  device: ${options.deviceId}');
  stdout.writeln('  mode:   ${options.mode}');
  stdout.writeln('  runs:   ${options.runs}');
  stdout.writeln('  out:    ${rootDir.path}');
  stdout.writeln('');

  final results = <_StartupInfo>[];
  for (var i = 1; i <= options.runs; i++) {
    final runDir = Directory('${rootDir.path}/run-$i');
    await runDir.create(recursive: true);

    stdout.writeln('Run $i/${options.runs}');
    final exit = await _runFlutterTrace(options, runDir);
    if (exit != 0) {
      stderr.writeln('flutter run failed for run $i with exit code $exit.');
      exitCode = exit;
      return;
    }

    final infoFile = File('${runDir.path}/start_up_info.json');
    if (!await infoFile.exists()) {
      stderr.writeln(
        'Missing ${infoFile.path}; flutter did not write metrics.',
      );
      exitCode = 1;
      return;
    }

    final info = _StartupInfo.fromJson(
      jsonDecode(await infoFile.readAsString()) as Map<String, Object?>,
      run: i,
    );
    results.add(info);
    stdout.writeln('  ${info.summary}');
    stdout.writeln('');
  }

  _printSummary(results);
}

Future<int> _runFlutterTrace(_Options options, Directory runDir) async {
  final modeArg = switch (options.mode) {
    'debug' => '--debug',
    'profile' => '--profile',
    'release' => '--release',
    _ => throw StateError('unsupported mode ${options.mode}'),
  };

  final args = [
    'run',
    '-d',
    options.deviceId!,
    modeArg,
    '--trace-startup',
    '--no-hot',
    '-t',
    options.target,
    for (final define in options.dartDefines) ...['--dart-define', define],
  ];

  final process = await Process.start(
    'flutter',
    args,
    environment: {
      ...Platform.environment,
      'FLUTTER_TEST_OUTPUTS_DIR': runDir.path,
    },
  );

  process.stdout.transform(utf8.decoder).listen(stdout.write);
  process.stderr.transform(utf8.decoder).listen(stderr.write);
  return process.exitCode;
}

void _printSummary(List<_StartupInfo> results) {
  stdout.writeln('Summary');
  stdout.writeln(
    'run  framework  after-framework  first-frame  rasterized-first-frame',
  );
  for (final result in results) {
    stdout.writeln(
      '${result.run.toString().padLeft(3)}  '
      '${_ms(result.frameworkInitMicros).padLeft(9)}  '
      '${_ms(result.afterFrameworkInitMicros).padLeft(15)}  '
      '${_ms(result.firstFrameMicros).padLeft(11)}  '
      '${_ms(result.firstFrameRasterizedMicros).padLeft(22)}',
    );
  }
  stdout.writeln('');
  stdout.writeln(
    'median first frame: ${_ms(_median(results.map((r) => r.firstFrameMicros)))}',
  );
  stdout.writeln(
    'median rasterized first frame: '
    '${_ms(_median(results.map((r) => r.firstFrameRasterizedMicros)))}',
  );
  stdout.writeln(
    'min/max first frame: '
    '${_ms(results.map((r) => r.firstFrameMicros).reduce(math.min))} / '
    '${_ms(results.map((r) => r.firstFrameMicros).reduce(math.max))}',
  );
}

int _median(Iterable<int> values) {
  final sorted = values.toList()..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return ((sorted[middle - 1] + sorted[middle]) / 2).round();
}

String _ms(int micros) => '${(micros / 1000).toStringAsFixed(0)}ms';

class _StartupInfo {
  const _StartupInfo({
    required this.run,
    required this.frameworkInitMicros,
    required this.afterFrameworkInitMicros,
    required this.firstFrameMicros,
    required this.firstFrameRasterizedMicros,
  });

  factory _StartupInfo.fromJson(Map<String, Object?> json, {required int run}) {
    int read(String key) {
      final value = json[key];
      if (value is int) return value;
      throw FormatException('Expected integer $key in start_up_info.json');
    }

    return _StartupInfo(
      run: run,
      frameworkInitMicros: read('timeToFrameworkInitMicros'),
      afterFrameworkInitMicros: read('timeAfterFrameworkInitMicros'),
      firstFrameMicros: read('timeToFirstFrameMicros'),
      firstFrameRasterizedMicros: read('timeToFirstFrameRasterizedMicros'),
    );
  }

  final int run;
  final int frameworkInitMicros;
  final int afterFrameworkInitMicros;
  final int firstFrameMicros;
  final int firstFrameRasterizedMicros;

  String get summary =>
      'framework=${_ms(frameworkInitMicros)}, '
      'afterFramework=${_ms(afterFrameworkInitMicros)}, '
      'firstFrame=${_ms(firstFrameMicros)}, '
      'rasterized=${_ms(firstFrameRasterizedMicros)}';
}

class _Options {
  const _Options({
    required this.help,
    required this.runs,
    required this.mode,
    required this.target,
    required this.outDir,
    required this.dartDefines,
    this.deviceId,
  });

  final bool help;
  final String? deviceId;
  final int runs;
  final String mode;
  final String target;
  final String outDir;
  final List<String> dartDefines;
}

_Options _parseArgs(List<String> args) {
  var help = false;
  String? deviceId;
  var runs = 3;
  var mode = 'debug';
  var target = 'lib/main.dart';
  var outDir = 'build/startup-benchmark';
  final dartDefines = <String>[];

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    String nextValue() {
      if (i + 1 >= args.length) {
        throw FormatException('Missing value for $arg');
      }
      return args[++i];
    }

    switch (arg) {
      case '--help':
      case '-h':
        help = true;
      case '--device':
      case '-d':
        deviceId = nextValue();
      case '--runs':
      case '-n':
        runs = int.parse(nextValue());
      case '--mode':
        mode = nextValue();
      case '--target':
      case '-t':
        target = nextValue();
      case '--out':
        outDir = nextValue();
      case '--dart-define':
        dartDefines.add(nextValue());
      default:
        throw FormatException('Unknown argument: $arg');
    }
  }

  return _Options(
    help: help,
    deviceId: deviceId,
    runs: runs,
    mode: mode,
    target: target,
    outDir: outDir,
    dartDefines: dartDefines,
  );
}
