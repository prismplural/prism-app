import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/chat_message.dart';
import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/conversation_category.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/repositories/chat_message_repository.dart';
import 'package:prism_plurality/features/chat/providers/category_providers.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/views/conversation_info_sheet.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';

import '../../../helpers/fake_repositories.dart';

class _FixedSpeakingAsNotifier extends SpeakingAsNotifier {
  @override
  String? build() => 'alice';
}

/// Counts route pops. The black-screen bug was one Navigator.pop() *per* tap of
/// the archive action: a spam-tap fired several pops in a row, punching past the
/// sheet into the app root → black, frozen screen. The per-member archive write
/// is idempotent, so pops — not writes — are the faithful signal.
class _PopCountingObserver extends NavigatorObserver {
  int popCount = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount += 1;
    super.didPop(route, previousRoute);
  }
}

/// Holds the first archive mutation open on [gate] so the test can land a burst
/// of taps on the still-present row *before* anything pops — the on-device
/// timing (slow mutation, impatient user) the deterministic fake otherwise hides.
class _GatedArchiveRepository extends FakeConversationRepository {
  final Completer<void> gate = Completer<void>();
  bool _gated = false;

  @override
  Future<Conversation?> getConversationById(String id) async {
    if (!_gated) {
      _gated = true;
      await gate.future;
    }
    return super.getConversationById(id);
  }
}

/// A throwaway route to sit *underneath* the info sheet so the test can confirm
/// the sheet was actually presented as a modal route (and dismissed once).
class _ChatPageStub extends StatelessWidget {
  const _ChatPageStub();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => ConversationInfoSheet.show(context, 'conv-1'),
          child: const Text('open info'),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('category assignment opens a dialog from conversation info', (
    tester,
  ) async {
    final now = DateTime(2026, 5, 9);
    final conversationRepo = FakeConversationRepository()
      ..conversations.add(
        Conversation(
          id: 'conv-1',
          createdAt: now,
          lastActivityAt: now,
          title: 'General',
          creatorId: 'alice',
          participantIds: const ['alice', 'bob'],
        ),
      );
    final memberRepo = FakeMemberRepository()
      ..seed([
        Member(id: 'alice', name: 'Alice', createdAt: now),
        Member(id: 'bob', name: 'Bob', createdAt: now),
      ]);
    final category = ConversationCategory(
      id: 'fandoms',
      name: 'Fandoms',
      displayOrder: 0,
      createdAt: now,
      modifiedAt: now,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conversationRepositoryProvider.overrideWithValue(conversationRepo),
          memberRepositoryProvider.overrideWithValue(memberRepo),
          speakingAsProvider.overrideWith(_FixedSpeakingAsNotifier.new),
          activeMembersProvider.overrideWithValue(
            AsyncValue.data(await memberRepo.getAllMembers()),
          ),
          activeSessionsProvider.overrideWithValue(
            const AsyncValue.data(<FrontingSession>[]),
          ),
          allGroupsProvider.overrideWith(
            (ref) => Stream.value(const <MemberGroup>[]),
          ),
          allGroupEntriesProvider.overrideWith(
            (ref) => Stream.value(const <MemberGroupEntry>[]),
          ),
          conversationCategoriesProvider.overrideWith(
            (ref) => Stream.value([category]),
          ),
          systemSettingsProvider.overrideWith(
            (ref) => Stream.value(const SystemSettings()),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          home: Scaffold(
            body: ConversationInfoSheet(
              conversationId: 'conv-1',
              scrollController: ScrollController(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Category'));
    await tester.pumpAndSettle();

    expect(find.byType(PrismDialog), findsOneWidget);
    expect(find.text('Fandoms'), findsOneWidget);

    await tester.tap(find.text('Fandoms'));
    await tester.pumpAndSettle();

    expect(find.byType(PrismDialog), findsNothing);
    expect(conversationRepo.conversations.single.categoryId, 'fandoms');
  });

  testWidgets(
    'spam-tapping archive dismisses only the sheet, never the route beneath',
    (tester) async {
      // Reproduce the phone layout (narrow → modal bottom sheet path) where the
      // black-screen-on-spam-archive report came from.
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime(2026, 6, 9);
      final popObserver = _PopCountingObserver();
      final conversationRepo = _GatedArchiveRepository()
        ..conversations.add(
          Conversation(
            id: 'conv-1',
            createdAt: now,
            lastActivityAt: now,
            title: 'General',
            creatorId: 'alice',
            participantIds: const ['alice', 'bob'],
          ),
        );
      final memberRepo = FakeMemberRepository()
        ..seed([
          Member(id: 'alice', name: 'Alice', createdAt: now),
          Member(id: 'bob', name: 'Bob', createdAt: now),
        ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            conversationRepositoryProvider.overrideWithValue(conversationRepo),
            chatMessageRepositoryProvider.overrideWithValue(
              _FakeChatMessageRepository(),
            ),
            memberRepositoryProvider.overrideWithValue(memberRepo),
            speakingAsProvider.overrideWith(_FixedSpeakingAsNotifier.new),
            activeMembersProvider.overrideWithValue(
              AsyncValue.data(await memberRepo.getAllMembers()),
            ),
            activeSessionsProvider.overrideWithValue(
              const AsyncValue.data(<FrontingSession>[]),
            ),
            allGroupsProvider.overrideWith(
              (ref) => Stream.value(const <MemberGroup>[]),
            ),
            allGroupEntriesProvider.overrideWith(
              (ref) => Stream.value(const <MemberGroupEntry>[]),
            ),
            conversationCategoriesProvider.overrideWith(
              (ref) => Stream.value(const <ConversationCategory>[]),
            ),
            systemSettingsProvider.overrideWith(
              (ref) => Stream.value(const SystemSettings()),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            navigatorObservers: [popObserver],
            home: const _ChatPageStub(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('open info'));
      await tester.pumpAndSettle();
      expect(find.byType(ConversationInfoSheet), findsOneWidget);
      popObserver.popCount = 0; // ignore the pop from any prior settle

      final archiveRow = find.text('Archive conversation');
      await tester.ensureVisible(archiveRow);
      await tester.pumpAndSettle();
      expect(archiveRow, findsOneWidget);

      // The first mutation is held open on the gate, so nothing pops during the
      // burst and every tap lands on the still-present row.
      for (var i = 0; i < 6; i++) {
        await tester.tap(archiveRow, warnIfMissed: false);
      }
      await tester.pump(); // let all six handlers enter and park

      // Release the mutation and drain the serialized pool with zero-duration
      // pumps, so every queued handler reaches its pop() while the dismiss
      // animation is frozen at t=0 (sheet still mounted) — the window where the
      // extra pops punch through the routes beneath.
      conversationRepo.gate.complete();
      for (var i = 0; i < 20; i++) {
        await tester.pump(Duration.zero);
      }

      expect(
        popObserver.popCount,
        1,
        reason: 'the re-entry guard must collapse a spam-tap to a single pop; '
            'extra pops punch past the sheet into the app root → black screen',
      );

      // Let everything settle and drain PrismToast's auto-dismiss timer so it
      // doesn't trip the pending-timer invariant at teardown.
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));

      expect(
        conversationRepo.conversations.single.archivedByMemberIds,
        ['alice'],
        reason: 'the conversation is archived for the speaking-as member',
      );
      expect(
        find.byType(ConversationInfoSheet),
        findsNothing,
        reason: 'the sheet should dismiss',
      );
      expect(
        find.text('open info'),
        findsOneWidget,
        reason: 'the route beneath the sheet must survive',
      );
    },
  );

  testWidgets(
    'co-fronting admin can transfer group ownership from conversation info',
    (tester) async {
      final now = DateTime(2026, 5, 15);
      final conversationRepo = FakeConversationRepository()
        ..conversations.add(
          Conversation(
            id: 'conv-1',
            createdAt: now,
            lastActivityAt: now,
            title: 'General',
            creatorId: 'alice',
            participantIds: const ['alice', 'bob', 'carol'],
          ),
        );
      final memberRepo = FakeMemberRepository()
        ..seed([
          Member(id: 'alice', name: 'Alice', createdAt: now),
          Member(id: 'bob', name: 'Bob', createdAt: now, isAdmin: true),
          Member(id: 'carol', name: 'Carol', createdAt: now),
        ]);
      final messages = _FakeChatMessageRepository();
      final activeMembers = await memberRepo.getAllMembers();
      final activeFronts = [
        FrontingSession(id: 'front-bob', startTime: now, memberId: 'bob'),
        FrontingSession(id: 'front-carol', startTime: now, memberId: 'carol'),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            conversationRepositoryProvider.overrideWithValue(conversationRepo),
            chatMessageRepositoryProvider.overrideWithValue(messages),
            memberRepositoryProvider.overrideWithValue(memberRepo),
            activeMembersProvider.overrideWithValue(
              AsyncValue.data(activeMembers),
            ),
            activeSessionsProvider.overrideWithValue(
              AsyncValue.data(activeFronts),
            ),
            allGroupsProvider.overrideWith(
              (ref) => Stream.value(const <MemberGroup>[]),
            ),
            allGroupEntriesProvider.overrideWith(
              (ref) => Stream.value(const <MemberGroupEntry>[]),
            ),
            conversationCategoriesProvider.overrideWith(
              (ref) => Stream.value(const <ConversationCategory>[]),
            ),
            systemSettingsProvider.overrideWith(
              (ref) => Stream.value(const SystemSettings()),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            home: Scaffold(
              body: ConversationInfoSheet(
                conversationId: 'conv-1',
                scrollController: ScrollController(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final ownerRow = find.byKey(const ValueKey('conversation-owner-row'));
      expect(ownerRow, findsNothing);

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(ownerRow, findsOneWidget);

      await tester.tap(ownerRow);
      await tester.pumpAndSettle();

      expect(find.byType(MemberSearchSheet), findsOneWidget);
      final picker = find.byType(MemberSearchSheet);
      expect(
        find.descendant(of: picker, matching: find.text('Alice')),
        findsNothing,
      );
      expect(
        find.descendant(of: picker, matching: find.text('Bob')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: picker, matching: find.text('Carol')),
        findsOneWidget,
      );

      await tester.tap(
        find.descendant(of: picker, matching: find.text('Carol')),
      );
      await tester.pumpAndSettle();

      expect(conversationRepo.conversations.single.creatorId, 'carol');
      expect(messages.messages.single.content, contains('Carol'));
    },
  );

  testWidgets('include-everyone toggle is only shown in edit mode', (
    tester,
  ) async {
    final now = DateTime(2026, 5, 15);
    final conversationRepo = FakeConversationRepository()
      ..conversations.add(
        Conversation(
          id: 'conv-1',
          createdAt: now,
          lastActivityAt: now,
          title: 'General',
          creatorId: 'alice',
          participantIds: const ['alice', 'bob'],
        ),
      );
    final memberRepo = FakeMemberRepository()
      ..seed([
        Member(id: 'alice', name: 'Alice', createdAt: now),
        Member(id: 'bob', name: 'Bob', createdAt: now),
      ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conversationRepositoryProvider.overrideWithValue(conversationRepo),
          chatMessageRepositoryProvider.overrideWithValue(
            _FakeChatMessageRepository(),
          ),
          memberRepositoryProvider.overrideWithValue(memberRepo),
          speakingAsProvider.overrideWith(_FixedSpeakingAsNotifier.new),
          activeMembersProvider.overrideWithValue(
            AsyncValue.data(await memberRepo.getAllMembers()),
          ),
          activeSessionsProvider.overrideWithValue(
            AsyncValue.data([
              FrontingSession(
                id: 'front-alice',
                startTime: now,
                memberId: 'alice',
              ),
            ]),
          ),
          allGroupsProvider.overrideWith(
            (ref) => Stream.value(const <MemberGroup>[]),
          ),
          allGroupEntriesProvider.overrideWith(
            (ref) => Stream.value(const <MemberGroupEntry>[]),
          ),
          conversationCategoriesProvider.overrideWith(
            (ref) => Stream.value(const <ConversationCategory>[]),
          ),
          systemSettingsProvider.overrideWith(
            (ref) => Stream.value(const SystemSettings()),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          home: Scaffold(
            body: ConversationInfoSheet(
              conversationId: 'conv-1',
              scrollController: ScrollController(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Include everyone'), findsNothing);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Include everyone'), findsOneWidget);
  });

  testWidgets(
    'everyone-group owner transfer does not count Unknown as a candidate',
    (tester) async {
      final now = DateTime(2026, 5, 15);
      final unknown = Member(
        id: unknownSentinelMemberId,
        name: 'Unknown',
        createdAt: now,
      );
      final conversationRepo = FakeConversationRepository()
        ..conversations.add(
          Conversation(
            id: 'everyone-1',
            createdAt: now,
            lastActivityAt: now,
            title: 'Everyone',
            creatorId: 'alice',
            participantIds: const ['alice'],
            includesAllMembers: true,
          ),
        );
      final memberRepo = FakeMemberRepository()
        ..seed([Member(id: 'alice', name: 'Alice', createdAt: now), unknown]);
      final activeMembers = await memberRepo.getAllMembers();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            conversationRepositoryProvider.overrideWithValue(conversationRepo),
            chatMessageRepositoryProvider.overrideWithValue(
              _FakeChatMessageRepository(),
            ),
            memberRepositoryProvider.overrideWithValue(memberRepo),
            speakingAsProvider.overrideWith(_FixedSpeakingAsNotifier.new),
            activeMembersProvider.overrideWithValue(
              AsyncValue.data(activeMembers),
            ),
            activeSessionsProvider.overrideWithValue(
              AsyncValue.data([
                FrontingSession(
                  id: 'front-alice',
                  startTime: now,
                  memberId: 'alice',
                ),
              ]),
            ),
            allGroupsProvider.overrideWith(
              (ref) => Stream.value(const <MemberGroup>[]),
            ),
            allGroupEntriesProvider.overrideWith(
              (ref) => Stream.value(const <MemberGroupEntry>[]),
            ),
            conversationCategoriesProvider.overrideWith(
              (ref) => Stream.value(const <ConversationCategory>[]),
            ),
            systemSettingsProvider.overrideWith(
              (ref) => Stream.value(const SystemSettings()),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            home: Scaffold(
              body: ConversationInfoSheet(
                conversationId: 'everyone-1',
                scrollController: ScrollController(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('conversation-owner-row')),
        findsNothing,
        reason: 'Unknown must not make the owner-transfer affordance appear.',
      );
    },
  );

  testWidgets('everyone-group owner transfer picker hides Unknown', (
    tester,
  ) async {
    final now = DateTime(2026, 5, 15);
    final unknown = Member(
      id: unknownSentinelMemberId,
      name: 'Unknown',
      createdAt: now,
    );
    final conversationRepo = FakeConversationRepository()
      ..conversations.add(
        Conversation(
          id: 'everyone-1',
          createdAt: now,
          lastActivityAt: now,
          title: 'Everyone',
          creatorId: 'alice',
          participantIds: const ['alice'],
          includesAllMembers: true,
        ),
      );
    final memberRepo = FakeMemberRepository()
      ..seed([
        Member(id: 'alice', name: 'Alice', createdAt: now),
        Member(id: 'bob', name: 'Bob', createdAt: now),
        unknown,
      ]);
    final activeMembers = await memberRepo.getAllMembers();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conversationRepositoryProvider.overrideWithValue(conversationRepo),
          chatMessageRepositoryProvider.overrideWithValue(
            _FakeChatMessageRepository(),
          ),
          memberRepositoryProvider.overrideWithValue(memberRepo),
          speakingAsProvider.overrideWith(_FixedSpeakingAsNotifier.new),
          activeMembersProvider.overrideWithValue(
            AsyncValue.data(activeMembers),
          ),
          activeSessionsProvider.overrideWithValue(
            AsyncValue.data([
              FrontingSession(
                id: 'front-alice',
                startTime: now,
                memberId: 'alice',
              ),
            ]),
          ),
          allGroupsProvider.overrideWith(
            (ref) => Stream.value(const <MemberGroup>[]),
          ),
          allGroupEntriesProvider.overrideWith(
            (ref) => Stream.value(const <MemberGroupEntry>[]),
          ),
          conversationCategoriesProvider.overrideWith(
            (ref) => Stream.value(const <ConversationCategory>[]),
          ),
          systemSettingsProvider.overrideWith(
            (ref) => Stream.value(const SystemSettings()),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          home: Scaffold(
            body: ConversationInfoSheet(
              conversationId: 'everyone-1',
              scrollController: ScrollController(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('conversation-owner-row')));
    await tester.pumpAndSettle();

    final picker = find.byType(MemberSearchSheet);
    expect(picker, findsOneWidget);
    expect(
      find.descendant(of: picker, matching: find.text('Bob')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: picker, matching: find.text('Unknown')),
      findsNothing,
    );
  });
}

class _FakeChatMessageRepository implements ChatMessageRepository {
  final messages = <ChatMessage>[];

  @override
  Future<void> createMessage(ChatMessage message) async {
    messages.add(message);
  }

  @override
  Future<void> deleteMessage(String id) async {}

  @override
  Future<List<ChatMessage>> getAllMessages() async => messages;

  @override
  Future<ChatMessage?> getLatestMessage(String conversationId) async => null;

  @override
  Future<ChatMessage?> getMessageById(String id) async => null;

  @override
  Future<bool> isMessageDeleted(String messageId) async => false;

  @override
  Future<List<ChatMessage>> getMessagesForConversation(
    String conversationId, {
    int? limit,
    int? offset,
  }) async => const [];

  @override
  Future<
    List<
      ({
        String? authorId,
        String conversationId,
        String messageId,
        String snippet,
        DateTime timestamp,
      })
    >
  >
  searchMessages(String query, {int limit = 20}) async => const [];

  @override
  Future<void> updateMessage(ChatMessage message) async {}

  @override
  Stream<Map<String, int>> watchAllUnreadCounts(
    Map<String, DateTime> conversationSince,
  ) => Stream.value(const {});

  @override
  Stream<Set<String>> watchConversationsWithMentions(
    Map<String, DateTime> conversationSince,
    String memberId,
  ) => Stream.value(const {});

  @override
  Stream<ChatMessage?> watchLatestMessage(String conversationId) =>
      Stream.value(null);

  @override
  Stream<List<ChatMessage>> watchMessagesForConversation(
    String conversationId,
  ) => Stream.value(const []);

  @override
  Stream<List<ChatMessage>> watchRecentMessages(
    String conversationId, {
    required int limit,
  }) => Stream.value(const []);

  @override
  Stream<int> watchUnreadCount(String conversationId, DateTime since) =>
      Stream.value(0);

  @override
  Stream<int> watchUnreadMentionCount(
    String conversationId,
    DateTime since,
    String memberId,
  ) => Stream.value(0);
}
