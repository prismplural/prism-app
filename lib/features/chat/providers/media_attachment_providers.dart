import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/data/mappers/media_attachment_mapper.dart';
import 'package:prism_plurality/domain/models/media_attachment.dart';

final mediaAttachmentsForMessageProvider =
    StreamProvider.autoDispose.family<List<MediaAttachment>, String>(
  (ref, messageId) {
    final repo = ref.watch(mediaAttachmentRepositoryProvider);
    return repo.watchForMessage(messageId);
  },
);

final mediaAttachmentByIdProvider =
    FutureProvider.autoDispose.family<MediaAttachment?, String>(
  (ref, attachmentId) async {
    final dao = ref.watch(mediaAttachmentsDaoProvider);
    final row = await dao.getById(attachmentId);
    if (row == null) return null;
    return MediaAttachmentMapper.toDomain(row);
  },
);
