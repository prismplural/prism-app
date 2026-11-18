// The chat list's pinned header: `_ChatTopBar` is a `PrismTopBar` plus the
// segmented tab switcher, and `SliverPinnedTopBar` sizes the band from that
// measurement, so both children keep the text size the user asked for and the band
// is exactly their height instead of a constant.
//
// Desired behaviour, asserted on the real `ChatScreen` with the repo's fake
// repositories: the pinned band is sized from the same measurements its
// children use, both children are painted at their requested text size inside
// the band, and the band re-measures when the text scale changes.
//
// The switcher's own label geometry inside its track is covered by the
// segmented-control tests; this file covers the band's extent and the title.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/domain/models/chat_message.dart' as domain;
import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/repositories/chat_message_repository.dart';
import 'package:prism_plurality/features/chat/providers/category_providers.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/views/chat_screen.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

import '../../helpers/fake_repositories.dart';
import 'chrome_text_scale_harness.dart';

class _TestSpeakingAsNotifier extends SpeakingAsNotifier {
  _TestSpeakingAsNotifier(this._memberId);

  final String? _memberId;

  @override
  String? build() => _memberId;

  @override
  void setMember(String? memberId, {bool recordLastUsed = true}) {
    state = memberId;
  }
}

class _EmptyChatMessageRepository implements ChatMessageRepository {
  @override
  Future<void> createMessage(domain.ChatMessage message) async {}

  @override
  Future<void> deleteMessage(String id) async {}

  @override
  Future<List<domain.ChatMessage>> getAllMessages() async => [];

  @override
  Future<domain.ChatMessage?> getLatestMessage(String conversationId) async =>
      null;

  @override
  Future<domain.ChatMessage?> getMessageById(String id) async => null;

  @override
  Future<bool> isMessageDeleted(String messageId) async => false;

  @override
  Future<List<domain.ChatMessage>> getMessagesForConversation(
    String conversationId, {
    int? limit,
    int? offset,
  }) async => [];

  @override
  Future<
    List<
      ({
        String messageId,
        String conversationId,
        String snippet,
        DateTime timestamp,
        String? authorId,
      })
    >
  >
  searchMessages(String query, {int limit = 50}) async => [];

  @override
  Future<void> updateMessage(domain.ChatMessage message) async {}

  @override
  Stream<Map<String, int>> watchAllUnreadCounts(
    Map<String, DateTime> conversationSince,
  ) => Stream.value({});

  @override
  Stream<Set<String>> watchConversationsWithMentions(
    Map<String, DateTime> conversationSince,
    String memberId,
  ) => Stream.value({});

  @override
  Stream<domain.ChatMessage?> watchLatestMessage(String conversationId) =>
      Stream.value(null);

  @override
  Stream<List<domain.ChatMessage>> watchMessagesForConversation(
    String conversationId,
  ) => Stream.value([]);

  @override
  Stream<List<domain.ChatMessage>> watchRecentMessages(
    String conversationId, {
    required int limit,
  }) => Stream.value([]);

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

Member _member(String id, String name) =>
    Member(id: id, name: name, createdAt: DateTime(2026, 5, 8));

Widget _subject({
  required double system,
  required double app,
  int groupUnread = 0,
  int dmUnread = 0,
  String fontFamily = 'Lexend',
}) {
  SharedPreferences.setMockInitialValues({});
  final now = DateTime(2026, 5, 8, 12);
  final alice = _member('alice', 'Alice');
  final bob = _member('bob', 'Bob');
  final members = FakeMemberRepository()..seed([alice, bob]);
  final conversations = FakeConversationRepository()
    ..conversations.addAll([
      Conversation(
        id: 'dm-1',
        createdAt: now,
        lastActivityAt: now,
        participantIds: const ['alice', 'bob'],
        isDirectMessage: true,
      ),
      Conversation(
        id: 'group-1',
        createdAt: now.subtract(const Duration(minutes: 1)),
        lastActivityAt: now.subtract(const Duration(minutes: 1)),
        participantIds: const ['alice', 'bob'],
        title: 'Planning',
      ),
    ]);

  return ProviderScope(
    overrides: [
      memberRepositoryProvider.overrideWithValue(members),
      conversationRepositoryProvider.overrideWithValue(conversations),
      chatMessageRepositoryProvider.overrideWithValue(
        _EmptyChatMessageRepository(),
      ),
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(const SystemSettings()),
      ),
      currentChatViewerProvider.overrideWithValue(alice),
      speakingAsProvider.overrideWith(() => _TestSpeakingAsNotifier('alice')),
      conversationCategoriesProvider.overrideWith((ref) => Stream.value([])),
      allGroupsProvider.overrideWith(
        (ref) => Stream.value(const <MemberGroup>[]),
      ),
      allGroupEntriesProvider.overrideWith(
        (ref) => Stream.value(const <MemberGroupEntry>[]),
      ),
      unreadDmCountProvider.overrideWithValue(dmUnread),
      unreadGroupCountProvider.overrideWithValue(groupUnread),
    ],
    child: chromeApp(
      const ChatScreen(),
      system: system,
      app: app,
      fontFamily: fontFamily,
    ),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadChromeFonts();
  });

  for (final (system, app, label) in chromeScales) {
    testWidgets('chat pinned header contains its bar and switcher ($label)', (
      tester,
    ) async {
      useWindow(tester, compactPhone);
      await tester.pumpWidget(_subject(system: system, app: app));
      await tester.pumpAndSettle();

      final barRect = tester.getRect(find.byType(PrismTopBar));
      // `_ChatSubTab` is private, so the generic control is matched by type test.
      final switcher = find.byWidgetPredicate(
        (w) => w is PrismSegmentedControl,
      );
      expect(switcher, findsOneWidget);
      final switcherRect = tester.getRect(switcher);
      final titleRect = expectFullSizeText(
        tester,
        'Chat',
        label: label,
        container: barRect,
      );

      expect(
        switcherRect.top,
        greaterThanOrEqualTo(barRect.bottom - 0.5),
        reason: '$label: the switcher must sit below the top bar, not over it',
      );
      expect(
        titleRect.bottom,
        lessThanOrEqualTo(switcherRect.top + 0.5),
        reason: '$label: the title must not be pushed into the switcher',
      );

      // The band's own extent, from the pinned sliver: the chat list may put a
      // visibility banner or a section header above the first conversation, so
      // the first tile is not a band marker.
      final bandBottom = barRect.top + pinnedBandHeight(tester);
      expect(
        switcherRect.bottom,
        lessThanOrEqualTo(bandBottom + 0.5),
        reason:
            '$label: the switcher (bottom ${switcherRect.bottom.toStringAsFixed(1)}) '
            'is clipped by the pinned band (bottom ${bandBottom.toStringAsFixed(1)})',
      );
      // The band must be exactly the height its children paint: bar + 8 + track
      // + 8. If the switcher reports less than it renders, the band is short and
      // the track is clipped; if the header over-reserves, this catches the gap.
      expect(
        bandBottom,
        closeTo(barRect.height + 16 + switcherRect.height, 0.5),
        reason:
            '$label: the pinned band (${bandBottom.toStringAsFixed(1)}) must equal '
            'bar (${barRect.height.toStringAsFixed(1)}) + padding (16) + switcher '
            '(${switcherRect.height.toStringAsFixed(1)})',
      );
      expectNoLayoutException(tester, label);
    });
  }

  testWidgets('chat pinned header re-measures when the text scale changes', (
    tester,
  ) async {
    useWindow(tester, compactPhone);
    await tester.pumpWidget(_subject(system: 1.0, app: 1.0));
    await tester.pumpAndSettle();
    final before = tester.getRect(find.byType(PrismTopBar)).height;

    await tester.pumpWidget(_subject(system: 2.25, app: 1.5));
    await tester.pumpAndSettle();

    final barRect = tester.getRect(find.byType(PrismTopBar));
    expect(
      barRect.height,
      greaterThan(before),
      reason: 'the pinned band must follow the new text scale',
    );
    expectFullSizeText(
      tester,
      'Chat',
      label: 'chat after scale change',
      container: barRect,
    );
    expectNoLayoutException(tester, 'chat after scale change');
  });

  // The pinned band must reserve exactly what the switcher renders, for the
  // badges that are actually shown: a synthetic "widest badge" could force a
  // needless label wrap and an extra line of reserve.
  for (final fontFamily in ['Lexend', 'OpenDyslexic']) {
    for (final width in [320.0, 390.0, 600.0, 1440.0]) {
      for (final badges in [
        (label: 'no badges', group: 0, dm: 0),
        (label: 'some badges', group: 3, dm: 1),
        (label: 'max badges', group: 120, dm: 120),
      ]) {
        testWidgets(
          'chat pinned band matches the rendered switcher with ${badges.label} '
          'at ${width.toInt()}dp, $fontFamily',
          (tester) async {
            useWindow(tester, Size(width, 900));
            await tester.pumpWidget(
              _subject(
                system: 1.0,
                app: 1.0,
                groupUnread: badges.group,
                dmUnread: badges.dm,
                fontFamily: fontFamily,
              ),
            );
            await tester.pumpAndSettle();

            expect(
              find.byType(PrismTopBar),
              findsOneWidget,
              reason: 'the chat list pane has exactly one top bar',
            );
            final barRect = tester.getRect(find.byType(PrismTopBar));
            final switcher = find.byWidgetPredicate(
              (widget) => widget is PrismSegmentedControl,
            );
            final switcherRect = tester.getRect(switcher);
            final bandBottom = barRect.top + pinnedBandHeight(tester);

            expect(
              bandBottom,
              closeTo(barRect.height + 16 + switcherRect.height, 0.5),
              reason:
                  'the band must be bar + padding + the switcher it renders, '
                  'with ${badges.label}',
            );
            expectFullSizeText(
              tester,
              'Chat',
              label: badges.label,
              container: barRect,
            );
            expectNoLayoutException(tester, '${badges.label} at $width');

            // At normal text the labels fit on one line with or without a badge,
            // so a badge must not add height.
            if (badges.group == 120) {
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pump();
              await tester.pumpWidget(
                _subject(system: 1.0, app: 1.0, fontFamily: fontFamily),
              );
              await tester.pumpAndSettle();
              final withoutBadges = tester.getRect(
                find.byWidgetPredicate(
                  (widget) => widget is PrismSegmentedControl,
                ),
              );
              expect(
                withoutBadges.height,
                closeTo(switcherRect.height, 0.5),
                reason:
                    'a badge must not add a line at normal text '
                    '(${withoutBadges.height} vs ${switcherRect.height})',
              );
            }
          },
        );
      }
    }
  }
}
