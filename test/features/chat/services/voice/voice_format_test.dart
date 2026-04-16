import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/chat/services/voice/voice_format.dart';
import 'package:prism_plurality/features/chat/services/voice/voice_models.dart';

void main() {
  group('detectVoiceFormat', () {
    test('detects ogg opus bytes and routes to audio/ogg', () {
      final bytes = Uint8List.fromList([
        ...'OggS'.codeUnits,
        ...List.filled(16, 0),
        ...'OpusHead'.codeUnits,
      ]);

      final format = detectVoiceFormat(bytes);

      expect(format.container, VoiceContainer.ogg);
      expect(format.codec, VoiceCodec.opus);
      expect(format.mimeType, 'audio/ogg');
      expect(format.canUseBufferStream, isTrue);
    });

    test('identifies CAF Opus bytes before remux', () {
      final bytes = Uint8List.fromList([
        ...'caff'.codeUnits,
        0,
        1,
        2,
        ...'OpusHead'.codeUnits,
      ]);

      final format = detectVoiceFormat(bytes);

      expect(format.container, VoiceContainer.caf);
      expect(format.codec, VoiceCodec.opus);
      expect(format.needsRemuxBeforeUpload, isTrue);
      expect(format.mimeType, 'audio/x-caf');
    });

    test('unknown bytes fall back safely', () {
      final format = detectVoiceFormat(Uint8List.fromList([1, 2, 3, 4]));

      expect(format.container, VoiceContainer.unknown);
      expect(format.codec, VoiceCodec.unknown);
      expect(format.mimeType, 'application/octet-stream');
    });

    test('validated ogg opus overrides a stale MIME fallback', () {
      final bytes = Uint8List.fromList([
        ...'OggS'.codeUnits,
        ...List.filled(8, 0),
        ...'OpusHead'.codeUnits,
      ]);

      expect(
        resolveVoiceMimeType(bytes, fallbackMimeType: 'audio/mp4'),
        'audio/ogg',
      );
    });

    test('unknown bytes keep an explicit MIME fallback', () {
      final bytes = Uint8List.fromList([9, 8, 7, 6]);

      expect(
        resolveVoiceMimeType(bytes, fallbackMimeType: 'audio/mp4'),
        'audio/mp4',
      );
    });
  });
}
