import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_board_post.dart';
import 'package:prism_plurality/shared/mentions/entity_mention_visibility.dart';

void main() {
  group('canMentionMember', () {
    test('requires active non-deleted user-visible member', () {
      final member = _member(id: 'm1');

      expect(canMentionMember(member), isTrue);
      expect(canMentionMember(member.copyWith(isActive: false)), isFalse);
      expect(canMentionMember(member.copyWith(isDeleted: true)), isFalse);
      expect(
        canMentionMember(member.copyWith(id: unknownSentinelMemberId)),
        isFalse,
      );
      expect(canMentionMember(null), isFalse);
    });
  });

  group('currentActiveFronters', () {
    test('intersects active sessions with active user-visible members', () {
      final m1 = _member(id: 'm1');
      final m2 = _member(id: 'm2', isDeleted: true);
      final m3 = _member(id: 'm3');

      final fronters = currentActiveFronters(
        activeSessions: [
          _session('s1', 'm1'),
          _session('s2', 'm1'),
          _session('s3', 'm2'),
          _session('s4', 'm3', isSleep: true),
          _session('s5', null),
        ],
        activeMembers: [m1, m2, m3],
      );

      expect(fronters.map((m) => m.id), ['m1']);
    });
  });

  group('canActiveFrontViewBoardPost', () {
    test('shows public posts to any active front', () {
      final post = _post(audience: 'public');

      expect(
        canActiveFrontViewBoardPost(post, activeFronters: const []),
        isTrue,
      );
    });

    test('shows private posts only to target or author fronters', () {
      final post = _post(
        audience: 'private',
        targetMemberId: 'target',
        authorId: 'author',
      );

      expect(
        canActiveFrontViewBoardPost(
          post,
          activeFronters: [_member(id: 'other')],
        ),
        isFalse,
      );
      expect(
        canActiveFrontViewBoardPost(
          post,
          activeFronters: [_member(id: 'target')],
        ),
        isTrue,
      );
      expect(
        canActiveFrontViewBoardPost(
          post,
          activeFronters: [_member(id: 'author')],
        ),
        isTrue,
      );
      expect(
        canActiveFrontViewBoardPost(
          post,
          activeFronters: [_member(id: 'admin', isAdmin: true)],
        ),
        isFalse,
      );
    });

    test('hides deleted or invalid audience posts', () {
      expect(
        canActiveFrontViewBoardPost(
          _post(audience: 'public', isDeleted: true),
          activeFronters: [_member(id: 'm1')],
        ),
        isFalse,
      );
      expect(
        canActiveFrontViewBoardPost(
          _post(audience: 'friends'),
          activeFronters: [_member(id: 'm1')],
        ),
        isFalse,
      );
    });
  });

  group('activeFrontersWhoCanViewConversation', () {
    test('uses ConversationPermissions for each active fronter', () {
      final conversation = Conversation(
        id: 'c1',
        createdAt: DateTime(2024),
        lastActivityAt: DateTime(2024),
        participantIds: const ['m1'],
      );

      expect(
        activeFrontersWhoCanViewConversation(
          conversation,
          activeFronters: [
            _member(id: 'm1'),
            _member(id: 'm2'),
          ],
        ).map((m) => m.id),
        ['m1'],
      );
    });

    test('allows admins to view non-DM groups but not unrelated DMs', () {
      final group = Conversation(
        id: 'group',
        createdAt: DateTime(2024),
        lastActivityAt: DateTime(2024),
        participantIds: const ['m1'],
      );
      final dm = group.copyWith(id: 'dm', isDirectMessage: true);
      final admin = _member(id: 'admin', isAdmin: true);

      expect(
        canActiveFrontViewConversation(group, activeFronters: [admin]),
        isTrue,
      );
      expect(
        canActiveFrontViewConversation(dm, activeFronters: [admin]),
        isFalse,
      );
    });
  });
}

Member _member({
  required String id,
  bool isActive = true,
  bool isDeleted = false,
  bool isAdmin = false,
}) {
  return Member(
    id: id,
    name: id,
    createdAt: DateTime(2024),
    isActive: isActive,
    isDeleted: isDeleted,
    isAdmin: isAdmin,
  );
}

FrontingSession _session(String id, String? memberId, {bool isSleep = false}) {
  return FrontingSession(
    id: id,
    startTime: DateTime(2024),
    memberId: memberId,
    sessionType: isSleep ? SessionType.sleep : SessionType.normal,
  );
}

MemberBoardPost _post({
  required String audience,
  String? targetMemberId,
  String? authorId,
  bool isDeleted = false,
}) {
  return MemberBoardPost(
    id: 'p1',
    targetMemberId: targetMemberId,
    authorId: authorId,
    audience: audience,
    body: 'body',
    createdAt: DateTime(2024),
    writtenAt: DateTime(2024),
    isDeleted: isDeleted,
  );
}
