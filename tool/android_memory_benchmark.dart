import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

const _usage = '''
Usage:
  dart run tool/android_memory_benchmark.dart [options]

Launches or uses an Android emulator/device, runs the Prism stress integration
benchmark, and samples `adb shell dumpsys meminfo` for the app process.

Options:
  --launch-avd <name>       Launch this AVD before running.
  --device, -d <serial>     Android device serial. Required unless --launch-avd
                            is used with --emulator-port.
  --emulator-port <port>    Emulator console port when launching. Default: 5570.
  --memory-mb <mb>          Emulator RAM override. Default: 4096.
  --cores <count>           Emulator CPU core override. Default: 2.
  --headless                Launch emulator without a window.
  --keep-emulator           Leave a launched emulator running after the test.
  --clear-data              Clear Prism app data before running.
  --package <id>            Android package id. Default: com.prismplural.prism.
  --preset <name>           reportedLarge, heavy5k, huge, or massive.
                            Default: reportedLarge.
  --mode <mode>             debug or profile. Default: profile.
  --sample-ms <ms>          Meminfo sampling interval. Default: 2000.
  --screenshot-ms <ms>      Optional screenshot sampling interval. Disabled by
                            default. Use 500-1000 for visual pop-in checks.
  --out <dir>               Output root. Default: build/android-memory-benchmark.
  --help, -h                Show this help.

Example:
  dart run tool/android_memory_benchmark.dart \\
    --launch-avd PrismBenchmarkApi35 \\
    --memory-mb 4096 \\
    --cores 2 \\
    --preset reportedLarge \\
    --clear-data
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

  if (options.launchAvd == null && options.deviceId == null) {
    stderr.writeln('Missing --device <serial> or --launch-avd <name>.\n');
    stderr.write(_usage);
    exitCode = 64;
    return;
  }

  final stamp = DateTime.now()
      .toIso8601String()
      .replaceAll(':', '-')
      .replaceAll('.', '-');
  final runDir = Directory('${options.outDir}/$stamp');
  final rawDir = Directory('${runDir.path}/meminfo-raw');
  final screenshotDir = Directory('${runDir.path}/screenshots');
  await rawDir.create(recursive: true);
  if (options.screenshotMs != null) {
    await screenshotDir.create(recursive: true);
  }

  final logFile = File('${runDir.path}/flutter-test.log');
  final csvFile = File('${runDir.path}/meminfo.csv');
  final summaryFile = File('${runDir.path}/summary.json');

  Process? emulatorProcess;
  var deviceId =
      options.deviceId ??
      (options.launchAvd == null ? null : 'emulator-${options.emulatorPort}');

  try {
    if (options.launchAvd != null) {
      emulatorProcess = await _launchEmulator(options, runDir);
      deviceId ??= 'emulator-${options.emulatorPort}';
    }

    if (deviceId == null) {
      throw StateError('No Android device serial resolved.');
    }

    await _waitForBoot(deviceId);
    final deviceInfo = await _collectDeviceInfo(deviceId);
    await File(
      '${runDir.path}/device.json',
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(deviceInfo));

    if (options.clearData) {
      await _run('adb', [
        '-s',
        deviceId,
        'shell',
        'pm',
        'clear',
        options.packageId,
      ], allowFailure: true);
    }

    stdout.writeln('Android memory benchmark');
    stdout.writeln('  device: $deviceId');
    stdout.writeln('  package: ${options.packageId}');
    stdout.writeln('  mode: ${options.mode}');
    stdout.writeln('  preset: ${options.preset}');
    stdout.writeln('  sample: ${options.sampleMs}ms');
    stdout.writeln('  out: ${runDir.path}');
    stdout.writeln('');

    await csvFile.writeAsString(_MemSample.csvHeader);

    final sampler = _MeminfoSampler(
      deviceId: deviceId,
      packageId: options.packageId,
      interval: Duration(milliseconds: options.sampleMs),
      rawDir: rawDir,
      csvFile: csvFile,
    );
    final screenshotSampler = options.screenshotMs == null
        ? null
        : _ScreenshotSampler(
            deviceId: deviceId,
            interval: Duration(milliseconds: options.screenshotMs!),
            screenshotDir: screenshotDir,
          );
    final samplerFuture = sampler.start();
    final screenshotFuture = screenshotSampler?.start();
    int flutterExitCode;
    try {
      flutterExitCode = await _runFlutterTest(options, deviceId, logFile);
    } finally {
      await Future.wait([
        sampler.stop(),
        if (screenshotSampler != null) screenshotSampler.stop(),
      ]);
      await Future.wait([samplerFuture, ?screenshotFuture]);
    }

    final summary = sampler.summary(
      deviceInfo: deviceInfo,
      flutterExitCode: flutterExitCode,
      runDir: runDir.path,
      screenshots: screenshotSampler?.count,
    );
    await summaryFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(summary),
    );

    _printSummary(summary);
    exitCode = flutterExitCode;
  } finally {
    if (emulatorProcess != null && !options.keepEmulator) {
      emulatorProcess.kill();
    }
  }
}

Future<Process> _launchEmulator(_Options options, Directory runDir) async {
  final args = [
    '-avd',
    options.launchAvd!,
    '-port',
    options.emulatorPort.toString(),
    '-memory',
    options.memoryMb.toString(),
    '-cores',
    options.cores.toString(),
    '-no-snapshot-load',
    '-no-snapshot-save',
    '-no-boot-anim',
    '-no-audio',
    if (options.headless) '-no-window',
  ];

  final process = await Process.start('emulator', args);
  final log = File('${runDir.path}/emulator.log').openWrite();
  process.stdout.transform(utf8.decoder).listen(log.write);
  process.stderr.transform(utf8.decoder).listen(log.write);
  unawaited(process.exitCode.whenComplete(log.close));
  return process;
}

Future<void> _waitForBoot(String deviceId) async {
  stdout.writeln('Waiting for Android device $deviceId...');
  await _run('adb', ['-s', deviceId, 'wait-for-device']);

  for (var i = 0; i < 180; i++) {
    final booted = await _run(
      'adb',
      ['-s', deviceId, 'shell', 'getprop', 'sys.boot_completed'],
      trim: true,
      allowFailure: true,
    );
    if (booted.stdout == '1') {
      await _run('adb', [
        '-s',
        deviceId,
        'shell',
        'input',
        'keyevent',
        '82',
      ], allowFailure: true);
      return;
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }

  throw TimeoutException('Timed out waiting for $deviceId to boot.');
}

Future<Map<String, Object?>> _collectDeviceInfo(String deviceId) async {
  Future<String> prop(String key) async {
    final result = await _run(
      'adb',
      ['-s', deviceId, 'shell', 'getprop', key],
      trim: true,
      allowFailure: true,
    );
    return result.stdout;
  }

  final meminfo = await _run('adb', [
    '-s',
    deviceId,
    'shell',
    'cat',
    '/proc/meminfo',
  ], allowFailure: true);

  return {
    'serial': deviceId,
    'avd': await prop('ro.boot.qemu.avd_name'),
    'model': await prop('ro.product.model'),
    'manufacturer': await prop('ro.product.manufacturer'),
    'androidRelease': await prop('ro.build.version.release'),
    'sdk': await prop('ro.build.version.sdk'),
    'hardware': await prop('ro.hardware'),
    'kernelQemu': await prop('ro.kernel.qemu'),
    'meminfo': meminfo.stdout,
  };
}

Future<int> _runFlutterTest(
  _Options options,
  String deviceId,
  File logFile,
) async {
  final modeArg = switch (options.mode) {
    'debug' => '--debug',
    'profile' => '--profile',
    _ => throw StateError('Unsupported mode ${options.mode}'),
  };

  final args = [
    'drive',
    '-d',
    deviceId,
    modeArg,
    '--no-dds',
    '--driver=test_driver/integration_test.dart',
    '--target=integration_test/stress_benchmark_test.dart',
    '--dart-define=PRISM_STRESS_PRESET=${options.preset}',
  ];

  final process = await Process.start('flutter', args);
  final log = logFile.openWrite();

  process.stdout.transform(utf8.decoder).listen((chunk) {
    stdout.write(chunk);
    log.write(chunk);
  });
  process.stderr.transform(utf8.decoder).listen((chunk) {
    stderr.write(chunk);
    log.write(chunk);
  });

  final exit = await process.exitCode;
  await log.close();
  return exit;
}

Future<_RunResult> _run(
  String executable,
  List<String> args, {
  bool trim = false,
  bool allowFailure = false,
}) async {
  final result = await Process.run(executable, args);
  final stdoutText = result.stdout.toString();
  final stderrText = result.stderr.toString();
  if (result.exitCode != 0 && !allowFailure) {
    throw ProcessException(
      executable,
      args,
      'exit ${result.exitCode}\n$stderrText',
      result.exitCode,
    );
  }
  return _RunResult(
    exitCode: result.exitCode,
    stdout: trim ? stdoutText.trim() : stdoutText,
    stderr: trim ? stderrText.trim() : stderrText,
  );
}

void _printSummary(Map<String, Object?> summary) {
  stdout.writeln('');
  stdout.writeln('Memory summary');
  stdout.writeln('  samples: ${summary['samples']}');
  stdout.writeln('  first total PSS: ${summary['firstTotalPssKb']} KB');
  stdout.writeln('  peak total PSS: ${summary['peakTotalPssKb']} KB');
  stdout.writeln('  last total PSS: ${summary['lastTotalPssKb']} KB');
  stdout.writeln(
    '  peak native heap PSS: ${summary['peakNativeHeapPssKb']} KB',
  );
  stdout.writeln(
    '  peak Dalvik heap PSS: ${summary['peakDalvikHeapPssKb']} KB',
  );
  stdout.writeln('  peak graphics PSS: ${summary['peakGraphicsPssKb']} KB');
  stdout.writeln('  flutter exit: ${summary['flutterExitCode']}');
  stdout.writeln('  screenshots: ${summary['screenshots']}');
  stdout.writeln('  out: ${summary['runDir']}');
}

class _MeminfoSampler {
  _MeminfoSampler({
    required this.deviceId,
    required this.packageId,
    required this.interval,
    required this.rawDir,
    required this.csvFile,
  });

  final String deviceId;
  final String packageId;
  final Duration interval;
  final Directory rawDir;
  final File csvFile;

  final List<_MemSample> _samples = [];
  final Stopwatch _elapsed = Stopwatch();
  final Completer<void> _stopped = Completer<void>();
  var _stopRequested = false;

  Future<void> start() async {
    _elapsed.start();
    var index = 0;
    while (!_stopRequested) {
      index += 1;
      final started = DateTime.now().toUtc();
      final result = await _run('adb', [
        '-s',
        deviceId,
        'shell',
        'dumpsys',
        'meminfo',
        packageId,
      ], allowFailure: true);
      final raw = result.stdout.isNotEmpty ? result.stdout : result.stderr;
      final rawPath =
          '${rawDir.path}/sample-${index.toString().padLeft(4, '0')}.txt';
      await File(rawPath).writeAsString(raw);

      final sample = _MemSample.parse(
        index: index,
        timestamp: started,
        elapsedMs: _elapsed.elapsedMilliseconds,
        raw: raw,
        status: result.exitCode == 0 ? 'ok' : 'adb-exit-${result.exitCode}',
      );
      _samples.add(sample);
      await csvFile.writeAsString(sample.csvRow, mode: FileMode.append);

      await Future<void>.delayed(interval);
    }
    _elapsed.stop();
    _stopped.complete();
  }

  Future<void> stop() async {
    _stopRequested = true;
    return _stopped.future;
  }

  Map<String, Object?> summary({
    required Map<String, Object?> deviceInfo,
    required int flutterExitCode,
    required String runDir,
    required int? screenshots,
  }) {
    final withPss = _samples.where((s) => s.totalPssKb != null).toList();
    int? maxOf(int? Function(_MemSample sample) read) {
      final values = _samples.map(read).whereType<int>().toList();
      if (values.isEmpty) return null;
      return values.reduce(math.max);
    }

    return {
      'runDir': runDir,
      'device': deviceInfo,
      'flutterExitCode': flutterExitCode,
      'samples': _samples.length,
      'screenshots': screenshots,
      'firstTotalPssKb': withPss.isEmpty ? null : withPss.first.totalPssKb,
      'peakTotalPssKb': maxOf((s) => s.totalPssKb),
      'lastTotalPssKb': withPss.isEmpty ? null : withPss.last.totalPssKb,
      'peakNativeHeapPssKb': maxOf((s) => s.nativeHeapPssKb),
      'peakDalvikHeapPssKb': maxOf((s) => s.dalvikHeapPssKb),
      'peakGraphicsPssKb': maxOf((s) => s.graphicsPssKb),
      'peakEglMtrackPssKb': maxOf((s) => s.eglMtrackPssKb),
      'peakGlMtrackPssKb': maxOf((s) => s.glMtrackPssKb),
    };
  }
}

class _ScreenshotSampler {
  _ScreenshotSampler({
    required this.deviceId,
    required this.interval,
    required this.screenshotDir,
  });

  final String deviceId;
  final Duration interval;
  final Directory screenshotDir;

  final Stopwatch _elapsed = Stopwatch();
  final Completer<void> _stopped = Completer<void>();
  var _stopRequested = false;
  var _count = 0;

  int get count => _count;

  Future<void> start() async {
    _elapsed.start();
    while (!_stopRequested) {
      _count += 1;
      final elapsed = _elapsed.elapsedMilliseconds.toString().padLeft(7, '0');
      final path =
          '${screenshotDir.path}/screen-${_count.toString().padLeft(4, '0')}'
          '-${elapsed}ms.png';
      await _captureScreenshot(path);
      await Future<void>.delayed(interval);
    }
    _elapsed.stop();
    _stopped.complete();
  }

  Future<void> stop() async {
    _stopRequested = true;
    return _stopped.future;
  }

  Future<void> _captureScreenshot(String path) async {
    final result = await Process.run(
      'adb',
      ['-s', deviceId, 'exec-out', 'screencap', '-p'],
      stdoutEncoding: null,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0 || result.stdout is! List<int>) return;
    await File(path).writeAsBytes(result.stdout as List<int>);
  }
}

class _MemSample {
  const _MemSample({
    required this.index,
    required this.timestamp,
    required this.elapsedMs,
    required this.pid,
    required this.totalPssKb,
    required this.nativeHeapPssKb,
    required this.dalvikHeapPssKb,
    required this.graphicsPssKb,
    required this.eglMtrackPssKb,
    required this.glMtrackPssKb,
    required this.status,
  });

  factory _MemSample.parse({
    required int index,
    required DateTime timestamp,
    required int elapsedMs,
    required String raw,
    required String status,
  }) {
    int? readRow(String label) {
      final match = RegExp(
        '^\\s*${RegExp.escape(label)}\\s+(\\d+)\\b',
        multiLine: true,
      ).firstMatch(raw);
      return match == null ? null : int.tryParse(match.group(1)!);
    }

    int? readAppSummary(String label) {
      final match = RegExp(
        '^\\s*${RegExp.escape(label)}:\\s+(\\d+)\\b',
        multiLine: true,
      ).firstMatch(raw);
      return match == null ? null : int.tryParse(match.group(1)!);
    }

    final pidMatch = RegExp(r'\bpid\s+(\d+)\b').firstMatch(raw);
    final totalPss =
        readRow('TOTAL') ??
        readAppSummary('TOTAL') ??
        _readFirstInt(RegExp(r'TOTAL PSS:\s+(\d+)').firstMatch(raw));

    return _MemSample(
      index: index,
      timestamp: timestamp,
      elapsedMs: elapsedMs,
      pid: _readFirstInt(pidMatch),
      totalPssKb: totalPss,
      nativeHeapPssKb: readRow('Native Heap') ?? readAppSummary('Native Heap'),
      dalvikHeapPssKb: readRow('Dalvik Heap') ?? readAppSummary('Java Heap'),
      graphicsPssKb: readRow('Graphics') ?? readAppSummary('Graphics'),
      eglMtrackPssKb: readRow('EGL mtrack'),
      glMtrackPssKb: readRow('GL mtrack'),
      status: totalPss == null ? 'no-process' : status,
    );
  }

  static int? _readFirstInt(RegExpMatch? match) {
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  static const csvHeader =
      'sample,timestamp,elapsedMs,pid,totalPssKb,nativeHeapPssKb,'
      'dalvikHeapPssKb,graphicsPssKb,eglMtrackPssKb,glMtrackPssKb,status\n';

  final int index;
  final DateTime timestamp;
  final int elapsedMs;
  final int? pid;
  final int? totalPssKb;
  final int? nativeHeapPssKb;
  final int? dalvikHeapPssKb;
  final int? graphicsPssKb;
  final int? eglMtrackPssKb;
  final int? glMtrackPssKb;
  final String status;

  String get csvRow {
    String cell(Object? value) => value?.toString() ?? '';
    return '${[index, timestamp.toIso8601String(), elapsedMs, pid, totalPssKb, nativeHeapPssKb, dalvikHeapPssKb, graphicsPssKb, eglMtrackPssKb, glMtrackPssKb, status].map(cell).join(',')}\n';
  }
}

class _RunResult {
  const _RunResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

class _Options {
  const _Options({
    required this.help,
    required this.launchAvd,
    required this.deviceId,
    required this.emulatorPort,
    required this.memoryMb,
    required this.cores,
    required this.headless,
    required this.keepEmulator,
    required this.clearData,
    required this.packageId,
    required this.preset,
    required this.mode,
    required this.sampleMs,
    required this.screenshotMs,
    required this.outDir,
  });

  final bool help;
  final String? launchAvd;
  final String? deviceId;
  final int emulatorPort;
  final int memoryMb;
  final int cores;
  final bool headless;
  final bool keepEmulator;
  final bool clearData;
  final String packageId;
  final String preset;
  final String mode;
  final int sampleMs;
  final int? screenshotMs;
  final String outDir;
}

_Options _parseArgs(List<String> args) {
  var help = false;
  String? launchAvd;
  String? deviceId;
  var emulatorPort = 5570;
  var memoryMb = 4096;
  var cores = 2;
  var headless = false;
  var keepEmulator = false;
  var clearData = false;
  var packageId = 'com.prismplural.prism';
  var preset = 'reportedLarge';
  var mode = 'profile';
  var sampleMs = 2000;
  int? screenshotMs;
  var outDir = 'build/android-memory-benchmark';

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    String nextValue() {
      if (i + 1 >= args.length) {
        throw FormatException('Missing value for $arg');
      }
      return args[++i];
    }

    int nextInt(String label) {
      final value = int.tryParse(nextValue());
      if (value == null) throw FormatException('$label must be an integer.');
      return value;
    }

    switch (arg) {
      case '--help':
      case '-h':
        help = true;
      case '--launch-avd':
        launchAvd = nextValue();
      case '--device':
      case '-d':
        deviceId = nextValue();
      case '--emulator-port':
        emulatorPort = nextInt('--emulator-port');
      case '--memory-mb':
        memoryMb = nextInt('--memory-mb');
      case '--cores':
        cores = nextInt('--cores');
      case '--headless':
        headless = true;
      case '--keep-emulator':
        keepEmulator = true;
      case '--clear-data':
        clearData = true;
      case '--package':
        packageId = nextValue();
      case '--preset':
        preset = nextValue();
      case '--mode':
        mode = nextValue();
      case '--sample-ms':
        sampleMs = nextInt('--sample-ms');
      case '--screenshot-ms':
        screenshotMs = nextInt('--screenshot-ms');
      case '--out':
        outDir = nextValue();
      default:
        throw FormatException('Unknown option: $arg');
    }
  }

  if (!{'reportedLarge', 'heavy5k', 'huge', 'massive'}.contains(preset)) {
    throw FormatException('Unknown --preset: $preset');
  }
  if (!{'debug', 'profile'}.contains(mode)) {
    throw const FormatException('--mode must be debug or profile.');
  }
  if (sampleMs < 250) {
    throw const FormatException('--sample-ms must be at least 250.');
  }
  if (screenshotMs != null && screenshotMs < 250) {
    throw const FormatException('--screenshot-ms must be at least 250.');
  }
  if (emulatorPort.isOdd) {
    throw const FormatException('--emulator-port must be even.');
  }

  return _Options(
    help: help,
    launchAvd: launchAvd,
    deviceId: deviceId,
    emulatorPort: emulatorPort,
    memoryMb: memoryMb,
    cores: cores,
    headless: headless,
    keepEmulator: keepEmulator,
    clearData: clearData,
    packageId: packageId,
    preset: preset,
    mode: mode,
    sampleMs: sampleMs,
    screenshotMs: screenshotMs,
    outDir: outDir,
  );
}
