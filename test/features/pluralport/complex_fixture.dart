import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:image/image.dart' as img;
import 'package:prism_sync/generated/frb_generated.dart';
import 'package:prism_plurality/core/services/media/media_encryption_service.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_mapper.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_bundle.dart';

Future<void> initializeFixtureCrypto() async {
  final manifest =
      jsonDecode(
            await File(
              'build/native_assets/${Platform.operatingSystem}/native_assets.json',
            ).readAsString(),
          )
          as Map;
  final targets = manifest['native-assets'] as Map;
  final target = targets.values.single as Map;
  final library =
      target['package:prism_sync/generated/frb_generated.dart'] as List;
  await RustLib.init(
    externalLibrary: ExternalLibrary.open(library.last as String),
  );
}

Uint8List fixturePng(int red) {
  final image = img.Image(width: 4, height: 4);
  img.fill(image, color: img.ColorRgba8(red, 120, 80, 255));
  return Uint8List.fromList(img.encodePng(image));
}

Future<({Json native, List<({String mediaId, Uint8List blob})> blobs})>
complexNativeFixture() async {
  final native =
      jsonDecode(
            await File(
              'test/features/pluralport/fixtures/complex_native.json',
            ).readAsString(),
          )
          as Json;
  final portrait = fixturePng(40), banner = fixturePng(80);
  (native['headmates'] as List).first.addAll({
    'pkBannerImageData': base64Encode(fixturePng(230)),
    'pkBannerUrl': 'https://example.invalid/cached-banner.png',
    'profileHeaderSource': 1,
  });
  (native['headmates'] as List).first['profilePhotoData'] = base64Encode(
    portrait,
  );
  (native['headmates'] as List).first['profileHeaderImageData'] = base64Encode(
    banner,
  );
  (native['memberGroups'] as List).first['avatarImageData'] = base64Encode(
    fixturePng(120),
  );
  (native['systemSettings'] as List).first['systemAvatarData'] = base64Encode(
    fixturePng(160),
  );
  final encryption = MediaEncryptionService();
  final blobs = <({String mediaId, Uint8List blob})>[];
  final attachments = <Json>[];
  Future<void> addMedia(
    String id,
    Uint8List bytes,
    String kind, {
    String member = '',
    String message = '',
    bool thumbnail = false,
  }) async {
    final encrypted = await encryption.encryptMedia(bytes);
    final mediaId = PluralPortMapper.stableId('fixture/media', id);
    blobs.add((mediaId: mediaId, blob: encrypted.ciphertext));
    final row = <String, dynamic>{
      'id': id,
      'mediaId': mediaId,
      'memberId': member,
      'messageId': message,
      'tag': member.isEmpty ? '' : 'memory',
      'mediaType': kind,
      'encryptionKeyB64': base64Encode(encrypted.key),
      'contentHash': encrypted.ciphertextHash,
      'plaintextHash': encrypted.plaintextHash,
      'mimeType': kind == 'audio' ? 'audio/wav' : 'image/png',
      'sizeBytes': encrypted.ciphertext.length,
      'width': kind == 'audio' ? 0 : 4,
      'height': kind == 'audio' ? 0 : 4,
      'durationMs': kind == 'audio' ? 1000 : 0,
      'waveformB64': kind == 'audio' ? base64Encode([2, 8, 4]) : '',
      'blurhash': kind == 'audio' ? '' : 'synthetic-blurhash',
    };
    if (thumbnail) {
      final encryptedThumbnail = await encryption.encryptMediaWithKey(
        fixturePng(200),
        encrypted.key,
      );
      blobs.add((
        mediaId: PluralPortMapper.stableId('fixture/thumbnail', id),
        blob: encryptedThumbnail.ciphertext,
      ));
      row.addAll({
        'thumbnailMediaId': PluralPortMapper.stableId('fixture/thumbnail', id),
        'thumbnailContentHash': encryptedThumbnail.ciphertextHash,
        'thumbnailPlaintextHash': encryptedThumbnail.plaintextHash,
      });
    }
    attachments.add(row);
  }

  // The same plaintext is used in a profile, a library image, and two chat
  // attachments: deduplicated bytes must not collapse their associations.
  await addMedia('library-image', portrait, 'image', member: 'm1');
  await addMedia(
    'chat-image',
    portrait,
    'image',
    message: 'msg1',
    thumbnail: true,
  );
  await addMedia('chat-image-copy', portrait, 'image', message: 'msg1');
  final wav = BytesBuilder()
    ..add(ascii.encode('RIFF'))
    ..add([68, 0, 0, 0])
    ..add(ascii.encode('WAVEfmt '))
    ..add([16, 0, 0, 0, 1, 0, 1, 0, 32, 78, 0, 0, 64, 156, 0, 0, 2, 0, 16, 0])
    ..add(ascii.encode('data'))
    ..add([32, 0, 0, 0])
    ..add(List<int>.generate(32, (i) => i));
  await addMedia('chat-audio', wav.toBytes(), 'audio', message: 'msg2');
  attachments.add({
    'id': 'remote-gif',
    'messageId': 'dmmsg',
    'mediaId': '',
    'mediaType': 'gif',
    'encryptionKeyB64': '',
    'contentHash': '',
    'plaintextHash': '',
    'sizeBytes': 0,
    'mimeType': 'video/mp4',
    'sourceUrl': 'https://example.invalid/fixture.mp4',
    'previewUrl': 'https://example.invalid/preview.webp',
    'width': 320,
    'height': 180,
    'blurhash': 'Animated fixture',
  });
  native['mediaAttachments'] = attachments;
  return (native: native, blobs: blobs);
}

PluralPortBundle opaqueFixture() => PluralPortBundle(
  {
    'pluralport_version': '0.1',
    'producer': {'app': 'Future fixture', 'app_id': 'future-fixture'},
    'extensions': {
      'future_fixture': {
        'nested': {'id': 'opaque-id', 'null': null},
        'value': [true, 42, '雪'],
      },
    },
    'experimental_module': {
      'records': [
        {
          'id': 'opaque-row',
          'payload': {'member_id': 'not-a-reference'},
        },
      ],
    },
    'taxonomy_terms': [
      {'id': 'future-role', 'kind': 'role', 'name': 'Future role'},
    ],
    'taxonomy_assignments': [
      {
        'id': 'future-assignment',
        'term_id': 'future-role',
        'subject_type': 'custom',
        'subject_id': 'opaque-subject',
      },
    ],
    'assets': [
      {
        'id': 'future-binary',
        'kind': 'binary',
        'mime_type': 'application/octet-stream',
        'bundle_path': 'foreign/unknown.bin',
      },
    ],
  },
  files: {
    'foreign/unknown.bin': Uint8List.fromList(
      List<int>.generate(257, (i) => i % 256),
    ),
  },
);
