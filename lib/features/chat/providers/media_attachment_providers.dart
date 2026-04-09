import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/media_attachment.dart';

/// Watches media attachments for a specific chat message.
///
/// Returns an empty list when no attachments exist. The provider is
/// `autoDispose` so it cleans up when the message scrolls off-screen.
///
/// TODO(batch-3): Replace stub with real repository stream once
/// `mediaAttachmentRepositoryProvider` is wired up from the data layer.
final messageAttachmentsProvider =
    StreamProvider.autoDispose.family<List<MediaAttachment>, String>(
  (ref, messageId) {
    // Stub: return empty stream until the media attachment repository is
    // available from Batch 3 data layer work. This keeps the widget code
    // compilable and functional (just shows no attachments).
    return Stream.value(<MediaAttachment>[]);
  },
);
