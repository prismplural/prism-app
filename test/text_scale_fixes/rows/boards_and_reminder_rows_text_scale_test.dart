// The post tile's header, the board section header and the reminder composer's
// label/control rows at large text sizes.
//
// Post header: the timestamp and the audience pill were non-flex children, so they kept
// their intrinsic width and collapsed the participant strip, whose own non-shrinkable
// pieces (two avatars and the "to" connector) then no longer fit. The header keeps the
// metadata inline whenever it fits beside those pieces and gives it its own line when it
// does not.
//
// Board section header: the title was a non-flex `Text` behind a `Spacer`, so the actor
// selector and the compose "+" were pushed past the card edge - the entry point for
// writing a post went off-screen.
//
// Reminder composer: `_LabeledRow` was `Row(spaceBetween, [Text(label), control])` with
// neither side flexible, so the label's intrinsic width pushed the control past the card.
//
// Each case asserts painted geometry and, where relevant, that the control, the selector
// and the compose action stay inside the window. The reminder sheet also renders the
// trigger/frequency segmented control; an overflow inside that control fails this test
// too, so read the failure location before attributing it to a row.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_board_post.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/reminder.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/boards/providers/board_posts_providers.dart';
import 'package:prism_plurality/features/boards/widgets/board_message_section.dart';
import 'package:prism_plurality/features/boards/widgets/post_tile.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart'
    show SpeakingAsNotifier, speakingAsProvider;
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/reminders/widgets/create_reminder_sheet.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

import '../../helpers/fake_repositories.dart';
import 'rows_text_scale_harness.dart';

final _now = DateTime.now();
final _alice = Member(
  id: 'alice',
  name: 'Alice',
  createdAt: _now.subtract(const Duration(days: 20)),
  isActive: true,
);
final _bob = Member(
  id: 'bob',
  name: 'Bob',
  createdAt: _now.subtract(const Duration(days: 20)),
  isActive: true,
);

MemberBoardPost _post() => MemberBoardPost(
  id: 'post-1',
  authorId: 'alice',
  targetMemberId: 'bob',
  audience: 'public',
  body: 'Hello system',
  createdAt: _now.subtract(const Duration(hours: 2)),
  writtenAt: _now.subtract(const Duration(hours: 2)),
);

/// A deliberately long user name: it must ellipsise on the inline header line instead
/// of forcing the metadata onto a second line.
const _longAuthorName = 'Alexandra-Rose Montgomery the Third';

class _FakeBoardPostNotifier extends MemberBoardPostNotifier {
  @override
  Future<void> build() async {}
}

class _FakeSpeakingAsNotifier extends SpeakingAsNotifier {
  @override
  String? build() => null;
}

Widget _postTile({
  required double system,
  required double app,
  String fontFamily = 'Lexend',
  TextScaler? scalerOverride,
  String? authorName,
}) {
  final post = _post();
  final author = authorName == null
      ? _alice
      : Member(
          id: _alice.id,
          name: authorName,
          createdAt: _alice.createdAt,
          isActive: true,
        );
  return ProviderScope(
    overrides: [
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(const SystemSettings()),
      ),
      memberByIdProvider.overrideWith(
        (ref, id) => Stream.value(
          [author, _bob].firstWhere((m) => m.id == id, orElse: () => author),
        ),
      ),
      memberBoardPostNotifierProvider.overrideWith(_FakeBoardPostNotifier.new),
    ],
    child: rowsApp(
      Scaffold(
        body: SingleChildScrollView(
          child: PostTile(
            post: post,
            viewerMember: author,
            showAudiencePill: true,
            onTap: () {},
          ),
        ),
      ),
      system: system,
      app: app,
      fontFamily: fontFamily,
      scalerOverride: scalerOverride,
    ),
  );
}

Widget _boardSection({
  required double system,
  required double app,
  String fontFamily = 'Lexend',
  TextScaler? scalerOverride,
}) {
  return ProviderScope(
    overrides: [
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(const SystemSettings()),
      ),
      boardsEnabledProvider.overrideWithValue(true),
      speakingAsProvider.overrideWith(_FakeSpeakingAsNotifier.new),
      activeMembersProvider.overrideWith((ref) => Stream.value([_alice, _bob])),
      activeMemberListProvider.overrideWith(
        (ref) => Stream.value([_alice, _bob]),
      ),
      memberByIdProvider.overrideWith(
        (ref, id) => Stream.value(
          [_alice, _bob].firstWhere((m) => m.id == id, orElse: () => _alice),
        ),
      ),
      memberBoardSectionProvider.overrideWith(
        (ref, memberId) => Stream.value(
          MemberBoardSection(publicPosts: [_post()], totalPublic: 1),
        ),
      ),
      memberBoardPostNotifierProvider.overrideWith(_FakeBoardPostNotifier.new),
    ],
    child: rowsApp(
      const SizedBox.shrink(),
      system: system,
      app: app,
      fontFamily: fontFamily,
      scalerOverride: scalerOverride,
      routerConfig: GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: SingleChildScrollView(
                child: BoardMessageSection(memberId: _alice.id),
              ),
            ),
          ),
          GoRoute(
            path: '/boards/member/:memberId',
            builder: (context, state) => Scaffold(
              body: Text('member board ${state.pathParameters['memberId']}'),
            ),
          ),
        ],
      ),
    ),
  );
}

Reminder _intervalReminder() => Reminder(
  id: 'r1',
  name: 'Test',
  message: '',
  trigger: ReminderTrigger.scheduled,
  frequency: ReminderFrequency.interval,
  intervalDays: 7,
  createdAt: DateTime(2024),
  modifiedAt: DateTime(2024),
);

Widget _reminderSheet({
  required double system,
  required double app,
  String fontFamily = 'Lexend',
  TextScaler? scalerOverride,
  TextDirection? textDirection,
}) {
  final appPrefs = FakeAppPreferenceRepository();
  addTearDown(appPrefs.close);
  return ProviderScope(
    overrides: [
      appPreferenceRepositoryProvider.overrideWithValue(appPrefs),
      activeMembersProvider.overrideWith((ref) => Stream.value([_alice, _bob])),
      allGroupsProvider.overrideWith(
        (ref) => Stream.value(const <MemberGroup>[]),
      ),
      allGroupEntriesProvider.overrideWith(
        (ref) => Stream.value(const <MemberGroupEntry>[]),
      ),
      systemSettingsProvider.overrideWithValue(
        const AsyncValue.data(SystemSettings()),
      ),
    ],
    child: rowsApp(
      Scaffold(body: CreateReminderSheet(editing: _intervalReminder())),
      system: system,
      app: app,
      fontFamily: fontFamily,
      scalerOverride: scalerOverride,
      textDirection: textDirection,
    ),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadRowsFonts();
  });

  group('B1 post tile header', () {
    testWidgets('default text keeps the whole header on one line (control)', (
      tester,
    ) async {
      useWindow(tester, compactPhone);
      await tester.pumpWidget(_postTile(system: 1, app: 1));
      await tester.pumpAndSettle();

      expectNoLayoutError(tester, label: 'post tile at 1x');
      for (final name in ['Alice', 'Bob']) {
        final finder = find.text(name);
        expect(finder, findsOneWidget, reason: name);
        expectNotVerticallyClipped(tester, finder, label: '$name at 1x');
      }
      expectOnTheSameLine(
        tester,
        find.text('Alice'),
        find.text('2h ago'),
        label: 'participants/timestamp at 1x',
      );
    });

    for (final (system, app, scaleLabel) in [
      (1.0, 1.0, 'default text'),
      (1.5, 1.0, 'large text'),
    ]) {
      testWidgets('a long author name keeps the inline header - $scaleLabel', (
        tester,
      ) async {
        useWindow(tester, compactPhone);
        await tester.pumpWidget(
          _postTile(system: system, app: app, authorName: _longAuthorName),
        );
        await tester.pumpAndSettle();

        expectNoLayoutError(tester, label: 'post tile long name $scaleLabel');

        // The metadata stays on the name's line: the old, sound geometry, where the
        // user's name ellipsises instead of pushing the header apart.
        final author = find.text(_longAuthorName);
        final timestamp = find.text('2h ago');
        expect(author, findsOneWidget);
        expect(timestamp, findsOneWidget);
        expectOnTheSameLine(
          tester,
          author,
          timestamp,
          label: 'long name / timestamp ($scaleLabel)',
        );
        expect(
          paragraphOf(tester, author).didExceedMaxLines,
          isTrue,
          reason:
              '$scaleLabel: the long name is expected to ellipsise on the inline line',
        );
        expectDescendantTextInside(
          tester,
          find.byType(PostTile),
          label: 'post tile (long name, $scaleLabel)',
        );
      });
    }

    for (final (system, app, scaleLabel) in rowsScales) {
      testWidgets('the header never paints outside the tile - $scaleLabel', (
        tester,
      ) async {
        useWindow(tester, compactPhone);
        await tester.pumpWidget(_postTile(system: system, app: app));
        await tester.pumpAndSettle();

        expectNoLayoutError(tester, label: 'post tile $scaleLabel');
        expectDescendantTextInside(
          tester,
          find.byType(PostTile),
          label: 'post tile ($scaleLabel)',
        );
        expectPaintedInside(tester, find.text('2h ago'), label: 'timestamp');
        expectPaintedInside(
          tester,
          find.text('public'),
          label: 'audience pill',
        );
      });
    }

    testWidgets('B1 wide window where it fits: nothing is reflowed (control)', (
      tester,
    ) async {
      useWindow(tester, wideWindow);
      await tester.pumpWidget(_postTile(system: 2.25, app: 1.5));
      await tester.pumpAndSettle();

      expectNoLayoutError(tester, label: 'post tile wide 3.375x');
      expectNotVerticallyClipped(
        tester,
        find.text('Alice'),
        label: 'author (wide)',
      );
      expectOnTheSameLine(
        tester,
        find.text('Alice'),
        find.text('2h ago'),
        label: 'participants/timestamp (wide 3.375x)',
      );
    });
  });

  group('B6 board section header', () {
    for (final (system, app, scaleLabel) in rowsScales) {
      for (final fontFamily in rowsFontFamilies) {
        testWidgets(
          'compose + and actor selector stay reachable - $scaleLabel / $fontFamily',
          (tester) async {
            useWindow(tester, compactPhone);
            await tester.pumpWidget(
              _boardSection(system: system, app: app, fontFamily: fontFamily),
            );
            await tester.pumpAndSettle();

            expectNoLayoutError(tester, label: 'board section $scaleLabel');

            final title = find.text('Public Posts');
            expect(title, findsOneWidget);
            expectStaticLabelFullyPainted(
              tester,
              title,
              label: 'section title',
            );

            // A control whose rect leaves the window cannot be tapped on the
            // device, so the compose entry point would be unreachable.
            final compose = find.byIcon(AppIcons.add);
            expect(compose, findsOneWidget);
            expectPaintedInside(
              tester,
              compose,
              label: 'compose + ($scaleLabel)',
            );
            final selector = find.byKey(const ValueKey('boards.actorSelector'));
            expect(selector, findsOneWidget);
            expectPaintedInside(
              tester,
              selector,
              label: 'actor selector ($scaleLabel)',
            );
          },
        );
      }
    }

    testWidgets('B6 wide window where it fits: nothing is reflowed (control)', (
      tester,
    ) async {
      useWindow(tester, wideWindow);
      await tester.pumpWidget(_boardSection(system: 2.25, app: 1.5));
      await tester.pumpAndSettle();

      expectNoLayoutError(tester, label: 'board section wide 3.375x');
      expectOnTheSameLine(
        tester,
        find.text('Public Posts'),
        find.byIcon(AppIcons.add),
        label: 'title/compose (wide 3.375x)',
      );
    });
  });

  group('R1 reminder composer rows', () {
    testWidgets('default text keeps the control beside its label (control)', (
      tester,
    ) async {
      useWindow(tester, tallCompactPage);
      await tester.pumpWidget(_reminderSheet(system: 1, app: 1));
      await tester.pumpAndSettle();

      expectNoLayoutError(tester, label: 'reminder sheet at 1x');
      final label = find.text('Repeat every');
      final control = find.text('7 days');
      expect(label, findsOneWidget);
      expect(control, findsOneWidget);
      expectOnTheSameLine(
        tester,
        label,
        control,
        label: 'repeat label/control at 1x',
      );
    });

    for (final (system, app, scaleLabel) in rowsScales) {
      testWidgets('label and control stay on the card - $scaleLabel', (
        tester,
      ) async {
        useWindow(tester, tallCompactPage);
        await tester.pumpWidget(_reminderSheet(system: system, app: app));
        await tester.pumpAndSettle();

        expectNoLayoutError(
          tester,
          label: 'reminder sheet $scaleLabel',
          ignoreCauseMatching: fixedHeightBarLayoutErrors,
          ignoreAlso: segmentedControlLayoutErrors,
        );

        final label = find.text('Repeat every');
        expect(label, findsOneWidget);
        expectStaticLabelFullyPainted(
          tester,
          label,
          label: 'repeat label ($scaleLabel)',
        );
        expectPaintedInside(tester, label, label: 'repeat label ($scaleLabel)');

        // The control keeps its own size and must remain on the sheet.
        final control = find.text('7 days');
        expect(control, findsOneWidget);
        expectStaticLabelFullyPainted(
          tester,
          control,
          label: 'control ($scaleLabel)',
        );
        expectPaintedInside(tester, control, label: 'control ($scaleLabel)');

        // The "Time" row is a second label/control pair of the same shape.
        expectPaintedInside(
          tester,
          find.text('Time'),
          label: 'time label ($scaleLabel)',
        );
        expectPaintedInside(
          tester,
          find.text('9:00 AM'),
          label: 'time control ($scaleLabel)',
        );
      });
    }

    testWidgets('RTL keeps the label and control on the card at 3.375x', (
      tester,
    ) async {
      useWindow(tester, tallCompactPage);
      await tester.pumpWidget(
        _reminderSheet(
          system: 2.25,
          app: 1.5,
          textDirection: TextDirection.rtl,
        ),
      );
      await tester.pumpAndSettle();

      expectNoLayoutError(
        tester,
        label: 'reminder sheet rtl 3.375x',
        ignoreCauseMatching: fixedHeightBarLayoutErrors,
        ignoreAlso: segmentedControlLayoutErrors,
      );
      for (final text in ['Repeat every', '7 days']) {
        final finder = find.text(text);
        expect(finder, findsOneWidget, reason: text);
        expectPaintedInside(tester, finder, label: '$text (rtl 3.375x)');
      }
    });

    testWidgets('R1 wide window where it fits: nothing is reflowed (control)', (
      tester,
    ) async {
      useWindow(tester, wideWindow);
      await tester.pumpWidget(_reminderSheet(system: 2.25, app: 1.5));
      await tester.pumpAndSettle();

      expectNoLayoutError(
        tester,
        label: 'reminder sheet wide 3.375x',
        ignoreCauseMatching: fixedHeightBarLayoutErrors,
        ignoreAlso: segmentedControlLayoutErrors,
      );
      expectOnTheSameLine(
        tester,
        find.text('Repeat every'),
        find.text('7 days'),
        label: 'repeat label/control (wide 3.375x)',
      );
    });
  });
}
