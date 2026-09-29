// iOS smoke test for the work moved off the main isolate: PIN hashing against
// the real keychain, native photo compression, and avatar encoding. On iOS the
// main isolate runs on the platform main thread, so a long stall there risks a
// watchdog kill.
//
//   flutter test integration_test/ios_main_isolate_smoke_test.dart -d <sim>

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:prism_media_codec/prism_media_codec.dart' as media_codec;
import 'package:prism_plurality/core/diagnostics/main_isolate_stalls.dart';
import 'package:prism_plurality/core/services/media/image_compression_service.dart';
import 'package:prism_plurality/core/services/pin_lock_service.dart';
import 'package:prism_plurality/shared/utils/avatar_image_picker.dart';
import 'package:prism_plurality/shared/utils/avatar_normalizer.dart';

import '../test/helpers/main_isolate_responsiveness.dart';
import 'support/main_isolate_pulse_monitor.dart';

/// Keychain round-trips add platform-channel latency the inline comparison
/// can't model, so end-to-end flows use a fixed bound instead.
const _maxFlowGapMicros = 250000;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (!Platform.isIOS) {
      throw UnsupportedError('This smoke test targets iOS.');
    }
    await media_codec.initializeMediaCodec();
  });

  testWidgets('the pulse monitor sees a deliberate stall on this device', (
    tester,
  ) async {
    final monitor = await MainIsolatePulseMonitor.start(
      interval: const Duration(milliseconds: 5),
    );
    final stall = Stopwatch()..start();
    while (stall.elapsedMilliseconds < 150) {}
    final summary = await monitor.stop();
    _report('deliberate stall', summary.maximumGapMicros);
    expect(summary.maximumGapMicros, greaterThanOrEqualTo(120000));
  });

  group('PIN lock on the real keychain', () {
    final service = PinLockService();

    setUp(service.clearPin);
    tearDown(service.clearPin);

    testWidgets('store and verify keep the main isolate responsive', (
      tester,
    ) async {
      final monitor = await MainIsolatePulseMonitor.start(
        interval: const Duration(milliseconds: 5),
      );
      await service.storePin('482915');
      final correct = await service.verifyStoredPin('482915');
      final wrong = await service.verifyStoredPin('482916');
      final summary = await monitor.stop();

      _report('PIN store + 2 verifies', summary.maximumGapMicros);
      expect(correct, isTrue);
      expect(wrong, isFalse);
      expect(await service.isPinSet(), isTrue);
      expect(summary.maximumGapMicros, lessThan(_maxFlowGapMicros));
    });

    testWidgets('overlapping PIN operations run in call order', (tester) async {
      final results = await Future.wait([
        service.storePin('111111').then((_) => true),
        service.verifyStoredPin('111111'),
        service.storePin('222222').then((_) => true),
        service.verifyStoredPin('222222'),
        service.verifyStoredPin('111111'),
      ]);

      expect(results, [true, true, true, true, false]);
      expect(await service.verifyStoredPin('222222'), isTrue);
    });

    testWidgets('Argon2 hashing stays off the main isolate', (tester) async {
      final pinBytes = Uint8List.fromList('135790'.codeUnits);
      await expectStaysResponsive(
        offMain: () => PinLockService.hashPinArgon2idBytesOffMainIsolate(
          pinBytes,
          'salt-abc',
        ),
        inline: () => PinLockService.hashPinArgon2idBytes(pinBytes, 'salt-abc'),
        pulseInterval: const Duration(milliseconds: 2),
      );
    });
  });

  group('images', () {
    late Uint8List photo;

    setUpAll(() => photo = _noisyJpeg(4032, 3024));

    testWidgets('photo compression with the native encoder stays responsive', (
      tester,
    ) async {
      final service = ImageCompressionService();
      final monitor = await MainIsolatePulseMonitor.start(
        interval: const Duration(milliseconds: 5),
      );
      final compressed = await service.compressImage(photo);
      final thumbnail = await service.generateThumbnail(photo);
      final summary = await monitor.stop();

      _report('12MP compress + thumbnail', summary.maximumGapMicros);
      expect((compressed.width, compressed.height), (2048, 1536));
      expect(compressed.bytes, isNotEmpty);
      expect(compressed.blurhash, isNotEmpty);
      expect(thumbnail, isNotEmpty);
      expect(summary.maximumGapMicros, lessThan(_maxFlowGapMicros));
    });

    testWidgets('avatar normalization stays off the main isolate', (
      tester,
    ) async {
      await expectStaysResponsive(
        offMain: () => AvatarNormalizer.normalizeOffMainIsolate(photo),
        inline: () => AvatarNormalizer.normalize(photo),
      );
    });

    testWidgets('picked avatar encoding stays off the main isolate', (
      tester,
    ) async {
      final cropped = Uint8List.fromList(
        img.encodePng(img.copyResize(img.decodeJpg(photo)!, width: 1600)),
      );
      await expectStaysResponsive(
        offMain: () => compute(encodeAvatarOutputForStorage, cropped),
        inline: () => encodeAvatarOutputForStorage(cropped),
      );
    });
  });

  testWidgets('the stall logger reports a blocked main isolate', (
    tester,
  ) async {
    final lines = <String>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) lines.add(message);
      original(message, wrapWidth: wrapWidth);
    };
    addTearDown(() => debugPrint = original);

    MainIsolateStalls.start();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    MainIsolateStalls.mark('smoke stall');
    final stall = Stopwatch()..start();
    while (stall.elapsedMilliseconds < 400) {}
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(
      lines.where((l) => l.contains('[stall]') && l.contains('smoke stall')),
      isNotEmpty,
    );
  });
}

void _report(String label, int gapMicros) {
  // ignore: avoid_print
  print('[smoke] $label: max main-isolate gap ${gapMicros ~/ 1000}ms');
}

/// Deterministic noise, so decoding does photo-like entropy work.
Uint8List _noisyJpeg(int width, int height) {
  final image = img.Image(width: width, height: height);
  var seed = 7;
  int next() => seed = (seed * 1103515245 + 12345) & 0x7fffffff;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, next() & 0xFF, next() & 0xFF, next() & 0xFF);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}
