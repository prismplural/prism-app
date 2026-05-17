import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/models/conversation_permissions.dart';

void main() {
  final now = DateTime(2026, 3, 15);

  Member makeMember({required String id, bool isAdmin = false}) =>
      Member(id: id, name: 'Member $id', createdAt: now, isAdmin: isAdmin);

  Conversation makeGroupConversation({
    String? creatorId,
    List<String> participantIds = const ['creator', 'member1', 'member2'],
  }) => Conversation(
    id: 'conv-1',
    createdAt: now,
    lastActivityAt: now,
    isDirectMessage: false,
    creatorId: creatorId,
    participantIds: participantIds,
  );

  Conversation makeDmConversation({
    List<String> participantIds = const ['member1', 'member2'],
  }) => Conversation(
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
    test('isParticipant is true', () => expect(perms.isParticipant, isTrue));
    test('canManage is true', () => expect(perms.canManage, isTrue));
    test(
      'canTransferOwnership is true',
      () => expect(perms.canTransferOwnership, isTrue),
    );
    test('canView is true', () => expect(perms.canView, isTrue));
    test('canWrite is true', () => expect(perms.canWrite, isTrue));
    test(
      'canEditTitleEmoji is true',
      () => expect(perms.canEditTitleEmoji, isTrue),
    );
    test('canAddMembers is true', () => expect(perms.canAddMembers, isTrue));
    test(
      'canRemoveMembers is true',
      () => expect(perms.canRemoveMembers, isTrue),
    );
    test(
      'canDeleteConversation is true',
      () => expect(perms.canDeleteConversation, isTrue),
    );
    test('canLeave is true', () => expect(perms.canLeave, isTrue));
    test('canArchive is true', () => expect(perms.canArchive, isTrue));

    test(
      'canEditMessage own',
      () => expect(perms.canEditMessage('creator'), isTrue),
    );
    test(
      'canEditMessage others is false',
      () => expect(perms.canEditMessage('member1'), isFalse),
    );
    test(
      'canDeleteMessage own',
      () => expect(perms.canDeleteMessage('creator'), isTrue),
    );
    test(
      'canDeleteMessage others (creator manages)',
      () => expect(perms.canDeleteMessage('member1'), isTrue),
    );
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
    test('isParticipant is false', () => expect(perms.isParticipant, isFalse));
    test('isAdmin is true', () => expect(perms.isAdmin, isTrue));
    test(
      'isAdminNonParticipantGroup is true',
      () => expect(perms.isAdminNonParticipantGroup, isTrue),
    );

    // View + moderate, no posting/reacting — the admin oversees the group
    // without participating in it. The DM rules below pin the opposite
    // behavior for DMs (admins never see DMs they aren't in).
    test('canView is true (admin override)',
        () => expect(perms.canView, isTrue));
    test(
      'canWrite is false (no posting)',
      () => expect(perms.canWrite, isFalse),
    );
    test(
      'canReact is false (no reacting)',
      () => expect(perms.canReact, isFalse),
    );
    test(
      'canSendMessages is false (no posting)',
      () => expect(perms.canSendMessages, isFalse),
    );
    test(
      'canManage is true (admin override)',
      () => expect(perms.canManage, isTrue),
    );
    test(
      'canTransferOwnership is true (admin moderation)',
      () => expect(perms.canTransferOwnership, isTrue),
    );
    test(
      'canEditTitleEmoji is true (admin moderation)',
      () => expect(perms.canEditTitleEmoji, isTrue),
    );
    test(
      'canAddMembers is true (admin moderation)',
      () => expect(perms.canAddMembers, isTrue),
    );
    test(
      'canRemoveMembers is true (admin moderation)',
      () => expect(perms.canRemoveMembers, isTrue),
    );
    test(
      'canDeleteConversation is true (admin moderation)',
      () => expect(perms.canDeleteConversation, isTrue),
    );
    test(
      'canLeave is false (not a participant)',
      () => expect(perms.canLeave, isFalse),
    );
    test(
      'canArchive is true (personal-state)',
      () => expect(perms.canArchive, isTrue),
    );
    test(
      'canMute is true (personal-state)',
      () => expect(perms.canMute, isTrue),
    );
    test(
      'canMarkRead is true (personal-state)',
      () => expect(perms.canMarkRead, isTrue),
    );

    test(
      'canEditMessage own is false (cannot write, never authored anything)',
      () => expect(perms.canEditMessage('admin1'), isFalse),
    );
    test(
      'canEditMessage others is false (admins never put words in others\' mouths)',
      () => expect(perms.canEditMessage('member1'), isFalse),
    );
    test(
      'canDeleteMessage others is true (admin moderation removes content)',
      () => expect(perms.canDeleteMessage('member1'), isTrue),
    );
    test(
      'canDeleteMessage with null authorId is true (moderation)',
      () => expect(perms.canDeleteMessage(null), isTrue),
    );
  });

  group('ConversationPermissions — regular member non-participant', () {
    late ConversationPermissions perms;

    setUp(() {
      final conv = makeGroupConversation(creatorId: 'creator');
      final member = makeMember(id: 'outsider', isAdmin: false);
      perms = ConversationPermissions(
        conversation: conv,
        speakingAsMemberId: 'outsider',
        speakingAsMember: member,
      );
    });

    test('isParticipant is false', () => expect(perms.isParticipant, isFalse));
    test(
      'isAdminNonParticipantGroup is false (not an admin)',
      () => expect(perms.isAdminNonParticipantGroup, isFalse),
    );
    test('canView is false', () => expect(perms.canView, isFalse));
    test('canWrite is false', () => expect(perms.canWrite, isFalse));
    test('canManage is false', () => expect(perms.canManage, isFalse));
    test(
      'canDeleteConversation is false',
      () => expect(perms.canDeleteConversation, isFalse),
    );
    test('canArchive is false', () => expect(perms.canArchive, isFalse));
    test(
      'canDeleteMessage own is false (no write, no manage)',
      () => expect(perms.canDeleteMessage('outsider'), isFalse),
    );
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
    test('isParticipant is true', () => expect(perms.isParticipant, isTrue));
    test('isAdmin is false', () => expect(perms.isAdmin, isFalse));
    test('canManage is false', () => expect(perms.canManage, isFalse));
    test(
      'canTransferOwnership is false',
      () => expect(perms.canTransferOwnership, isFalse),
    );
    test('canView is true', () => expect(perms.canView, isTrue));
    test('canWrite is true', () => expect(perms.canWrite, isTrue));
    test(
      'canEditTitleEmoji is false',
      () => expect(perms.canEditTitleEmoji, isFalse),
    );
    test('canAddMembers is false', () => expect(perms.canAddMembers, isFalse));
    test(
      'canRemoveMembers is false',
      () => expect(perms.canRemoveMembers, isFalse),
    );
    test(
      'canDeleteConversation is false',
      () => expect(perms.canDeleteConversation, isFalse),
    );
    test('canLeave is true', () => expect(perms.canLeave, isTrue));
    test('canArchive is true', () => expect(perms.canArchive, isTrue));

    test(
      'canEditMessage own',
      () => expect(perms.canEditMessage('member1'), isTrue),
    );
    test(
      'canEditMessage others is false',
      () => expect(perms.canEditMessage('creator'), isFalse),
    );
    test(
      'canDeleteMessage own',
      () => expect(perms.canDeleteMessage('member1'), isTrue),
    );
    test(
      'canDeleteMessage others is false',
      () => expect(perms.canDeleteMessage('creator'), isFalse),
    );
  });

  group('ConversationPermissions — DM conversation', () {
    late ConversationPermissions permsA;
    late ConversationPermissions permsB;
    late ConversationPermissions permsAdmin;

    setUp(() {
      final conv = makeDmConversation(participantIds: ['member1', 'member2']);
      final memberA = makeMember(id: 'member1');
      final memberB = makeMember(id: 'member2');
      final admin = makeMember(id: 'admin1', isAdmin: true);
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
      permsAdmin = ConversationPermissions(
        conversation: conv,
        speakingAsMemberId: 'admin1',
        speakingAsMember: admin,
      );
    });

    test('member1 canView is true', () => expect(permsA.canView, isTrue));
    test('member1 canWrite is true', () => expect(permsA.canWrite, isTrue));
    test(
      'member1 canEditTitleEmoji is true',
      () => expect(permsA.canEditTitleEmoji, isTrue),
    );
    test(
      'member2 canEditTitleEmoji is true',
      () => expect(permsB.canEditTitleEmoji, isTrue),
    );
    test(
      'canAddMembers is false for DM',
      () => expect(permsA.canAddMembers, isFalse),
    );
    test(
      'canRemoveMembers is false for DM',
      () => expect(permsA.canRemoveMembers, isFalse),
    );
    test('canLeave is false for DM', () => expect(permsA.canLeave, isFalse));
    test(
      'canDeleteConversation is true for DM participant',
      () => expect(permsA.canDeleteConversation, isTrue),
    );
    test('canArchive is true for DM', () => expect(permsA.canArchive, isTrue));
    test(
      'admin non-participant canView is false',
      () => expect(permsAdmin.canView, isFalse),
    );
    test(
      'admin non-participant canWrite is false',
      () => expect(permsAdmin.canWrite, isFalse),
    );
    test(
      'admin non-participant cannot transfer ownership in DM',
      () => expect(permsAdmin.canTransferOwnership, isFalse),
    );
    test(
      'admin non-participant cannot edit title in DM',
      () => expect(permsAdmin.canEditTitleEmoji, isFalse),
    );
    test(
      'admin non-participant cannot archive DM',
      () => expect(permsAdmin.canArchive, isFalse),
    );
    test(
      'admin non-participant cannot mark DM read',
      () => expect(permsAdmin.canMarkRead, isFalse),
    );
    test(
      'admin non-participant cannot react in DM',
      () => expect(permsAdmin.canReact, isFalse),
    );
    test(
      'admin non-participant cannot delete DM messages',
      () => expect(permsAdmin.canDeleteMessage('member1'), isFalse),
    );
    test(
      'admin non-participant cannot delete DM conversation',
      () => expect(permsAdmin.canDeleteConversation, isFalse),
    );
  });

  group('ConversationPermissions — unscoped DM (empty participantIds)', () {
    Conversation makeUnscopedDm() => Conversation(
      id: 'unscoped-dm',
      createdAt: now,
      lastActivityAt: now,
      isDirectMessage: true,
      participantIds: const [],
    );

    test('non-participant non-admin can view', () {
      final perms = ConversationPermissions(
        conversation: makeUnscopedDm(),
        speakingAsMemberId: 'someone',
        speakingAsMember: makeMember(id: 'someone'),
      );
      expect(perms.canView, isTrue);
    });

    test('null speakingAs can view', () {
      final perms = ConversationPermissions(
        conversation: makeUnscopedDm(),
        speakingAsMemberId: null,
        speakingAsMember: null,
      );
      expect(perms.canView, isTrue);
      expect(perms.canWrite, isTrue);
    });

    test('non-participant can write (consistent with view)', () {
      final perms = ConversationPermissions(
        conversation: makeUnscopedDm(),
        speakingAsMemberId: 'someone',
        speakingAsMember: makeMember(id: 'someone'),
      );
      expect(perms.canWrite, isTrue);
    });

    test('scoped DM still gates non-participant view', () {
      final conv = Conversation(
        id: 'scoped-dm',
        createdAt: now,
        lastActivityAt: now,
        isDirectMessage: true,
        participantIds: const ['member1', 'member2'],
      );
      final perms = ConversationPermissions(
        conversation: conv,
        speakingAsMemberId: 'outsider',
        speakingAsMember: makeMember(id: 'outsider'),
      );
      expect(perms.canView, isFalse);
      expect(perms.canWrite, isFalse);
    });
  });

  group('ConversationPermissions — orphaned DM', () {
    test('remaining participant can view, archive, mark read, and delete', () {
      final perms = ConversationPermissions(
        conversation: makeDmConversation(participantIds: ['member1']),
        speakingAsMemberId: 'member1',
        speakingAsMember: makeMember(id: 'member1'),
      );

      expect(perms.canView, isTrue);
      expect(perms.canArchive, isTrue);
      expect(perms.canMarkRead, isTrue);
      expect(perms.canDeleteConversation, isTrue);
    });

    test(
      'remaining participant cannot continue writing to the orphaned DM',
      () {
        final perms = ConversationPermissions(
          conversation: makeDmConversation(participantIds: ['member1']),
          speakingAsMemberId: 'member1',
          speakingAsMember: makeMember(id: 'member1'),
        );

        expect(perms.canWrite, isFalse);
        expect(perms.canEditTitleEmoji, isFalse);
        expect(perms.canSendMessages, isFalse);
        expect(perms.canReact, isFalse);
        expect(perms.canEditMessage('member1'), isFalse);
        expect(perms.canDeleteMessage('member1'), isFalse);
      },
    );

    test('non-participant cannot view orphaned DM', () {
      final perms = ConversationPermissions(
        conversation: makeDmConversation(participantIds: ['member1']),
        speakingAsMemberId: 'outsider',
        speakingAsMember: makeMember(id: 'outsider'),
      );

      expect(perms.canView, isFalse);
      expect(perms.canArchive, isFalse);
      expect(perms.canDeleteConversation, isFalse);
    });
  });

  group('ConversationPermissions — legacy DM shape', () {
    test('untitled two-person conversation is treated as DM', () {
      final conv = Conversation(
        id: 'legacy-dm',
        createdAt: now,
        lastActivityAt: now,
        isDirectMessage: false,
        title: '',
        participantIds: const ['member1', 'member2'],
      );
      final member = makeMember(id: 'member1');
      final perms = ConversationPermissions(
        conversation: conv,
        speakingAsMemberId: 'member1',
        speakingAsMember: member,
      );

      expect(perms.isDirectMessage, isTrue);
      expect(perms.canLeave, isFalse);
      expect(perms.canAddMembers, isFalse);
    });
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
    test('anonymous browser sees group list but cannot write', () {
      final conv = makeGroupConversation(creatorId: 'creator');
      final perms = ConversationPermissions(
        conversation: conv,
        speakingAsMemberId: null,
        speakingAsMember: null,
      );
      expect(perms.isCreator, isFalse);
      expect(perms.isAdmin, isFalse);
      // Anonymous viewer (no fronter, none picked) sees the group list as
      // metadata so the chat list isn't empty when no one is fronting.
      expect(perms.canView, isTrue);
      // But cannot send messages until a speaking-as member is picked.
      expect(perms.canWrite, isFalse);
      expect(perms.canManage, isFalse);
    });

    test('anonymous browser cannot view scoped DMs', () {
      final perms = ConversationPermissions(
        conversation: makeDmConversation(),
        speakingAsMemberId: null,
        speakingAsMember: null,
      );
      expect(perms.canView, isFalse);
      expect(perms.canWrite, isFalse);
    });
  });

  group('ConversationPermissions — includesAllMembers (everyone groups)', () {
    Conversation makeEveryoneGroup({
      String? creatorId = 'creator',
      List<String> participantIds = const ['creator'],
    }) => Conversation(
      id: 'everyone-1',
      createdAt: now,
      lastActivityAt: now,
      isDirectMessage: false,
      creatorId: creatorId,
      participantIds: participantIds,
      includesAllMembers: true,
    );

    test(
      'active non-listed member counts as participant (full access)',
      () {
        final perms = ConversationPermissions(
          conversation: makeEveryoneGroup(),
          speakingAsMemberId: 'outsider',
          speakingAsMember: makeMember(id: 'outsider'),
        );
        expect(perms.isParticipant, isTrue);
        expect(perms.canView, isTrue);
        expect(perms.canWrite, isTrue);
        expect(perms.canSendMessages, isTrue);
        expect(perms.canReact, isTrue);
        expect(perms.canLeave, isTrue);
      },
    );

    test('explicit creator is still a participant and remains creator', () {
      final perms = ConversationPermissions(
        conversation: makeEveryoneGroup(),
        speakingAsMemberId: 'creator',
        speakingAsMember: makeMember(id: 'creator'),
      );
      expect(perms.isParticipant, isTrue);
      expect(perms.isCreator, isTrue);
      expect(perms.canManage, isTrue);
      expect(perms.canTransferOwnership, isTrue);
    });

    test('add/remove members is hidden on everyone groups (no-op action)', () {
      final perms = ConversationPermissions(
        conversation: makeEveryoneGroup(),
        speakingAsMemberId: 'creator',
        speakingAsMember: makeMember(id: 'creator'),
      );
      expect(perms.canAddMembers, isFalse,
          reason: 'cannot add to "everyone"');
      expect(perms.canRemoveMembers, isFalse,
          reason: 'cannot remove from "everyone"');
    });

    test('deleted member does NOT count as everyone-participant', () {
      // Member.isDeleted defaults false; explicitly construct a deleted one
      // via copyWith to verify the gate excludes them.
      final base = makeMember(id: 'ghost');
      final deleted = base.copyWith(isDeleted: true);
      final perms = ConversationPermissions(
        conversation: makeEveryoneGroup(),
        speakingAsMemberId: 'ghost',
        speakingAsMember: deleted,
      );
      expect(perms.isParticipant, isFalse);
      expect(perms.canView, isFalse);
    });

    test('inactive member does NOT count as everyone-participant', () {
      final base = makeMember(id: 'paused');
      final inactive = base.copyWith(isActive: false);
      final perms = ConversationPermissions(
        conversation: makeEveryoneGroup(),
        speakingAsMemberId: 'paused',
        speakingAsMember: inactive,
      );
      expect(perms.isParticipant, isFalse);
      expect(perms.canView, isFalse);
    });

    test('null speakingAsMember does NOT count as everyone-participant', () {
      final perms = ConversationPermissions(
        conversation: makeEveryoneGroup(),
        speakingAsMemberId: 'unknown',
        speakingAsMember: null,
      );
      expect(perms.isParticipant, isFalse);
    });

    test('flag does NOT extend to DMs (isParticipant still gates DMs)', () {
      // A DM with includesAllMembers=true is nonsensical but defensively
      // tested: the participant gate stays strict for DMs.
      final dm = Conversation(
        id: 'odd-dm',
        createdAt: now,
        lastActivityAt: now,
        isDirectMessage: true,
        participantIds: const ['alice', 'bob'],
        includesAllMembers: true,
      );
      final perms = ConversationPermissions(
        conversation: dm,
        speakingAsMemberId: 'outsider',
        speakingAsMember: makeMember(id: 'outsider'),
      );
      expect(perms.isParticipant, isFalse);
      expect(perms.canView, isFalse);
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

    test(
      'returns false for current participant',
      () => expect(perms.isMemberDeparted('member1'), isFalse),
    );
    test(
      'returns false for creator in participants',
      () => expect(perms.isMemberDeparted('creator'), isFalse),
    );
    test(
      'returns true for non-participant',
      () => expect(perms.isMemberDeparted('gone'), isTrue),
    );
    test(
      'returns false for null memberId',
      () => expect(perms.isMemberDeparted(null), isFalse),
    );
  });
}
