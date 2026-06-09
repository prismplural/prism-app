import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/features/chat/providers/pending_conversation_selection_provider.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';

void openChatConversation(
  BuildContext context,
  WidgetRef ref, {
  required String conversationId,
  String? messageId,
}) {
  if (MediaQuery.sizeOf(context).width >= PrismTokens.listDetailBreakpoint) {
    ref
        .read(pendingConversationSelectionProvider.notifier)
        .request(conversationId, messageId: messageId);
    context.go(AppRoutePaths.chat);
    return;
  }

  final messageQuery = messageId == null
      ? ''
      : '?messageId=${Uri.encodeQueryComponent(messageId)}';
  context.push(
    '${AppRoutePaths.chatConversation(conversationId)}$messageQuery',
  );
}
