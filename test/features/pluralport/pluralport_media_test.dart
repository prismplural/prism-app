import 'dart:async';
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
import 'package:prism_plurality/features/pluralport/services/pluralport_preservation.dart';
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
  Future<EncryptedMedia> encryptMediaWithKey(
    Uint8List plaintext,
    Uint8List key,
  ) async {
    final encrypted = transform(plaintext);
    return EncryptedMedia(
      ciphertext: encrypted,
      key: key,
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

/// Deterministic stand-in for the app's authenticated media recovery. Records
/// every request so a test can prove the export stayed off the network.
class _FakeRecovery {
  _FakeRecovery({
    Map<String, Uint8List>? remote,
    Uint8List? generated,
    bool generateThrows = false,
    PluralPortMediaRecoveryLimits limits =
        const PluralPortMediaRecoveryLimits(),
  }) : _remote = remote ?? const <String, Uint8List>{},
       _generated = generated,
       _generateThrows = generateThrows,
       _limits = limits;

  final Map<String, Uint8List> _remote;
  final Uint8List? _generated;
  final bool _generateThrows;
  final PluralPortMediaRecoveryLimits _limits;

  final List<String> fetchRequests = [];
  int generateCalls = 0;

  PluralPortMediaRecovery get adapter => PluralPortMediaRecovery(
    limits: _limits,
    fetch: (request) async {
      fetchRequests.add(request.mediaId);
      final bytes = _remote[request.mediaId];
      if (bytes == null) return const PluralPortRemoteMedia.failed('not_found');
      return PluralPortRemoteMedia.ok(bytes);
    },
    generateThumbnail: (original) async {
      generateCalls += 1;
      if (_generateThrows) throw StateError('codec unavailable');
      return PluralPortRecoveredMedia(
        bytes:
            _generated ??
            Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...original.take(16)]),
      );
    },
  );
}

PluralPortService _recoveryService(
  AppDatabase db,
  Directory dir, {
  PluralPortMediaRecovery? recovery,
}) => PluralPortService(
  db: db,
  exporter: makeExport(db),
  importer: makeImport(db, supportDirectory: dir),
  encryption: _Encryption(),
  supportDirectory: () async => dir,
  recovery: recovery,
);

/// Seed one native attachment row. [cacheOriginal] writes the encrypted blob to
/// the cache; a null [thumbnailPlaintext] leaves the thumbnail integrity fields
/// empty (the shape a peer-blanked row has after a backup restore).
Future<void> _seedAttachment(
  AppDatabase db,
  Directory dir, {
  required String id,
  required Uint8List plaintext,
  bool cacheOriginal = true,
  String? thumbnailMediaId,
  Uint8List? thumbnailPlaintext,
  bool cacheThumbnail = false,
  String mediaType = 'image',
  String mimeType = 'image/png',
}) async {
  final encryption = _Encryption();
  final encrypted = await encryption.encryptMedia(plaintext);
  final mediaId = 'media-$id';
  final mediaDirectory = Directory('${dir.path}/prism_media');
  if (cacheOriginal) {
    await mediaDirectory.create(recursive: true);
    await File(
      '${mediaDirectory.path}/$mediaId.enc',
    ).writeAsBytes(encrypted.ciphertext);
  }
  var thumbnailContentHash = '';
  var thumbnailPlaintextHash = '';
  if (thumbnailMediaId != null && thumbnailPlaintext != null) {
    final encryptedThumbnail = await encryption.encryptMediaWithKey(
      thumbnailPlaintext,
      encrypted.key,
    );
    thumbnailContentHash = encryptedThumbnail.ciphertextHash;
    thumbnailPlaintextHash = encryptedThumbnail.plaintextHash;
    if (cacheThumbnail) {
      await mediaDirectory.create(recursive: true);
      await File(
        '${mediaDirectory.path}/$thumbnailMediaId.enc',
      ).writeAsBytes(encryptedThumbnail.ciphertext);
    }
  }
  await db.mediaAttachmentsDao.insertAttachment(
    MediaAttachmentsCompanion.insert(
      id: id,
      mediaId: drift.Value(mediaId),
      mediaType: drift.Value(mediaType),
      encryptionKeyB64: drift.Value(base64Encode(encrypted.key)),
      contentHash: drift.Value(encrypted.ciphertextHash),
      plaintextHash: drift.Value(encrypted.plaintextHash),
      mimeType: drift.Value(mimeType),
      sizeBytes: drift.Value(plaintext.length),
      width: const drift.Value(4),
      height: const drift.Value(4),
      thumbnailMediaId: drift.Value(thumbnailMediaId ?? ''),
      thumbnailContentHash: drift.Value(thumbnailContentHash),
      thumbnailPlaintextHash: drift.Value(thumbnailPlaintextHash),
    ),
  );
}

Json _associationFor(PluralPortBundle bundle, String attachmentId) {
  for (final asset in PluralPortMapper.rows(bundle.envelope, 'assets')) {
    final prism = (asset['extensions'] as Map?)?['prism'] as Map?;
    for (final association in (prism?['media_attachments'] as List? ?? [])) {
      if (association is Map && association['id'] == attachmentId) {
        return association.cast<String, dynamic>();
      }
    }
  }
  throw StateError('no exported association for $attachmentId');
}

Json _assetWithId(PluralPortBundle bundle, String id) => PluralPortMapper.rows(
  bundle.envelope,
  'assets',
).singleWhere((a) => a['id'] == id);

List _warnings(PluralPortBundle bundle) => bundle.envelope['warnings'] as List;

bool _hasWarning(PluralPortBundle bundle, String code) =>
    _warnings(bundle).any((w) => w is Map && w['code'] == code);

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

  group('export media recovery', () {
    test('generates a thumbnail from the cached original, offline', () async {
      final dir = await Directory.systemTemp.createTemp('pluralport-recover-');
      addTearDown(() => dir.delete(recursive: true));
      final db = makeDb();
      addTearDown(db.close);
      final original = Uint8List.fromList(List.generate(64, (i) => i));
      await _seedAttachment(
        db,
        dir,
        id: 'gen',
        plaintext: original,
        // The phone's shape: a thumbnail id with blank integrity fields and no
        // cached bytes, while the original is present.
        thumbnailMediaId: 'thumb-gen',
      );
      final fake = _FakeRecovery();
      final bundle = await _recoveryService(
        db,
        dir,
        recovery: fake.adapter,
      ).exportBundle();

      expect(fake.fetchRequests, isEmpty, reason: 'nothing to fetch');
      expect(fake.generateCalls, 1);

      final thumbnailAssetId = PluralPortMapper.stableId(
        'prism/thumbnail',
        'gen',
      );
      final thumbnail = _assetWithId(bundle, thumbnailAssetId);
      final path = thumbnail['bundle_path'] as String;
      expect(path, isNot(contains('null')));
      expect(bundle.files.containsKey(path), isTrue);
      expect(
        thumbnail['sha256'],
        sha256.convert(bundle.files[path]!).toString(),
      );
      expect(thumbnail['size_bytes'], bundle.files[path]!.length);
      expect(thumbnail['mime_type'], 'image/jpeg');
      expect(thumbnail['kind'], 'image');

      final association = _associationFor(bundle, 'gen');
      expect(association['thumbnail_asset_id'], thumbnailAssetId);
      expect(_hasWarning(bundle, 'asset_thumbnail_generated'), isTrue);
      expect(_hasWarning(bundle, 'asset_bundle_missing'), isFalse);
      expect(PluralPortService.validateBundle(bundle), isEmpty);
      expect(
        () => PluralPortMapper.plan(PluralPortBundle.decode(bundle.encode())),
        returnsNormally,
      );
    });

    test('recovers a missing original from the authenticated path', () async {
      final dir = await Directory.systemTemp.createTemp('pluralport-recover-');
      addTearDown(() => dir.delete(recursive: true));
      final db = makeDb();
      addTearDown(db.close);
      final original = Uint8List.fromList(List.generate(48, (i) => 200 - i));
      await _seedAttachment(
        db,
        dir,
        id: 'fetch',
        plaintext: original,
        cacheOriginal: false,
        thumbnailMediaId: 'thumb-fetch',
      );
      final fake = _FakeRecovery(remote: {'media-fetch': original});
      final bundle = await _recoveryService(
        db,
        dir,
        recovery: fake.adapter,
      ).exportBundle();

      expect(fake.fetchRequests, ['media-fetch']);
      final asset = _assetWithId(
        bundle,
        PluralPortMapper.stableId('prism/media', 'fetch'),
      );
      expect(bundle.assetBytes(asset), original);
      expect(asset['sha256'], sha256.convert(original).toString());
      expect(asset['size_bytes'], original.length);
      // The recovered original is enough to generate the thumbnail too.
      expect(fake.generateCalls, 1);
      expect(_hasWarning(bundle, 'asset_media_recovered'), isTrue);
      expect(PluralPortService.validateBundle(bundle), isEmpty);
    });

    test('uses cached bytes and never touches the network', () async {
      final dir = await Directory.systemTemp.createTemp('pluralport-recover-');
      addTearDown(() => dir.delete(recursive: true));
      final db = makeDb();
      addTearDown(db.close);
      final original = Uint8List.fromList(List.generate(32, (i) => i + 1));
      final thumbnailPlaintext = Uint8List.fromList([1, 2, 3, 4, 5]);
      await _seedAttachment(
        db,
        dir,
        id: 'cached',
        plaintext: original,
        thumbnailMediaId: 'thumb-cached',
        thumbnailPlaintext: thumbnailPlaintext,
        cacheThumbnail: true,
      );
      final fake = _FakeRecovery(remote: {'media-cached': original});
      final bundle = await _recoveryService(
        db,
        dir,
        recovery: fake.adapter,
      ).exportBundle();

      expect(fake.fetchRequests, isEmpty);
      expect(fake.generateCalls, 0);
      final asset = _assetWithId(
        bundle,
        PluralPortMapper.stableId('prism/media', 'cached'),
      );
      expect(bundle.assetBytes(asset), original);
      final thumbnail = _assetWithId(
        bundle,
        PluralPortMapper.stableId('prism/thumbnail', 'cached'),
      );
      expect(bundle.assetBytes(thumbnail), thumbnailPlaintext);
      expect(_hasWarning(bundle, 'asset_bundle_missing'), isFalse);
      expect(PluralPortService.validateBundle(bundle), isEmpty);
    });

    test('exports metadata only when no bytes can be produced', () async {
      final dir = await Directory.systemTemp.createTemp('pluralport-recover-');
      addTearDown(() => dir.delete(recursive: true));
      final db = makeDb();
      addTearDown(db.close);
      await _seedAttachment(
        db,
        dir,
        id: 'gone',
        plaintext: Uint8List.fromList([7, 7, 7, 7]),
        cacheOriginal: false,
        thumbnailMediaId: 'thumb-gone',
      );
      // No recovery adapter at all: the fully offline case.
      final bundle = await _recoveryService(db, dir).exportBundle();

      final asset = _assetWithId(
        bundle,
        PluralPortMapper.stableId('prism/media', 'gone'),
      );
      expect(asset.containsKey('bundle_path'), isFalse);
      expect(asset.containsKey('sha256'), isFalse);
      expect(asset.containsKey('size_bytes'), isFalse);
      expect(asset['kind'], 'image');
      expect(asset['mime_type'], 'image/png');
      expect(asset['width'], 4);
      final unavailable =
          ((asset['extensions'] as Map)['prism'] as Map)['unavailable'] as Map;
      expect(unavailable['reason'], 'bytes_not_on_this_device');
      expect(_hasWarning(bundle, 'asset_bundle_missing'), isTrue);
      // The descriptor survives even though the bytes do not.
      expect(_associationFor(bundle, 'gone')['id'], 'gone');
      expect(PluralPortService.validateBundle(bundle), isEmpty);
      expect(jsonEncode(bundle.envelope), isNot(contains('assets/null')));
      expect(
        () => PluralPortMapper.plan(PluralPortBundle.decode(bundle.encode())),
        returnsNormally,
      );
    });

    test(
      'a blank-hash thumbnail never becomes an assets/null record',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'pluralport-recover-',
        );
        addTearDown(() => dir.delete(recursive: true));
        final db = makeDb();
        addTearDown(db.close);
        await _seedAttachment(
          db,
          dir,
          id: 'blank',
          plaintext: Uint8List.fromList([9, 9, 9]),
          cacheOriginal: false,
          thumbnailMediaId: 'thumb-blank',
        );
        final fake = _FakeRecovery();
        final bundle = await _recoveryService(
          db,
          dir,
          recovery: fake.adapter,
        ).exportBundle();

        final thumbnailAssetId = PluralPortMapper.stableId(
          'prism/thumbnail',
          'blank',
        );
        expect(
          PluralPortMapper.rows(
            bundle.envelope,
            'assets',
          ).where((a) => a['id'] == thumbnailAssetId),
          isEmpty,
        );
        final association = _associationFor(bundle, 'blank');
        expect(association.containsKey('thumbnail_asset_id'), isFalse);
        expect(jsonEncode(bundle.envelope), isNot(contains('assets/null')));
        for (final asset in PluralPortMapper.rows(bundle.envelope, 'assets')) {
          expect(asset['sha256'], isNot(''));
        }
        expect(_hasWarning(bundle, 'asset_bundle_missing'), isTrue);
        expect(PluralPortService.validateBundle(bundle), isEmpty);
        expect(
          () => PluralPortMapper.plan(PluralPortBundle.decode(bundle.encode())),
          returnsNormally,
        );
      },
    );

    test(
      'a codec failure degrades to a warning, not a failed export',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'pluralport-recover-',
        );
        addTearDown(() => dir.delete(recursive: true));
        final db = makeDb();
        addTearDown(db.close);
        await _seedAttachment(
          db,
          dir,
          id: 'codec',
          plaintext: Uint8List.fromList([4, 5, 6, 7]),
          thumbnailMediaId: 'thumb-codec',
        );
        final fake = _FakeRecovery(generateThrows: true);
        final bundle = await _recoveryService(
          db,
          dir,
          recovery: fake.adapter,
        ).exportBundle();

        expect(fake.generateCalls, 1);
        expect(
          PluralPortMapper.rows(bundle.envelope, 'assets').where(
            (a) =>
                a['id'] ==
                PluralPortMapper.stableId('prism/thumbnail', 'codec'),
          ),
          isEmpty,
        );
        expect(
          _associationFor(bundle, 'codec').containsKey('thumbnail_asset_id'),
          isFalse,
        );
        expect(_hasWarning(bundle, 'asset_bundle_missing'), isTrue);
        expect(PluralPortService.validateBundle(bundle), isEmpty);
      },
    );

    test('every declared media asset resolves inside the archive', () async {
      final dir = await Directory.systemTemp.createTemp('pluralport-recover-');
      addTearDown(() => dir.delete(recursive: true));
      final db = makeDb();
      addTearDown(db.close);
      final cached = Uint8List.fromList(List.generate(24, (i) => i));
      final remote = Uint8List.fromList(List.generate(20, (i) => 90 - i));
      await _seedAttachment(
        db,
        dir,
        id: 'mix-cached',
        plaintext: cached,
        thumbnailMediaId: 'thumb-mix-cached',
      );
      await _seedAttachment(
        db,
        dir,
        id: 'mix-fetched',
        plaintext: remote,
        cacheOriginal: false,
        thumbnailMediaId: 'thumb-mix-fetched',
      );
      await _seedAttachment(
        db,
        dir,
        id: 'mix-missing',
        plaintext: Uint8List.fromList([1, 2, 3, 4, 5, 6]),
        cacheOriginal: false,
        thumbnailMediaId: 'thumb-mix-missing',
      );
      final fake = _FakeRecovery(remote: {'media-mix-fetched': remote});
      final bundle = await _recoveryService(
        db,
        dir,
        recovery: fake.adapter,
      ).exportBundle();

      expect(PluralPortService.validateBundle(bundle), isEmpty);
      for (final asset in PluralPortMapper.rows(bundle.envelope, 'assets')) {
        final path = asset['bundle_path'];
        if (path is! String) continue;
        expect(bundle.files.containsKey(path), isTrue, reason: path);
        final bytes = bundle.files[path]!;
        expect(asset['sha256'], sha256.convert(bytes).toString());
        expect(asset['size_bytes'], bytes.length);
        expect(asset['mime_type'], isA<String>());
        expect(bundle.assetBytes(asset), bytes);
      }
      expect(
        () => PluralPortMapper.plan(PluralPortBundle.decode(bundle.encode())),
        returnsNormally,
      );
    });

    test('remote recovery rejects an item that exceeds its byte cap', () async {
      final dir = await Directory.systemTemp.createTemp('pluralport-recover-');
      addTearDown(() => dir.delete(recursive: true));
      final db = makeDb();
      addTearDown(db.close);
      final remote = Uint8List.fromList(List.generate(16, (i) => i));
      await _seedAttachment(
        db,
        dir,
        id: 'byte-cap',
        plaintext: remote,
        cacheOriginal: false,
      );
      await _seedAttachment(
        db,
        dir,
        id: 'byte-cap-second',
        plaintext: remote,
        cacheOriginal: false,
      );
      final fake = _FakeRecovery(
        remote: {'media-byte-cap': remote, 'media-byte-cap-second': remote},
        limits: const PluralPortMediaRecoveryLimits(maxRemoteBytes: 8),
      );

      final bundle = await _recoveryService(
        db,
        dir,
        recovery: fake.adapter,
      ).exportBundle();
      final asset = PluralPortMapper.rows(bundle.envelope, 'assets')
          .singleWhere(
            (row) =>
                row['id'] ==
                PluralPortMapper.stableId('prism/media', 'byte-cap'),
          );
      final unavailable =
          ((asset['extensions'] as Map)['prism'] as Map)['unavailable'] as Map;

      expect(fake.fetchRequests, ['media-byte-cap']);
      expect(asset['bundle_path'], isNull);
      expect(unavailable['reason'], 'remote_byte_limit');
      expect(PluralPortService.validateBundle(bundle), isEmpty);
    });

    test(
      'local media omitted by the bundle cap is reported truthfully',
      () async {
        final dir = await Directory.systemTemp.createTemp('pluralport-budget-');
        addTearDown(() => dir.delete(recursive: true));
        final db = makeDb();
        addTearDown(db.close);
        final local = Uint8List.fromList(List.generate(16, (i) => i));
        await _seedAttachment(db, dir, id: 'bundle-cap', plaintext: local);
        final fake = _FakeRecovery(
          limits: const PluralPortMediaRecoveryLimits(maxBundleMediaBytes: 8),
        );

        final bundle = await _recoveryService(
          db,
          dir,
          recovery: fake.adapter,
        ).exportBundle();
        final asset = PluralPortMapper.rows(bundle.envelope, 'assets').single;

        expect(asset['bundle_path'], isNull);
        expect(_hasWarning(bundle, 'asset_bundle_omitted'), isTrue);
        expect(_hasWarning(bundle, 'asset_bundle_missing'), isFalse);
        expect(PluralPortService.validateBundle(bundle), isEmpty);
      },
    );

    test('retained dangling asset declarations become metadata-only', () async {
      final dir = await Directory.systemTemp.createTemp('pluralport-retained-');
      addTearDown(() => dir.delete(recursive: true));
      final db = makeDb();
      addTearDown(db.close);
      await PluralPortPreservation(db).retain({
        'kind': 'import',
        'namespace': 'foreign:test',
        'imported_at': '2026-01-01T00:00:00.000Z',
        'envelope': {
          'openplural_version': '0.1',
          'producer': {'app': 'Foreign'},
          'capabilities': {
            'modules': ['assets'],
          },
          'warnings': <dynamic>[],
          'assets': [
            {
              'id': 'dangling-asset',
              'kind': 'image',
              'bundle_path': 'assets/null',
              'sha256': null,
              'size_bytes': 12,
            },
            {
              'id': 'sheaf-dangling',
              'kind': 'image',
              'extensions': {
                'sheaf': {
                  'bundle_path': 'media/missing.png',
                  'other_metadata': 'kept',
                },
              },
            },
            {
              'id': 'sheaf-malformed',
              'kind': 'image',
              'extensions': {
                'sheaf': {'bundle_path': 42},
              },
            },
          ],
        },
        'files': <String, String>{},
        'bindings': <String, dynamic>{},
        'baseline': <String, dynamic>{},
      });

      final bundle = await _recoveryService(db, dir).exportBundle();
      final asset = PluralPortMapper.rows(
        bundle.envelope,
        'assets',
      ).singleWhere((row) => row['id'] == 'dangling-asset');

      expect(asset['bundle_path'], isNull);
      expect(asset['sha256'], isNull);
      expect(asset['size_bytes'], isNull);
      final prismEvidence = (asset['extensions'] as Map)['prism'] as Map;
      expect(prismEvidence['unusable_media_declaration'], {
        'bundle_path': 'assets/null',
        'size_bytes': 12,
      });
      final legacy = PluralPortMapper.rows(
        bundle.envelope,
        'assets',
      ).singleWhere((row) => row['id'] == 'sheaf-dangling');
      expect(((legacy['extensions'] as Map)['sheaf'] as Map), {
        'other_metadata': 'kept',
      });
      expect(_hasWarning(bundle, 'export_self_check'), isTrue);
      expect(PluralPortService.validateBundle(bundle), isEmpty);
    });

    test('remote deadline releases an export with a stalled fetch', () async {
      final dir = await Directory.systemTemp.createTemp('pluralport-deadline-');
      addTearDown(() => dir.delete(recursive: true));
      final db = makeDb();
      addTearDown(db.close);
      await _seedAttachment(
        db,
        dir,
        id: 'stalled',
        plaintext: Uint8List.fromList([1, 2, 3]),
        cacheOriginal: false,
      );
      final pending = Completer<PluralPortRemoteMedia>();
      final recovery = PluralPortMediaRecovery(
        limits: const PluralPortMediaRecoveryLimits(
          remoteDeadline: Duration(milliseconds: 100),
        ),
        fetch: (_) => pending.future,
        generateThumbnail: (_) async => throw StateError('not needed'),
      );
      final bundle = await _recoveryService(
        db,
        dir,
        recovery: recovery,
      ).exportBundle().timeout(const Duration(seconds: 5));
      pending.complete(const PluralPortRemoteMedia.failed('late'));
      expect(_hasWarning(bundle, 'asset_recovery_skipped'), isTrue);
      expect(PluralPortService.validateBundle(bundle), isEmpty);
      final asset = PluralPortMapper.rows(bundle.envelope, 'assets').single;
      final prism = (asset['extensions'] as Map)['prism'] as Map;
      expect((prism['unavailable'] as Map)['reason'], 'recovery_deadline');
    });

    test('thumbnail generation respects its item cap', () async {
      final dir = await Directory.systemTemp.createTemp('pluralport-thumbs-');
      addTearDown(() => dir.delete(recursive: true));
      final db = makeDb();
      addTearDown(db.close);
      for (final id in ['thumb-cap-1', 'thumb-cap-2']) {
        await _seedAttachment(
          db,
          dir,
          id: id,
          plaintext: Uint8List.fromList([1, 2, 3, 4]),
          thumbnailMediaId: 'legacy-$id',
        );
      }
      final fake = _FakeRecovery(
        limits: const PluralPortMediaRecoveryLimits(maxGeneratedThumbnails: 1),
      );
      final bundle = await _recoveryService(
        db,
        dir,
        recovery: fake.adapter,
      ).exportBundle();
      expect(fake.generateCalls, 1);
      expect(fake.fetchRequests, isEmpty);
      expect(PluralPortService.validateBundle(bundle), isEmpty);
      expect(_hasWarning(bundle, 'asset_thumbnail_generated'), isTrue);
      expect(_hasWarning(bundle, 'asset_bundle_missing'), isTrue);
    });

    test(
      'container brands preserve image and audio MIME distinctions',
      () async {
        final dir = await Directory.systemTemp.createTemp('pluralport-mime-');
        addTearDown(() => dir.delete(recursive: true));
        final db = makeDb();
        addTearDown(db.close);
        const brands = {
          'heic': 'image/heic',
          'avif': 'image/avif',
          'M4A ': 'audio/mp4',
          'qt  ': 'video/quicktime',
          'isom': 'audio/mp4',
        };
        var index = 0;
        for (final brand in brands.entries) {
          await _seedAttachment(
            db,
            dir,
            id: 'mime-${index++}',
            plaintext: Uint8List.fromList([
              0,
              0,
              0,
              24,
              ...ascii.encode('ftyp'),
              ...ascii.encode(brand.key),
            ]),
            mimeType: brand.value,
          );
        }
        final bundle = await _recoveryService(db, dir).exportBundle();
        index = 0;
        for (final mime in brands.values) {
          final id = PluralPortMapper.stableId(
            'prism/media',
            'mime-${index++}',
          );
          final asset = PluralPortMapper.rows(
            bundle.envelope,
            'assets',
          ).singleWhere((row) => row['id'] == id);
          expect(asset['mime_type'], mime);
        }
      },
    );

    test('remote recovery respects its item cap', () async {
      final dir = await Directory.systemTemp.createTemp('pluralport-recover-');
      addTearDown(() => dir.delete(recursive: true));
      final db = makeDb();
      addTearDown(db.close);
      final first = Uint8List.fromList(List.generate(16, (i) => i));
      final second = Uint8List.fromList(List.generate(16, (i) => 31 - i));
      await _seedAttachment(
        db,
        dir,
        id: 'cap-1',
        plaintext: first,
        cacheOriginal: false,
      );
      await _seedAttachment(
        db,
        dir,
        id: 'cap-2',
        plaintext: second,
        cacheOriginal: false,
      );
      final fake = _FakeRecovery(
        remote: {'media-cap-1': first, 'media-cap-2': second},
        limits: const PluralPortMediaRecoveryLimits(maxRemoteItems: 1),
      );
      final bundle = await _recoveryService(
        db,
        dir,
        recovery: fake.adapter,
      ).exportBundle();

      expect(fake.fetchRequests, hasLength(1));
      expect(_hasWarning(bundle, 'asset_recovery_skipped'), isTrue);
      expect(_hasWarning(bundle, 'asset_bundle_missing'), isTrue);
      expect(PluralPortService.validateBundle(bundle), isEmpty);
    });
  });
}
