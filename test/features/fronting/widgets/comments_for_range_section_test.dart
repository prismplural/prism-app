import 'dart:async';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/front_session_comment.dart';
import 'package:prism_plurality/features/fronting/providers/front_comments_providers.dart';
import 'package:prism_plurality/features/fronting/widgets/add_comment_sheet.dart';
import 'package:prism_plurality/features/fronting/widgets/comments_for_range_section.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';

final _time = DateTime(2026, 4, 1, 10);
final _range = DateTimeRange(
  start: _time,
  end: _time.add(const Duration(hours: 1)),
);

FrontSessionComment _comment({String sessionId = 'session-a'}) =>
    FrontSessionComment(
      id: 'comment-a',
      sessionId: sessionId,
      body: 'Original comment',
      timestamp: _time,
      createdAt: _time,
    );

class _RecordingComments extends CommentNotifier {
  final updates = <FrontSessionComment>[];
  final deletes = <String>[];
  final creates = <String>[];
  Completer<void>? pendingUpdate;

  @override
  Future<void> build() async {}

  @override
  Future<void> updateComment(FrontSessionComment comment) async {
    updates.add(comment);
    await pendingUpdate?.future;
  }

  @override
  Future<void> deleteComment(String id) async {
    deletes.add(id);
  }

  @override
  Future<void> createComment({
    required String sessionId,
    required String body,
    required DateTime timestamp,
  }) async {
    creates.add(body);
  }
}

Widget _wrap({
  required _RecordingComments notifier,
  List<FrontSessionComment>? comments,
}) => ProviderScope(
  overrides: [
    commentNotifierProvider.overrideWith(() => notifier),
    commentsForPeriodProvider(
      PeriodCommentsQuery(sessionIds: const ['session-a'], range: _range),
    ).overrideWith((ref) => Stream.value(comments ?? [_comment()])),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: const [Locale('en')],
    home: Scaffold(
      body: CommentsForRangeSection(
        sessionIds: const ['session-a'],
        range: _range,
      ),
    ),
  ),
);

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('More options'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('comment exposes visible edit and delete without long press', (
    tester,
  ) async {
    final notifier = _RecordingComments();
    await tester.pumpWidget(_wrap(notifier: notifier));
    await tester.pumpAndSettle();

    expect(find.byTooltip('More options'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    await _openMenu(tester);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(notifier.updates, isEmpty);
    expect(notifier.deletes, isEmpty);
  });

  testWidgets('mouse can open visible comment actions', (tester) async {
    await tester.pumpWidget(_wrap(notifier: _RecordingComments()));
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    final position = tester.getCenter(find.byTooltip('More options'));
    await mouse.moveTo(position);
    await mouse.down(position);
    await mouse.up();
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    await mouse.removePointer();
  });

  testWidgets('keyboard can open menu and activate edit', (tester) async {
    await tester.pumpWidget(_wrap(notifier: _RecordingComments()));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(AddCommentSheet), findsOneWidget);
  });

  testWidgets('overflow has a labelled screen reader tap action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(_wrap(notifier: _RecordingComments()));
      await tester.pumpAndSettle();
      final data = tester
          .getSemantics(find.byTooltip('More options'))
          .getSemanticsData();
      // Material exposes the tooltip as the accessible name on native bridges.
      // Focus and expanded-state metadata may accompany this actionable button.
      expect([data.label, data.tooltip], contains('More options'));
      expect(data.flagsCollection.isButton, isTrue);
      // A non-none input-focus state means this node can receive focus.
      expect(data.flagsCollection.isFocused, isNot(Tristate.none));
      expect(data.flagsCollection.isEnabled, Tristate.isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('long press retains existing edit and delete actions', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(notifier: _RecordingComments()));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Original comment'));
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.byType(AddCommentSheet), findsOneWidget);
    expect(find.text('Original comment'), findsWidgets);
  });

  testWidgets('edit reuses original identity and submits only once', (
    tester,
  ) async {
    final notifier = _RecordingComments()..pendingUpdate = Completer<void>();
    await tester.pumpWidget(_wrap(notifier: notifier));
    await tester.pumpAndSettle();
    await _openMenu(tester);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.byType(AddCommentSheet), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Updated comment');
    // Loading replaces the visible Text with a spinner, but the control's
    // label and semantics remain Save throughout the pending update.
    final save = find.byWidgetPredicate(
      (widget) => widget is PrismButton && widget.label == 'Save',
    );
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pump();
    // The existing saving guard must also protect the newly exposed path.
    await tester.tap(save);
    expect(notifier.updates, hasLength(1));
    expect(
      notifier.updates.single,
      _comment().copyWith(body: 'Updated comment'),
    );
    expect(notifier.creates, isEmpty);
    notifier.pendingUpdate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AddCommentSheet), findsNothing);
  });

  testWidgets('delete requires confirmation and emits a single mutation', (
    tester,
  ) async {
    final notifier = _RecordingComments();
    await tester.pumpWidget(_wrap(notifier: notifier));
    await tester.pumpAndSettle();
    await _openMenu(tester);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.byType(PrismDialog), findsOneWidget);
    expect(notifier.deletes, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(notifier.deletes, isEmpty);
    await _openMenu(tester);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PrismButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(notifier.deletes, ['comment-a']);
    expect(notifier.updates, isEmpty);
  });

  testWidgets('empty comments have no action affordance', (tester) async {
    await tester.pumpWidget(
      _wrap(notifier: _RecordingComments(), comments: []),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FrontSessionCommentTile), findsNothing);
    expect(find.byTooltip('More options'), findsNothing);
    expect(find.text('No comments yet'), findsOneWidget);
  });

  testWidgets('existing blank-session edit guard is not bypassed', (
    tester,
  ) async {
    final notifier = _RecordingComments();
    await tester.pumpWidget(
      _wrap(
        notifier: notifier,
        comments: [_comment(sessionId: ' ')],
      ),
    );
    await tester.pumpAndSettle();
    await _openMenu(tester);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.byType(AddCommentSheet), findsNothing);
    expect(notifier.updates, isEmpty);
    expect(notifier.creates, isEmpty);
    expect(notifier.deletes, isEmpty);
  });
}
