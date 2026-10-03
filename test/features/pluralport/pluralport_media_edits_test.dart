import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/services/media/media_encryption_service.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_bundle.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_mapper.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_service.dart';
import 'harness.dart';

class Encryption extends MediaEncryptionService {
  @override
  Future<EncryptedMedia> encryptMedia(Uint8List p) async => EncryptedMedia(
    ciphertext: p,
    key: Uint8List.fromList([42]),
    plaintextHash: sha256.convert(p).toString(),
    ciphertextHash: sha256.convert(p).toString(),
  );
  @override
  Future<Uint8List> decryptMedia({
    required Uint8List ciphertext,
    required Uint8List key,
    required String expectedCiphertextHash,
    required String expectedPlaintextHash,
  }) async => ciphertext;
}

void main() {
  test('edited library media metadata survives reexport', () async {
    final dir = await Directory.systemTemp.createTemp('pluralport-media-edit-');
    addTearDown(() => dir.delete(recursive: true));
    final db = makeDb();
    addTearDown(db.close);
    final service = PluralPortService(
      db: db,
      exporter: makeExport(db),
      importer: makeImport(db, supportDirectory: dir),
      encryption: Encryption(),
      supportDirectory: () async => dir,
    );
    final bundle = PluralPortBundle({
      'pluralport_version': '0.1',
      'producer': {'app': 'Prism'},
      'members': [
        {
          'id': 'm',
          'name': 'M',
          'source_refs': [
            {'app': 'prism', 'collection': 'headmates', 'id': 'm'},
          ],
        },
      ],
      'assets': [
        {
          'id': 'a',
          'kind': 'image',
          'mime_type': 'image/png',
          'data_base64': base64Encode([1, 2, 3]),
          'extensions': {
            'prism': {
              'media_attachments': [
                {
                  'id': 'lib',
                  'member_id': 'm',
                  'tag': 'before',
                  'media_type': 'image',
                },
              ],
            },
          },
        },
      ],
    });
    await service.importPlan(PluralPortMapper.plan(bundle));
    await db.customStatement(
      "UPDATE media_attachments SET tag = 'after' WHERE id = 'lib'",
    );
    final exported = await service.exportBundle();
    final db2 = makeDb();
    addTearDown(db2.close);
    final dir2 = await dir.createTemp('second-');
    final service2 = PluralPortService(
      db: db2,
      exporter: makeExport(db2),
      importer: makeImport(db2, supportDirectory: dir2),
      encryption: Encryption(),
      supportDirectory: () async => dir2,
    );
    await service2.importPlan(
      PluralPortMapper.plan(PluralPortBundle.decode(exported.encode())),
    );
    final media = await db2.select(db2.mediaAttachments).get();
    expect(media.single.tag, 'after');
  });
}
