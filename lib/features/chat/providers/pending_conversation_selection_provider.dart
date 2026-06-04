import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A request to open a conversation in the chat screen's detail pane, optionally
/// scrolled to a specific message.
typedef PendingConversationSelection = ({
  String conversationId,
  String? messageId,
});

/// A one-shot request to open a conversation (optionally at a specific message)
/// in the chat screen's detail pane on wide windows. Call [request], then
/// navigate to the chat tab; `ChatScreen` consumes it (selecting the
/// conversation in its pane and scrolling to the message) and [clear]s it. Lets
/// other screens — e.g. the media-usage list — deep-link a conversation into the
/// pane instead of pushing it full-screen.
class PendingConversationSelectionNotifier
    extends Notifier<PendingConversationSelection?> {
  @override
  PendingConversationSelection? build() => null;

  void request(String conversationId, {String? messageId}) =>
      state = (conversationId: conversationId, messageId: messageId);
  void clear() => state = null;
}

final pendingConversationSelectionProvider =
    NotifierProvider<
      PendingConversationSelectionNotifier,
      PendingConversationSelection?
    >(PendingConversationSelectionNotifier.new);
