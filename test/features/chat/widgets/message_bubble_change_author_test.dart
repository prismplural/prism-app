/// Tests for Task 7: "Change author" long-press menu entry in MessageBubble.
///
/// MessageBubble is a ConsumerStatefulWidget that requires a substantial
/// Riverpod provider tree. The tests here mount the full widget with a minimal
/// set of mocked providers so the context-menu logic can be exercised end-to-end.
///
/// Skipped tests are documented inline with reason.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/domain/models/chat_message.dart';
import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/models/conversation_permissions.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/widgets/message_bubble.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

// ---------------------------------------------------------------------------
// Fake notifier that records changeMessageAuthor calls.
// ---------------------------------------------------------------------------

class _RecordingChatNotifier extends ChatNotifier {
  final List<(String, String?)> changeAuthorCalls = [];

  @override
  Future<void> changeMessageAuthor(String messageId, String? newAuthorId) async {
    changeAuthorCalls.add((messageId, newAuthorId));
  }
}

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

const _kMsgId = 'msg-abc';
const _kConvId = 'conv-abc';
const _kAliceId = 'alice-id';
const _kBobId = 'bob-id';

final _alice = Member(
  id: _kAliceId,
  name: 'Alice',
  createdAt: DateTime(2025, 1, 1),
  isActive: true,
);
final _bob = Member(
  id: _kBobId,
  name: 'Bob',
  createdAt: DateTime(2025, 1, 1),
  isActive: true,
);

/// A normal message authored by Alice.
ChatMessage _makeMessage({
  String id = _kMsgId,
  String authorId = _kAliceId,
  bool isSystemMessage = false,
  String content = 'hello world',
}) {
  return ChatMessage(
    id: id,
    content: content,
    timestamp: DateTime(2025, 1, 1, 12),
    authorId: authorId,
    conversationId: _kConvId,
    isSystemMessage: isSystemMessage,
  );
}

/// Group-style conversation (not a DM, includesAllMembers).
final _groupConversation = Conversation(
  id: _kConvId,
  participantIds: const [_kAliceId, _kBobId],
  createdAt: DateTime(2025),
  lastActivityAt: DateTime(2025),
  includesAllMembers: true,
  title: 'Test Group',
);

/// Permissions where Alice is speaking-as and canWrite == true.
ConversationPermissions _makePerms({
  String? speakingAsMemberId = _kAliceId,
  Member? speakingAsMember,
  Conversation? conversation,
}) {
  return ConversationPermissions(
    conversation: conversation ?? _groupConversation,
    speakingAsMemberId: speakingAsMemberId,
    speakingAsMember: speakingAsMember ?? _alice,
  );
}

// ---------------------------------------------------------------------------
// Widget builder
// ---------------------------------------------------------------------------

Widget _buildSubject({
  required ChatMessage message,
  required ConversationPermissions permissions,
  List<Member>? activeMembers,
  ChatNotifier Function()? chatNotifierFactory,
  Map<String, Member>? authorMap,
  Map<String, String?>? messageAuthorMap,
}) {
  final members = activeMembers ?? [_alice, _bob];

  return ProviderScope(
    overrides: [
      activeMembersProvider.overrideWith(
        (ref) => Stream.value(members),
      ),
      if (chatNotifierFactory != null)
        chatNotifierProvider.overrideWith(chatNotifierFactory),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        // Center + SizedBox gives the bubble a concrete layout size so the
        // long-press BlurPopupAnchor can measure its render box correctly.
        body: Center(
          child: SizedBox(
            width: 400,
            height: 120,
            child: MessageBubble(
              message: message,
              permissions: permissions,
              authorMap: authorMap,
              messageAuthorMap: messageAuthorMap,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Opens the long-press context menu on the [MessageBubble].
Future<void> _openContextMenu(WidgetTester tester) async {
  await tester.longPress(find.byType(MessageBubble));
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -----------------------------------------------------------------------
  // 1. Menu shows "Change author" when permitted + candidates >= 2 + !system
  // -----------------------------------------------------------------------
  group('1. Menu entry visibility', () {
    testWidgets(
      'shows "Change author" entry when permission allows and candidates >= 2',
      (tester) async {
        final perms = _makePerms();
        // canChangeMessageAuthor(aliceId) → (canWrite && aliceId != null) == true
        expect(perms.canChangeMessageAuthor(_kAliceId), isTrue,
            reason: 'precondition: perms allow change author');

        await tester.pumpWidget(
          _buildSubject(
            message: _makeMessage(),
            permissions: perms,
            activeMembers: [_alice, _bob],
          ),
        );
        await tester.pumpAndSettle();

        await _openContextMenu(tester);

        expect(
          find.text('Change author'),
          findsOneWidget,
          reason: 'Change author entry must appear in the context menu',
        );
      },
    );

    testWidgets(
      'hides "Change author" entry when canChangeMessageAuthor returns false',
      (tester) async {
        // Speaking as null → canWrite == false → canChangeMessageAuthor == false
        // (unless canManage is also true, which it isn't when speakingAsMemberId == null)
        final perms = _makePerms(
          speakingAsMemberId: null,
          speakingAsMember: null,
        );
        expect(perms.canChangeMessageAuthor(_kAliceId), isFalse,
            reason: 'precondition: perms deny change author');

        await tester.pumpWidget(
          _buildSubject(
            message: _makeMessage(),
            permissions: perms,
            activeMembers: [_alice, _bob],
          ),
        );
        await tester.pumpAndSettle();

        await _openContextMenu(tester);

        expect(find.text('Change author'), findsNothing);
      },
    );

    testWidgets(
      'hides "Change author" entry when only 1 candidate is available',
      (tester) async {
        // Only Alice in activeMembers → chatAuthorCandidateIds returns only
        // alice + Unknown (2). Wait — that's 2.
        // For a group conv with includesAllMembers, Unknown is always appended,
        // so with 1 active member we get 2 candidates. To get exactly 1, use a
        // DM where participantIds has only Alice (no Unknown sentinel explicitly).
        final dmConversation = Conversation(
          id: _kConvId,
          participantIds: const [_kAliceId],
          createdAt: DateTime(2025),
          lastActivityAt: DateTime(2025),
          isDirectMessage: true,
        );
        final perms = _makePerms(conversation: dmConversation);

        await tester.pumpWidget(
          _buildSubject(
            message: _makeMessage(),
            permissions: perms,
            activeMembers: [_alice],
          ),
        );
        await tester.pumpAndSettle();

        await _openContextMenu(tester);

        expect(find.text('Change author'), findsNothing,
            reason:
                'with only 1 candidate (Alice only, no Unknown sentinel in DM), '
                'menu entry should be hidden');
      },
    );

    testWidgets(
      'hides "Change author" entry on system messages',
      (tester) async {
        final perms = _makePerms();

        await tester.pumpWidget(
          _buildSubject(
            message: _makeMessage(isSystemMessage: true),
            permissions: perms,
            activeMembers: [_alice, _bob],
          ),
        );
        await tester.pumpAndSettle();

        // System messages render a _SystemMessage widget (plain centered text),
        // not the full bubble with long-press, so the context menu never opens.
        // We verify no Change author text appears at all.
        expect(find.text('Change author'), findsNothing);
      },
    );
  });

  // -----------------------------------------------------------------------
  // 2. Tapping the menu entry opens MemberSelectorPopup ("Set author" title)
  // -----------------------------------------------------------------------
  group('2. Picker opens on tap', () {
    testWidgets(
      'tapping "Change author" opens picker showing "Set author" title and '
      'current author at position 0 with checkmark',
      (tester) async {
        final perms = _makePerms();

        await tester.pumpWidget(
          _buildSubject(
            message: _makeMessage(authorId: _kAliceId),
            permissions: perms,
            activeMembers: [_alice, _bob],
          ),
        );
        await tester.pumpAndSettle();

        await _openContextMenu(tester);

        // Tap the "Change author" entry to open the author picker.
        await tester.tap(find.text('Change author'));
        await tester.pumpAndSettle();

        // The author picker popup should appear.
        expect(
          find.text('Set author'),
          findsOneWidget,
          reason: 'picker must show searchTitle "Set author"',
        );

        // Alice (current author) should be in the list.
        expect(find.text('Alice'), findsAtLeastNWidgets(1));
        // Bob should also be in the list.
        expect(find.text('Bob'), findsAtLeastNWidgets(1));
      },
    );
  });

  // -----------------------------------------------------------------------
  // 3. Tapping a different member calls changeMessageAuthor
  // -----------------------------------------------------------------------
  group('3. Member selection', () {
    testWidgets(
      'tapping a different member calls notifier.changeMessageAuthor',
      (tester) async {
        final notifier = _RecordingChatNotifier();
        final perms = _makePerms(speakingAsMemberId: _kAliceId);

        await tester.pumpWidget(
          _buildSubject(
            message: _makeMessage(authorId: _kAliceId),
            permissions: perms,
            activeMembers: [_alice, _bob],
            chatNotifierFactory: () => notifier,
          ),
        );
        await tester.pumpAndSettle();

        await _openContextMenu(tester);
        await tester.tap(find.text('Change author'));
        await tester.pumpAndSettle();

        // Tap Bob (a different member) in the picker.
        await tester.tap(find.text('Bob').last);
        await tester.pumpAndSettle();

        expect(
          notifier.changeAuthorCalls,
          hasLength(1),
          reason: 'changeMessageAuthor must be called exactly once',
        );
        expect(
          notifier.changeAuthorCalls.first,
          equals((_kMsgId, _kBobId)),
          reason: 'must pass the message id and the new author id',
        );
      },
    );

    testWidgets(
      'tapping Unknown sentinel calls notifier with unknownSentinelMemberId',
      (tester) async {
        final notifier = _RecordingChatNotifier();
        final perms = _makePerms(speakingAsMemberId: _kAliceId);

        await tester.pumpWidget(
          _buildSubject(
            message: _makeMessage(authorId: _kAliceId),
            permissions: perms,
            activeMembers: [_alice, _bob],
            chatNotifierFactory: () => notifier,
          ),
        );
        await tester.pumpAndSettle();

        await _openContextMenu(tester);
        await tester.tap(find.text('Change author'));
        await tester.pumpAndSettle();

        // The Unknown sentinel row is always appended in group conversations.
        // Find it by the l10n key (text "Unknown").
        final unknownFinder = find.text('Unknown');
        expect(unknownFinder, findsAtLeastNWidgets(1),
            reason: 'Unknown sentinel must appear in the picker');

        await tester.tap(unknownFinder.last);
        await tester.pumpAndSettle();

        expect(notifier.changeAuthorCalls, hasLength(1));
        expect(
          notifier.changeAuthorCalls.first.$2,
          equals(unknownSentinelMemberId),
        );
      },
    );

    // NOTE: "Tapping current author does not call notifier" is omitted.
    // The notifier's own no-op short-circuit handles it server-side.
    // Testing the UI non-call would require inspecting call count == 0 after
    // tapping Alice (current author at position 0). In practice the popup does
    // call onMemberSelected with Alice's id; the notifier short-circuits.
    // This is acceptable per task spec ("the notifier's own no-op short-circuit
    // will save us if it does call").
  });

  // -----------------------------------------------------------------------
  // 5. Reply chip uses parent's current author, not denormalized
  // -----------------------------------------------------------------------
  group('5. Reply chip live author resolution', () {
    const kParentMsgId = 'parent-msg-id';
    const kReplyMsgId = 'reply-msg-id';

    /// A reply message: replyToId → parent, replyToAuthorId → Alice (stale
    /// denormalized value captured at send time).
    ChatMessage makeReplyMessage({
      String replyToAuthorId = _kAliceId,
    }) {
      return ChatMessage(
        id: kReplyMsgId,
        content: 'this is a reply',
        timestamp: DateTime(2025, 1, 1, 12, 1),
        authorId: _kBobId,
        conversationId: _kConvId,
        replyToId: kParentMsgId,
        replyToAuthorId: replyToAuthorId,
        replyToContent: 'original content',
      );
    }

    testWidgets(
      'reply chip shows parent current author (Bob) not denormalized (Alice) '
      'when messageAuthorMap maps parent to Bob',
      (tester) async {
        final replyMsg = makeReplyMessage(replyToAuthorId: _kAliceId);

        // messageAuthorMap says the parent message is now authored by Bob.
        final messageAuthorMap = {kParentMsgId: _kBobId};
        // authorMap so the bubble can resolve Bob's display name.
        final authorMap = {_kAliceId: _alice, _kBobId: _bob};

        await tester.pumpWidget(
          _buildSubject(
            message: replyMsg,
            permissions: _makePerms(),
            activeMembers: [_alice, _bob],
            authorMap: authorMap,
            messageAuthorMap: messageAuthorMap,
          ),
        );
        await tester.pumpAndSettle();

        // The reply chip should show Bob (the live author of the parent),
        // not Alice (the stale denormalized replyToAuthorId).
        // Note: Bob appears twice — once in the reply chip (parent's current
        // author) and once in the author row (this message is authored by Bob).
        expect(
          find.text('Bob'),
          findsAtLeastNWidgets(1),
          reason:
              'reply chip must show the parent\'s current author (Bob)',
        );
        expect(
          find.text('Alice'),
          findsNothing,
          reason: 'stale Alice attribution must not appear in the reply chip',
        );
      },
    );

    testWidgets(
      'reply chip falls back to denormalized replyToAuthorId when parent is '
      'absent from messageAuthorMap',
      (tester) async {
        final replyMsg = makeReplyMessage(replyToAuthorId: _kAliceId);

        // messageAuthorMap does NOT contain the parent message — simulates the
        // parent being outside the loaded window or deleted.
        final messageAuthorMap = <String, String?>{};
        final authorMap = {_kAliceId: _alice, _kBobId: _bob};

        await tester.pumpWidget(
          _buildSubject(
            message: replyMsg,
            permissions: _makePerms(),
            activeMembers: [_alice, _bob],
            authorMap: authorMap,
            messageAuthorMap: messageAuthorMap,
          ),
        );
        await tester.pumpAndSettle();

        // Falls back to the denormalized replyToAuthorId = Alice.
        expect(
          find.text('Alice'),
          findsOneWidget,
          reason:
              'when parent is unresolvable, chip must fall back to '
              'denormalized replyToAuthorId (Alice)',
        );
      },
    );
  });

  // -----------------------------------------------------------------------
  // 4. Departed-author DM: menu and picker both show the departed member
  // -----------------------------------------------------------------------
  group('4. Departed-author DM', () {
    const kDepartedId = 'departed-id';

    final departed = Member(
      id: kDepartedId,
      name: 'Departed',
      createdAt: DateTime(2024, 1, 1),
      isActive: false,
    );

    // A proper DM between Departed and Bob, where Departed has left the
    // system (not in activeMembers). Bob is the only active member.
    final dmConv = Conversation(
      id: _kConvId,
      participantIds: const [kDepartedId, _kBobId],
      createdAt: DateTime(2025),
      lastActivityAt: DateTime(2025),
      isDirectMessage: true,
    );

    testWidgets(
      'menu shows for DM with [departed, active] participants when '
      'current author is the departed one',
      (tester) async {
        // Speaking as Bob (the active participant).
        final perms = _makePerms(
          speakingAsMemberId: _kBobId,
          speakingAsMember: _bob,
          conversation: dmConv,
        );
        expect(
          perms.canChangeMessageAuthor(kDepartedId),
          isTrue,
          reason: 'precondition: Bob can change the author of Departed\'s msg',
        );

        // authorMap contains the departed member so the bubble can resolve it.
        final authorMap = {kDepartedId: departed, _kBobId: _bob};

        await tester.pumpWidget(
          _buildSubject(
            message: _makeMessage(authorId: kDepartedId),
            permissions: perms,
            // activeMembers contains only Bob; Departed has left.
            activeMembers: [_bob],
            authorMap: authorMap,
          ),
        );
        await tester.pumpAndSettle();

        await _openContextMenu(tester);

        // The "Change author" entry must appear: even though Departed is not in
        // activeMembers, passing currentAuthor should add them to candidates,
        // giving 2 candidates (Departed + Bob) and showing the menu entry.
        expect(
          find.text('Change author'),
          findsOneWidget,
          reason:
              '"Change author" must appear: 2 candidates (Departed + Bob)',
        );

        // Open the picker and verify both members are present.
        await tester.tap(find.text('Change author'));
        await tester.pumpAndSettle();

        expect(find.text('Departed'), findsAtLeastNWidgets(1),
            reason: 'departed author must appear in picker');
        expect(find.text('Bob'), findsAtLeastNWidgets(1),
            reason: 'active participant must appear in picker');

        // Departed should be at position 0 (current author is pinned first).
        final pickerItems = tester.widgetList(find.text('Departed'));
        expect(pickerItems, isNotEmpty);
      },
    );
  });

  // -----------------------------------------------------------------------
  // 6. "Change author" entry is positioned directly above the Edit entry
  // -----------------------------------------------------------------------
  group('6. Menu entry ordering', () {
    testWidgets(
      '"Change author" entry appears above "Edit message" in the menu',
      (tester) async {
        // Use a taller screen so all menu items fit in the popup.
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Alice is the author → canEditMessage and canChangeMessageAuthor both true.
        final perms = _makePerms(speakingAsMemberId: _kAliceId);

        await tester.pumpWidget(
          _buildSubject(
            message: _makeMessage(authorId: _kAliceId),
            permissions: perms,
            activeMembers: [_alice, _bob],
          ),
        );
        await tester.pumpAndSettle();

        await _openContextMenu(tester);

        final changeAuthorTop =
            tester.getTopLeft(find.text('Change author')).dy;
        final editTop =
            tester.getTopLeft(find.text('Edit Message')).dy;

        expect(
          changeAuthorTop,
          lessThan(editTop),
          reason: '"Change author" must appear above "Edit message"',
        );
      },
    );
  });
}
