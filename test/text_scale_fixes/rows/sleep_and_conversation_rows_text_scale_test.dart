// The sleep row's "date looks off" chip and the conversation tile at large text sizes.
//
// Chip: its label was a hardcoded English literal, so a Spanish UI showed English, and
// its `Row(mainAxisSize.min, [Icon, Text])` gave the label no width bound, so at 3.375x
// the warning could only paint past the row edge. The checks are that the warning is
// localised and that it stays inside its row.
//
// Conversation tile: a title is unbounded user content, so a single-line ellipsis is the
// intended behaviour and is not treated as a defect here. What is checked is genuine
// health: no layout error, nothing paints outside the tile, the timestamp and unread
// badge keep their requested size, and the row's tap callback still fires.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/widgets/conversation_tile.dart';
import 'package:prism_plurality/features/fronting/widgets/sleep_session_row.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';

import 'rows_text_scale_harness.dart';

FrontingSession _futureSleep() {
  final start = DateTime.now().add(const Duration(hours: 6));
  return FrontingSession(
    id: 'sleep-future',
    startTime: start,
    endTime: start.add(const Duration(hours: 8)),
    sessionType: SessionType.sleep,
    quality: SleepQuality.good,
  );
}

Widget _sleepRow({
  required double system,
  required double app,
  String fontFamily = 'Lexend',
  Locale locale = const Locale('en'),
  TextScaler? scalerOverride,
}) {
  return rowsApp(
    // A ListView item, like the fronting/sleep list: the row gets its natural height
    // rather than the body's tight one, which is the geometry it really runs in.
    Scaffold(
      body: ListView(
        children: [
          SleepSessionRow(
            session: _futureSleep(),
            onTap: () {},
            onLongPress: () {},
          ),
        ],
      ),
    ),
    system: system,
    app: app,
    fontFamily: fontFamily,
    locale: locale,
    scalerOverride: scalerOverride,
  );
}

final _now = DateTime(2026, 5, 1, 12);

final _alice = Member(id: 'alice', name: 'Alice', createdAt: _now);
final _bob = Member(id: 'bob', name: 'Bob', createdAt: _now);

// `_relativeTimestamp` compares against the real clock, so the sample activity time has
// to be relative to `DateTime.now()`: a fixed calendar date renders as a date, not as
// the "5m" these assertions read.
Conversation _conversation() => Conversation(
  id: 'c1',
  title: 'Book Club',
  participantIds: const ['alice', 'bob'],
  createdAt: _now,
  lastActivityAt: DateTime.now().subtract(const Duration(minutes: 5)),
);

Widget _tile({
  required double system,
  required double app,
  String fontFamily = 'Lexend',
  TextScaler? scalerOverride,
  VoidCallback? onTap,
}) {
  final conversation = _conversation();
  return ProviderScope(
    overrides: [
      conversationTileDataProvider(conversation.id).overrideWith((ref) {
        return ConversationTileData(
          conversation: conversation,
          participantMap: {'alice': _alice, 'bob': _bob},
          unreadCount: 3,
          showUnreadBadge: true,
          speakingAs: 'alice',
          lastMessageAuthorName: 'Bob',
          lastMessageDisplayContent: 'Hello there',
        );
      }),
      memberNamePreferDisplayProvider.overrideWithValue(true),
    ],
    child: rowsApp(
      // A ListView item, like the chat conversation list: the tile gets its natural
      // height instead of the full window, which is what the header geometry (and
      // the trailing column's vertical centring) depends on.
      Scaffold(
        body: ListView(
          children: [
            ConversationTile(conversation: conversation, onTap: onTap ?? () {}),
          ],
        ),
      ),
      system: system,
      app: app,
      fontFamily: fontFamily,
      scalerOverride: scalerOverride,
    ),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadRowsFonts();
  });

  group('F1 sleep date warning chip', () {
    testWidgets('the warning is shown in the user\'s language (es)', (
      tester,
    ) async {
      useWindow(tester, compactPhone);
      await tester.pumpWidget(
        _sleepRow(system: 1, app: 1, locale: const Locale('es')),
      );
      await tester.pumpAndSettle();

      expectNoLayoutError(tester, label: 'sleep row es');
      // sleepDateLooksOff already ships in app_es.arb; a Spanish UI must not
      // show the English literal.
      expect(find.text('La fecha parece incorrecta'), findsOneWidget);
      expect(find.text('Date looks off'), findsNothing);
    });

    for (final (system, app, scaleLabel) in rowsScales) {
      for (final fontFamily in rowsFontFamilies) {
        testWidgets(
          'the warning stays inside the sleep row - $scaleLabel / $fontFamily',
          (tester) async {
            useWindow(tester, compactPhone);
            await tester.pumpWidget(
              _sleepRow(system: system, app: app, fontFamily: fontFamily),
            );
            await tester.pumpAndSettle();

            expectNoLayoutError(tester, label: 'sleep row $scaleLabel');

            final hint = find.text('Date looks off');
            expect(hint, findsOneWidget);
            // The row is a list item: bring the warning into view first, and bound it by
            // the row it belongs to rather than by the viewport (at 3.375x the chip can sit
            // below the fold).
            await tester.ensureVisible(hint);
            await tester.pumpAndSettle();
            expectPaintedInside(
              tester,
              hint,
              label: 'warning chip ($scaleLabel)',
              bounds: tester.getRect(find.byType(SleepSessionRow)),
            );
            expectDescendantTextInside(
              tester,
              find.byType(SleepSessionRow),
              label: 'sleep row ($scaleLabel)',
            );
          },
        );
      }
    }
  });

  group('C4 conversation tile', () {
    testWidgets('default text keeps the timestamp beside the title (control)', (
      tester,
    ) async {
      useWindow(tester, compactPhone);
      await tester.pumpWidget(_tile(system: 1, app: 1));
      await tester.pumpAndSettle();

      expectNoLayoutError(tester, label: 'conversation tile at 1x');
      final title = find.text('Book Club');
      expectNotVerticallyClipped(tester, title, label: 'title at 1x');
      // The tile's metadata layout is deliberately unchanged, so this only checks that
      // the timestamp is painted at its own size inside the tile.
      expectStaticLabelFullyPainted(
        tester,
        find.text('5m'),
        label: 'timestamp at 1x',
      );
      expectPaintedInside(tester, find.text('5m'), label: 'timestamp at 1x');
    });

    testWidgets('tapping the tile still runs its callback (control)', (
      tester,
    ) async {
      useWindow(tester, compactPhone);
      var taps = 0;
      await tester.pumpWidget(
        _tile(system: 2.25, app: 1.5, onTap: () => taps++),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ConversationTile));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    // Accepted disposition (parent, matched): a conversation title is unbounded
    // user content, so a single-line ellipsis is the intended behaviour and is
    // NOT treated as a defect. What is still required is that the tile holds its
    // own geometry and that the metadata keeps its requested size.
    for (final (system, app, scaleLabel) in [
      (1.5, 1.0, 'large text'),
      (2.25, 1.5, 'system 225% x Prism 150% = 3.375x'),
    ]) {
      testWidgets(
        'the tile keeps its geometry and full-size metadata - $scaleLabel',
        (tester) async {
          useWindow(tester, compactPhone);
          await tester.pumpWidget(_tile(system: system, app: app));
          await tester.pumpAndSettle();

          expectNoLayoutError(tester, label: 'conversation tile $scaleLabel');

          // Nothing escapes the tile (paint overflow).
          expectDescendantTextInside(
            tester,
            find.byType(ConversationTile),
            label: 'conversation tile ($scaleLabel)',
          );
          // The title may ellipsise; it still has to be painted on the tile.
          expectPaintedInside(
            tester,
            find.text('Book Club'),
            label: 'title ($scaleLabel)',
          );
          // The metadata is not allowed to shrink, clip or drop out.
          for (final text in ['5m', '3']) {
            final finder = find.text(text);
            expect(finder, findsOneWidget, reason: text);
            expectStaticLabelFullyPainted(
              tester,
              finder,
              label: '$text ($scaleLabel)',
            );
            expectPaintedInside(tester, finder, label: '$text ($scaleLabel)');
          }
        },
      );
    }

    testWidgets('wide window where it fits: nothing is reflowed (control)', (
      tester,
    ) async {
      useWindow(tester, wideWindow);
      await tester.pumpWidget(_tile(system: 2.25, app: 1.5));
      await tester.pumpAndSettle();

      expectNoLayoutError(tester, label: 'conversation tile wide 3.375x');
      // Metadata layout unchanged: on a wide window this only checks that the tile holds
      // its geometry and that both texts paint inside it.
      for (final text in ['Book Club', '5m']) {
        final finder = find.text(text);
        expect(finder, findsOneWidget, reason: text);
        expectNotVerticallyClipped(
          tester,
          finder,
          label: '$text (wide 3.375x)',
        );
        expectPaintedInside(tester, finder, label: '$text (wide 3.375x)');
      }
      expectDescendantTextInside(
        tester,
        find.byType(ConversationTile),
        label: 'conversation tile (wide 3.375x)',
      );
    });
  });
}
