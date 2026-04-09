// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media_attachments_dao.dart';

// ignore_for_file: type=lint
mixin _$MediaAttachmentsDaoMixin on DatabaseAccessor<AppDatabase> {
  $MediaAttachmentsTable get mediaAttachments =>
      attachedDatabase.mediaAttachments;
  MediaAttachmentsDaoManager get managers => MediaAttachmentsDaoManager(this);
}

class MediaAttachmentsDaoManager {
  final _$MediaAttachmentsDaoMixin _db;
  MediaAttachmentsDaoManager(this._db);
  $$MediaAttachmentsTableTableManager get mediaAttachments =>
      $$MediaAttachmentsTableTableManager(
        _db.attachedDatabase,
        _db.mediaAttachments,
      );
}
