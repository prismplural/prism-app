import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pool/pool.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/features/chat/utils/mention_utils.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/members_batch_provider.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/providers/member_stats_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';

/// All conversations ordered by last activity.
final conversationsProvider = StreamProvider<List<Conversation>>((ref) {
  final repo = ref.watch(conversationRepositoryProvider);
  return repo.watchAllConversations();
});

/// Whether to show archived conversations in the chat list.
class ShowArchivedNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void toggle() => state = !state;
}

final showArchivedProvider =
    NotifierProvider<ShowArchivedNotifier, bool>(ShowArchivedNotifier.new);

/// Whether the current speaking-as member has any archived conversations.
final hasArchivedConversationsProvider = Provider<bool>((ref) {
  final conversationsAsync = ref.watch(conversationsProvider);
  final speakingAs = ref.watch(speakingAsProvider);
  return conversationsAsync.whenOrNull(
        data: (conversations) =>
            speakingAs != null &&
            conversations.any((c) => c.archivedByMemberIds.contains(speakingAs)),
      ) ??
      false;
});

/// Conversations filtered by archive state for the current speaking-as member,
/// sorted by last activity (newest first).
final filteredConversationsProvider =
    Provider<AsyncValue<List<Conversation>>>((ref) {
  final conversationsAsync = ref.watch(conversationsProvider);
  final speakingAs = ref.watch(speakingAsProvider);
  final showArchived = ref.watch(showArchivedProvider);

  return conversationsAsync.whenData((conversations) {
    final filtered = showArchived
        ? conversations
        : conversations
            .where((c) =>
                speakingAs == null ||
                !c.archivedByMemberIds.contains(speakingAs))
            .toList();
    // Sort by last activity descending (newest first).
    return filtered.toList()
      ..sort((a, b) => b.lastActivityAt.compareTo(a.lastActivityAt));
  });
});

/// How many messages to load per page.
const messagePageSize = 50;

/// Tracks how many messages to load for a given conversation.
/// Starts at [messagePageSize], increases by [messagePageSize] on scroll.
class MessageLimitNotifier extends Notifier<int> {
  MessageLimitNotifier(this.conversationId);
  final String conversationId;

  @override
  int build() => messagePageSize;

  void loadMore() => state = state + messagePageSize;
}

final messageLimitProvider =
    NotifierProvider.family<MessageLimitNotifier, int, String>(
  MessageLimitNotifier.new,
);

/// Messages for a conversation — paginated by [messageLimitProvider].
final messagesProvider =
    StreamProvider.autoDispose.family<List<ChatMessage>, String>((ref, conversationId) {
  final limit = ref.watch(messageLimitProvider(conversationId));
  final repo = ref.watch(chatMessageRepositoryProvider);
  return repo.watchRecentMessages(conversationId, limit: limit);
});

/// Latest message for a conversation (for tile preview).
final lastMessageProvider =
    StreamProvider.autoDispose.family<ChatMessage?, String>((ref, conversationId) {
  final repo = ref.watch(chatMessageRepositoryProvider);
  return repo.watchLatestMessage(conversationId);
});

/// Single conversation by ID.
final conversationByIdProvider =
    StreamProvider.autoDispose.family<Conversation?, String>((ref, id) {
  final repo = ref.watch(conversationRepositoryProvider);
  return repo.watchConversationById(id);
});

/// Currently selected "speaking as" member for chat.
/// Defaults to the current fronter if not explicitly set.
final speakingAsProvider = NotifierProvider<SpeakingAsNotifier, String?>(SpeakingAsNotifier.new);

class SpeakingAsNotifier extends Notifier<String?> {
  String? _explicitSelection;

  @override
  String? build() {
    // Watch active session so we update when fronter changes.
    final activeSession = ref.watch(activeSessionProvider);
    final fronterId = activeSession.value?.memberId;

    // If user explicitly picked someone, use that. Otherwise use fronter.
    return _explicitSelection ?? fronterId;
  }

  void setMember(String? memberId) {
    _explicitSelection = memberId;
    ref.invalidateSelf();

    // Optionally log a front when switching the speaking member.
    if (memberId != null) {
      final chatLogsFront = ref.read(chatLogsFrontProvider);
      if (chatLogsFront) {
        ref.read(frontingNotifierProvider.notifier).switchFronter(memberId);
      }
    }
  }
}

/// Chat actions notifier.
class ChatNotifier extends Notifier<void> {
  static const _uuid = Uuid();
  static final _mutationPool = Pool(1);

  @override
  void build() {}

  Future<Conversation> createGroupConversation({
    required String title,
    String? emoji,
    required String creatorId,
    required List<String> participantIds,
    String? categoryId,
  }) async {
    final repo = ref.read(conversationRepositoryProvider);
    final conversation = Conversation(
      id: _uuid.v4(),
      createdAt: DateTime.now(),
      lastActivityAt: DateTime.now(),
      title: title,
      emoji: emoji,
      creatorId: creatorId,
      participantIds: participantIds,
      categoryId: categoryId,
    );
    await repo.createConversation(conversation);
    for (final id in participantIds) {
      ref.invalidate(memberConversationsProvider(id));
    }
    return conversation;
  }

  Future<String> sendMessage({
    required String conversationId,
    required String content,
    required String authorId,
    String? messageId,
    String? replyToId,
    String? replyToAuthorId,
    String? replyToContent,
  }) async {
    final msgRepo = ref.read(chatMessageRepositoryProvider);
    final convRepo = ref.read(conversationRepositoryProvider);

    final id = messageId ?? _uuid.v4();
    final message = ChatMessage(
      id: id,
      content: content,
      timestamp: DateTime.now(),
      authorId: authorId,
      conversationId: conversationId,
      replyToId: replyToId,
      replyToAuthorId: replyToAuthorId,
      replyToContent: replyToContent,
    );
    await msgRepo.createMessage(message);
    await convRepo.updateLastActivity(conversationId);

    // Auto-unarchive if any member had it archived.
    final conv = await convRepo.getConversationById(conversationId);
    if (conv != null && conv.archivedByMemberIds.isNotEmpty) {
      await convRepo.setArchivedByMemberIds(conversationId, []);
    }

    return id;
  }

  Future<void> _sendSystemMessage(
    String conversationId,
    String content,
  ) async {
    final msgRepo = ref.read(chatMessageRepositoryProvider);
    final convRepo = ref.read(conversationRepositoryProvider);
    final message = ChatMessage(
      id: _uuid.v4(),
      content: content,
      timestamp: DateTime.now(),
      conversationId: conversationId,
      isSystemMessage: true,
    );
    await msgRepo.createMessage(message);
    await convRepo.updateLastActivity(conversationId);
  }

  Future<void> removeParticipant(
    String conversationId,
    String memberId, {
    String? removedByName,
  }) async {
    final convRepo = ref.read(conversationRepositoryProvider);
    final conv = await convRepo.getConversationById(conversationId);
    if (conv == null) return;

    await convRepo.removeParticipantId(conversationId, memberId);
    ref.invalidate(memberConversationsProvider(memberId));

    if (removedByName != null) {
      final memberRepo = ref.read(memberRepositoryProvider);
      final member = await memberRepo.getMemberById(memberId);
      if (member != null) {
        await _sendSystemMessage(
          conversationId,
          '${member.name} was removed by $removedByName',
        );
      }
    }
  }

  Future<void> transferCreator(
    String conversationId,
    String newCreatorId,
  ) async {
    final convRepo = ref.read(conversationRepositoryProvider);
    final conv = await convRepo.getConversationById(conversationId);
    if (conv == null) return;

    await convRepo.updateConversation(conv.copyWith(creatorId: newCreatorId));

    final memberRepo = ref.read(memberRepositoryProvider);
    final member = await memberRepo.getMemberById(newCreatorId);
    if (member != null) {
      await _sendSystemMessage(
        conversationId,
        '${member.name} is now the conversation owner',
      );
    }
  }

  Future<void> archiveConversation(
    String conversationId,
    String memberId,
  ) async {
    await _mutationPool.withResource(() async {
      final convRepo = ref.read(conversationRepositoryProvider);
      final conv = await convRepo.getConversationById(conversationId);
      if (conv == null) return;

      if (conv.archivedByMemberIds.contains(memberId)) return;

      final updatedArchived = [...conv.archivedByMemberIds, memberId];
      await convRepo.setArchivedByMemberIds(conversationId, updatedArchived);
    });
  }

  Future<void> unarchiveConversation(
    String conversationId,
    String memberId,
  ) async {
    await _mutationPool.withResource(() async {
      final convRepo = ref.read(conversationRepositoryProvider);
      final conv = await convRepo.getConversationById(conversationId);
      if (conv == null) return;

      final updatedArchived =
          conv.archivedByMemberIds.where((id) => id != memberId).toList();
      await convRepo.setArchivedByMemberIds(conversationId, updatedArchived);
    });
  }

  Future<void> leaveConversation(
    String conversationId,
    String memberId,
  ) async {
    final memberRepo = ref.read(memberRepositoryProvider);
    final member = await memberRepo.getMemberById(memberId);
    await removeParticipant(conversationId, memberId);
    if (member != null) {
      await _sendSystemMessage(
        conversationId,
        '${member.name} left the conversation',
      );
    }
  }

  Future<void> editMessage(String messageId, String newContent) async {
    await _mutationPool.withResource(() async {
      final repo = ref.read(chatMessageRepositoryProvider);
      final message = await repo.getMessageById(messageId);
      if (message != null) {
        final updated = message.copyWith(
          content: newContent,
          editedAt: DateTime.now(),
        );
        await repo.updateMessage(updated);
      }
    });
  }

  Future<void> deleteMessage(String messageId) async {
    await _mutationPool.withResource(() async {
      final msgRepo = ref.read(chatMessageRepositoryProvider);
      final convRepo = ref.read(conversationRepositoryProvider);

      // Look up the message before deleting so we know which conversation to fix.
      final message = await msgRepo.getMessageById(messageId);
      await msgRepo.deleteMessage(messageId);

      // After deletion, update the conversation's lastActivityAt to reflect the
      // latest remaining message. Without this, the conversation list shows "now"
      // because the original sendMessage set lastActivityAt but deleting the
      // message never reverted it.
      if (message != null) {
        final conv = await convRepo.getConversationById(message.conversationId);
        if (conv != null) {
          final latestMessage =
              await msgRepo.getLatestMessage(message.conversationId);
          final newActivityAt = latestMessage?.timestamp ?? conv.createdAt;
          if (newActivityAt != conv.lastActivityAt) {
            await convRepo.updateConversation(
              conv.copyWith(lastActivityAt: newActivityAt),
            );
          }
        }
      }
    });
  }

  Future<void> updateConversation(
    String id, {
    String? title,
    String? emoji,
    String? categoryId,
    bool clearCategory = false,
  }) async {
    final repo = ref.read(conversationRepositoryProvider);
    final conv = await repo.getConversationById(id);
    if (conv != null) {
      final updated = conv.copyWith(
        title: title ?? conv.title,
        emoji: emoji,
        categoryId: clearCategory ? null : (categoryId ?? conv.categoryId),
      );
      await repo.updateConversation(updated);
    }
  }

  Future<void> addParticipants(
    String conversationId,
    List<String> memberIds, {
    String? addedByName,
  }) async {
    final repo = ref.read(conversationRepositoryProvider);
    final conv = await repo.getConversationById(conversationId);
    if (conv != null) {
      final existingIds = conv.participantIds.toSet();
      final newIds = memberIds.where((id) => !existingIds.contains(id)).toList();
      await repo.addParticipantIds(conversationId, newIds);
      for (final id in memberIds) {
        ref.invalidate(memberConversationsProvider(id));
      }
      if (addedByName != null && newIds.isNotEmpty) {
        final memberRepo = ref.read(memberRepositoryProvider);
        final members = await memberRepo.getMembersByIds(newIds.toList());
        for (final member in members) {
          await _sendSystemMessage(
            conversationId,
            '${member.name} was added by $addedByName',
          );
        }
      }
    }
  }

  Future<void> deleteConversation(String id) async {
    final repo = ref.read(conversationRepositoryProvider);
    final conv = await repo.getConversationById(id);
    await repo.deleteConversation(id);
    if (conv != null) {
      for (final pid in conv.participantIds) {
        ref.invalidate(memberConversationsProvider(pid));
      }
    }
  }

  Future<void> markConversationAsRead(String conversationId, String memberId) async {
    await _mutationPool.withResource(() async {
      final repo = ref.read(conversationRepositoryProvider);
      final conv = await repo.getConversationById(conversationId);
      if (conv == null) return;

      final updatedTimestamps = Map<String, DateTime>.from(conv.lastReadTimestamps);
      updatedTimestamps[memberId] = DateTime.now();
      await repo.setLastReadTimestamps(conversationId, updatedTimestamps);
    });
  }

  Future<void> toggleMute(String conversationId, String memberId) async {
    await _mutationPool.withResource(() async {
      final repo = ref.read(conversationRepositoryProvider);
      final conv = await repo.getConversationById(conversationId);
      if (conv == null) return;

      final muted = conv.mutedByMemberIds.contains(memberId);
      final updatedMuted = muted
          ? conv.mutedByMemberIds.where((id) => id != memberId).toList()
          : [...conv.mutedByMemberIds, memberId];
      await repo.setMutedByMemberIds(conversationId, updatedMuted);
    });
  }

  Future<void> toggleReaction({
    required String messageId,
    required String emoji,
    required String memberId,
  }) async {
    await _mutationPool.withResource(() async {
      final repo = ref.read(chatMessageRepositoryProvider);
      final message = await repo.getMessageById(messageId);
      if (message == null) return;

      final existingIndex = message.reactions.indexWhere(
        (r) => r.emoji == emoji && r.memberId == memberId,
      );

      List<MessageReaction> updatedReactions;
      if (existingIndex >= 0) {
        updatedReactions = [...message.reactions]..removeAt(existingIndex);
      } else {
        updatedReactions = [
          ...message.reactions,
          MessageReaction(
            id: _uuid.v4(),
            emoji: emoji,
            memberId: memberId,
            timestamp: DateTime.now(),
          ),
        ];
      }
      await repo.updateMessage(message.copyWith(reactions: updatedReactions));
    });
  }
}

final chatNotifierProvider =
    NotifierProvider<ChatNotifier, void>(ChatNotifier.new);

class ReplyingToNotifier extends Notifier<ChatMessage?> {
  final String conversationId;
  ReplyingToNotifier(this.conversationId);

  @override
  ChatMessage? build() => null;

  void setReplyTo(ChatMessage message) => state = message;

  void clear() => state = null;
}

final replyingToProvider =
    NotifierProvider.family<ReplyingToNotifier, ChatMessage?, String>(
  ReplyingToNotifier.new,
);

/// Batch unread message counts for all conversations — single SQL stream.
///
/// Returns a map of conversationId → unread count. Watched by all
/// ConversationTiles via [unreadMessageCountProvider], so there's only
/// one Drift stream subscription instead of one per visible tile.
final allUnreadCountsProvider =
    StreamProvider<Map<String, int>>((ref) {
  final speakingAs = ref.watch(speakingAsProvider);
  if (speakingAs == null) return Stream.value({});

  final conversationsAsync = ref.watch(conversationsProvider);
  final conversations = conversationsAsync.value;
  if (conversations == null) return Stream.value({});

  final conversationSince = <String, DateTime>{};
  for (final conv in conversations) {
    final lastRead = conv.lastReadTimestamps[speakingAs];
    conversationSince[conv.id] = lastRead ?? conv.createdAt;
  }

  if (conversationSince.isEmpty) return Stream.value({});

  final repo = ref.watch(chatMessageRepositoryProvider);
  return repo.watchAllUnreadCounts(conversationSince);
});

/// Unread message count for a single conversation (derived from batch).
final unreadMessageCountProvider =
    Provider.autoDispose.family<int, String>((ref, conversationId) {
  final allCounts = ref.watch(allUnreadCountsProvider).value;
  return allCounts?[conversationId] ?? 0;
});

/// Total number of conversations with unread messages (for the chat tab badge).
///
/// Respects badge preference: if a member's preference is 'mentions_only',
/// uses a single batch query to find conversations with mentions, rather than
/// opening N individual stream subscriptions.
final unreadConversationCountProvider = Provider<int>((ref) {
  final speakingAs = ref.watch(speakingAsProvider);
  if (speakingAs == null) return 0;

  final conversationsAsync = ref.watch(conversationsProvider);
  final conversations = conversationsAsync.value;
  if (conversations == null) return 0;

  final badgePrefs = ref.watch(chatBadgePreferencesProvider);
  final mentionsOnly = badgePrefs[speakingAs] == 'mentions_only';

  // Collect unread conversations (excluding muted/archived).
  final unreadConvs = <Conversation>[];
  for (final conv in conversations) {
    if (conv.mutedByMemberIds.contains(speakingAs)) continue;
    if (conv.archivedByMemberIds.contains(speakingAs)) continue;

    final lastRead = conv.lastReadTimestamps[speakingAs];
    final hasUnread = lastRead == null
        ? conv.lastActivityAt.isAfter(conv.createdAt)
        : conv.lastActivityAt.isAfter(lastRead);

    if (hasUnread) unreadConvs.add(conv);
  }

  if (!mentionsOnly) return unreadConvs.length;

  // Mentions-only: single batch query instead of N individual streams.
  final conversationSince = <String, DateTime>{};
  for (final conv in unreadConvs) {
    final lastRead = conv.lastReadTimestamps[speakingAs];
    conversationSince[conv.id] = lastRead ?? conv.createdAt;
  }

  if (conversationSince.isEmpty) return 0;

  final mentionConvIds = ref
      .watch(conversationsWithMentionsProvider((
        conversationSince: conversationSince,
        memberId: speakingAs,
      )))
      .value;

  return mentionConvIds?.length ?? 0;
});

/// Single batch stream that returns which conversations have mentions for a member.
final conversationsWithMentionsProvider = StreamProvider.autoDispose
    .family<Set<String>, ({Map<String, DateTime> conversationSince, String memberId})>(
        (ref, params) {
  final repo = ref.watch(chatMessageRepositoryProvider);
  return repo.watchConversationsWithMentions(
    params.conversationSince,
    params.memberId,
  );
});

/// Unread mention count for a specific conversation and member.
final unreadMentionCountProvider = StreamProvider.autoDispose
    .family<int, ({String conversationId, String memberId})>((ref, params) {
  final conversationsAsync = ref.watch(conversationsProvider);
  final conversations = conversationsAsync.value;
  if (conversations == null) return Stream.value(0);

  final conv = conversations
      .where((c) => c.id == params.conversationId)
      .firstOrNull;
  if (conv == null) return Stream.value(0);

  final lastRead = conv.lastReadTimestamps[params.memberId];
  final since = lastRead ?? conv.createdAt;

  final repo = ref.watch(chatMessageRepositoryProvider);
  return repo.watchUnreadMentionCount(
    params.conversationId,
    since,
    params.memberId,
  );
});

class HighlightedMessageIdNotifier extends Notifier<String?> {
  final String conversationId;
  HighlightedMessageIdNotifier(this.conversationId);

  @override
  String? build() => null;

  void highlight(String messageId) => state = messageId;

  void clear() => state = null;
}

final highlightedMessageIdProvider =
    NotifierProvider.family<HighlightedMessageIdNotifier, String?, String>(
  HighlightedMessageIdNotifier.new,
);

/// Pre-fetched data for a single [ConversationTile].
///
/// Batches all the per-tile provider watches into one derived provider so each
/// tile triggers a single rebuild instead of 5+ independent listener fan-outs.
class ConversationTileData {
  final Conversation conversation;
  final ChatMessage? lastMessage;
  final Map<String, Member> participantMap;
  final int unreadCount;
  final String? speakingAs;
  final Member? dmPartner;
  final String? lastMessageAuthorName;
  final String? lastMessageDisplayContent;

  const ConversationTileData({
    required this.conversation,
    this.lastMessage,
    required this.participantMap,
    required this.unreadCount,
    this.speakingAs,
    this.dmPartner,
    this.lastMessageAuthorName,
    this.lastMessageDisplayContent,
  });

  bool get hasUnread {
    if (speakingAs == null) return false;
    final lastRead = conversation.lastReadTimestamps[speakingAs];
    if (lastRead == null) {
      return conversation.lastActivityAt.isAfter(conversation.createdAt);
    }
    return conversation.lastActivityAt.isAfter(lastRead);
  }

  bool get isArchived =>
      speakingAs != null &&
      conversation.archivedByMemberIds.contains(speakingAs);

  String get displayTitle {
    if (conversation.title != null && conversation.title!.isNotEmpty) {
      return conversation.title!;
    }
    final otherNames = conversation.participantIds
        .where((id) => id != speakingAs)
        .map((id) => participantMap[id]?.name ?? 'Unknown')
        .toList();
    if (otherNames.isEmpty) return 'Conversation';
    return otherNames.join(', ');
  }
}

/// O(1) conversation lookup by ID. Built once from the conversation list, shared
/// across all tile providers. Avoids O(N) linear scan per tile.
final conversationMapProvider =
    Provider.autoDispose<Map<String, Conversation>>((ref) {
  final list = ref.watch(conversationsProvider).value;
  if (list == null) return const {};
  return {for (final c in list) c.id: c};
});

/// Batched per-tile data provider. Each [ConversationTile] watches this single
/// provider instead of 5+ individual providers, reducing listener fan-out.
final conversationTileDataProvider = Provider.autoDispose
    .family<ConversationTileData?, String>((ref, conversationId) {
  final speakingAs = ref.watch(speakingAsProvider);

  // O(1) lookup via the shared map provider.
  final conversationMap = ref.watch(conversationMapProvider);
  final conversation = conversationMap[conversationId];
  if (conversation == null) return null;

  // Participant map (batch loaded).
  final participantMapAsync = ref.watch(
    membersByIdsProvider(memberIdsKey(conversation.participantIds)),
  );
  final participantMap = participantMapAsync.value ?? const {};

  // Last message.
  final lastMessageAsync = ref.watch(lastMessageProvider(conversationId));
  final lastMessage = lastMessageAsync.value;

  // Unread count (derived from batch provider).
  final unreadCount = ref.watch(unreadMessageCountProvider(conversationId));

  // Mention name map — always watch to keep the dependency graph stable.
  final nameMap = ref.watch(memberNameMapProvider);

  // DM partner: derive from participantMap (already batch-loaded) rather than
  // a conditional ref.watch() that would destabilize the dependency graph.
  Member? dmPartner;
  if (conversation.emoji == null && conversation.isDirectMessage) {
    final otherId = conversation.participantIds
        .where((id) => id != speakingAs)
        .firstOrNull;
    if (otherId != null) {
      dmPartner = participantMap[otherId];
    }
  }

  // Last message author name + display content (resolves mentions).
  // Derive author name from the already-watched participantMap to avoid
  // conditional ref.watch() calls that change the dependency graph.
  String? lastMessageAuthorName;
  String? lastMessageDisplayContent;
  if (lastMessage != null) {
    if (lastMessage.authorId != null) {
      lastMessageAuthorName = participantMap[lastMessage.authorId]?.name;
    }
    lastMessageDisplayContent =
        replaceMentionsWithNames(lastMessage.content, nameMap);
  }

  return ConversationTileData(
    conversation: conversation,
    lastMessage: lastMessage,
    participantMap: participantMap,
    unreadCount: unreadCount,
    speakingAs: speakingAs,
    dmPartner: dmPartner,
    lastMessageAuthorName: lastMessageAuthorName,
    lastMessageDisplayContent: lastMessageDisplayContent,
  );
});
