import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/polls/providers/poll_providers.dart';
import 'package:prism_plurality/features/polls/views/poll_detail_screen.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_pill.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';

void main() {
  final time = DateTime(2026, 4, 15);
  final members = [
    Member(id: 'member-1', name: 'Alex', createdAt: time),
    Member(id: 'member-2', name: 'Bea', createdAt: time),
  ];

  Poll makePoll({
    bool anonymous = true,
    bool closed = true,
    String firstVoter = 'member-1',
    DateTime? expiresAt,
  }) => Poll(
    id: 'poll-1',
    question: 'Where should we go?',
    createdAt: time,
    isAnonymous: anonymous,
    isClosed: closed,
    expiresAt: expiresAt,
    allowsMultipleVotes: true,
    options: [
      const PollOption(id: 'standard', text: 'Park'),
      PollOption(
        id: 'other',
        text: 'Other',
        isOtherOption: true,
        votes: [
          PollVote(
            id: 'vote-1',
            memberId: firstVoter,
            votedAt: time,
            responseText: 'Library',
          ),
          PollVote(
            id: 'vote-2',
            memberId: 'member-2',
            votedAt: time,
            responseText: 'Museum',
          ),
          PollVote(id: 'blank', memberId: 'absent', votedAt: time),
        ],
      ),
    ],
  );

  Future<List<String>> pumpPoll(
    WidgetTester tester,
    Poll poll, {
    List<Member>? activeMembers,
  }) async {
    final nameLookups = <String>[];
    final container = ProviderContainer(
      overrides: [
        pollByIdProvider.overrideWith((ref, id) => Stream.value(poll)),
        pollOptionsProvider.overrideWith(
          (ref, id) => Stream.value(poll.options),
        ),
        activeMembersProvider.overrideWith(
          (ref) => Stream.value(activeMembers ?? members),
        ),
        allGroupsProvider.overrideWith(
          (ref) => Stream.value(const <MemberGroup>[]),
        ),
        allGroupEntriesProvider.overrideWith(
          (ref) => Stream.value(const <MemberGroupEntry>[]),
        ),
        memberByIdProvider.overrideWith((ref, id) {
          nameLookups.add(id);
          final matching = members.where((member) => member.id == id);
          return Stream.value(matching.isEmpty ? null : matching.first);
        }),
        activeSessionProvider.overrideWith((ref) => Stream.value(null)),
        memberFrontingCountsProvider.overrideWith(
          (ref) async => const <String, int>{},
        ),
        systemSettingsProvider.overrideWith(
          (ref) => Stream.value(const SystemSettings()),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: [Locale('en')],
          home: PollDetailScreen(pollId: 'poll-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    return nameLookups;
  }

  testWidgets(
    'anonymous Other results show all answers without voter identity',
    (tester) async {
      final lookups = await pumpPoll(tester, makePoll());
      expect(find.text('Library'), findsOneWidget);
      expect(find.text('Museum'), findsOneWidget);
      expect(find.textContaining('Alex'), findsNothing);
      expect(find.textContaining('Bea'), findsNothing);
      expect(find.text('Unknown'), findsNothing);
      expect(lookups, isEmpty);
    },
  );

  testWidgets(
    'anonymous answers preserve duplicates and skip blank/non-Other text',
    (tester) async {
      final poll = makePoll();
      final other = poll.options.last;
      final lookups = await pumpPoll(
        tester,
        poll.copyWith(
          options: [
            poll.options.first.copyWith(
              votes: [
                PollVote(
                  id: 'stray',
                  memberId: 'member-1',
                  votedAt: time,
                  responseText: 'Not an Other answer',
                ),
              ],
            ),
            other.copyWith(
              votes: [
                ...other.votes,
                PollVote(
                  id: 'duplicate',
                  memberId: 'member-3',
                  votedAt: time,
                  responseText: 'Library',
                ),
                PollVote(
                  id: 'empty',
                  memberId: 'member-4',
                  votedAt: time,
                  responseText: '',
                ),
                PollVote(
                  id: 'whitespace',
                  memberId: 'member-5',
                  votedAt: time,
                  responseText: '   ',
                ),
              ],
            ),
          ],
        ),
      );
      final otherTile = find.ancestor(
        of: find.text('Other'),
        matching: find.byType(PrismSurface),
      );
      final labels = tester
          .widgetList<PrismPill>(
            find.descendant(of: otherTile, matching: find.byType(PrismPill)),
          )
          .map((pill) => pill.label)
          .toList();
      expect(labels, ['Library', 'Museum', 'Library']);
      expect(find.text('Not an Other answer'), findsNothing);
      expect(lookups, isEmpty);
    },
  );

  testWidgets('named Other results retain voter attribution', (tester) async {
    await pumpPoll(tester, makePoll(anonymous: false));
    expect(find.text('Alex: Library'), findsOneWidget);
    expect(find.text('Bea: Museum'), findsOneWidget);
  });

  testWidgets('open anonymous results follow the existing voted-member rule', (
    tester,
  ) async {
    await pumpPoll(tester, makePoll(closed: false));
    // The selected member's answer is also restored in the editable field;
    // the other member's answer can only come from result projection.
    expect(find.text('Museum'), findsOneWidget);
    expect(find.text('Bea: Museum'), findsNothing);
  });

  testWidgets(
    'Other answers stay hidden when result access is not yet allowed',
    (tester) async {
      await pumpPoll(tester, makePoll(closed: false), activeMembers: []);
      expect(find.textContaining('Library'), findsNothing);
      expect(find.textContaining('Museum'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );

  testWidgets('expired anonymous polls expose answers without voter names', (
    tester,
  ) async {
    final lookups = await pumpPoll(
      tester,
      makePoll(closed: false, expiresAt: time),
      activeMembers: [],
    );
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Museum'), findsOneWidget);
    expect(lookups, isEmpty);
  });
}
