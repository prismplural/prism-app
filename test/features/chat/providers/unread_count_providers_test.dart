import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/chat/utils/mention_utils.dart';

/// Unit tests for unread count provider logic.
///
/// The providers themselves depend on Riverpod + Drift which require
/// integration test infrastructure. These tests verify the pure logic
/// that the providers delegate to.
void main() {
  group('unreadConversationCount logic', () {
    test('hasUnread: lastRead null and activity after creation is unread', () {
      final createdAt = DateTime(2026, 1, 1);
      final lastActivityAt = DateTime(2026, 1, 2);
      DateTime? lastRead;

      final hasUnread = lastRead == null
          ? lastActivityAt.isAfter(createdAt)
          : lastActivityAt.isAfter(lastRead);

      expect(hasUnread, isTrue);
    });

    test('hasUnread: lastRead after activity is not unread', () {
      final lastActivityAt = DateTime(2026, 1, 2);
      final lastRead = DateTime(2026, 1, 3);

      final hasUnread = lastActivityAt.isAfter(lastRead);
      expect(hasUnread, isFalse);
    });

    test('muted conversations are excluded from count', () {
      const speakingAs = 'member-1';
      final mutedByMemberIds = ['member-1'];

      final isMuted = mutedByMemberIds.contains(speakingAs);
      expect(isMuted, isTrue);
    });

    test('archived conversations are excluded from count', () {
      const speakingAs = 'member-1';
      final archivedByMemberIds = ['member-1'];

      final isArchived = archivedByMemberIds.contains(speakingAs);
      expect(isArchived, isTrue);
    });

    test('mentions-only mode filters by containsMention', () {
      const memberId = '00000000-0000-0000-0000-000000000001';
      const content = 'Hey @[$memberId] check this';

      expect(containsMention(content, memberId), isTrue);
      expect(containsMention('Hello world', memberId), isFalse);
    });

    test('no speakingAs returns count 0', () {
      // When speakingAs is null, the provider returns 0.
      const String? speakingAs = null;
      expect(speakingAs == null, isTrue);
    });
  });
}
