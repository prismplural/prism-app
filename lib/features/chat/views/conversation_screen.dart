import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/chat/models/conversation_permissions.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/views/conversation_info_sheet.dart';
import 'package:prism_plurality/features/chat/widgets/date_separator.dart';
import 'package:prism_plurality/features/chat/widgets/message_input.dart';
import 'package:prism_plurality/features/chat/widgets/prism_message_group.dart';
import 'package:prism_plurality/features/members/providers/members_batch_provider.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_app_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

/// Full chat view for a single conversation.
class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({
    super.key,
    required this.conversationId,
    this.initialMessageId,
  });

  final String conversationId;
  final String? initialMessageId;

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final _scrollController = ScrollController();
  bool _hasMarkedRead = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    // In a reversed ListView, maxScrollExtent is the TOP (oldest messages).
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      final currentLimit = ref.read(messageLimitProvider(widget.conversationId));
      final messages = ref.read(messagesProvider(widget.conversationId)).value;
      // Only load more if the current page is full (previous load completed).
      if (messages != null && messages.length >= currentLimit) {
        ref.read(messageLimitProvider(widget.conversationId).notifier).state =
            currentLimit + messagePageSize;
        SemanticsService.announce('Loading older messages', TextDirection.ltr);
      }
    }
  }

  // Captured before dispose so we can safely mark-as-read during unmount.
  String? _lastSpeakingAs;
  ChatNotifier? _chatNotifier;

  final Map<String, GlobalKey> _messageKeys = {};
  Timer? _highlightTimer;
  bool _hasScrolledToInitial = false;

  @override
  void dispose() {
    // Mark as read on exit too (catches messages that arrived while viewing).
    // Capture the values locally so we don't rely on instance fields that may
    // reference a stale provider / notifier after the container is disposed.
    final speakingAs = _lastSpeakingAs;
    final notifier = _chatNotifier;
    if (speakingAs != null && notifier != null) {
      try {
        notifier.markConversationAsRead(widget.conversationId, speakingAs);
      } catch (_) {
        // Provider container may already be disposed — safe to ignore.
      }
    }
    _highlightTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToMessage(String messageId) {
    final ctx = _messageKeys[messageId]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      alignment: 0.5,
    );
    _highlightTimer?.cancel();
    ref
        .read(highlightedMessageIdProvider(widget.conversationId).notifier)
        .highlight(messageId);
    _highlightTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        ref
            .read(highlightedMessageIdProvider(widget.conversationId).notifier)
            .clear();
      }
    });
  }

  void _markAsReadIfNeeded() {
    if (_hasMarkedRead) return;
    final speakingAs = ref.read(speakingAsProvider);
    if (speakingAs == null) return;
    _hasMarkedRead = true;
    ref
        .read(chatNotifierProvider.notifier)
        .markConversationAsRead(widget.conversationId, speakingAs);
  }

  static const _groupBuilder = MessageGroupBuilder();

  @override
  Widget build(BuildContext context) {
    // Capture refs for safe use in dispose().
    _lastSpeakingAs = ref.watch(speakingAsProvider);
    _chatNotifier = ref.read(chatNotifierProvider.notifier);

    final conversationAsync = ref.watch(
      conversationByIdProvider(widget.conversationId),
    );
    final messagesAsync = ref.watch(messagesProvider(widget.conversationId));

    // Watch the speaking-as member object for admin check.
    final speakingAsMemberAsync = _lastSpeakingAs != null
        ? ref.watch(memberByIdProvider(_lastSpeakingAs!))
        : const AsyncValue<Member?>.data(null);
    final speakingAsMember = speakingAsMemberAsync.value;

    return conversationAsync.when(
      data: (conversation) {
        if (conversation == null) {
          return const PrismPageScaffold(
            topBar: PrismTopBar(title: 'Chat', showBackButton: true),
            body: Center(child: Text('Conversation not found')),
          );
        }

        // Build permissions and participant set for this conversation.
        final permissions = ConversationPermissions(
          conversation: conversation,
          speakingAsMemberId: _lastSpeakingAs,
          speakingAsMember: speakingAsMember,
        );
        final participantIds = conversation.participantIds.toSet();

        // Mark conversation as read when opened.
        _markAsReadIfNeeded();

        return Scaffold(
          appBar: PrismGlassAppBar(
            title: _conversationTitle(ref, conversation),
            leading: PrismGlassIconButton(
              icon: AppIcons.arrowBackIosNewRounded,
              iconSize: 18,
              tooltip: 'Back',
              onPressed: () => context.pop(),
            ),
            trailing: PrismGlassIconButton(
              icon: AppIcons.infoOutlineRounded,
              iconSize: 20,
              tooltip: 'Conversation info',
              onPressed: () =>
                  ConversationInfoSheet.show(context, widget.conversationId),
            ),
          ),
          body: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            behavior: HitTestBehavior.translucent,
            child: Column(
            children: [
              // Messages list
              Expanded(
                child: messagesAsync.when(
                  data: (messages) {
                    if (messages.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              AppIcons.chatBubbleOutline,
                              size: 64,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withValues(alpha: 0.4),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No messages yet',
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Start the conversation!',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      );
                    }

                    // Batch-load all message authors in one provider call.
                    final authorIds = {
                      ...messages.map((m) => m.authorId).whereType<String>(),
                      ...messages
                          .map((m) => m.replyToAuthorId)
                          .whereType<String>(),
                    };
                    final authorMapAsync = ref.watch(
                      membersByIdsProvider(memberIdsKey(authorIds)),
                    );
                    final authorMap = authorMapAsync.value ?? {};

                    // Group messages by author / time, inserting date
                    // separators between days.
                    final groupItems = _groupBuilder.build(messages);

                    // Populate GlobalKeys for each message and prune stale entries.
                    final currentMessageIds = <String>{};
                    for (final item in groupItems) {
                      if (item is MessageGroup) {
                        for (final msg in item.messages) {
                          currentMessageIds.add(msg.id);
                          _messageKeys.putIfAbsent(msg.id, GlobalKey.new);
                        }
                      }
                    }
                    _messageKeys.removeWhere((id, _) => !currentMessageIds.contains(id));

                    // Auto-scroll to initial message (from search)
                    if (!_hasScrolledToInitial &&
                        widget.initialMessageId != null &&
                        _messageKeys.containsKey(widget.initialMessageId)) {
                      _hasScrolledToInitial = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          _scrollToMessage(widget.initialMessageId!);
                        }
                      });
                    }

                    final highlightedMessageId = ref.watch(
                      highlightedMessageIdProvider(widget.conversationId),
                    );

                    final hasMore = messages.length >=
                        ref.read(messageLimitProvider(widget.conversationId));

                    return ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: groupItems.length + (hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (hasMore && index == groupItems.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                                child: CircularProgressIndicator.adaptive()),
                          );
                        }
                        final item = groupItems[index];
                        return switch (item) {
                          DateSeparatorItem(:final date) =>
                            DateSeparator(date: date),
                          MessageGroup() => PrismMessageGroup(
                              group: item,
                              permissions: permissions,
                              participantIds: participantIds,
                              authorMap: authorMap,
                              messageKeys: _messageKeys,
                              onScrollToMessage: _scrollToMessage,
                              onReply: (msg) => ref
                                  .read(
                                    replyingToProvider(
                                      widget.conversationId,
                                    ).notifier,
                                  )
                                  .setReplyTo(msg),
                              highlightedMessageId: highlightedMessageId,
                            ),
                        };
                      },
                    );
                  },
                  loading: () =>
                      const PrismLoadingState(),
                  error: (error, _) => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          AppIcons.errorOutline,
                          size: 48,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(height: 8),
                        Text('Error loading messages: $error'),
                      ],
                    ),
                  ),
                ),
              ),

              // Message input
              MessageInput(conversationId: widget.conversationId),
            ],
          ),
          ),
        );
      },
      loading: () => const PrismPageScaffold(
        topBar: PrismTopBar(title: 'Chat', showBackButton: true),
        body: PrismLoadingState(),
      ),
      error: (error, _) => PrismPageScaffold(
        topBar: const PrismTopBar(title: 'Chat', showBackButton: true),
        body: Center(child: Text('Error: $error')),
      ),
    );
  }

}

String _conversationTitle(WidgetRef ref, Conversation conversation) {
  final speakingAs = ref.watch(speakingAsProvider);

  if (conversation.title != null && conversation.title!.isNotEmpty) {
    return conversation.title!;
  }

  final participantMapAsync = ref.watch(
    membersByIdsProvider(memberIdsKey(conversation.participantIds)),
  );

  return participantMapAsync.when(
    data: (participantMap) {
      final names = conversation.participantIds
          .where((id) => id != speakingAs)
          .map((id) => participantMap[id]?.name ?? 'Unknown')
          .toList();
      return names.isEmpty ? 'Conversation' : names.join(', ');
    },
    loading: () => 'Loading...',
    error: (_, _) => 'Conversation',
  );
}

