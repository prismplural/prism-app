import 'package:prism_sync/generated/api.dart' as ffi;
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
    final companion = MediaAttachmentMapper.toCompanion(attachment);
    await _dao.insertAttachment(companion);
    await syncRecordCreate(_table, attachment.id, _attachmentFields(attachment));
  }

  @override
  Future<void> delete(String id) async {
    await _dao.softDelete(id);
    await syncRecordDelete(_table, id);
  }

  Map<String, dynamic> _attachmentFields(domain.MediaAttachment a) {
    return {
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
      'source_url': a.sourceUrl,
      'preview_url': a.previewUrl,
      'is_deleted': false,
    };
  }
}
