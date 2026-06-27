import 'package:drift/drift.dart' show Value;
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/media_attachments_dao.dart';
import 'package:prism_plurality/data/mappers/media_attachment_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/media_attachment.dart' as domain;
import 'package:prism_plurality/domain/repositories/media_attachment_repository.dart';

class DriftMediaAttachmentRepository
    with SyncRecordMixin
    implements MediaAttachmentRepository {
  final MediaAttachmentsDao _dao;
  final ffi.PrismSyncHandle? _syncHandle;

  @override
  ffi.PrismSyncHandle? get syncHandle => _syncHandle;

  @override
  AppDatabase get syncOutboxDatabase => _dao.attachedDatabase;

  static const _table = 'media_attachments';

  DriftMediaAttachmentRepository(this._dao, this._syncHandle);

  @override
  Stream<List<domain.MediaAttachment>> watchForMessage(String messageId) {
    return _dao
        .watchForMessage(messageId)
        .map((rows) => rows.map(MediaAttachmentMapper.toDomain).toList());
  }

  @override
  Future<List<domain.MediaAttachment>> getForMessage(String messageId) async {
    final rows = await _dao.getForMessage(messageId);
    return rows.map(MediaAttachmentMapper.toDomain).toList();
  }

  @override
  Future<void> create(domain.MediaAttachment attachment) async {
    await runSyncedWrite(() async {
      final companion = MediaAttachmentMapper.toCompanion(attachment);
      await _dao.insertAttachment(companion);
      await syncRecordCreate(
        _table,
        attachment.id,
        _attachmentFields(attachment),
      );
    });
  }

  @override
  Future<void> delete(String id) async {
    await runSyncedWrite(() async {
      await _dao.softDelete(id);
      await syncRecordDelete(_table, id);
    });
  }

  @override
  Future<List<domain.MediaAttachment>> getForMember(String memberId) async {
    final rows = await _dao.getForMember(memberId);
    return rows.map(MediaAttachmentMapper.toDomain).toList();
  }

  @override
  Stream<List<domain.MediaAttachment>> watchForMember(String memberId) => _dao
      .watchForMember(memberId)
      .map((rows) => rows.map(MediaAttachmentMapper.toDomain).toList());

  @override
  Stream<List<domain.MediaAttachment>> watchAllBioMedia() => _dao
      .watchAllBioMedia()
      .map((rows) => rows.map(MediaAttachmentMapper.toDomain).toList());

  @override
  Stream<List<domain.MediaAttachment>> watchAllChatMedia() => _dao
      .watchAllChatMedia()
      .map((rows) => rows.map(MediaAttachmentMapper.toDomain).toList());

  @override
  Stream<List<domain.MediaAttachment>> watchLibraryImages() => _dao
      .watchLibraryImages()
      .map((rows) => rows.map(MediaAttachmentMapper.toDomain).toList());

  @override
  Future<void> updateTag(String attachmentId, String tag) async {
    await runSyncedWrite(() async {
      await _dao.updateAttachment(
        MediaAttachmentsCompanion(id: Value(attachmentId), tag: Value(tag)),
      );
      await syncRecordUpdate(_table, attachmentId, {'tag': tag});
    });
  }

  @override
  Future<void> replaceMedia(
    String attachmentId,
    domain.MediaAttachment data,
  ) async {
    await runSyncedWrite(() async {
      await _dao.updateAttachment(
        MediaAttachmentsCompanion(
          id: Value(attachmentId),
          mediaId: Value(data.mediaId),
          encryptionKeyB64: Value(data.encryptionKeyB64),
          contentHash: Value(data.contentHash),
          plaintextHash: Value(data.plaintextHash),
          mimeType: Value(data.mimeType),
          sizeBytes: Value(data.sizeBytes),
          width: Value(data.width),
          height: Value(data.height),
          blurhash: Value(data.blurhash),
          sourceUrl: Value(data.sourceUrl),
        ),
      );
      await syncRecordUpdate(_table, attachmentId, {
        'media_id': data.mediaId,
        'encryption_key_b64': data.encryptionKeyB64,
        'content_hash': data.contentHash,
        'plaintext_hash': data.plaintextHash,
        'mime_type': data.mimeType,
        'size_bytes': data.sizeBytes,
        'width': data.width,
        'height': data.height,
        'blurhash': data.blurhash,
        'source_url': data.sourceUrl,
      });
    });
  }

  @override
  Future<void> softDeleteBioMedia(String attachmentId) async {
    await runSyncedWrite(() async {
      await _dao.updateAttachment(
        MediaAttachmentsCompanion(
          id: Value(attachmentId),
          isDeleted: const Value(true),
        ),
      );
      await syncRecordUpdate(_table, attachmentId, {'is_deleted': true});
    });
  }

  Map<String, dynamic> _attachmentFields(domain.MediaAttachment a) =>
      attachmentFields(a);

  /// Field-map builder for media-attachment sync emissions.
  ///
  /// Public so the importer (`DataImportService`) can construct
  /// byte-identical `fields` payloads when it bypasses `create()` for the raw
  /// bulk insert — mirroring `DriftMemberRepository.memberFields` and
  /// `DriftMemberBoardPostsRepository.postFields`. Single source of truth per
  /// entity keeps sync emissions aligned.
  ///
  /// `isDeleted` defaults to false because a `create()`-d row is always live;
  /// the importer passes the row's real state so an imported tombstoned
  /// attachment propagates as a tombstone instead of resurrecting on a peer
  /// (mirroring `postFields(p.isDeleted)`).
  static Map<String, dynamic> attachmentFields(
    domain.MediaAttachment a, {
    bool isDeleted = false,
  }) {
    return {
      'member_id': a.memberId,
      'tag': a.tag,
      'message_id': a.messageId,
      'media_id': a.mediaId,
      'media_type': a.mediaType,
      'encryption_key_b64': a.encryptionKeyB64,
      'content_hash': a.contentHash,
      'plaintext_hash': a.plaintextHash,
      'mime_type': a.mimeType,
      'size_bytes': a.sizeBytes,
      'width': a.width,
      'height': a.height,
      'duration_ms': a.durationMs,
      'blurhash': a.blurhash,
      'waveform_b64': a.waveformB64,
      'thumbnail_media_id': a.thumbnailMediaId,
      'thumbnail_content_hash': a.thumbnailContentHash,
      'thumbnail_plaintext_hash': a.thumbnailPlaintextHash,
      'source_url': a.sourceUrl,
      'preview_url': a.previewUrl,
      'is_deleted': isDeleted,
    };
  }
}
