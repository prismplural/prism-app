import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' as drift;
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/services/media/media_encryption_service.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_bundle.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_mapper.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_service.dart';
import 'harness.dart';

// Exercise the file/metadata boundary independently from the Rust crypto tests.
class _Encryption extends MediaEncryptionService {
  Uint8List transform(Uint8List bytes) =>
      Uint8List.fromList(bytes.map((b) => b ^ 42).toList());
  @override
  Future<EncryptedMedia> encryptMedia(Uint8List plaintext) async {
    final encrypted = transform(plaintext);
    return EncryptedMedia(
      ciphertext: encrypted,
      key: Uint8List.fromList([42]),
      plaintextHash: sha256.convert(plaintext).toString(),
      ciphertextHash: sha256.convert(encrypted).toString(),
    );
  }

  @override
  Future<Uint8List> decryptMedia({
    required Uint8List ciphertext,
    required Uint8List key,
    required String expectedCiphertextHash,
    required String expectedPlaintextHash,
  }) async {
    expect(sha256.convert(ciphertext).toString(), expectedCiphertextHash);
    final plaintext = transform(ciphertext);
    expect(sha256.convert(plaintext).toString(), expectedPlaintextHash);
    return plaintext;
  }
}

void main() {
  test(
    'chat media survives encrypted local storage and deletion removes its link',
    () async {
      final dir = await Directory.systemTemp.createTemp('pluralport-media-');
      addTearDown(() => dir.delete(recursive: true));
      final db = makeDb();
      addTearDown(db.close);
      final service = PluralPortService(
        db: db,
        exporter: makeExport(db),
        importer: makeImport(db, supportDirectory: dir),
        encryption: _Encryption(),
        supportDirectory: () async => dir,
      );
      final document = <String, dynamic>{
        'pluralport_version': '0.1',
        'producer': {'app': 'Fixture'},
        'members': [
          {'id': 'm', 'name': 'Member'},
        ],
        'assets': [
          {
            'id': 'a',
            'kind': 'image',
            'mime_type': 'image/png',
            'data_base64': base64Encode([1, 2, 3]),
          },
        ],
        'chat': {
          'conversations': [
            {'id': 'c', 'kind': 'internal_chat', 'title': 'Chat'},
          ],
          'messages': [
            {
              'id': 'msg',
              'conversation_id': 'c',
              'body': 'Photo',
              'author_member_id': 'm',
              'created_at': '2026-01-01T00:00:00Z',
            },
          ],
          'attachments': [
            {
              'id': 'at',
              'message_id': 'msg',
              'asset_id': 'a',
              'caption': 'Keep caption',
            },
          ],
        },
      };
      final plan = PluralPortMapper.plan(PluralPortBundle(document));
      await service.importPlan(plan);
      final attachment = (await db.mediaAttachmentsDao.getAll()).single;
      expect(
        await File(
          '${dir.path}/prism_media/${attachment.mediaId}.enc',
        ).readAsBytes(),
        isNot([1, 2, 3]),
      );
      final bundle = await service.exportBundle();
      final message = PluralPortMapper.rows(
        bundle.envelope,
        'chat.messages',
      ).single;
      final assetId = (message['attachment_asset_ids'] as List).single;
      expect(
        bundle.assetBytes(
          PluralPortMapper.rows(
            bundle.envelope,
            'assets',
          ).singleWhere((a) => a['id'] == assetId),
        ),
        [1, 2, 3],
      );
      expect(
        PluralPortMapper.rows(
          bundle.envelope,
          'chat.attachments',
        ).single['caption'],
        'Keep caption',
      );
      await db.mediaAttachmentsDao.softDelete(attachment.id);
      final deleted = await service.exportBundle();
      expect(
        PluralPortMapper.rows(deleted.envelope, 'chat.attachments'),
        isEmpty,
      );
      expect(
        PluralPortMapper.rows(
              deleted.envelope,
              'chat.messages',
            ).single['attachment_asset_ids'] ??
            [],
        isEmpty,
      );
      expect(
        () => PluralPortMapper.plan(PluralPortBundle.decode(deleted.encode())),
        returnsNormally,
      );
      // A native attachment with no local blob must still export its descriptor
      // and message link, so absence of bytes never becomes absence of metadata.
      await db.delete(db.pluralPortUnsupported).go();
      await db
          .update(db.mediaAttachments)
          .write(
            const MediaAttachmentsCompanion(isDeleted: drift.Value(false)),
          );
      await File('${dir.path}/prism_media/${attachment.mediaId}.enc').delete();
      final missing = await service.exportBundle();
      expect(
        PluralPortMapper.rows(
          missing.envelope,
          'chat.messages',
        ).single['attachment_asset_ids'],
        hasLength(1),
      );
      expect(
        PluralPortMapper.rows(missing.envelope, 'assets').single['mime_type'],
        'image/png',
      );
      expect(
        (missing.envelope['warnings'] as List).any(
          (w) => w['code'] == 'asset_bundle_missing',
        ),
        true,
      );
      expect(
        () => PluralPortMapper.plan(PluralPortBundle.decode(missing.encode())),
        returnsNormally,
      );
    },
  );
}
