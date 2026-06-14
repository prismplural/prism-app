import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:prism_plurality/core/services/media/image_compression_service.dart';
import 'package:prism_sync/generated/frb_generated.dart';

void main() {
  group('ImageCompressionService.fitWithin', () {
    test('rejects a 0x0 decode instead of throwing "Infinity or NaN toInt"', () {
      // A zero-dimension decode drove `0 / 0 = NaN`, and `.round()` on NaN
      // threw "Infinity or NaN toInt". Must be a clear ArgumentError instead.
      expect(
        () => ImageCompressionService.fitWithin(0, 0, 2048),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            contains('invalid dimensions'),
          ),
        ),
      );
    });

    test('rejects a zero height (degenerate decode)', () {
      expect(
        () => ImageCompressionService.fitWithin(100, 0, 2048),
        throwsArgumentError,
      );
    });

    test('rejects a zero width (degenerate decode)', () {
      expect(
        () => ImageCompressionService.fitWithin(0, 100, 2048),
        throwsArgumentError,
      );
    });

    test('rejects negative dimensions', () {
      expect(
        () => ImageCompressionService.fitWithin(-1, 10, 2048),
        throwsArgumentError,
      );
    });

    test('scales a landscape image down to the max dimension', () {
      expect(ImageCompressionService.fitWithin(4000, 2000, 2048), (2048, 1024));
    });

    test('scales a portrait image down to the max dimension', () {
      expect(ImageCompressionService.fitWithin(2000, 4000, 2048), (1024, 2048));
    });

    test('does not upscale an image already within bounds', () {
      expect(ImageCompressionService.fitWithin(640, 480, 2048), (640, 480));
    });

    test('floors the minor axis at 1 for an extreme landscape ratio', () {
      // 100000x1 previously fitted to (300, 0) — a 0 reaching the encoder.
      // Positive-but-extreme ratios must floor the minor axis at 1.
      expect(ImageCompressionService.fitWithin(100000, 1, 300), (300, 1));
      expect(ImageCompressionService.fitWithin(100000, 1, 2048), (2048, 1));
    });

    test('floors the minor axis at 1 for an extreme portrait ratio', () {
      expect(ImageCompressionService.fitWithin(1, 100000, 300), (1, 300));
    });
  });

  group('ImageCompressionService.computeBlurhashFromImage', () {
    test('computes a blurhash for an extreme-wide image without dividing by zero',
        () async {
      // A 2000x30 banner made the blurhash resize round to height 0 (32x0),
      // and BlurHash.encode then threw "Infinity or NaN toInt".
      final wide = img.Image(width: 2000, height: 30);
      img.fill(wide, color: img.ColorRgb8(10, 20, 30));

      final hash = await ImageCompressionService.computeBlurhashFromImage(wide);
      expect(hash, isNotEmpty);
    });

    test('bounds the blurhash resize for an extreme-tall image (no OOM)',
        () async {
      // copyResize(width: 32) on a 1x100000 image derived height ~3.2M
      // (~102M px) → OOM. fitWithin keeps both axes <= 32.
      final tall = img.Image(width: 1, height: 100000);
      img.fill(tall, color: img.ColorRgb8(30, 20, 10));

      final hash = await ImageCompressionService.computeBlurhashFromImage(tall);
      expect(hash, isNotEmpty);
    });

    test('computes a blurhash for an ordinary landscape image', () async {
      final normal = img.Image(width: 400, height: 300);
      img.fill(normal, color: img.ColorRgb8(120, 60, 200));

      final hash =
          await ImageCompressionService.computeBlurhashFromImage(normal);
      expect(hash, isNotEmpty);
    });
  });

  group('ImageCompressionService.compressImage', () {
    test(
      'bakes EXIF orientation before storing dimensions',
      skip: _missingFfiLibReason(),
      () async {
        final ffiLibPath = _resolveFfiLibPath()!;
        await RustLib.init(externalLibrary: ExternalLibrary.open(ffiLibPath));

        final source = img.Image(width: 80, height: 40);
        img.fill(source, color: img.ColorRgb8(120, 60, 200));
        source.exif.imageIfd.orientation = 6;

        try {
          final encoded = Uint8List.fromList(img.encodeJpg(source));
          final decodedFixture = img.decodeImage(encoded)!;
          expect((decodedFixture.width, decodedFixture.height), (40, 80));

          final compressed = await ImageCompressionService().compressImage(
            encoded,
          );
          final decodedCompressed = img.decodeImage(compressed.bytes)!;

          expect((compressed.width, compressed.height), (40, 80));
          expect(
            (decodedCompressed.width, decodedCompressed.height),
            (compressed.width, compressed.height),
          );
        } finally {
          RustLib.dispose();
        }
      },
    );
  });
}

String? _missingFfiLibReason() => _resolveFfiLibPath() == null
    ? 'Rust FFI lib not built for image compression integration test'
    : null;

String? _resolveFfiLibPath() {
  final name = Platform.isWindows
      ? 'prism_sync_ffi.dll'
      : Platform.isMacOS
      ? 'libprism_sync_ffi.dylib'
      : 'libprism_sync_ffi.so';
  final nativeAssetsDir = Platform.isMacOS
      ? 'macos'
      : Platform.isLinux
      ? 'linux'
      : Platform.isWindows
      ? 'windows'
      : Platform.operatingSystem;
  final cwd = Directory.current.path;
  final candidates = [
    '$cwd/build/native_assets/$nativeAssetsDir/$name',
    '$cwd/../prism-sync/target/debug/$name',
    '$cwd/../prism-sync/target/debug/deps/$name',
    '$cwd/../prism-sync/target/release/$name',
    '$cwd/../prism-sync/target/release/deps/$name',
  ];

  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  return null;
}
