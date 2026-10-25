import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_chip.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';

void main() {
  final poll = Poll(
    id: 'poll-1',
    question: 'Favorite color?',
    createdAt: DateTime(2026, 4, 15),
    options: const [
      PollOption(id: 'opt-1', text: 'Blue'),
      PollOption(id: 'opt-2', text: 'Green'),
    ],
  );
  final members = [
    Member(id: 'member-1', name: 'Alex', createdAt: DateTime(2026, 4, 15)),
    Member(id: 'member-2', name: 'Bea', createdAt: DateTime(2026, 4, 15)),
  ];

  Widget buildSubject(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: [Locale('en')],
        home: PollDetailScreen(pollId: 'poll-1'),
      ),
    );
  }

  final manyMembers = List.generate(
    40,
    (index) => Member(
      id: 'voter-$index',
      name: 'Synthetic voter ${index.toString().padLeft(2, '0')}',
      createdAt: DateTime(2026, 4, 15),
    ),
  );

  Future<ProviderContainer> pumpManyVoters(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        pollByIdProvider.overrideWith((ref, id) => Stream.value(poll)),
        pollOptionsProvider.overrideWith(
          (ref, id) => Stream.value(poll.options),
        ),
        activeMembersProvider.overrideWith((ref) => Stream.value(manyMembers)),
        allGroupsProvider.overrideWith(
          (ref) => Stream.value(const <MemberGroup>[]),
        ),
        allGroupEntriesProvider.overrideWith(
          (ref) => Stream.value(const <MemberGroupEntry>[]),
        ),
        memberByIdProvider.overrideWith((ref, id) {
          return Stream.value(
            manyMembers.where((member) => member.id == id).firstOrNull,
          );
        }),
        activeSessionProvider.overrideWith((ref) => Stream.value(null)),
        memberFrontingCountsProvider.overrideWith(
          // Distinct counts keep the last fixture member last even though
          // the production frequency sort does not promise stable ties.
          (ref) async => {
            for (var index = 0; index < manyMembers.length; index++)
              manyMembers[index].id: manyMembers.length - index,
          },
        ),
        systemSettingsProvider.overrideWith(
          (ref) => Stream.value(const SystemSettings()),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(buildSubject(container));
    await tester.pumpAndSettle();
    expect(container.read(votingAsProvider), manyMembers.first.id);
    return container;
  }

  Finder voterList() => find.byWidgetPredicate(
    (widget) => widget is ListView && widget.scrollDirection == Axis.horizontal,
  );

  bool focusedWithin(bool Function(Widget) matches) {
    var found = false;
    FocusManager.instance.primaryFocus?.context?.visitAncestorElements((
      element,
    ) {
      if (matches(element.widget)) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  testWidgets(
    'mouse scrollbar reaches and selects the last offscreen voter',
    (tester) async {
      final container = await pumpManyVoters(tester);
      expect(find.text(manyMembers.last.name).hitTestable(), findsNothing);
      expect(
        Theme.of(tester.element(voterList())).platform,
        TargetPlatform.windows,
      );
      expect(
        ScrollConfiguration.of(
          tester.element(voterList()),
        ).getPlatform(tester.element(voterList())),
        TargetPlatform.windows,
      );

      // Use the horizontal track's screen position, not a concrete Scrollbar
      // widget type: an automatic desktop scrollbar must count too.
      final rect = tester.getRect(voterList());
      final thumbPoint = Offset(rect.left + 18, rect.bottom - 5);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: thumbPoint);
      await mouse.moveTo(thumbPoint);
      await tester.pump();
      await mouse.down(thumbPoint);
      await tester.pump();
      // Lay out the lazy list between pointer updates, as a real drag does;
      // its estimated scroll extent can change as new chips become visible.
      for (var step = 1; step <= 20; step++) {
        await mouse.moveTo(
          thumbPoint + Offset((rect.width - 36) * step / 20, 0),
        );
        await tester.pump();
      }
      await mouse.up();
      await mouse.removePointer();
      await tester.pumpAndSettle();
      expect(container.read(votingAsProvider), manyMembers.first.id);
      expect(find.text(manyMembers.last.name).hitTestable(), findsOneWidget);
      await tester.tap(
        find.text(manyMembers.last.name),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(container.read(votingAsProvider), manyMembers.last.id);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets(
    'touch and horizontal pointer scrolling preserve the voter',
    (tester) async {
      final container = await pumpManyVoters(tester);
      final scrollable = find.descendant(
        of: voterList(),
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      final initial = position.pixels;
      await tester.drag(voterList(), const Offset(-250, 0));
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(initial));
      final afterTouch = position.pixels;
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(voterList()),
          scrollDelta: const Offset(250, 0),
        ),
      );
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(afterTouch));
      expect(container.read(votingAsProvider), manyMembers.first.id);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets(
    'keyboard search can select the last offscreen voter',
    (tester) async {
      final container = await pumpManyVoters(tester);
      for (var i = 0; i < 12; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        if (focusedWithin(
          (widget) => widget is PrismChip && widget.label == 'Search',
        )) {
          break;
        }
      }
      expect(
        focusedWithin(
          (widget) => widget is PrismChip && widget.label == 'Search',
        ),
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText), manyMembers.last.name);
      await tester.pumpAndSettle();
      expect(container.read(votingAsProvider), manyMembers.first.id);
      bool lastRow(Widget widget) =>
          widget is PrismListRow &&
          widget.title is Text &&
          (widget.title as Text).data == manyMembers.last.name;
      for (var i = 0; i < 12; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        if (focusedWithin(lastRow)) break;
      }
      expect(focusedWithin(lastRow), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(container.read(votingAsProvider), manyMembers.last.id);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets(
    'defaults voting-as after first frame without Riverpod build error',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          pollByIdProvider.overrideWith((ref, pollId) {
            return Stream.value(pollId == poll.id ? poll : null);
          }),
          pollOptionsProvider.overrideWith((ref, pollId) {
            return Stream.value(pollId == poll.id ? poll.options : const []);
          }),
          activeMembersProvider.overrideWith((ref) => Stream.value(members)),
          allGroupsProvider.overrideWith(
            (ref) => Stream.value(const <MemberGroup>[]),
          ),
          allGroupEntriesProvider.overrideWith(
            (ref) => Stream.value(const <MemberGroupEntry>[]),
          ),
          memberByIdProvider.overrideWith((ref, memberId) {
            final matching = members.where((member) => member.id == memberId);
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

      await tester.pumpWidget(buildSubject(container));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(container.read(votingAsProvider), 'member-1');
      expect(find.text('Favorite color?'), findsOneWidget);
    },
  );

  testWidgets('reflects saved vote state for the selected member', (
    tester,
  ) async {
    final votedPoll = poll.copyWith(
      options: [
        const PollOption(id: 'opt-1', text: 'Blue'),
        PollOption(
          id: 'opt-2',
          text: 'Green',
          votes: [
            PollVote(
              id: 'vote-1',
              memberId: 'member-1',
              votedAt: DateTime(2026, 4, 16),
            ),
          ],
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        pollByIdProvider.overrideWith((ref, pollId) {
          return Stream.value(pollId == poll.id ? votedPoll : null);
        }),
        pollOptionsProvider.overrideWith((ref, pollId) {
          return Stream.value(pollId == poll.id ? votedPoll.options : const []);
        }),
        activeMembersProvider.overrideWith((ref) => Stream.value(members)),
        allGroupsProvider.overrideWith(
          (ref) => Stream.value(const <MemberGroup>[]),
        ),
        allGroupEntriesProvider.overrideWith(
          (ref) => Stream.value(const <MemberGroupEntry>[]),
        ),
        memberByIdProvider.overrideWith((ref, memberId) {
          final matching = members.where((member) => member.id == memberId);
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

    await tester.pumpWidget(buildSubject(container));
    await tester.pumpAndSettle();

    expect(find.byIcon(AppIcons.radioButtonChecked), findsOneWidget);
    expect(find.text('Vote submitted'), findsOneWidget);
    expect(find.text('Submit Vote'), findsNothing);
  });
}
