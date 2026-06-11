import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/media_attachments_table.dart';

part 'media_attachments_dao.g.dart';

@DriftAccessor(tables: [MediaAttachments])
class MediaAttachmentsDao extends DatabaseAccessor<AppDatabase>
    with _$MediaAttachmentsDaoMixin {
  MediaAttachmentsDao(super.db);

  Stream<List<MediaAttachment>> watchForMessage(String messageId) =>
      (select(mediaAttachments)..where(
            (a) => a.messageId.equals(messageId) & a.isDeleted.equals(false),
          ))
          .watch();

  Future<List<MediaAttachment>> getForMessage(String messageId) =>
      (select(mediaAttachments)..where(
            (a) => a.messageId.equals(messageId) & a.isDeleted.equals(false),
          ))
          .get();

  Future<List<MediaAttachment>> getForMember(String memberId) =>
      (select(mediaAttachments)..where(
            (a) => a.memberId.equals(memberId) & a.isDeleted.equals(false),
          ))
          .get();

  Stream<List<MediaAttachment>> watchForMember(String memberId) =>
      (select(mediaAttachments)..where(
            (a) => a.memberId.equals(memberId) & a.isDeleted.equals(false),
          ))
          .watch();

  Future<MediaAttachment?> getByMediaId(String mediaId) =>
      (select(mediaAttachments)
            ..where((a) => a.mediaId.equals(mediaId))
            ..limit(1))
          .getSingleOrNull();

  /// Resolve an attachment by EITHER its primary `media_id` OR its
  /// `thumbnail_media_id`. The media heal (re-supply + re-download) can target a
  /// thumbnail, which has no row of its own — it lives in the
  /// `thumbnail_media_id` column of its parent attachment. Returns null when
  /// neither matches. Empty `mediaId` returns null rather than spuriously
  /// matching the many rows whose `thumbnail_media_id` defaults to ''.
  Future<MediaAttachment?> getByAnyMediaId(String mediaId) {
    if (mediaId.isEmpty) return Future.value(null);
    return (select(mediaAttachments)
          ..where(
            (a) =>
                a.mediaId.equals(mediaId) |
                a.thumbnailMediaId.equals(mediaId),
          )
          ..limit(1))
        .getSingleOrNull();
  }

  Future<List<MediaAttachment>> getAll() =>
      (select(mediaAttachments)..where((a) => a.isDeleted.equals(false))).get();

  Future<MediaAttachment?> getById(String id) => (select(
    mediaAttachments,
  )..where((a) => a.id.equals(id))).getSingleOrNull();

  Future<int> insertAttachment(MediaAttachmentsCompanion attachment) =>
      into(mediaAttachments).insert(attachment);

  Future<void> updateAttachment(MediaAttachmentsCompanion attachment) {
    assert(attachment.id.present, 'Attachment id is required for update');
    return (update(
      mediaAttachments,
    )..where((a) => a.id.equals(attachment.id.value))).write(attachment);
  }

  Future<void> softDelete(String id) =>
      (update(mediaAttachments)..where((a) => a.id.equals(id))).write(
        const MediaAttachmentsCompanion(isDeleted: Value(true)),
      );

  Future<MediaAttachment?> getByTag(String tag) =>
      (select(mediaAttachments)
            ..where((a) => a.tag.equals(tag) & a.isDeleted.equals(false))
            ..limit(1))
          .getSingleOrNull();

  Stream<List<MediaAttachment>> watchLibraryImages() => (select(
    mediaAttachments,
  )..where((a) => a.tag.equals('').not() & a.isDeleted.equals(false))).watch();

  Stream<List<MediaAttachment>> watchAllBioMedia() =>
      (select(mediaAttachments)..where(
            (a) => a.memberId.equals('').not() & a.isDeleted.equals(false),
          ))
          .watch();

  Stream<List<MediaAttachment>> watchAllChatMedia() =>
      customSelect(
        '''
        SELECT a.*
        FROM media_attachments AS a
        LEFT JOIN chat_messages AS m
          ON m.id = a.message_id
        WHERE a.message_id != ''
          AND a.is_deleted = 0
          AND a.media_type = 'image'
          AND (m.id IS NULL OR m.is_deleted = 0)
        ORDER BY a.id DESC
        ''',
        readsFrom: {mediaAttachments, attachedDatabase.chatMessages},
      ).watch().map(
        (rows) => rows.map((row) => mediaAttachments.map(row.data)).toList(),
      );
}
