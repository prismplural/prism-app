import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
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
  final carol = Member(
    id: 'carol-id',
    name: 'Carol',
    createdAt: DateTime(2025, 1, 1),
    isActive: true,
  );
  final unknown = Member(
    id: unknownSentinelMemberId,
    name: 'Unknown',
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

  Widget buildSubject({
    Conversation? conversationOverride,
    List<Member>? activeMembersOverride,
  }) {
    final testConversation = conversationOverride ?? conversation;
    final activeMembers = activeMembersOverride ?? [alice, bob];

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
        activeMembersProvider.overrideWith(
          (ref) => Stream.value(activeMembers),
        ),
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
        ).overrideWith((ref) => Stream.value(testConversation)),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: [Locale('en')],
        home: Scaffold(
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

    final searchTop = tester.getTopLeft(find.text('Search')).dy;
    final firstMemberTop = tester.getTopLeft(find.text('Alice')).dy;
    expect(
      searchTop,
      lessThan(firstMemberTop),
      reason: 'Search should be the first visible popup option.',
    );

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(find.byType(MemberSearchSheet), findsOneWidget);
    expect(find.text('Cluster'), findsOneWidget);
  });

  testWidgets('speaking-as popup in DMs only lists conversation participants', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildSubject(
        conversationOverride: conversation.copyWith(isDirectMessage: true),
        activeMembersOverride: [alice, bob, carol, unknown],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(BlurPopupAnchor).first);
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Carol'), findsNothing);
    expect(find.text('Unknown'), findsNothing);

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(find.byType(MemberSearchSheet), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Carol'), findsNothing);
    expect(find.text('Unknown'), findsNothing);
  });

  testWidgets('speaking-as popup in group chats keeps all active members', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildSubject(activeMembersOverride: [alice, bob, carol, unknown]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(BlurPopupAnchor).first);
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Carol'), findsOneWidget);
    expect(find.text('Unknown'), findsNothing);
  });

  testWidgets(
    'speaking-as popup Search row closes popup and shows sheet without '
    'Flutter errors (regression: BuildContext-after-await guard)',
    (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      // Open the blur popup, then tap the "Search" row. The production code
      // captures the parent BuildContext before `close()` + `await` so that
      // the mounted-guarded MemberSearchSheet.showSingle call does not hit
      // a deactivated popup context.
      await tester.tap(find.byType(BlurPopupAnchor).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();

      expect(find.byType(MemberSearchSheet), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason:
            'closing the blur popup and awaiting the member search sheet '
            'must not produce any Flutter framework exceptions',
      );
    },
  );

  testWidgets(
    'speaking-as popup drops composer focus when keyboard is closed',
    (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      final textFieldFinder = find.byType(TextField);
      await tester.tap(textFieldFinder);
      await tester.pump();

      final textField = tester.widget<TextField>(textFieldFinder);
      expect(textField.focusNode?.hasFocus, isTrue);
      expect(tester.view.viewInsets.bottom, 0);

      await tester.tap(find.byType(BlurPopupAnchor).first);
      await tester.pump();

      expect(textField.focusNode?.hasFocus, isFalse);
    },
  );

  testWidgets('speaking-as popup keeps composer focus while keyboard is open', (
    tester,
  ) async {
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    final textFieldFinder = find.byType(TextField);
    await tester.tap(textFieldFinder);
    await tester.pump();

    final textField = tester.widget<TextField>(textFieldFinder);
    expect(textField.focusNode?.hasFocus, isTrue);

    await tester.tap(find.byType(BlurPopupAnchor).first);
    await tester.pump();

    expect(textField.focusNode?.hasFocus, isTrue);
  });
}
