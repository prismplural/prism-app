// test/data/repositories/drift_media_attachment_repository_replace_test.dart
//
// Covers the library image "Replace image" path:
// DriftMediaAttachmentRepository.replaceMedia(attachmentId, data).
//
// The Media screen's "Replace image" swaps an image's bytes (new mediaId +
// hashes/size/blurhash) while keeping the SAME library row (same id + tag) so
// every `![](tag)` reference resolves to the new image. A create() here would
// collide on the primary key, so replacement must be an in-place update.
//
// These tests run against an in-memory AppDatabase and assert:
//   * the row keeps its id + tag, gains the new media metadata, and stays a
//     single row (no PK collision / duplicate insert),
//   * sourceUrl behaviour matches the implementation (the repo writes whatever
//     `data.sourceUrl` is; the real caller passes the prior sourceUrl through
//     `attachment.copyWith(...)`, so provenance is preserved end-to-end),
//   * exactly ONE sync record is emitted, as an `update` (not a second create),
//     observed via SyncRecordMixin's capture sink.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/media_attachments_dao.dart';
import 'package:prism_plurality/data/repositories/drift_media_attachment_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/media_attachment.dart' as domain;

void main() {
  late AppDatabase db;
  late MediaAttachmentsDao dao;
  late DriftMediaAttachmentRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = MediaAttachmentsDao(db);
    // Null sync handle — the SyncRecordMixin capture sink intercepts before
    // any FFI call, so emission is observable without a live handle.
    repo = DriftMediaAttachmentRepository(dao, null);
  });

  tearDown(() => db.close());

  // A library row: non-empty tag, empty memberId/messageId.
  domain.MediaAttachment makeLibraryImage({
    String id = 'lib1',
    String tag = 'avatar-ref',
    String mediaId = 'media-old',
    String contentHash = 'chash-old',
    String plaintextHash = 'phash-old',
    String mimeType = 'image/jpeg',
    int sizeBytes = 1000,
    int width = 100,
    int height = 100,
    String blurhash = 'LBLD-old',
    String sourceUrl = 'https://example.com/original.jpg',
  }) {
    return domain.MediaAttachment(
      id: id,
      messageId: '',
      memberId: '',
      tag: tag,
      mediaId: mediaId,
      mediaType: 'image',
      encryptionKeyB64: 'key-old',
      contentHash: contentHash,
      plaintextHash: plaintextHash,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      width: width,
      height: height,
      durationMs: 0,
      blurhash: blurhash,
      waveformB64: '',
      thumbnailMediaId: '',
      sourceUrl: sourceUrl,
      previewUrl: '',
    );
  }

  group('replaceMedia (library image bytes swap)', () {
    test(
      'updates media metadata in place: same id + tag, new media fields, '
      'still exactly one row',
      () async {
        final original = makeLibraryImage();
        await repo.create(original);

        await repo.replaceMedia(
          original.id,
          original.copyWith(
            mediaId: 'media-new',
            encryptionKeyB64: 'key-new',
            contentHash: 'chash-new',
            plaintextHash: 'phash-new',
            mimeType: 'image/png',
            sizeBytes: 2048,
            width: 200,
            height: 150,
            blurhash: 'LBLD-new',
          ),
        );

        final row = await dao.getById(original.id);
        expect(row, isNotNull);

        // Same identity: id + tag are unchanged so references still resolve.
        expect(row!.id, original.id);
        expect(row.tag, original.tag);

        // New media bytes/metadata took effect.
        expect(row.mediaId, 'media-new');
        expect(row.encryptionKeyB64, 'key-new');
        expect(row.contentHash, 'chash-new');
        expect(row.plaintextHash, 'phash-new');
        expect(row.mimeType, 'image/png');
        expect(row.sizeBytes, 2048);
        expect(row.width, 200);
        expect(row.height, 150);
        expect(row.blurhash, 'LBLD-new');

        // No PK collision / no duplicate insert: exactly one row for this id.
        final matching =
            (await dao.getAll()).where((r) => r.id == original.id).toList();
        expect(matching, hasLength(1));
      },
    );

    test(
      'preserves sourceUrl when the caller passes the prior value through '
      'copyWith (matches _replaceImage in media_settings_screen)',
      () async {
        final original =
            makeLibraryImage(sourceUrl: 'https://cdn.example/avatar.png');
        await repo.create(original);

        // The real caller does attachment.copyWith(mediaId: ..., blurhash: ...)
        // and never touches sourceUrl, so the original provenance flows in.
        await repo.replaceMedia(
          original.id,
          original.copyWith(mediaId: 'media-new', blurhash: 'LBLD-new'),
        );

        final row = await dao.getById(original.id);
        expect(row!.sourceUrl, 'https://cdn.example/avatar.png');
      },
    );

    test(
      'sourceUrl is whatever data.sourceUrl is — the repo writes it verbatim '
      '(does not force-preserve the stored value)',
      () async {
        final original =
            makeLibraryImage(sourceUrl: 'https://cdn.example/original.png');
        await repo.create(original);

        // If a caller supplied a different sourceUrl, the repo would write it.
        // This pins replaceMedia's actual contract (it sets, not preserves).
        await repo.replaceMedia(
          original.id,
          original.copyWith(
            mediaId: 'media-new',
            sourceUrl: 'https://cdn.example/changed.png',
          ),
        );

        final row = await dao.getById(original.id);
        expect(row!.sourceUrl, 'https://cdn.example/changed.png');
      },
    );

    test('emits exactly one sync record, as an update (not a second create)',
        () async {
      final original = makeLibraryImage();
      await repo.create(original);

      // Start capturing only after create(), so we observe just the replace.
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.replaceMedia(
        original.id,
        original.copyWith(
          mediaId: 'media-new',
          contentHash: 'chash-new',
          plaintextHash: 'phash-new',
          sizeBytes: 2048,
          blurhash: 'LBLD-new',
        ),
      );

      expect(captured, hasLength(1));
      final op = captured.single;
      expect(op.opType, SyncRecordOpType.update);
      expect(op.table, 'media_attachments');
      expect(op.entityId, original.id);
      // The repo emits a fixed media-field set on replace.
      expect(op.fields['media_id'], 'media-new');
      expect(op.fields['content_hash'], 'chash-new');
      expect(op.fields['plaintext_hash'], 'phash-new');
      expect(op.fields['size_bytes'], 2048);
      expect(op.fields['blurhash'], 'LBLD-new');
    });
  });
}
