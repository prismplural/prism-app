import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/domain/models/media_attachment.dart' as domain;

class MediaAttachmentMapper {
  MediaAttachmentMapper._();

  static domain.MediaAttachment toDomain(MediaAttachment row) {
    return domain.MediaAttachment(
      id: row.id,
      messageId: row.messageId,
      mediaId: row.mediaId,
      mediaType: row.mediaType,
      encryptionKeyB64: row.encryptionKeyB64,
      contentHash: row.contentHash,
      plaintextHash: row.plaintextHash,
      mimeType: row.mimeType,
      sizeBytes: row.sizeBytes,
      width: row.width,
      height: row.height,
      durationMs: row.durationMs,
      blurhash: row.blurhash,
      waveformB64: row.waveformB64,
      thumbnailMediaId: row.thumbnailMediaId,
      sourceUrl: row.sourceUrl,
      previewUrl: row.previewUrl,
      isDeleted: row.isDeleted,
    );
  }

  static MediaAttachmentsCompanion toCompanion(domain.MediaAttachment model) {
    return MediaAttachmentsCompanion(
      id: Value(model.id),
      messageId: Value(model.messageId),
      mediaId: Value(model.mediaId),
      mediaType: Value(model.mediaType),
      encryptionKeyB64: Value(model.encryptionKeyB64),
      contentHash: Value(model.contentHash),
      plaintextHash: Value(model.plaintextHash),
      mimeType: Value(model.mimeType),
      sizeBytes: Value(model.sizeBytes),
      width: Value(model.width),
      height: Value(model.height),
      durationMs: Value(model.durationMs),
      blurhash: Value(model.blurhash),
      waveformB64: Value(model.waveformB64),
      thumbnailMediaId: Value(model.thumbnailMediaId),
      sourceUrl: Value(model.sourceUrl),
      previewUrl: Value(model.previewUrl),
      isDeleted: Value(model.isDeleted),
    );
  }
}
