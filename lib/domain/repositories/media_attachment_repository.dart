import 'package:prism_plurality/domain/models/media_attachment.dart' as domain;

abstract class MediaAttachmentRepository {
  Stream<List<domain.MediaAttachment>> watchForMessage(String messageId);
  Future<List<domain.MediaAttachment>> getForMessage(String messageId);
  Future<void> create(domain.MediaAttachment attachment);
  Future<void> delete(String id);
  Future<List<domain.MediaAttachment>> getForMember(String memberId);
  Stream<List<domain.MediaAttachment>> watchForMember(String memberId);
  Future<void> softDeleteBioMedia(String attachmentId);
  Stream<List<domain.MediaAttachment>> watchAllBioMedia();
  Stream<List<domain.MediaAttachment>> watchAllChatMedia();
  Stream<List<domain.MediaAttachment>> watchLibraryImages();
  Future<void> updateTag(String attachmentId, String tag);

  /// Swap the underlying media of an existing attachment (keeping its id/tag),
  /// e.g. "replace image" in the library. Updates the blob fields + syncs.
  Future<void> replaceMedia(String attachmentId, domain.MediaAttachment data);
}
