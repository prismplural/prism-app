import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/polls/providers/poll_providers.dart';
import 'package:prism_plurality/features/polls/views/poll_detail_screen.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

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
          activeSessionProvider.overrideWith((ref) => Stream.value(null)),
          systemSettingsProvider.overrideWith(
            (ref) => Stream.value(const SystemSettings()),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(buildSubject(container));
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(container.read(votingAsProvider), 'member-1');
      expect(find.text('Favorite color?'), findsOneWidget);
    },
  );
}
