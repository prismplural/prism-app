import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/features/polls/models/poll_summary.dart';
import 'package:prism_plurality/features/polls/providers/poll_providers.dart';
import 'package:prism_plurality/features/polls/views/polls_list_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

void main() {
  Widget buildSubject(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: [Locale('en')],
        home: PollsListScreen(),
      ),
    );
  }

  testWidgets('defaults to the all-polls filter', (tester) async {
    final allPoll = PollSummary(
      id: 'poll-closed',
      question: 'Already closed',
      isAnonymous: false,
      allowsMultipleVotes: false,
      isClosed: true,
      expiresAt: null,
      createdAt: DateTime(2026, 4, 15),
      optionCount: 2,
      voteCount: 3,
    );
    final container = ProviderContainer(
      overrides: [
        activePollsProvider.overrideWith((ref) => Stream.value(const [])),
        closedPollsProvider.overrideWith((ref) => Stream.value(const [])),
        allPollsProvider.overrideWith((ref) => Stream.value([allPoll])),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(buildSubject(container));
    await tester.pump();

    expect(find.text('Already closed'), findsOneWidget);
  });
}
