import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class _NullSpeakingAsNotifier extends SpeakingAsNotifier {
  @override
  String? build() => null;
}

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
    proxyTagsJson: '[{"prefix":"A:","suffix":null}]',
  );
  final bob = Member(
    id: 'bob-id',
    name: 'Bob',
    createdAt: DateTime(2025, 1, 1),
    isActive: true,
    proxyTagsJson: '[{"prefix":"B:","suffix":null}]',
  );

  final conversation = Conversation(
    id: 'conv-1',
    participantIds: const ['alice-id', 'bob-id'],
    createdAt: DateTime(2025, 1, 1),
    lastActivityAt: DateTime(2025, 1, 1),
    isDirectMessage: false,
  );
  final dmConversation = Conversation(
    id: 'dm-1',
    participantIds: const ['alice-id', 'bob-id'],
    createdAt: DateTime(2025, 1, 1),
    lastActivityAt: DateTime(2025, 1, 1),
    isDirectMessage: true,
  );
  final admin = Member(
    id: 'admin-id',
    name: 'Admin',
    createdAt: DateTime(2025, 1, 1),
    isActive: true,
    isAdmin: true,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildSubject({required bool proxyTagsEnabled}) {
    return ProviderScope(
      overrides: [
        systemSettingsProvider.overrideWith(
          (ref) => Stream.value(const SystemSettings()),
        ),
        gifServiceConfigProvider.overrideWith(
          (ref) async => const GifServiceConfig.disabled(),
        ),
        speakingAsProvider.overrideWith(_NullSpeakingAsNotifier.new),
        activeMembersProvider.overrideWith((ref) => Stream.value([alice, bob])),
        allGroupsProvider.overrideWith(
          (ref) => Stream.value(const <MemberGroup>[]),
        ),
        allGroupEntriesProvider.overrideWith(
          (ref) => Stream.value(const <MemberGroupEntry>[]),
        ),
        conversationByIdProvider(
          'conv-1',
        ).overrideWith((ref) => Stream.value(conversation)),
        useProxyTagsForAuthoringProvider.overrideWith(
          () => _FixedProxyTagNotifier(proxyTagsEnabled),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: const Scaffold(body: MessageInput(conversationId: 'conv-1')),
      ),
    );
  }

  group('MessageInput proxy-tag authoring', () {
    testWidgets('no chip when toggle is off, even with matching text', (
      tester,
    ) async {
      await tester.pumpWidget(buildSubject(proxyTagsEnabled: false));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'A: hello');
      await tester.pumpAndSettle();

      expect(find.textContaining('Posting as Alice'), findsNothing);
    });

    testWidgets('chip appears and send enables when tag matches', (
      tester,
    ) async {
      await tester.pumpWidget(buildSubject(proxyTagsEnabled: true));
      await tester.pumpAndSettle();

      // speakingAs is null → send button should be disabled initially.
      await tester.enterText(find.byType(TextField), 'A: hello');
      await tester.pumpAndSettle();

      expect(find.textContaining('Posting as Alice'), findsOneWidget);
      // With a proxy match, the send button becomes enabled even though
      // speakingAs is null.
      expect(find.bySemanticsLabel('Send message'), findsOneWidget);
    });

    testWidgets('dismissing chip suppresses for same tag+member', (
      tester,
    ) async {
      await tester.pumpWidget(buildSubject(proxyTagsEnabled: true));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'A: hello');
      await tester.pumpAndSettle();
      expect(find.textContaining('Posting as Alice'), findsOneWidget);

      // Tap the chip dismiss button.
      await tester.tap(find.bySemanticsLabel("Don't post as proxy"));
      await tester.pumpAndSettle();
      expect(find.textContaining('Posting as Alice'), findsNothing);

      // Typing a different tag re-opens the chip (different member).
      await tester.enterText(find.byType(TextField), 'B: hi');
      await tester.pumpAndSettle();
      expect(find.textContaining('Posting as Bob'), findsOneWidget);
    });

    testWidgets('admin read-only DM access keeps send disabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            systemSettingsProvider.overrideWith(
              (ref) => Stream.value(const SystemSettings()),
            ),
            gifServiceConfigProvider.overrideWith(
              (ref) async => const GifServiceConfig.disabled(),
            ),
            speakingAsProvider.overrideWith(
              () => _FixedSpeakingAsNotifier('admin-id'),
            ),
            activeMembersProvider.overrideWith(
              (ref) => Stream.value([alice, bob, admin]),
            ),
            allGroupsProvider.overrideWith(
              (ref) => Stream.value(const <MemberGroup>[]),
            ),
            allGroupEntriesProvider.overrideWith(
              (ref) => Stream.value(const <MemberGroupEntry>[]),
            ),
            conversationByIdProvider(
              'dm-1',
            ).overrideWith((ref) => Stream.value(dmConversation)),
            useProxyTagsForAuthoringProvider.overrideWith(
              () => _FixedProxyTagNotifier(false),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            home: const Scaffold(body: MessageInput(conversationId: 'dm-1')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Send message, disabled'), findsOneWidget);
    });
  });
}

class _FixedProxyTagNotifier extends UseProxyTagsForAuthoringNotifier {
  _FixedProxyTagNotifier(this._value);
  final bool _value;

  @override
  Future<bool> build() async => _value;
}
