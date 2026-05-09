import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/conversation_category.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/chat/providers/category_providers.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/views/conversation_info_sheet.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';

import '../../../helpers/fake_repositories.dart';

class _FixedSpeakingAsNotifier extends SpeakingAsNotifier {
  @override
  String? build() => 'alice';
}

void main() {
  testWidgets('category assignment opens a dialog from conversation info', (
    tester,
  ) async {
    final now = DateTime(2026, 5, 9);
    final conversationRepo = FakeConversationRepository()
      ..conversations.add(
        Conversation(
          id: 'conv-1',
          createdAt: now,
          lastActivityAt: now,
          title: 'General',
          creatorId: 'alice',
          participantIds: const ['alice', 'bob'],
        ),
      );
    final memberRepo = FakeMemberRepository()
      ..seed([
        Member(id: 'alice', name: 'Alice', createdAt: now),
        Member(id: 'bob', name: 'Bob', createdAt: now),
      ]);
    final category = ConversationCategory(
      id: 'fandoms',
      name: 'Fandoms',
      displayOrder: 0,
      createdAt: now,
      modifiedAt: now,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conversationRepositoryProvider.overrideWithValue(conversationRepo),
          memberRepositoryProvider.overrideWithValue(memberRepo),
          speakingAsProvider.overrideWith(_FixedSpeakingAsNotifier.new),
          allGroupsProvider.overrideWith(
            (ref) => Stream.value(const <MemberGroup>[]),
          ),
          allGroupEntriesProvider.overrideWith(
            (ref) => Stream.value(const <MemberGroupEntry>[]),
          ),
          conversationCategoriesProvider.overrideWith(
            (ref) => Stream.value([category]),
          ),
          systemSettingsProvider.overrideWith(
            (ref) => Stream.value(const SystemSettings()),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          home: Scaffold(
            body: ConversationInfoSheet(
              conversationId: 'conv-1',
              scrollController: ScrollController(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Category'));
    await tester.pumpAndSettle();

    expect(find.byType(PrismDialog), findsOneWidget);
    expect(find.text('Fandoms'), findsOneWidget);

    await tester.tap(find.text('Fandoms'));
    await tester.pumpAndSettle();

    expect(find.byType(PrismDialog), findsNothing);
    expect(conversationRepo.conversations.single.categoryId, 'fandoms');
  });
}
