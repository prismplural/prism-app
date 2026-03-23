import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/models/conversation_permissions.dart';

void main() {
  final now = DateTime(2026, 3, 15);

  Member makeMember({
    required String id,
    bool isAdmin = false,
  }) =>
      Member(
        id: id,
        name: 'Member $id',
        createdAt: now,
        isAdmin: isAdmin,
      );

  Conversation makeGroupConversation({
    String? creatorId,
    List<String> participantIds = const ['creator', 'member1', 'member2'],
  }) =>
      Conversation(
        id: 'conv-1',
        createdAt: now,
        lastActivityAt: now,
        isDirectMessage: false,
        creatorId: creatorId,
        participantIds: participantIds,
      );

  Conversation makeDmConversation({
    List<String> participantIds = const ['member1', 'member2'],
  }) =>
      Conversation(
        id: 'conv-dm',
        createdAt: now,
        lastActivityAt: now,
        isDirectMessage: true,
        participantIds: participantIds,
      );

  group('ConversationPermissions — creator', () {
    late ConversationPermissions perms;

    setUp(() {
      final conv = makeGroupConversation(creatorId: 'creator');
      final member = makeMember(id: 'creator', isAdmin: false);
      perms = ConversationPermissions(
        conversation: conv,
        speakingAsMemberId: 'creator',
        speakingAsMember: member,
      );
    });

    test('isCreator is true', () => expect(perms.isCreator, isTrue));
    test('canManage is true', () => expect(perms.canManage, isTrue));
    test('canEditTitleEmoji is true', () => expect(perms.canEditTitleEmoji, isTrue));
    test('canAddMembers is true', () => expect(perms.canAddMembers, isTrue));
    test('canRemoveMembers is true', () => expect(perms.canRemoveMembers, isTrue));
    test('canDeleteConversation is true', () => expect(perms.canDeleteConversation, isTrue));
    test('canLeave is true', () => expect(perms.canLeave, isTrue));
    test('canArchive is true', () => expect(perms.canArchive, isTrue));

    test('canEditMessage own', () => expect(perms.canEditMessage('creator'), isTrue));
    test('canEditMessage others is false', () => expect(perms.canEditMessage('member1'), isFalse));
    test('canDeleteMessage own', () => expect(perms.canDeleteMessage('creator'), isTrue));
    test('canDeleteMessage others (creator manages)', () =>
        expect(perms.canDeleteMessage('member1'), isTrue));
  });

  group('ConversationPermissions — admin non-creator', () {
    late ConversationPermissions perms;

    setUp(() {
      final conv = makeGroupConversation(creatorId: 'creator');
      final member = makeMember(id: 'admin1', isAdmin: true);
      perms = ConversationPermissions(
        conversation: conv,
        speakingAsMemberId: 'admin1',
        speakingAsMember: member,
      );
    });

    test('isCreator is false', () => expect(perms.isCreator, isFalse));
    test('isAdmin is true', () => expect(perms.isAdmin, isTrue));
    test('canManage is true', () => expect(perms.canManage, isTrue));
    test('canEditTitleEmoji is true', () => expect(perms.canEditTitleEmoji, isTrue));
    test('canAddMembers is true', () => expect(perms.canAddMembers, isTrue));
    test('canRemoveMembers is true', () => expect(perms.canRemoveMembers, isTrue));
    test('canDeleteConversation is true', () => expect(perms.canDeleteConversation, isTrue));
    test('canLeave is true', () => expect(perms.canLeave, isTrue));
    test('canArchive is true', () => expect(perms.canArchive, isTrue));

    test('canEditMessage own', () => expect(perms.canEditMessage('admin1'), isTrue));
    test('canEditMessage others is false', () => expect(perms.canEditMessage('member1'), isFalse));
    test('canDeleteMessage own', () => expect(perms.canDeleteMessage('admin1'), isTrue));
    test('canDeleteMessage others (admin manages)', () =>
        expect(perms.canDeleteMessage('member1'), isTrue));
  });

  group('ConversationPermissions — regular member', () {
    late ConversationPermissions perms;

    setUp(() {
      final conv = makeGroupConversation(creatorId: 'creator');
      final member = makeMember(id: 'member1', isAdmin: false);
      perms = ConversationPermissions(
        conversation: conv,
        speakingAsMemberId: 'member1',
        speakingAsMember: member,
      );
    });

    test('isCreator is false', () => expect(perms.isCreator, isFalse));
    test('isAdmin is false', () => expect(perms.isAdmin, isFalse));
    test('canManage is false', () => expect(perms.canManage, isFalse));
    test('canEditTitleEmoji is false', () => expect(perms.canEditTitleEmoji, isFalse));
    test('canAddMembers is false', () => expect(perms.canAddMembers, isFalse));
    test('canRemoveMembers is false', () => expect(perms.canRemoveMembers, isFalse));
    test('canDeleteConversation is false', () => expect(perms.canDeleteConversation, isFalse));
    test('canLeave is true', () => expect(perms.canLeave, isTrue));
    test('canArchive is true', () => expect(perms.canArchive, isTrue));

    test('canEditMessage own', () => expect(perms.canEditMessage('member1'), isTrue));
    test('canEditMessage others is false', () => expect(perms.canEditMessage('creator'), isFalse));
    test('canDeleteMessage own', () => expect(perms.canDeleteMessage('member1'), isTrue));
    test('canDeleteMessage others is false', () =>
        expect(perms.canDeleteMessage('creator'), isFalse));
  });

  group('ConversationPermissions — DM conversation', () {
    late ConversationPermissions permsA;
    late ConversationPermissions permsB;

    setUp(() {
      final conv = makeDmConversation(participantIds: ['member1', 'member2']);
      final memberA = makeMember(id: 'member1');
      final memberB = makeMember(id: 'member2');
      permsA = ConversationPermissions(
        conversation: conv,
        speakingAsMemberId: 'member1',
        speakingAsMember: memberA,
      );
      permsB = ConversationPermissions(
        conversation: conv,
        speakingAsMemberId: 'member2',
        speakingAsMember: memberB,
      );
    });

    test('member1 canEditTitleEmoji is true', () => expect(permsA.canEditTitleEmoji, isTrue));
    test('member2 canEditTitleEmoji is true', () => expect(permsB.canEditTitleEmoji, isTrue));
    test('canAddMembers is false for DM', () => expect(permsA.canAddMembers, isFalse));
    test('canRemoveMembers is false for DM', () => expect(permsA.canRemoveMembers, isFalse));
    test('canLeave is false for DM', () => expect(permsA.canLeave, isFalse));
    test('canDeleteConversation is false for DM', () =>
        expect(permsA.canDeleteConversation, isFalse));
    test('canArchive is true for DM', () => expect(permsA.canArchive, isTrue));
  });

  group('ConversationPermissions — null creatorId', () {
    test('first participant treated as creator', () {
      final conv = makeGroupConversation(
        creatorId: null,
        participantIds: ['first', 'second', 'third'],
      );
      final member = makeMember(id: 'first');
      final perms = ConversationPermissions(
        conversation: conv,
        speakingAsMemberId: 'first',
        speakingAsMember: member,
      );
      expect(perms.isCreator, isTrue);
      expect(perms.canManage, isTrue);
    });

    test('non-first participant is not creator when creatorId is null', () {
      final conv = makeGroupConversation(
        creatorId: null,
        participantIds: ['first', 'second', 'third'],
      );
      final member = makeMember(id: 'second');
      final perms = ConversationPermissions(
        conversation: conv,
        speakingAsMemberId: 'second',
        speakingAsMember: member,
      );
      expect(perms.isCreator, isFalse);
      expect(perms.canManage, isFalse);
    });

    test('empty participantIds with null creatorId yields no creator', () {
      final conv = Conversation(
        id: 'conv-empty',
        createdAt: now,
        lastActivityAt: now,
        isDirectMessage: false,
        creatorId: null,
        participantIds: const [],
      );
      final member = makeMember(id: 'someone');
      final perms = ConversationPermissions(
        conversation: conv,
        speakingAsMemberId: 'someone',
        speakingAsMember: member,
      );
      expect(perms.isCreator, isFalse);
    });
  });

  group('ConversationPermissions — null speakingAsMemberId', () {
    test('isCreator is false when speaking as null', () {
      final conv = makeGroupConversation(creatorId: 'creator');
      final perms = ConversationPermissions(
        conversation: conv,
        speakingAsMemberId: null,
        speakingAsMember: null,
      );
      expect(perms.isCreator, isFalse);
      expect(perms.isAdmin, isFalse);
      expect(perms.canManage, isFalse);
    });
  });

  group('ConversationPermissions — isMemberDeparted', () {
    late ConversationPermissions perms;

    setUp(() {
      final conv = makeGroupConversation(
        creatorId: 'creator',
        participantIds: ['creator', 'member1'],
      );
      final member = makeMember(id: 'creator');
      perms = ConversationPermissions(
        conversation: conv,
        speakingAsMemberId: 'creator',
        speakingAsMember: member,
      );
    });

    test('returns false for current participant', () =>
        expect(perms.isMemberDeparted('member1'), isFalse));
    test('returns false for creator in participants', () =>
        expect(perms.isMemberDeparted('creator'), isFalse));
    test('returns true for non-participant', () =>
        expect(perms.isMemberDeparted('gone'), isTrue));
    test('returns false for null memberId', () =>
        expect(perms.isMemberDeparted(null), isFalse));
  });
}
