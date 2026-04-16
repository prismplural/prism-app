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
      // Realistic CAF header: 8-byte file header, 12-byte desc chunk header,
      // 8-byte mSampleRate, then 'opus' mFormatID at byte 28.
      final bytes = Uint8List(36);
      // File header: 'caff' magic
      bytes.setRange(0, 4, 'caff'.codeUnits);
      // bytes 4-7: version (zeros ok)
      // Chunk header at byte 8: 'desc' type
      bytes.setRange(8, 12, 'desc'.codeUnits);
      // bytes 12-19: chunk size (8 bytes, zeros ok for test)
      // bytes 20-27: mSampleRate (Float64, zeros ok for test)
      // mFormatID at byte 28: 'opus'
      bytes.setRange(28, 32, 'opus'.codeUnits);

      final format = detectVoiceFormat(bytes);

      expect(format.container, VoiceContainer.caf);
      expect(format.codec, VoiceCodec.opus);
      expect(format.needsRemuxBeforeUpload, isTrue);
      expect(format.mimeType, 'audio/x-caf');
    });

    test('identifies CAF with unknown codec when opus marker is absent', () {
      final bytes = Uint8List(36);
      bytes.setRange(0, 4, 'caff'.codeUnits);
      bytes.setRange(8, 12, 'desc'.codeUnits);
      // mFormatID at byte 28: 'aac_' (not opus)
      bytes.setRange(28, 32, 'aac_'.codeUnits);

      final format = detectVoiceFormat(bytes);

      expect(format.container, VoiceContainer.caf);
      expect(format.codec, VoiceCodec.unknown);
      expect(format.needsRemuxBeforeUpload, isFalse);
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
        resolveVoiceMimeType(bytes, fallbackMimeType: 'audio/aac'),
        'audio/ogg',
      );
    });

    test('unknown bytes keep an explicit MIME fallback', () {
      final bytes = Uint8List.fromList([9, 8, 7, 6]);

      expect(
        resolveVoiceMimeType(bytes, fallbackMimeType: 'audio/aac'),
        'audio/aac',
      );
    });
  });
}
