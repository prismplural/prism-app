import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/models/search_result.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';

class ChatSearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';
  void set(String value) => state = value;
}

final chatSearchQueryProvider =
    NotifierProvider<ChatSearchQueryNotifier, String>(
      ChatSearchQueryNotifier.new,
    );

final chatSearchResultsProvider =
    FutureProvider.autoDispose<List<MessageSearchResult>>((ref) async {
      final query = ref.watch(chatSearchQueryProvider);
      if (query.length < 2) return [];

      final repo = ref.watch(chatMessageRepositoryProvider);
      final convRepo = ref.watch(conversationRepositoryProvider);
      final memberRepo = ref.watch(memberRepositoryProvider);
      final speakingAs = ref.watch(speakingAsProvider);
      final speakingAsMember = ref.watch(currentChatViewerProvider);

      if (speakingAs == null) return [];

      final raw = await repo.searchMessages(query, limit: 50);
      if (raw.isEmpty) return [];

      // Batch-fetch conversations and members to avoid N+1 sequential queries.
      final convIds = raw.map((r) => r.conversationId).toSet();
      final authorIds = raw.map((r) => r.authorId).whereType<String>().toSet();

      final convFutures = convIds.map((id) async {
        final c = await convRepo.getConversationById(id);
        return MapEntry(id, c);
      });
      final convEntries = await Future.wait(convFutures);
      final convMap = Map.fromEntries(convEntries);

      final members = authorIds.isNotEmpty
          ? await memberRepo.getMembersByIds(authorIds.toList())
          : <Member>[];
      final memberMap = {for (final m in members) m.id: m};

      final results = <MessageSearchResult>[];
      for (final r in raw) {
        final conv = convMap[r.conversationId];
        if (conv == null) continue;

        final permissions = conversationPermissionsForViewer(
          conv,
          speakingAsMemberId: speakingAs,
          speakingAsMember: speakingAsMember,
        );
        if (!permissions.canView) continue;

        final author = r.authorId != null ? memberMap[r.authorId] : null;

        results.add(
          MessageSearchResult(
            messageId: r.messageId,
            conversationId: r.conversationId,
            snippet: r.snippet,
            timestamp: r.timestamp,
            authorId: r.authorId,
            authorName: author?.name,
            authorEmoji: author?.emoji,
            authorAvatarData: author?.avatarImageData,
            authorCustomColorEnabled: author?.customColorEnabled,
            authorCustomColorHex: author?.customColorHex,
            conversationTitle: conv.title,
            conversationEmoji: conv.emoji,
          ),
        );
        if (results.length >= 30) break;
      }
      return results;
    });
