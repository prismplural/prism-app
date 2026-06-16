import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const _masterSuffix = '_masterImage.png';
const _testSuffix = '_testImage.png';
const _defaultRoot = 'test';

void main(List<String> args) {
  final options = _Options.parse(args);
  final root = Directory(options.root);
  if (!root.existsSync()) {
    stderr.writeln('No such directory: ${root.path}');
    exitCode = 2;
    return;
  }

  final pairs = _findGoldenPairs(root);
  if (pairs.isEmpty) {
    stdout.writeln(
      'No Flutter golden failure image pairs found in ${root.path}.',
    );
    return;
  }

  final reports = <Map<String, Object?>>[];
  for (final pair in pairs) {
    final report = _writeReport(pair, options);
    reports.add(report.toJson());
    stdout.writeln(report.markdown);
    stdout.writeln('');
  }

  final aggregatePath = File('${root.path}/golden_failure_report.json');
  aggregatePath.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(reports),
  );
  stdout.writeln('Wrote ${aggregatePath.path}');
}

class _Options {
  const _Options({
    required this.root,
    required this.padding,
    required this.maxCropHeight,
    required this.maxOverviewHeight,
    required this.diffThreshold,
    required this.maxFocusImages,
  });

  final String root;
  final int padding;
  final int maxCropHeight;
  final int maxOverviewHeight;
  final int diffThreshold;
  final int maxFocusImages;

  static _Options parse(List<String> args) {
    var root = _defaultRoot;
    var padding = 36;
    var maxCropHeight = 720;
    var maxOverviewHeight = 1100;
    var diffThreshold = 0;
    var maxFocusImages = 4;

    for (final arg in args) {
      if (arg.startsWith('--padding=')) {
        padding = int.parse(arg.substring('--padding='.length));
      } else if (arg.startsWith('--max-crop-height=')) {
        maxCropHeight = int.parse(arg.substring('--max-crop-height='.length));
      } else if (arg.startsWith('--max-overview-height=')) {
        maxOverviewHeight = int.parse(
          arg.substring('--max-overview-height='.length),
        );
      } else if (arg.startsWith('--diff-threshold=')) {
        diffThreshold = int.parse(arg.substring('--diff-threshold='.length));
      } else if (arg.startsWith('--max-focus-images=')) {
        maxFocusImages = int.parse(arg.substring('--max-focus-images='.length));
      } else if (arg == '--help' || arg == '-h') {
        _printUsageAndExit();
      } else if (arg.startsWith('--')) {
        stderr.writeln('Unknown option: $arg');
        _printUsageAndExit(2);
      } else {
        root = arg;
      }
    }

    return _Options(
      root: root,
      padding: padding,
      maxCropHeight: maxCropHeight,
      maxOverviewHeight: maxOverviewHeight,
      diffThreshold: diffThreshold,
      maxFocusImages: maxFocusImages,
    );
  }
}

void _printUsageAndExit([int code = 0]) {
  stdout.writeln('''
Usage: dart tool/golden_failure_report.dart [failure-root] [options]

Scans Flutter golden failure artifacts for *_masterImage.png and
*_testImage.png pairs, then writes readable side-by-side comparison images.

Options:
  --padding=N              Pixels of context around detected diff crops.
  --max-crop-height=N      Max height for each focused crop image.
  --max-overview-height=N  Max rendered height for overview images.
  --diff-threshold=N       Per-channel pixel delta threshold. Default: 0.
  --max-focus-images=N     Maximum focused crops per failed golden.

Default failure-root: test
''');
  exit(code);
}

List<_GoldenPair> _findGoldenPairs(Directory root) {
  final masters =
      root
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith(_masterSuffix))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final pairs = <_GoldenPair>[];
  for (final master in masters) {
    final stem = master.path.substring(
      0,
      master.path.length - _masterSuffix.length,
    );
    final test = File('$stem$_testSuffix');
    if (!test.existsSync()) continue;
    pairs.add(
      _GoldenPair(
        name: stem.split(Platform.pathSeparator).last,
        directory: master.parent,
        master: master,
        test: test,
      ),
    );
  }
  return pairs;
}

_GoldenReport _writeReport(_GoldenPair pair, _Options options) {
  final master = _decodePng(pair.master);
  final test = _decodePng(pair.test);
  final stats = _diffStats(master, test, options.diffThreshold);

  final outputDir = Directory('${pair.directory.path}/readable')
    ..createSync(recursive: true);
  final overviewPath = '${outputDir.path}/${pair.name}_overview.png';
  _writeComparison(
    path: overviewPath,
    title: '${pair.name}: full golden comparison',
    leftLabel: 'Baseline golden',
    rightLabel: 'Current render',
    left: _resizeForOverview(master, options.maxOverviewHeight),
    right: _resizeForOverview(test, options.maxOverviewHeight),
    notes: [
      _formatDiff(stats),
      'Use focused crops below for readable changed regions.',
    ],
  );

  final focusPaths = <String>[];
  if (stats.diffPixels > 0) {
    final crops = _focusCrops(stats, master.width, master.height, options);
    for (var i = 0; i < crops.length; i += 1) {
      final crop = crops[i];
      final focusPath =
          '${outputDir.path}/${pair.name}_focus_${(i + 1).toString().padLeft(2, '0')}.png';
      focusPaths.add(focusPath);
      _writeComparison(
        path: focusPath,
        title:
            '${pair.name}: focus ${i + 1}/${crops.length} '
            '(x ${crop.x}-${crop.right}, y ${crop.y}-${crop.bottom})',
        leftLabel: 'Baseline crop',
        rightLabel: 'Current crop',
        left: _crop(master, crop),
        right: _crop(test, crop),
        notes: [
          _formatDiff(stats),
          'Crop is selected from pixel-diff bounds with surrounding context.',
        ],
        highlight: crop.highlight,
      );
    }
  }

  final report = _GoldenReport(
    pair: pair,
    diff: stats,
    overviewPath: File(overviewPath).absolute.path,
    focusPaths: [for (final path in focusPaths) File(path).absolute.path],
  );

  File('${outputDir.path}/${pair.name}_report.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(report.toJson()),
  );
  File(
    '${outputDir.path}/${pair.name}_report.md',
  ).writeAsStringSync('${report.markdown}\n');
  return report;
}

img.Image _decodePng(File file) {
  final decoded = img.decodePng(file.readAsBytesSync());
  if (decoded == null) {
    throw FormatException('Could not decode PNG: ${file.path}');
  }
  return decoded.convert(numChannels: 4);
}

img.Image _resizeForOverview(img.Image image, int maxHeight) {
  if (image.height <= maxHeight) return image;
  final width = (image.width * (maxHeight / image.height)).round();
  return img.copyResize(image, width: width, height: maxHeight);
}

img.Image _crop(img.Image image, _Crop crop) {
  return img.copyCrop(
    image,
    x: crop.x,
    y: crop.y,
    width: crop.width,
    height: crop.height,
  );
}

_DiffStats _diffStats(img.Image master, img.Image test, int threshold) {
  final width = math.min(master.width, test.width);
  final height = math.min(master.height, test.height);
  var diffPixels = 0;
  var minX = width;
  var minY = height;
  var maxX = -1;
  var maxY = -1;
  final rowHasDiff = List<bool>.filled(height, false);

  for (var y = 0; y < height; y += 1) {
    for (var x = 0; x < width; x += 1) {
      final a = master.getPixel(x, y);
      final b = test.getPixel(x, y);
      if (_channelDelta(a.r, b.r) <= threshold &&
          _channelDelta(a.g, b.g) <= threshold &&
          _channelDelta(a.b, b.b) <= threshold &&
          _channelDelta(a.a, b.a) <= threshold) {
        continue;
      }
      diffPixels += 1;
      rowHasDiff[y] = true;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }
  }

  final totalPixels = width * height;
  final bbox = diffPixels == 0
      ? const _Rect(0, 0, 0, 0)
      : _Rect(minX, minY, maxX - minX + 1, maxY - minY + 1);
  return _DiffStats(
    width: width,
    height: height,
    totalPixels: totalPixels,
    diffPixels: diffPixels,
    boundingBox: bbox,
    rowHasDiff: rowHasDiff,
  );
}

int _channelDelta(num a, num b) => (a - b).abs().round();

List<_Crop> _focusCrops(
  _DiffStats stats,
  int imageWidth,
  int imageHeight,
  _Options options,
) {
  final clusters = _rowClusters(stats.rowHasDiff, maxGap: 18);
  final crops = <_Crop>[];
  final sourceClusters = clusters.isEmpty
      ? [stats.boundingBox]
      : clusters.map((cluster) {
          final y = cluster.y;
          final height = cluster.height;
          return _Rect(stats.boundingBox.x, y, stats.boundingBox.width, height);
        });

  for (final cluster in sourceClusters) {
    final expanded = cluster.expand(
      paddingX: options.padding,
      paddingY: options.padding,
      maxWidth: imageWidth,
      maxHeight: imageHeight,
    );
    if (expanded.height <= options.maxCropHeight) {
      crops.add(_Crop.fromRect(expanded, highlight: expanded));
    } else {
      var y = expanded.y;
      while (y < expanded.bottom && crops.length < options.maxFocusImages) {
        final height = math.min(options.maxCropHeight, expanded.bottom - y);
        final rect = _Rect(expanded.x, y, expanded.width, height);
        crops.add(_Crop.fromRect(rect, highlight: rect));
        y += options.maxCropHeight - options.padding;
      }
    }
    if (crops.length >= options.maxFocusImages) break;
  }

  if (crops.isEmpty) {
    final expanded = stats.boundingBox.expand(
      paddingX: options.padding,
      paddingY: options.padding,
      maxWidth: imageWidth,
      maxHeight: imageHeight,
    );
    crops.add(_Crop.fromRect(expanded, highlight: expanded));
  }
  return crops.take(options.maxFocusImages).toList();
}

List<_Rect> _rowClusters(List<bool> rowHasDiff, {required int maxGap}) {
  final clusters = <_Rect>[];
  var start = -1;
  var last = -1;
  for (var y = 0; y < rowHasDiff.length; y += 1) {
    if (!rowHasDiff[y]) continue;
    if (start == -1) {
      start = y;
      last = y;
      continue;
    }
    if (y - last <= maxGap) {
      last = y;
      continue;
    }
    clusters.add(_Rect(0, start, 0, last - start + 1));
    start = y;
    last = y;
  }
  if (start != -1) {
    clusters.add(_Rect(0, start, 0, last - start + 1));
  }
  return clusters;
}

void _writeComparison({
  required String path,
  required String title,
  required String leftLabel,
  required String rightLabel,
  required img.Image left,
  required img.Image right,
  required List<String> notes,
  _Rect? highlight,
}) {
  const margin = 24;
  const gap = 32;
  const header = 86;
  final noteHeight = 28 + notes.length * 22;
  final contentHeight = math.max(left.height, right.height);
  final canvas = img.Image(
    width: margin * 2 + left.width + gap + right.width,
    height: header + contentHeight + noteHeight,
    numChannels: 4,
  );
  img.fill(canvas, color: img.ColorRgb8(245, 241, 233));
  _drawString(canvas, title, x: margin, y: 16, font: img.arial24);
  _drawString(canvas, leftLabel, x: margin, y: 54, font: img.arial24);
  final rightX = margin + left.width + gap;
  _drawString(canvas, rightLabel, x: rightX, y: 54, font: img.arial24);

  img.compositeImage(canvas, left, dstX: margin, dstY: header);
  img.compositeImage(canvas, right, dstX: rightX, dstY: header);

  if (highlight != null) {
    final boxColor = img.ColorRgb8(37, 99, 235);
    final leftBox = _highlightInCrop(highlight, left.width, left.height);
    final rightBox = _highlightInCrop(highlight, right.width, right.height);
    _drawRect(canvas, leftBox.offset(margin, header), boxColor);
    _drawRect(canvas, rightBox.offset(rightX, header), boxColor);
  }

  var noteY = header + contentHeight + 16;
  for (final note in notes) {
    _drawString(canvas, note, x: margin, y: noteY, font: img.arial14);
    noteY += 22;
  }

  File(path).writeAsBytesSync(img.encodePng(canvas));
}

_Rect _highlightInCrop(_Rect highlight, int width, int height) {
  return _Rect(0, 0, width, height);
}

void _drawString(
  img.Image image,
  String text, {
  required int x,
  required int y,
  required img.BitmapFont font,
}) {
  img.drawString(
    image,
    text,
    font: font,
    x: x,
    y: y,
    color: img.ColorRgb8(38, 38, 38),
  );
}

void _drawRect(img.Image image, _Rect rect, img.Color color) {
  img.drawRect(
    image,
    x1: rect.x,
    y1: rect.y,
    x2: rect.right - 1,
    y2: rect.bottom - 1,
    color: color,
    thickness: 4,
  );
}

String _formatDiff(_DiffStats stats) {
  final percent = stats.totalPixels == 0
      ? 0
      : stats.diffPixels * 100 / stats.totalPixels;
  return 'Diff: ${percent.toStringAsFixed(2)}%, '
      '${stats.diffPixels} px, '
      'bbox x ${stats.boundingBox.x}-${stats.boundingBox.right}, '
      'y ${stats.boundingBox.y}-${stats.boundingBox.bottom}.';
}

class _GoldenPair {
  const _GoldenPair({
    required this.name,
    required this.directory,
    required this.master,
    required this.test,
  });

  final String name;
  final Directory directory;
  final File master;
  final File test;
}

class _GoldenReport {
  const _GoldenReport({
    required this.pair,
    required this.diff,
    required this.overviewPath,
    required this.focusPaths,
  });

  final _GoldenPair pair;
  final _DiffStats diff;
  final String overviewPath;
  final List<String> focusPaths;

  Map<String, Object?> toJson() {
    return {
      'name': pair.name,
      'failureDirectory': pair.directory.absolute.path,
      'masterImage': pair.master.absolute.path,
      'testImage': pair.test.absolute.path,
      'diffPixels': diff.diffPixels,
      'diffPercent': diff.totalPixels == 0
          ? 0
          : diff.diffPixels * 100 / diff.totalPixels,
      'boundingBox': diff.boundingBox.toJson(),
      'overview': overviewPath,
      'focus': focusPaths,
    };
  }

  String get markdown {
    final buffer = StringBuffer()
      ..writeln('### ${pair.name}')
      ..writeln(_formatDiff(diff))
      ..writeln()
      ..writeln('![${pair.name} overview]($overviewPath)');
    for (var i = 0; i < focusPaths.length; i += 1) {
      buffer
        ..writeln()
        ..writeln('![${pair.name} focus ${i + 1}](${focusPaths[i]})');
    }
    return buffer.toString().trimRight();
  }
}

class _DiffStats {
  const _DiffStats({
    required this.width,
    required this.height,
    required this.totalPixels,
    required this.diffPixels,
    required this.boundingBox,
    required this.rowHasDiff,
  });

  final int width;
  final int height;
  final int totalPixels;
  final int diffPixels;
  final _Rect boundingBox;
  final List<bool> rowHasDiff;
}

class _Rect {
  const _Rect(this.x, this.y, this.width, this.height);

  final int x;
  final int y;
  final int width;
  final int height;

  int get right => x + width;
  int get bottom => y + height;

  _Rect expand({
    required int paddingX,
    required int paddingY,
    required int maxWidth,
    required int maxHeight,
  }) {
    final nextX = math.max(0, x - paddingX);
    final nextY = math.max(0, y - paddingY);
    final nextRight = math.min(maxWidth, right + paddingX);
    final nextBottom = math.min(maxHeight, bottom + paddingY);
    return _Rect(nextX, nextY, nextRight - nextX, nextBottom - nextY);
  }

  _Rect offset(int dx, int dy) => _Rect(x + dx, y + dy, width, height);

  Map<String, int> toJson() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'right': right,
    'bottom': bottom,
  };
}

class _Crop extends _Rect {
  const _Crop(
    super.x,
    super.y,
    super.width,
    super.height, {
    required this.highlight,
  });

  factory _Crop.fromRect(_Rect rect, {required _Rect highlight}) {
    return _Crop(rect.x, rect.y, rect.width, rect.height, highlight: highlight);
  }

  final _Rect highlight;
}
