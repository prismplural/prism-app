import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';

void main() {
  final now = DateTime(2026, 4, 1);

  Member makeMember({required String id, String? name}) => Member(
        id: id,
        name: name ?? 'Member $id',
        createdAt: now,
      );

  Conversation makeConversation({
    String? title,
    DateTime? createdAt,
    DateTime? lastActivityAt,
    List<String> participantIds = const [],
    List<String> archivedByMemberIds = const [],
    Map<String, DateTime> lastReadTimestamps = const {},
  }) =>
      Conversation(
        id: 'conv-1',
        createdAt: createdAt ?? now,
        lastActivityAt: lastActivityAt ?? now,
        title: title,
        participantIds: participantIds,
        archivedByMemberIds: archivedByMemberIds,
        lastReadTimestamps: lastReadTimestamps,
      );

  ConversationTileData makeTileData({
    Conversation? conversation,
    String? speakingAs,
    Map<String, Member>? participantMap,
    int unreadCount = 0,
  }) =>
      ConversationTileData(
        conversation: conversation ?? makeConversation(),
        participantMap: participantMap ?? const {},
        unreadCount: unreadCount,
        speakingAs: speakingAs,
      );

  // ── hasUnread ──────────────────────────────────────────────────────────

  group('hasUnread', () {
    test('returns false when speakingAs is null', () {
      final tile = makeTileData(
        conversation: makeConversation(
          createdAt: now,
          lastActivityAt: now.add(const Duration(hours: 1)),
        ),
        speakingAs: null,
      );
      expect(tile.hasUnread, isFalse);
    });

    test('returns true when lastRead is null but activity is after creation', () {
      final tile = makeTileData(
        conversation: makeConversation(
          createdAt: now,
          lastActivityAt: now.add(const Duration(hours: 1)),
          lastReadTimestamps: {}, // no entry for this member
        ),
        speakingAs: 'member-1',
      );
      expect(tile.hasUnread, isTrue);
    });

    test('returns false when lastRead is after lastActivityAt', () {
      final tile = makeTileData(
        conversation: makeConversation(
          createdAt: now,
          lastActivityAt: now.add(const Duration(hours: 1)),
          lastReadTimestamps: {
            'member-1': now.add(const Duration(hours: 2)),
          },
        ),
        speakingAs: 'member-1',
      );
      expect(tile.hasUnread, isFalse);
    });

    test('returns true when lastActivityAt is after lastRead', () {
      final tile = makeTileData(
        conversation: makeConversation(
          createdAt: now,
          lastActivityAt: now.add(const Duration(hours: 3)),
          lastReadTimestamps: {
            'member-1': now.add(const Duration(hours: 1)),
          },
        ),
        speakingAs: 'member-1',
      );
      expect(tile.hasUnread, isTrue);
    });
  });

  // ── isArchived ─────────────────────────────────────────────────────────

  group('isArchived', () {
    test('returns true when speakingAs is in archivedByMemberIds', () {
      final tile = makeTileData(
        conversation: makeConversation(
          archivedByMemberIds: ['member-1', 'member-2'],
        ),
        speakingAs: 'member-1',
      );
      expect(tile.isArchived, isTrue);
    });

    test('returns false when speakingAs is null', () {
      final tile = makeTileData(
        conversation: makeConversation(
          archivedByMemberIds: ['member-1'],
        ),
        speakingAs: null,
      );
      expect(tile.isArchived, isFalse);
    });

    test('returns false when speakingAs is not in archivedByMemberIds', () {
      final tile = makeTileData(
        conversation: makeConversation(
          archivedByMemberIds: ['member-2'],
        ),
        speakingAs: 'member-1',
      );
      expect(tile.isArchived, isFalse);
    });
  });

  // ── displayTitle ───────────────────────────────────────────────────────

  group('displayTitle', () {
    test('returns explicit title when set', () {
      final tile = makeTileData(
        conversation: makeConversation(title: 'Team Chat'),
        speakingAs: 'member-1',
      );
      expect(tile.displayTitle, 'Team Chat');
    });

    test('falls back to participant names when title is empty', () {
      final m2 = makeMember(id: 'member-2', name: 'Alice');
      final m3 = makeMember(id: 'member-3', name: 'Bob');
      final tile = makeTileData(
        conversation: makeConversation(
          title: '',
          participantIds: ['member-1', 'member-2', 'member-3'],
        ),
        speakingAs: 'member-1',
        participantMap: {'member-2': m2, 'member-3': m3},
      );
      expect(tile.displayTitle, 'Alice, Bob');
    });

    test('falls back to participant names when title is null', () {
      final m2 = makeMember(id: 'member-2', name: 'Carol');
      final tile = makeTileData(
        conversation: makeConversation(
          title: null,
          participantIds: ['member-1', 'member-2'],
        ),
        speakingAs: 'member-1',
        participantMap: {'member-2': m2},
      );
      expect(tile.displayTitle, 'Carol');
    });

    test('returns "Conversation" when no other participants', () {
      final tile = makeTileData(
        conversation: makeConversation(
          title: '',
          participantIds: ['member-1'],
        ),
        speakingAs: 'member-1',
      );
      expect(tile.displayTitle, 'Conversation');
    });

    test('shows "Unknown" for participants not in the map', () {
      final tile = makeTileData(
        conversation: makeConversation(
          title: '',
          participantIds: ['member-1', 'member-2'],
        ),
        speakingAs: 'member-1',
        participantMap: {}, // member-2 not in map
      );
      expect(tile.displayTitle, 'Unknown');
    });
  });
}
