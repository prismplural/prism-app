import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/providers/klipy_providers.dart';
import 'package:prism_plurality/features/chat/services/klipy_service.dart';
import 'package:prism_plurality/features/chat/widgets/message_input.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';

class _FixedSpeakingAsNotifier extends SpeakingAsNotifier {
  _FixedSpeakingAsNotifier(this.memberId);

  final String? memberId;

  @override
  String? build() => memberId;
}

void main() {
  final alice = Member(
    id: 'alice-id',
    name: 'Alice',
    createdAt: DateTime(2025, 1, 1),
    isActive: true,
  );
  final bob = Member(
    id: 'bob-id',
    name: 'Bob',
    createdAt: DateTime(2025, 1, 1),
    isActive: true,
  );
  final conversation = Conversation(
    id: 'conv-1',
    participantIds: const ['alice-id', 'bob-id'],
    createdAt: DateTime(2025, 1, 1),
    lastActivityAt: DateTime(2025, 1, 1),
    isDirectMessage: false,
  );
  final cluster = MemberGroup(
    id: 'group-1',
    name: 'Cluster',
    createdAt: DateTime(2025, 1, 1),
  );

  Widget buildSubject() {
    return ProviderScope(
      overrides: [
        systemSettingsProvider.overrideWith(
          (ref) => Stream.value(const SystemSettings()),
        ),
        gifServiceConfigProvider.overrideWith(
          (ref) async => const GifServiceConfig.disabled(),
        ),
        speakingAsProvider.overrideWith(
          () => _FixedSpeakingAsNotifier('alice-id'),
        ),
        activeMembersProvider.overrideWith((ref) => Stream.value([alice, bob])),
        allGroupsProvider.overrideWith((ref) => Stream.value([cluster])),
        allGroupEntriesProvider.overrideWith(
          (ref) => Stream.value(const [
            MemberGroupEntry(
              id: 'entry-1',
              groupId: 'group-1',
              memberId: 'alice-id',
            ),
          ]),
        ),
        conversationByIdProvider(
          'conv-1',
        ).overrideWith((ref) => Stream.value(conversation)),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: const Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: MessageInput(conversationId: 'conv-1'),
          ),
        ),
      ),
    );
  }

  testWidgets('member popup exposes Search and launches grouped search sheet', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(BlurPopupAnchor).first);
    await tester.pumpAndSettle();

    expect(find.text('Search'), findsOneWidget);

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(find.byType(MemberSearchSheet), findsOneWidget);
    expect(find.text('Cluster'), findsOneWidget);
  });
}
