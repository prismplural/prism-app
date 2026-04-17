import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/media_attachments_table.dart';

part 'media_attachments_dao.g.dart';

@DriftAccessor(tables: [MediaAttachments])
class MediaAttachmentsDao extends DatabaseAccessor<AppDatabase>
    with _$MediaAttachmentsDaoMixin {
  MediaAttachmentsDao(super.db);

  Stream<List<MediaAttachment>> watchForMessage(String messageId) =>
      (select(mediaAttachments)
            ..where((a) =>
                a.messageId.equals(messageId) & a.isDeleted.equals(false)))
          .watch();

  Future<List<MediaAttachment>> getForMessage(String messageId) =>
      (select(mediaAttachments)
            ..where((a) =>
                a.messageId.equals(messageId) & a.isDeleted.equals(false)))
          .get();

  Future<List<MediaAttachment>> getAll() =>
      (select(mediaAttachments)..where((a) => a.isDeleted.equals(false))).get();

  Future<MediaAttachment?> getById(String id) =>
      (select(mediaAttachments)..where((a) => a.id.equals(id)))
          .getSingleOrNull();

  Future<int> insertAttachment(MediaAttachmentsCompanion attachment) =>
      into(mediaAttachments).insert(attachment);

  Future<void> updateAttachment(MediaAttachmentsCompanion attachment) {
    assert(attachment.id.present, 'Attachment id is required for update');
    return (update(mediaAttachments)
          ..where((a) => a.id.equals(attachment.id.value)))
        .write(attachment);
  }

  Future<void> softDelete(String id) =>
      (update(mediaAttachments)..where((a) => a.id.equals(id)))
          .write(const MediaAttachmentsCompanion(isDeleted: Value(true)));
}
