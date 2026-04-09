import 'package:prism_plurality/domain/models/media_attachment.dart' as domain;

abstract class MediaAttachmentRepository {
  Stream<List<domain.MediaAttachment>> watchForMessage(String messageId);
  Future<List<domain.MediaAttachment>> getForMessage(String messageId);
  Future<void> create(domain.MediaAttachment attachment);
  Future<void> delete(String id);
}
