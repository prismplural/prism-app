import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/widgets/session_comments_section.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

import '../../../helpers/fake_repositories.dart';

void main() {
  testWidgets('new comments on active fronts default to the current time', (
    tester,
  ) async {
    final commentsRepo = FakeFrontSessionCommentsRepository();
    final session = FrontingSession(
      id: 'active-session',
      memberId: 'member-1',
      startTime: DateTime(2001, 1, 2, 3, 4),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          frontSessionCommentsRepositoryProvider.overrideWithValue(
            commentsRepo,
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          home: Scaffold(body: SessionCommentsSection(session: session)),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final openedAt = DateTime.now();
    await tester.tap(find.byIcon(AppIcons.addCommentOutlined));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(EditableText), 'current note');
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    final savedAt = DateTime.now();

    expect(commentsRepo.comments, hasLength(1));
    final timestamp = commentsRepo.comments.single.timestamp;
    expect(timestamp.isBefore(openedAt), isFalse);
    expect(timestamp.isAfter(savedAt), isFalse);
  });
}
