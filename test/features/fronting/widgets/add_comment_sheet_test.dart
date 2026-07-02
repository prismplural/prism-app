import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/front_session_comment.dart';
import 'package:prism_plurality/features/fronting/providers/front_comments_providers.dart';
import 'package:prism_plurality/features/fronting/widgets/add_comment_sheet.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

void main() {
  testWidgets('save ignores repeated taps while comment create is pending', (
    tester,
  ) async {
    final notifier = _FakeCommentNotifier()
      ..createCompleter = Completer<void>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [commentNotifierProvider.overrideWith(() => notifier)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          home: Scaffold(
            body: AddCommentSheet(
              sessionId: 'session-1',
              timestamp: DateTime(2026, 1, 1, 12),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'A note');
    await tester.pump();

    final saveButton = find.widgetWithText(PrismButton, 'Add');
    await tester.tap(saveButton);
    await tester.tap(saveButton);

    expect(notifier.createCalls, 1);

    notifier.createCompleter!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('edit save ignores repeated taps while update is pending', (
    tester,
  ) async {
    final notifier = _FakeCommentNotifier()
      ..updateCompleter = Completer<void>();
    final comment = FrontSessionComment(
      id: 'comment-1',
      sessionId: 'session-1',
      body: 'Old note',
      timestamp: DateTime(2026, 1, 1, 12),
      createdAt: DateTime(2026, 1, 1, 12),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [commentNotifierProvider.overrideWith(() => notifier)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          home: Scaffold(
            body: AddCommentSheet(
              sessionId: 'session-1',
              timestamp: DateTime(2026, 1, 1, 12),
              comment: comment,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Updated note');
    await tester.pump();

    final saveButton = find.widgetWithText(PrismButton, 'Save');
    await tester.tap(saveButton);
    await tester.tap(saveButton);

    expect(notifier.updateCalls, 1);
    expect(notifier.updated.single.body, 'Updated note');

    notifier.updateCompleter!.complete();
    await tester.pumpAndSettle();
  });
}

class _FakeCommentNotifier extends CommentNotifier {
  int createCalls = 0;
  int updateCalls = 0;
  final updated = <FrontSessionComment>[];
  Completer<void>? createCompleter;
  Completer<void>? updateCompleter;

  @override
  Future<void> build() async {}

  @override
  Future<void> createComment({
    required String sessionId,
    required String body,
    required DateTime timestamp,
  }) async {
    createCalls++;
    await createCompleter?.future;
  }

  @override
  Future<void> updateComment(FrontSessionComment comment) async {
    updateCalls++;
    updated.add(comment);
    await updateCompleter?.future;
  }
}
