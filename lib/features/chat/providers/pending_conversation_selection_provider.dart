import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A one-shot request to open a specific conversation in the chat screen's
/// detail pane on wide windows. Call [PendingConversationSelectionNotifier.request],
/// then navigate to the chat tab; `ChatScreen` consumes it (selecting the
/// conversation in its pane) and [PendingConversationSelectionNotifier.clear]s
/// it. Lets other screens — e.g. the media-usage list — deep-link a
/// conversation into the pane instead of pushing it full-screen.
class PendingConversationSelectionNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void request(String conversationId) => state = conversationId;
  void clear() => state = null;
}

final pendingConversationSelectionProvider =
    NotifierProvider<PendingConversationSelectionNotifier, String?>(
      PendingConversationSelectionNotifier.new,
    );
