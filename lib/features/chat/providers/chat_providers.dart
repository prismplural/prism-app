import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pool/pool.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/domain/preferences/composer_default_member.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/features/chat/models/conversation_permissions.dart';
import 'package:prism_plurality/features/chat/utils/chat_author_options.dart';
import 'package:prism_plurality/features/chat/utils/chat_markdown_syntax.dart';
import 'package:prism_plurality/features/chat/utils/markdown_utils.dart';
import 'package:prism_plurality/features/chat/utils/mention_utils.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/members_batch_provider.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/providers/member_stats_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';

Member? findCurrentChatViewer(List<Member>? members, String? speakingAs) {
  if (members == null || speakingAs == null) return null;
  for (final member in members) {
    if (member.id == speakingAs) return member;
  }
  return null;
}

/// Whether `memberId` is a participant of `conversation` for badge / read-state
/// purposes — listed explicitly, or implicit via `includesAllMembers`.
/// Callers must ensure `memberId` belongs to an active member; SpeakingAsNotifier
/// already enforces that for `speakingAsProvider`.
bool isImplicitParticipantOf(Conversation conversation, String memberId) {
  return isConversationParticipant(conversation, memberId);
}

bool _tracksUnreadFor(Conversation conversation, String memberId) {
  return isImplicitParticipantOf(conversation, memberId) &&
      !conversation.mutedByMemberIds.contains(memberId) &&
      !conversation.archivedByMemberIds.contains(memberId) &&
      // Also drop from unread/badge counts, like per-member archive above —
      // else a hidden chat shows a badge no one can clear.
      !conversation.archivedForEveryone;
}

ConversationPermissions conversationPermissionsForViewer(
  Conversation conversation, {
  required String? speakingAsMemberId,
  required Member? speakingAsMember,
}) {
  return ConversationPermissions(
    conversation: conversation,
    speakingAsMemberId: speakingAsMemberId,
    speakingAsMember: speakingAsMember,
  );
}

bool currentFrontCanManageConversation(
  Conversation conversation, {
  required List<FrontingSession> activeSessions,
  required List<Member> activeMembers,
}) {
  final activeMembersById = {
    for (final member in activeMembers)
      if (!member.isDeleted && member.isActive) member.id: member,
  };

  for (final session in activeSessions) {
    final memberId = session.memberId;
    if (memberId == null || session.endTime != null || session.isSleep) {
      continue;
    }

    final member = activeMembersById[memberId];
    if (member == null) continue;

    final permissions = conversationPermissionsForViewer(
      conversation,
      speakingAsMemberId: memberId,
      speakingAsMember: member,
    );
    if (permissions.canTransferOwnership) return true;
  }

  return false;
}

final currentFrontCanManageConversationProvider = Provider.autoDispose
    .family<bool, Conversation>((ref, conversation) {
      final activeSessions =
          ref.watch(activeSessionsProvider).value ?? const <FrontingSession>[];
      final activeMembers =
          ref.watch(activeMembersProvider).value ?? const <Member>[];
      return currentFrontCanManageConversation(
        conversation,
        activeSessions: activeSessions,
        activeMembers: activeMembers,
      );
    });

final currentChatViewerProvider = Provider<Member?>((ref) {
  final speakingAs = ref.watch(speakingAsProvider);
  final members = ref.watch(activeMembersProvider).value;
  return findCurrentChatViewer(members, speakingAs);
});

/// All conversations visible to the current viewer, ordered by last activity.
final conversationsProvider = StreamProvider<List<Conversation>>((ref) {
  final repo = ref.watch(conversationRepositoryProvider);
  final speakingAs = ref.watch(speakingAsProvider);
  final speakingAsMember = ref.watch(currentChatViewerProvider);
  return repo.watchAllConversations().map(
    (conversations) => conversations.where((conversation) {
      final permissions = conversationPermissionsForViewer(
        conversation,
        speakingAsMemberId: speakingAs,
        speakingAsMember: speakingAsMember,
      );
      return permissions.canView;
    }).toList(),
  );
});

/// Whether to show archived conversations in the chat list.
class ShowArchivedNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void toggle() => state = !state;
}

final showArchivedProvider = NotifierProvider<ShowArchivedNotifier, bool>(
  ShowArchivedNotifier.new,
);

/// Whether there are any archived conversations to surface to the current
/// member — either archived-for-everyone, or archived by the speaking-as member.
final hasArchivedConversationsProvider = Provider<bool>((ref) {
  final conversationsAsync = ref.watch(conversationsProvider);
  final speakingAs = ref.watch(speakingAsProvider);
  return conversationsAsync.whenOrNull(
        data: (conversations) => conversations.any(
          (c) =>
              c.archivedForEveryone ||
              (speakingAs != null &&
                  c.archivedByMemberIds.contains(speakingAs)),
        ),
      ) ??
      false;
});

/// Conversations filtered by archive state for the current speaking-as member,
/// sorted by last activity (newest first).
final filteredConversationsProvider = Provider<AsyncValue<List<Conversation>>>((
  ref,
) {
  final conversationsAsync = ref.watch(conversationsProvider);
  final speakingAs = ref.watch(speakingAsProvider);
  final showArchived = ref.watch(showArchivedProvider);

  return conversationsAsync.whenData((conversations) {
    final filtered = showArchived
        ? conversations
        : conversations
              .where(
                (c) =>
                    !c.archivedForEveryone &&
                    (speakingAs == null ||
                        !c.archivedByMemberIds.contains(speakingAs)),
              )
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

final messageLimitProvider = NotifierProvider.autoDispose
    .family<MessageLimitNotifier, int, String>(MessageLimitNotifier.new);

/// Messages for a conversation — paginated by [messageLimitProvider].
final messagesProvider = StreamProvider.autoDispose
    .family<List<ChatMessage>, String>((ref, conversationId) {
      final limit = ref.watch(messageLimitProvider(conversationId));
      final repo = ref.watch(chatMessageRepositoryProvider);
      return repo.watchRecentMessages(conversationId, limit: limit);
    });

/// Latest message for a conversation (for tile preview).
final lastMessageProvider = StreamProvider.autoDispose
    .family<ChatMessage?, String>((ref, conversationId) {
      final repo = ref.watch(chatMessageRepositoryProvider);
      return repo.watchLatestMessage(conversationId);
    });

/// Single conversation by ID.
final conversationByIdProvider = StreamProvider.autoDispose
    .family<Conversation?, String>((ref, id) {
      final repo = ref.watch(conversationRepositoryProvider);
      final speakingAs = ref.watch(speakingAsProvider);
      final speakingAsMember = ref.watch(currentChatViewerProvider);
      return repo.watchConversationById(id).map((conversation) {
        if (conversation == null) return null;
        final permissions = conversationPermissionsForViewer(
          conversation,
          speakingAsMemberId: speakingAs,
          speakingAsMember: speakingAsMember,
        );
        return permissions.canView ? conversation : null;
      });
    });

/// Currently selected "speaking as" member for chat.
/// Defaults to the current fronter if not explicitly set.
final speakingAsProvider = NotifierProvider<SpeakingAsNotifier, String?>(
  SpeakingAsNotifier.new,
);

class SpeakingAsNotifier extends Notifier<String?> {
  String? _explicitSelection;
  Set<String>? _lastActiveSessionMemberIds;

  @override
  String? build() {
    // With co-fronters, default to the most recently-started session — "who's
    // at the wheel right now." A null default would fall through to the
    // anonymous viewer gate and expose every group chat on the device.
    final activeSessions = ref.watch(activeSessionsProvider);
    final activeMembers = ref.watch(activeMembersProvider);
    final sessions = activeSessions.value ?? [];
    final activeMemberIds = activeMembers.value?.map((m) => m.id).toSet();

    // In latestFronter mode, clear stale explicit selection when sessions change.
    final currentSessionMemberIds = sessions
        .map((s) => s.memberId)
        .whereType<String>()
        .toSet();
    if (_lastActiveSessionMemberIds != null &&
        !setEquals(_lastActiveSessionMemberIds, currentSessionMemberIds)) {
      final mode =
          ref.watch(composerDefaultMemberProvider).value ??
          ComposerDefaultMember.defaultValue;
      if (mode == ComposerDefaultMember.latestFronter) {
        _explicitSelection = null;
      }
    }
    _lastActiveSessionMemberIds = currentSessionMemberIds;

    final explicitSelection = _explicitSelection;
    if (explicitSelection != null) {
      if (explicitSelection == unknownSentinelMemberId ||
          activeMemberIds == null ||
          activeMemberIds.contains(explicitSelection)) {
        return explicitSelection;
      }
      _explicitSelection = null;
    }

    // A loading/error preference resolves to latestFronter so the viewer gate
    // never sees a null default during startup.
    final mode =
        ref.watch(composerDefaultMemberProvider).value ??
        ComposerDefaultMember.defaultValue;

    // A cold-stored id (unlike a fresh in-session pick) must be confirmed
    // against a loaded roster before we trust it; otherwise fall through to the
    // live fronter rather than returning null.
    if (mode == ComposerDefaultMember.lastUsed) {
      final lastUsed = ref.watch(lastUsedSpeakingAsMemberProvider).value;
      if (lastUsed != null &&
          lastUsed != unknownSentinelMemberId &&
          activeMemberIds != null &&
          activeMemberIds.contains(lastUsed)) {
        return lastUsed;
      }
    }

    // askEachTime's prompt is driven by the composer surface; build() still
    // returns the safe fronter default so the viewer gate stays satisfied.
    final fronterId = _mostRecentActiveFronter(sessions);
    if (fronterId == null) return null;
    if (activeMemberIds == null || activeMemberIds.contains(fronterId)) {
      return fronterId;
    }
    return null;
  }

  static String? _mostRecentActiveFronter(List<FrontingSession> sessions) {
    String? bestId;
    DateTime? bestStart;
    for (final s in sessions) {
      final memberId = s.memberId;
      if (memberId == null) continue;
      if (bestStart == null ||
          s.startTime.isAfter(bestStart) ||
          (s.startTime.isAtSameMomentAs(bestStart) &&
              memberId.compareTo(bestId!) < 0)) {
        bestStart = s.startTime;
        bestId = memberId;
      }
    }
    return bestId;
  }

  /// [recordLastUsed] persists the choice for the "last used" default. Pass
  /// `false` for automatic seeding so "last used" only reflects explicit picks.
  void setMember(String? memberId, {bool recordLastUsed = true}) {
    final activeMemberIds = ref
        .read(activeMembersProvider)
        .value
        ?.map((m) => m.id)
        .toSet();
    final selectedMemberId =
        memberId == null ||
            memberId == unknownSentinelMemberId ||
            activeMemberIds == null ||
            activeMemberIds.contains(memberId)
        ? memberId
        : null;
    _explicitSelection = selectedMemberId;
    ref.invalidateSelf();

    // Best-effort — a storage hiccup must never block switching the member.
    if (recordLastUsed &&
        selectedMemberId != null &&
        selectedMemberId != unknownSentinelMemberId) {
      try {
        unawaited(
          ref
              .read(lastUsedSpeakingAsMemberProvider.notifier)
              .set(selectedMemberId)
              .catchError((Object e) {
                debugPrint(
                  '[Chat] Persisting last-used speaking-as failed: $e',
                );
              }),
        );
      } catch (e) {
        debugPrint('[Chat] Persisting last-used speaking-as failed: $e');
      }
    }

    // Optionally log a front when switching the speaking member.
    if (selectedMemberId != null) {
      final chatLogsFront = ref.read(chatLogsFrontProvider);
      if (chatLogsFront) {
        // TODO(spec §2.5): verify this matches user intent — old switchFronter
        // implied replace semantics; startFronting is additive in the per-member
        // model (does not end other active sessions).
        unawaited(
          ref
              .read(frontingNotifierProvider.notifier)
              .startFronting([selectedMemberId])
              .catchError((Object e) {
                debugPrint('[Chat] Auto-front on member switch failed: $e');
              }),
        );
      }
    }
  }
}

/// Chat actions notifier.
class ChatNotifier extends AsyncNotifier<void> {
  static const _uuid = Uuid();
  static final _mutationPool = Pool(1);

  @override
  Future<void> build() async {}

  Future<ConversationPermissions?> _conversationPermissions(
    String conversationId, {
    String? speakingAsMemberId,
  }) async {
    final conversation = await ref
        .read(conversationRepositoryProvider)
        .getConversationById(conversationId);
    if (conversation == null) return null;

    final effectiveMemberId =
        speakingAsMemberId ?? ref.read(speakingAsProvider);
    final speakingAsMember = effectiveMemberId == null
        ? null
        : await ref
              .read(memberRepositoryProvider)
              .getMemberById(effectiveMemberId);
    final isDeletedMember = speakingAsMember?.isDeleted == true;
    final activeSpeakingAsMember = isDeletedMember ? null : speakingAsMember;
    final activeSpeakingAsMemberId = isDeletedMember ? null : effectiveMemberId;

    return conversationPermissionsForViewer(
      conversation,
      speakingAsMemberId: activeSpeakingAsMemberId,
      speakingAsMember: activeSpeakingAsMember,
    );
  }

  Future<void> _requireConversationAction(
    String conversationId,
    bool Function(ConversationPermissions permissions) allowed, {
    String? speakingAsMemberId,
  }) async {
    final permissions = await _conversationPermissions(
      conversationId,
      speakingAsMemberId: speakingAsMemberId,
    );
    if (permissions == null || !allowed(permissions)) {
      throw StateError('Read-only DM access cannot modify this conversation.');
    }
  }

  Future<void> _requireCurrentFrontCanTransferOwnership(
    String conversationId,
    Conversation conversation,
  ) async {
    final activeSessions = await ref.read(activeSessionsProvider.future);
    final activeMembers = await ref.read(activeMembersProvider.future);
    final canTransfer = currentFrontCanManageConversation(
      conversation,
      activeSessions: activeSessions,
      activeMembers: activeMembers,
    );
    if (canTransfer) return;

    final selectedPermissions = await _conversationPermissions(conversationId);
    if (selectedPermissions?.canTransferOwnership == true) {
      return;
    }

    throw StateError(
      'Only a currently-fronting owner or admin can transfer ownership.',
    );
  }

  void _invalidateMemberConversationActivityFor(
    Conversation conversation, {
    Iterable<String> additionalMemberIds = const [],
    bool includeAllMembers = false,
  }) {
    if (conversation.includesAllMembers || includeAllMembers) {
      ref.invalidate(memberConversationPreviewActivityProvider);
      ref.invalidate(memberConversationActivityProvider);
      ref.invalidate(memberConversationsProvider);
      return;
    }

    final memberIds = <String>{
      ...conversation.participantIds,
      ...conversation.archivedByMemberIds,
      ...additionalMemberIds,
    };

    for (final memberId in memberIds) {
      ref.invalidate(memberConversationPreviewActivityProvider(memberId));
      ref.invalidate(memberConversationActivityProvider(memberId));
      ref.invalidate(memberConversationsProvider(memberId));
    }
  }

  Future<Conversation> createGroupConversation({
    required String title,
    String? emoji,
    required String creatorId,
    required List<String> participantIds,
    String? categoryId,
    bool isDirectMessage = false,
    bool includesAllMembers = false,
  }) async {
    final repo = ref.read(conversationRepositoryProvider);
    final conversation = Conversation(
      id: _uuid.v4(),
      createdAt: DateTime.now(),
      lastActivityAt: DateTime.now(),
      title: title,
      emoji: emoji,
      isDirectMessage: isDirectMessage,
      creatorId: creatorId,
      participantIds: participantIds,
      includesAllMembers: includesAllMembers,
      categoryId: categoryId,
    );
    await repo.createConversation(conversation);
    _invalidateMemberConversationActivityFor(conversation);
    return conversation;
  }

  Future<Conversation?> seedDefaultConversationIfNeeded({
    required String title,
    required String emoji,
    required List<Member> members,
  }) async {
    state = const AsyncLoading();
    try {
      Conversation? seeded;
      if (members.isNotEmpty) {
        final repo = ref.read(conversationRepositoryProvider);
        final existingConversations = await repo.getAllConversations();
        if (existingConversations.isEmpty) {
          final creatorId = members.first.id;
          seeded = await createGroupConversation(
            title: title,
            emoji: emoji,
            creatorId: creatorId,
            participantIds: [creatorId],
            includesAllMembers: true,
          );
        }
      }
      state = const AsyncData(null);
      return seeded;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<void> setIncludesAllMembers(String conversationId, bool value) async {
    state = await AsyncValue.guard(() async {
      await _requireConversationAction(conversationId, (p) => p.canManage);
      final repo = ref.read(conversationRepositoryProvider);
      final conv = await repo.getConversationById(conversationId);
      await repo.setIncludesAllMembers(conversationId, value);
      if (conv != null) {
        _invalidateMemberConversationActivityFor(
          conv.copyWith(includesAllMembers: value),
          includeAllMembers: conv.includesAllMembers,
        );
      }
    });
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
    await _requireConversationAction(
      conversationId,
      (permissions) => permissions.canSendMessages,
      speakingAsMemberId: authorId,
    );

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

    // Fetch once for both post-send mutations.
    final conv = await convRepo.getConversationById(conversationId);
    if (conv != null) {
      // Unarchive only the author (they're engaging); leave other members'
      // archives and the for-everyone flag alone — the old code cleared the
      // whole list. archivedByMemberIds is whole-field LWW, so concurrent
      // edits can still clobber (pre-existing).
      if (conv.archivedByMemberIds.contains(authorId)) {
        await convRepo.setArchivedByMemberIds(
          conversationId,
          conv.archivedByMemberIds.where((id) => id != authorId).toList(),
        );
      }

      // Mark as read for the author. Without this, lastActivityAt > lastRead
      // until dispose() fires its async markConversationAsRead, causing the
      // conversation tile to flash as unread on swipe-back.
      final updatedTimestamps = Map<String, DateTime>.from(
        conv.lastReadTimestamps,
      );
      updatedTimestamps[authorId] = DateTime.now();
      await convRepo.setLastReadTimestamps(conversationId, updatedTimestamps);
      _invalidateMemberConversationActivityFor(conv);
    }

    return id;
  }

  Future<void> _sendSystemMessage(String conversationId, String content) async {
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
    final conv = await convRepo.getConversationById(conversationId);
    if (conv != null) {
      _invalidateMemberConversationActivityFor(conv);
    }
  }

  Future<void> _removeParticipantCore(
    String conversationId,
    String memberId, {
    String? removedByName,
  }) async {
    final convRepo = ref.read(conversationRepositoryProvider);
    final conv = await convRepo.getConversationById(conversationId);
    if (conv == null) return;

    await convRepo.removeParticipantId(conversationId, memberId);
    _invalidateMemberConversationActivityFor(
      conv,
      additionalMemberIds: [memberId],
    );

    if (removedByName != null) {
      final memberRepo = ref.read(memberRepositoryProvider);
      final member = await memberRepo.getMemberById(memberId);
      if (member != null && !member.isDeleted) {
        await _sendSystemMessage(
          conversationId,
          '${member.name} was removed by $removedByName',
        );
      }
    }
  }

  Future<void> removeParticipant(
    String conversationId,
    String memberId, {
    String? removedByName,
  }) async {
    state = await AsyncValue.guard(() async {
      await _requireConversationAction(
        conversationId,
        (permissions) => permissions.canRemoveMembers,
        speakingAsMemberId: ref.read(speakingAsProvider),
      );
      await _removeParticipantCore(
        conversationId,
        memberId,
        removedByName: removedByName,
      );
    });
  }

  Future<void> transferCreator(
    String conversationId,
    String newCreatorId,
  ) async {
    state = await AsyncValue.guard(() async {
      final convRepo = ref.read(conversationRepositoryProvider);
      final conv = await convRepo.getConversationById(conversationId);
      if (conv == null) return;
      await _requireCurrentFrontCanTransferOwnership(conversationId, conv);
      if (!isImplicitParticipantOf(conv, newCreatorId)) {
        throw StateError('Conversation owner must be a participant.');
      }
      if (isUnknownChatAuthor(newCreatorId)) {
        throw StateError('Conversation owner must be a real member.');
      }
      // Defense-in-depth: `isImplicitParticipantOf` short-circuits true for any
      // id on an everyone-group, so independently verify the candidate is a
      // real, active, non-deleted member before writing.
      final memberRepo = ref.read(memberRepositoryProvider);
      final member = await memberRepo.getMemberById(newCreatorId);
      if (member == null || member.isDeleted || !member.isActive) {
        throw StateError('Conversation owner must be an active member.');
      }
      if (conv.creatorId == newCreatorId) return;

      await convRepo.updateConversation(conv.copyWith(creatorId: newCreatorId));

      await _sendSystemMessage(
        conversationId,
        '${member.name} is now the conversation owner',
      );
    });
  }

  Future<void> archiveConversation(
    String conversationId,
    String memberId,
  ) async {
    state = await AsyncValue.guard(() async {
      await _mutationPool.withResource(() async {
        final convRepo = ref.read(conversationRepositoryProvider);
        final conv = await convRepo.getConversationById(conversationId);
        if (conv == null) return;
        await _requireConversationAction(
          conversationId,
          (permissions) => permissions.canArchive,
          speakingAsMemberId: memberId,
        );

        if (conv.archivedByMemberIds.contains(memberId)) return;

        final updatedArchived = [...conv.archivedByMemberIds, memberId];
        await convRepo.setArchivedByMemberIds(conversationId, updatedArchived);
        _invalidateMemberConversationActivityFor(
          conv.copyWith(archivedByMemberIds: updatedArchived),
        );
      });
    });
  }

  Future<void> unarchiveConversation(
    String conversationId,
    String memberId,
  ) async {
    state = await AsyncValue.guard(() async {
      await _mutationPool.withResource(() async {
        final convRepo = ref.read(conversationRepositoryProvider);
        final conv = await convRepo.getConversationById(conversationId);
        if (conv == null) return;
        await _requireConversationAction(
          conversationId,
          (permissions) => permissions.canArchive,
          speakingAsMemberId: memberId,
        );

        final updatedArchived = conv.archivedByMemberIds
            .where((id) => id != memberId)
            .toList();
        await convRepo.setArchivedByMemberIds(conversationId, updatedArchived);
        _invalidateMemberConversationActivityFor(
          conv.copyWith(archivedByMemberIds: updatedArchived),
          additionalMemberIds: [memberId],
        );
      });
    });
  }

  /// Admin/creator action: archive this conversation for every member at once.
  /// Independent of per-member archive — sets a convo-level flag that hides the
  /// chat for all members (and any added later) until unarchived for everyone.
  /// Gated on [ConversationPermissions.canArchiveForEveryone].
  Future<void> archiveForEveryone(String conversationId) async {
    state = await AsyncValue.guard(() async {
      await _mutationPool.withResource(() async {
        final convRepo = ref.read(conversationRepositoryProvider);
        final conv = await convRepo.getConversationById(conversationId);
        if (conv == null) return;
        await _requireConversationAction(
          conversationId,
          (permissions) => permissions.canArchiveForEveryone,
          speakingAsMemberId: ref.read(speakingAsProvider),
        );

        if (conv.archivedForEveryone) return;
        await convRepo.setArchivedForEveryone(conversationId, true);
        _invalidateMemberConversationActivityFor(
          conv.copyWith(archivedForEveryone: true),
        );
      });
    });
  }

  /// Admin/creator action: clear the system-wide archive set by
  /// [archiveForEveryone]. Per-member archive state is left untouched.
  Future<void> unarchiveForEveryone(String conversationId) async {
    state = await AsyncValue.guard(() async {
      await _mutationPool.withResource(() async {
        final convRepo = ref.read(conversationRepositoryProvider);
        final conv = await convRepo.getConversationById(conversationId);
        if (conv == null) return;
        await _requireConversationAction(
          conversationId,
          (permissions) => permissions.canUnarchiveForEveryone,
          speakingAsMemberId: ref.read(speakingAsProvider),
        );

        if (!conv.archivedForEveryone) return;
        await convRepo.setArchivedForEveryone(conversationId, false);
        _invalidateMemberConversationActivityFor(
          conv.copyWith(archivedForEveryone: false),
        );
      });
    });
  }

  Future<void> leaveConversation(String conversationId, String memberId) async {
    state = await AsyncValue.guard(() async {
      // The leaving member is the actor; gate on their permission so an
      // implicit everyone-group member can't trigger a no-op removal plus
      // bogus "left" system message.
      await _requireConversationAction(
        conversationId,
        (permissions) => permissions.canLeave,
        speakingAsMemberId: memberId,
      );
      final memberRepo = ref.read(memberRepositoryProvider);
      final member = await memberRepo.getMemberById(memberId);
      await _removeParticipantCore(conversationId, memberId);
      if (member != null && !member.isDeleted) {
        await _sendSystemMessage(
          conversationId,
          '${member.name} left the conversation',
        );
      }
    });
  }

  Future<void> editMessage(String messageId, String newContent) async {
    state = await AsyncValue.guard(() async {
      await _mutationPool.withResource(() async {
        final repo = ref.read(chatMessageRepositoryProvider);
        final message = await repo.getMessageById(messageId);
        if (message != null) {
          await _requireConversationAction(
            message.conversationId,
            (permissions) => permissions.canEditMessage(message.authorId),
            speakingAsMemberId: ref.read(speakingAsProvider),
          );
          final updated = message.copyWith(
            content: newContent,
            editedAt: DateTime.now(),
          );
          await repo.updateMessage(updated);
        }
      });
    });
  }

  Future<void> changeMessageAuthor(String messageId, String newAuthorId) async {
    state = await AsyncValue.guard(() async {
      await _mutationPool.withResource(() async {
        final repo = ref.read(chatMessageRepositoryProvider);
        final message = await repo.getMessageById(messageId);
        if (message == null || message.isSystemMessage) return;
        if (message.authorId == newAuthorId) return;
        if (await repo.isMessageDeleted(messageId)) return;

        await _requireConversationAction(
          message.conversationId,
          (perms) => perms.canChangeMessageAuthor(message.authorId),
          speakingAsMemberId: ref.read(speakingAsProvider),
        );

        final conversation = await ref
            .read(conversationRepositoryProvider)
            .getConversationById(message.conversationId);
        if (conversation == null) return;
        final activeMembers = await ref.read(activeMembersProvider.future);
        final validIds = chatAuthorCandidateIds(
          conversation,
          activeMembers,
          currentAuthorId: message.authorId,
        );
        if (!validIds.contains(newAuthorId)) {
          throw StateError('Invalid author candidate for re-attribution.');
        }

        // Re-attribution is a correction, not an edit — leave editedAt alone.
        await repo.updateMessage(message.copyWith(authorId: newAuthorId));
      });
    });
  }

  Future<void> deleteMessage(String messageId) async {
    state = await AsyncValue.guard(() async {
      await _mutationPool.withResource(() async {
        final msgRepo = ref.read(chatMessageRepositoryProvider);
        final convRepo = ref.read(conversationRepositoryProvider);

        // Look up the message before deleting so we know which conversation to fix.
        final message = await msgRepo.getMessageById(messageId);
        if (message != null) {
          await _requireConversationAction(
            message.conversationId,
            (permissions) => permissions.canDeleteMessage(message.authorId),
            speakingAsMemberId: ref.read(speakingAsProvider),
          );
        }
        await msgRepo.deleteMessage(messageId);

        // After deletion, update the conversation's lastActivityAt to reflect the
        // latest remaining message. Without this, the conversation list shows "now"
        // because the original sendMessage set lastActivityAt but deleting the
        // message never reverted it.
        if (message != null) {
          final conv = await convRepo.getConversationById(
            message.conversationId,
          );
          if (conv != null) {
            final latestMessage = await msgRepo.getLatestMessage(
              message.conversationId,
            );
            final newActivityAt = latestMessage?.timestamp ?? conv.createdAt;
            if (newActivityAt != conv.lastActivityAt) {
              await convRepo.updateConversation(
                conv.copyWith(lastActivityAt: newActivityAt),
              );
            }
            _invalidateMemberConversationActivityFor(conv);
          }
        }
      });
    });
  }

  Future<void> updateConversation(
    String id, {
    String? title,
    String? emoji,
    String? categoryId,
    bool clearEmoji = false,
    bool clearCategory = false,
  }) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(conversationRepositoryProvider);
      final conv = await repo.getConversationById(id);
      if (conv != null) {
        final speakingAsMemberId = ref.read(speakingAsProvider);
        final allowUpdate = clearCategory
            ? (ConversationPermissions permissions) => permissions.canManage
            : (ConversationPermissions permissions) =>
                  permissions.canEditTitleEmoji || permissions.canManage;
        await _requireConversationAction(
          id,
          allowUpdate,
          speakingAsMemberId: speakingAsMemberId,
        );
        final updated = conv.copyWith(
          title: title ?? conv.title,
          emoji: clearEmoji ? null : (emoji ?? conv.emoji),
          categoryId: clearCategory ? null : (categoryId ?? conv.categoryId),
        );
        await repo.updateConversation(updated);
        _invalidateMemberConversationActivityFor(updated);
      }
    });
  }

  Future<void> addParticipants(
    String conversationId,
    List<String> memberIds, {
    String? addedByName,
  }) async {
    state = await AsyncValue.guard(() async {
      await _requireConversationAction(
        conversationId,
        (permissions) => permissions.canAddMembers,
        speakingAsMemberId: ref.read(speakingAsProvider),
      );
      final repo = ref.read(conversationRepositoryProvider);
      final conv = await repo.getConversationById(conversationId);
      if (conv != null) {
        final existingIds = conv.participantIds.toSet();
        final newIds = memberIds
            .where((id) => !existingIds.contains(id))
            .toList();
        await repo.addParticipantIds(conversationId, newIds);
        _invalidateMemberConversationActivityFor(
          conv,
          additionalMemberIds: memberIds,
        );
        if (addedByName != null && newIds.isNotEmpty) {
          final memberRepo = ref.read(memberRepositoryProvider);
          final members = await memberRepo.getMembersByIds(newIds.toList());
          for (final member in members.where((member) => !member.isDeleted)) {
            await _sendSystemMessage(
              conversationId,
              '${member.name} was added by $addedByName',
            );
          }
        }
      }
    });
  }

  Future<void> deleteConversation(String id) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(conversationRepositoryProvider);
      final conv = await repo.getConversationById(id);
      await _requireConversationAction(
        id,
        (permissions) => permissions.canDeleteConversation,
        speakingAsMemberId: ref.read(speakingAsProvider),
      );
      await repo.deleteConversation(id);
      if (conv != null) {
        _invalidateMemberConversationActivityFor(conv);
      }
    });
  }

  Future<void> markConversationAsRead(
    String conversationId,
    String memberId,
  ) async {
    final nextState = await AsyncValue.guard(() async {
      await _mutationPool.withResource(() async {
        final repo = ref.read(conversationRepositoryProvider);
        final conv = await repo.getConversationById(conversationId);
        if (conv == null) return;
        await _requireConversationAction(
          conversationId,
          (permissions) => permissions.canMarkRead,
          speakingAsMemberId: memberId,
        );

        final updatedTimestamps = Map<String, DateTime>.from(
          conv.lastReadTimestamps,
        );
        updatedTimestamps[memberId] = DateTime.now();
        await repo.setLastReadTimestamps(conversationId, updatedTimestamps);
      });
    });
    if (ref.mounted) {
      state = nextState;
    }
  }

  Future<void> markAllConversationsAsRead(String memberId) async {
    state = await AsyncValue.guard(() async {
      await _mutationPool.withResource(() async {
        final repo = ref.read(conversationRepositoryProvider);
        // Use filteredConversationsProvider so archived conversations
        // (hidden from this headmate's view) are not touched.
        final conversations =
            ref.read(filteredConversationsProvider).value ?? [];
        final now = DateTime.now();
        for (final conv in conversations) {
          final updated = Map<String, DateTime>.from(conv.lastReadTimestamps);
          updated[memberId] = now;
          await repo.setLastReadTimestamps(conv.id, updated);
        }
      });
    });
  }

  Future<void> toggleMute(String conversationId, String memberId) async {
    state = await AsyncValue.guard(() async {
      await _mutationPool.withResource(() async {
        final repo = ref.read(conversationRepositoryProvider);
        final conv = await repo.getConversationById(conversationId);
        if (conv == null) return;
        await _requireConversationAction(
          conversationId,
          (permissions) => permissions.canMute,
          speakingAsMemberId: memberId,
        );

        final muted = conv.mutedByMemberIds.contains(memberId);
        final updatedMuted = muted
            ? conv.mutedByMemberIds.where((id) => id != memberId).toList()
            : [...conv.mutedByMemberIds, memberId];
        await repo.setMutedByMemberIds(conversationId, updatedMuted);
      });
    });
  }

  Future<void> toggleReaction({
    required String messageId,
    required String emoji,
    required String memberId,
  }) async {
    state = await AsyncValue.guard(() async {
      await _mutationPool.withResource(() async {
        final repo = ref.read(chatMessageRepositoryProvider);
        final message = await repo.getMessageById(messageId);
        if (message == null) return;
        await _requireConversationAction(
          message.conversationId,
          (permissions) => permissions.canReact,
          speakingAsMemberId: memberId,
        );

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
    });
  }
}

final chatNotifierProvider = AsyncNotifierProvider<ChatNotifier, void>(
  ChatNotifier.new,
);

class ReplyingToNotifier extends Notifier<ChatMessage?> {
  final String conversationId;
  ReplyingToNotifier(this.conversationId);

  @override
  ChatMessage? build() => null;

  void setReplyTo(ChatMessage message) => state = message;

  void clear() => state = null;
}

final replyingToProvider = NotifierProvider.autoDispose
    .family<ReplyingToNotifier, ChatMessage?, String>(ReplyingToNotifier.new);

/// Batch unread message counts for all conversations — single SQL stream.
///
/// Returns a map of conversationId → unread count. Watched by all
/// ConversationTiles via [unreadMessageCountProvider], so there's only
/// one Drift stream subscription instead of one per visible tile.
final allUnreadCountsProvider = StreamProvider<Map<String, int>>((ref) {
  final speakingAs = ref.watch(speakingAsProvider);
  if (speakingAs == null) return Stream.value({});

  final conversationsAsync = ref.watch(conversationsProvider);
  final conversations = conversationsAsync.value;
  if (conversations == null) return Stream.value({});

  final conversationSince = <String, DateTime>{};
  for (final conv in conversations) {
    if (!_tracksUnreadFor(conv, speakingAs)) continue;
    final lastRead = conv.lastReadTimestamps[speakingAs];
    conversationSince[conv.id] = lastRead ?? conv.createdAt;
  }

  if (conversationSince.isEmpty) return Stream.value({});

  final repo = ref.watch(chatMessageRepositoryProvider);
  return repo.watchAllUnreadCounts(conversationSince);
});

/// Unread message count for a single conversation (derived from batch).
final unreadMessageCountProvider = Provider.autoDispose.family<int, String>((
  ref,
  conversationId,
) {
  final allCounts = ref.watch(allUnreadCountsProvider).value;
  return allCounts?[conversationId] ?? 0;
});

class ConversationsWithMentionsQuery {
  ConversationsWithMentionsQuery({
    required Map<String, DateTime> conversationSince,
    required this.memberId,
  }) : conversationSince = Map.unmodifiable(conversationSince),
       _cacheKeyParts = _buildCacheKeyParts(conversationSince) {
    _hashCode = Object.hash(memberId, Object.hashAll(_cacheKeyParts));
  }

  final Map<String, DateTime> conversationSince;
  final String memberId;
  final List<String> _cacheKeyParts;
  late final int _hashCode;

  static List<String> _buildCacheKeyParts(
    Map<String, DateTime> conversationSince,
  ) {
    final entries = conversationSince.entries.toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key));
    return [
      for (final entry in entries)
        '${entry.key}\u0000${entry.value.toUtc().microsecondsSinceEpoch}',
    ];
  }

  @override
  bool operator ==(Object other) {
    return other is ConversationsWithMentionsQuery &&
        other.memberId == memberId &&
        listEquals(other._cacheKeyParts, _cacheKeyParts);
  }

  @override
  int get hashCode => _hashCode;
}

/// Total number of conversations with unread messages (for the chat tab badge).
///
/// Respects badge preference: if a member's preference is 'mentions_only',
/// uses a single batch query to find conversations with mentions, rather than
/// opening N individual stream subscriptions.
final unreadConversationCountProvider = Provider<int>(_unreadConversationCount);

/// Unread direct-message conversations for the chat screen's DM segment badge.
final unreadDmCountProvider = Provider<int>(
  (ref) => _unreadConversationCount(ref, isDirectMessage: true),
);

/// Unread group-chat conversations for the chat screen's Group Chats segment badge.
final unreadGroupCountProvider = Provider<int>(
  (ref) => _unreadConversationCount(ref, isDirectMessage: false),
);

// [isDirectMessage] null = any conversation kind, true = DMs only, false =
// groups only. The kind filter runs alongside the existing
// participant/muted/archived gates so the segment badges share the same
// exclusion rules as the bottom-nav chat tab badge.
int _unreadConversationCount(Ref ref, {bool? isDirectMessage}) {
  final speakingAs = ref.watch(speakingAsProvider);
  if (speakingAs == null) return 0;

  final conversationsAsync = ref.watch(conversationsProvider);
  final conversations = conversationsAsync.value;
  if (conversations == null) return 0;

  final badgePrefs = ref.watch(chatBadgePreferencesProvider);
  final mentionsOnly = badgePrefs[speakingAs] == 'mentions_only';

  final eligibleConvs = <Conversation>[];
  for (final conv in conversations) {
    if (isDirectMessage != null && conv.isDirectMessage != isDirectMessage) {
      continue;
    }
    if (!_tracksUnreadFor(conv, speakingAs)) continue;
    eligibleConvs.add(conv);
  }

  if (!mentionsOnly) {
    final allCounts = ref.watch(allUnreadCountsProvider).value;
    if (allCounts == null || allCounts.isEmpty) return 0;
    return eligibleConvs.where((conv) => (allCounts[conv.id] ?? 0) > 0).length;
  }

  final conversationSince = <String, DateTime>{};
  for (final conv in eligibleConvs) {
    final lastRead = conv.lastReadTimestamps[speakingAs];
    conversationSince[conv.id] = lastRead ?? conv.createdAt;
  }

  if (conversationSince.isEmpty) return 0;

  final mentionConvIds = ref
      .watch(
        conversationsWithMentionsProvider(
          ConversationsWithMentionsQuery(
            conversationSince: conversationSince,
            memberId: speakingAs,
          ),
        ),
      )
      .value;

  return mentionConvIds?.length ?? 0;
}

/// IDs of conversations with unread mentions for the speaking-as member.
///
/// Returns an empty set when mentions-only badging is off — keeps the watch
/// cheap so per-tile [conversationTileDataProvider]s can subscribe
/// unconditionally without recomputing per tile.
final mentionConversationIdsProvider = Provider.autoDispose<Set<String>>((ref) {
  final speakingAs = ref.watch(speakingAsProvider);
  if (speakingAs == null) return const {};

  final badgePrefs = ref.watch(chatBadgePreferencesProvider);
  if (badgePrefs[speakingAs] != 'mentions_only') return const {};

  final conversations = ref.watch(conversationsProvider).value;
  if (conversations == null) return const {};

  final conversationSince = <String, DateTime>{};
  for (final conv in conversations) {
    if (!_tracksUnreadFor(conv, speakingAs)) continue;
    final lastRead = conv.lastReadTimestamps[speakingAs];
    conversationSince[conv.id] = lastRead ?? conv.createdAt;
  }

  if (conversationSince.isEmpty) return const {};

  return ref
          .watch(
            conversationsWithMentionsProvider(
              ConversationsWithMentionsQuery(
                conversationSince: conversationSince,
                memberId: speakingAs,
              ),
            ),
          )
          .value ??
      const <String>{};
});

/// Single batch stream that returns which conversations have mentions for a member.
final conversationsWithMentionsProvider = StreamProvider.autoDispose
    .family<Set<String>, ConversationsWithMentionsQuery>((ref, params) {
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

final highlightedMessageIdProvider = NotifierProvider.autoDispose
    .family<HighlightedMessageIdNotifier, String?, String>(
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
  final bool showUnreadBadge;
  final String? speakingAs;
  final Member? dmPartner;
  final String? lastMessageAuthorName;
  final String? lastMessageDisplayContent;

  const ConversationTileData({
    required this.conversation,
    this.lastMessage,
    required this.participantMap,
    required this.unreadCount,
    required this.showUnreadBadge,
    this.speakingAs,
    this.dmPartner,
    this.lastMessageAuthorName,
    this.lastMessageDisplayContent,
  });

  bool get hasUnread {
    if (speakingAs == null) return false;
    if (!_tracksUnreadFor(conversation, speakingAs!)) return false;
    return unreadCount > 0;
  }

  bool get isArchived =>
      speakingAs != null &&
      conversation.archivedByMemberIds.contains(speakingAs);

  String get displayTitle {
    if (conversation.title != null && conversation.title!.isNotEmpty) {
      return conversation.title!;
    }
    // Untitled everyone-group: enumerating creator-only would be misleading.
    if (conversation.includesAllMembers) return 'Everyone';
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
final conversationMapProvider = Provider.autoDispose<Map<String, Conversation>>(
  (ref) {
    final list = ref.watch(conversationsProvider).value;
    if (list == null) return const {};
    return {for (final c in list) c.id: c};
  },
);

/// Batched per-tile data provider. Each [ConversationTile] watches this single
/// provider instead of 5+ individual providers, reducing listener fan-out.
final conversationTileDataProvider = Provider.autoDispose
    .family<ConversationTileData?, String>((ref, conversationId) {
      final speakingAs = ref.watch(speakingAsProvider);

      // O(1) lookup via the shared map provider.
      final conversationMap = ref.watch(conversationMapProvider);
      final conversation = conversationMap[conversationId];
      if (conversation == null) return null;

      // Last message.
      final lastMessageAsync = ref.watch(lastMessageProvider(conversationId));
      final lastMessage = lastMessageAsync.value;

      // Participant/author map (batch loaded). Everyone-group senders may be
      // implicit participants, so include the latest author even when they are
      // not in the explicit participantIds list.
      final memberIdsForTile = <String>{...conversation.participantIds};
      final lastMessageAuthorId = lastMessage?.authorId;
      if (lastMessageAuthorId != null) {
        memberIdsForTile.add(lastMessageAuthorId);
      }
      final participantMapAsync = ref.watch(
        membersByIdsProvider(memberIdsKey(memberIdsForTile)),
      );
      final participantMap = participantMapAsync.value ?? const {};

      // Unread count (derived from batch provider).
      final unreadCount = ref.watch(unreadMessageCountProvider(conversationId));

      // Badge gating: in mentions-only mode, only show the per-tile badge
      // when this conversation actually has an unread mention. Outside
      // mentions-only mode the provider returns an empty set, so the
      // mentions_only branch short-circuits without extra work.
      final mentionsOnly =
          speakingAs != null &&
          ref.watch(chatBadgePreferencesProvider)[speakingAs] ==
              'mentions_only';
      final showUnreadBadge =
          unreadCount > 0 &&
          (!mentionsOnly ||
              ref
                  .watch(mentionConversationIdsProvider)
                  .contains(conversationId));

      // Mention name map — always watch to keep the dependency graph stable.
      final nameMap = ref.watch(memberNameMapProvider);

      // DM partner: derive from participantMap (already batch-loaded) rather than
      // a conditional ref.watch() that would destabilize the dependency graph.
      Member? dmPartner;
      if (conversation.emoji == null &&
          isDirectMessageConversation(conversation)) {
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
        lastMessageDisplayContent = buildTilePreviewContent(
          lastMessage.content,
          nameMap,
        );
      }

      return ConversationTileData(
        conversation: conversation,
        lastMessage: lastMessage,
        participantMap: participantMap,
        unreadCount: unreadCount,
        showUnreadBadge: showUnreadBadge,
        speakingAs: speakingAs,
        dmPartner: dmPartner,
        lastMessageAuthorName: lastMessageAuthorName,
        lastMessageDisplayContent: lastMessageDisplayContent,
      );
    });

// Strip → resolve → redact: stripping the raw text first protects member
// names containing markdown chars (`A_B_C`); resolving before redaction
// keeps the spoiler block count clamped on the visible `@Name` length.
String buildTilePreviewContent(String rawContent, Map<String, String> nameMap) {
  final stripped = stripMarkdownMarkers(rawContent);
  final resolved = replaceMentionsWithNames(stripped, nameMap);
  return redactSpoilers(resolved);
}
