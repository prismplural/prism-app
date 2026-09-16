import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:prism_plurality/shared/services/template_image_code_reader.dart';

/// Renders [data] as a black/white QR bitmap and encodes it through a lossy
/// JPEG, mirroring what a chat app does to a shared template card: the pixels
/// survive, the PNG metadata does not. Real production bytes, not a stub.
Uint8List _jpegQr(String data, {int scale = 8, int quietZone = 4}) {
  final qr = QrImage(
    QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M),
  );
  final side = (qr.moduleCount + quietZone * 2) * scale;
  final image = img.Image(width: side, height: side, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  for (var row = 0; row < qr.moduleCount; row++) {
    for (var col = 0; col < qr.moduleCount; col++) {
      if (!qr.isDark(row, col)) continue;
      img.fillRect(
        image,
        x1: (col + quietZone) * scale,
        y1: (row + quietZone) * scale,
        x2: (col + quietZone + 1) * scale - 1,
        y2: (row + quietZone + 1) * scale - 1,
        color: img.ColorRgb8(0, 0, 0),
      );
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 85));
}

/// A **complete, fully decodable** PNG of [side]×[side] pixels of flat black.
///
/// Uniform content compresses to a few tens of KB, so this is simultaneously
/// (a) over the pixel budget for any meaningful [side] and (b) far under the
/// 16 MiB byte cap. It therefore reaches the code path where a missing pixel
/// guard would really decode 36 MP — no truncated or malformed fixture needed.
Uint8List _completeOversizedPng(int side) {
  final image = img.Image(
    width: side,
    height: side,
    numChannels: 1,
    format: img.Format.uint1,
  );
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  const code = 'PF1:jpegroundtrip';

  group('allowlist', () {
    test('offers png, jpg, and jpeg (recompressed cards arrive as JPEG)', () {
      expect(kTemplateImageExtensions, ['png', 'jpg', 'jpeg']);
    });
  });

  group('pixel-budget guard runs before any full decode', () {
    /// A complete 6000×6000 (36 MP) PNG: valid, decodable, and over
    /// [kMaxTemplateImagePixels]. Small enough on disk to be a realistic
    /// hostile input.
    final oversized = _completeOversizedPng(6000);

    test('fixture is genuinely over-budget, under the byte cap, decodable', () {
      expect(oversized.length, lessThan(kMaxTemplateImageBytes));
      expect(6000 * 6000, greaterThan(kMaxTemplateImagePixels));
      final decoded = img.decodeImage(oversized);
      expect(decoded, isNotNull);
      expect(decoded!.width, 6000);
      expect(decoded.height, 6000);
      expect(
        img.findDecoderForData(oversized)?.startDecode(oversized)?.width,
        6000,
      );
    });

    test('read() rejects it without invoking the full decoder', () async {
      var decodeCalls = 0;
      final reader = TemplateImageCodeReader(
        platform: TargetPlatform.linux,
        decodeVisibleQr: (bytes) async {
          decodeCalls++;
          return code;
        },
      );

      expect(await reader.read(oversized), isNull);
      // The guard is only meaningful if the full decode never happened: a
      // decode-then-check implementation would report decodeCalls == 1 and hand
      // back `code`.
      expect(decodeCalls, 0, reason: 'header probe must precede any decode');
    });

    test(
      'rejects an over-budget image even when it carries metadata',
      () async {
        // The ordering that matters: template metadata must not be a way around
        // the pixel bound. Embed a real code, then make the image oversized.
        final withText = img.Image(width: 6000, height: 6000, numChannels: 1)
          ..addTextData({'prismFieldTemplate': code});
        final oversizedWithMetadata = Uint8List.fromList(
          img.encodePng(withText),
        );
        expect(oversizedWithMetadata.length, lessThan(kMaxTemplateImageBytes));

        // Prove the metadata really is present and readable from the header:
        // the null below is caused by the pixel guard, not by absent metadata.
        // Under the pre-fix ordering (metadata read first, by a full decode)
        // this call returned `code` instead of null.
        final probeInfo = img
            .findDecoderForData(oversizedWithMetadata)!
            .startDecode(oversizedWithMetadata)!;
        expect((probeInfo as img.PngInfo).textData['prismFieldTemplate'], code);

        var decodeCalls = 0;
        final reader = TemplateImageCodeReader(
          platform: TargetPlatform.linux,
          decodeVisibleQr: (bytes) async {
            decodeCalls++;
            return code;
          },
        );

        expect(await reader.read(oversizedWithMetadata), isNull);
        expect(decodeCalls, 0);
      },
    );
  });

  group('mobile analyzer is restricted to QR codes', () {
    // The mobile fallback runs the platform analyzer over a whole picked photo.
    // Left unrestricted it hunts every supported barcode format, which is both
    // wasted work and a chance to match a barcode that is not the template.
    // Asserted at the source level because the call site is a platform-channel
    // invocation that a unit test cannot intercept.
    test('analyzeImage is called with formats: [BarcodeFormat.qrCode]', () {
      final source = File(
        'lib/shared/services/template_image_code_reader.dart',
      );
      expect(
        source.existsSync(),
        isTrue,
        reason: 'test must run from the package root',
      );
      final text = source.readAsStringSync();

      final callIndex = text.indexOf('analyzeImage(');
      expect(callIndex, isNonNegative, reason: 'analyzeImage call not found');

      // Inspect just the invocation, up to its closing paren.
      final call = text.substring(callIndex, text.indexOf(')', callIndex));
      expect(
        call.contains('formats:'),
        isTrue,
        reason: 'analyzeImage must pin formats explicitly',
      );
      expect(
        call.contains('BarcodeFormat.qrCode'),
        isTrue,
        reason: 'analyzeImage must be limited to QR codes, found: $call',
      );
      expect(
        call.contains('BarcodeFormat.'),
        isTrue,
        reason: 'formats must be a real BarcodeFormat, found: $call',
      );
      // Exactly one format, so no non-QR symbology sneaks back in.
      final formatsList = call.substring(
        call.indexOf('[') + 1,
        call.indexOf(']'),
      );
      expect(
        formatsList.split(',').where((f) => f.trim().isNotEmpty).length,
        1,
        reason: 'exactly one format expected, found: $formatsList',
      );
    });

    test('the format the source pins exists in mobile_scanner', () {
      // Guards against an upstream rename silently making the assertion above
      // vacuous.
      expect(BarcodeFormat.values, contains(BarcodeFormat.qrCode));
    });
  });

  group('read', () {
    test('runs both QR fallbacks, in order, for a metadata-less PNG', () async {
      var rgbaCalls = 0;
      var filePathCalls = 0;
      final reader = TemplateImageCodeReader(
        platform: TargetPlatform.android,
        decodeFilePath: (_) async {
          filePathCalls++;
          return null;
        },
        decodeVisibleQr: (bytes) async {
          rgbaCalls++;
          return null;
        },
      );

      final plainPng = Uint8List.fromList(
        img.encodePng(img.Image(width: 4, height: 4)),
      );

      // No embedded code and no QR in the image: both fallbacks run, in order,
      // and the result is null rather than a throw.
      final result = await reader.read(plainPng, path: '/tmp/template.png');
      expect(result, isNull);
      expect(filePathCalls, 1, reason: 'mobile tries the platform analyzer');
      expect(rgbaCalls, 1, reason: 'then the pure-Dart pixel decode');
    });

    test('recovers the visible QR from a JPEG via the real decoder', () async {
      // No injected decoders: this exercises the shipping decodeDesktopQr
      // (pure-Dart zxing) against real JPEG bytes carrying no PNG metadata —
      // the desktop end-to-end path, including the isolate round-trip through
      // the production default.
      final reader = TemplateImageCodeReader(platform: TargetPlatform.macOS);

      expect(await reader.read(_jpegQr(code)), code);
    });

    test('the production isolate entry point decodes a JPEG', () async {
      // Proves the shipping default (compute) really works, not just the
      // current-isolate twin the widget tests use.
      expect(await decodeTemplateVisibleQr(_jpegQr(code)), code);
      expect(
        await decodeTemplateVisibleQr(
          Uint8List.fromList(List.generate(64, (i) => i)),
        ),
        isNull,
      );
    });

    test('reports the embedded code from the header probe alone', () async {
      // A PNG carrying template metadata: the code comes back with the full
      // decoder never invoked, so the fast path costs no pixels.
      final embedded = Uint8List.fromList(
        img.encodePng(
          img.Image(width: 8, height: 8)
            ..addTextData({'prismFieldTemplate': code}),
        ),
      );

      var decodeCalls = 0;
      final reader = TemplateImageCodeReader(
        platform: TargetPlatform.linux,
        decodeVisibleQr: (bytes) async {
          decodeCalls++;
          return null;
        },
      );

      expect(await reader.read(embedded), code);
      expect(decodeCalls, 0, reason: 'metadata needs no pixel decode');
    });

    test('does not call the mobile file analyzer on desktop', () async {
      var filePathCalls = 0;
      final reader = TemplateImageCodeReader(
        platform: TargetPlatform.windows,
        decodeFilePath: (_) async {
          filePathCalls++;
          return code;
        },
        decodeVisibleQr: (bytes) async => null,
      );

      expect(await reader.read(_jpegQr(code), path: '/tmp/card.jpg'), isNull);
      expect(filePathCalls, 0);
    });

    test('prefers the mobile file analyzer when it finds a code', () async {
      var rgbaCalls = 0;
      final reader = TemplateImageCodeReader(
        platform: TargetPlatform.iOS,
        decodeFilePath: (_) async => code,
        decodeVisibleQr: (bytes) async {
          rgbaCalls++;
          return null;
        },
      );

      expect(await reader.read(_jpegQr(code), path: '/tmp/card.jpg'), code);
      expect(rgbaCalls, 0, reason: 'no pixel decode once the QR is recovered');
    });

    test('returns null for empty, non-image, and truncated bytes', () async {
      final reader = TemplateImageCodeReader(platform: TargetPlatform.linux);

      expect(await reader.read(Uint8List(0)), isNull);
      expect(
        await reader.read(Uint8List.fromList(List.generate(64, (i) => i))),
        isNull,
      );

      final truncated = _jpegQr(code).sublist(0, 128);
      expect(await reader.read(truncated), isNull);
    });

    test('rejects an image over the byte cap without decoding', () async {
      var decodeCalls = 0;
      final reader = TemplateImageCodeReader(
        platform: TargetPlatform.linux,
        decodeVisibleQr: (bytes) async {
          decodeCalls++;
          return code;
        },
      );

      final oversized = Uint8List(kMaxTemplateImageBytes + 1);
      oversized.setRange(0, 3, [0xFF, 0xD8, 0xFF]); // looks like a JPEG
      expect(await reader.read(oversized), isNull);
      expect(decodeCalls, 0);
    });

    test('survives a decoder that throws', () async {
      final reader = TemplateImageCodeReader(
        platform: TargetPlatform.linux,
        decodeVisibleQr: (bytes) async => throw StateError('decoder exploded'),
      );

      expect(await reader.read(_jpegQr(code)), isNull);
    });

    test(
      'a repeated read of the same bytes reuses the cached result',
      () async {
        var decodeCalls = 0;
        final reader = TemplateImageCodeReader(
          platform: TargetPlatform.linux,
          decodeVisibleQr: (bytes) async {
            decodeCalls++;
            return null;
          },
        );

        final jpeg = _jpegQr(code);
        await reader.read(jpeg);
        await reader.read(jpeg);
        expect(decodeCalls, 1, reason: 'second read is served from the memo');
      },
    );
  });
}
