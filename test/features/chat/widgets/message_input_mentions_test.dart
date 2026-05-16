import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/providers/klipy_providers.dart';
import 'package:prism_plurality/features/chat/services/klipy_service.dart';
import 'package:prism_plurality/features/chat/widgets/mention_overlay.dart';
import 'package:prism_plurality/features/chat/widgets/message_input.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

class _FixedSpeakingAsNotifier extends SpeakingAsNotifier {
  _FixedSpeakingAsNotifier(this.memberId);

  final String? memberId;

  @override
  String? build() => memberId;
}

void main() {
  const aliceId = '00000000-0000-0000-0000-000000000001';
  const bobId = '00000000-0000-0000-0000-000000000002';
  const caseyId = '00000000-0000-0000-0000-000000000003';
  const drewId = '00000000-0000-0000-0000-000000000004';
  const eliId = '00000000-0000-0000-0000-000000000005';
  const fayeId = '00000000-0000-0000-0000-000000000006';

  final alice = Member(
    id: aliceId,
    name: 'Alice',
    createdAt: DateTime(2025, 1, 1),
    isActive: true,
  );
  final bob = Member(
    id: bobId,
    name: 'Bob',
    createdAt: DateTime(2025, 1, 1),
    isActive: true,
  );
  final casey = Member(
    id: caseyId,
    name: 'Casey',
    createdAt: DateTime(2025, 1, 1),
    isActive: true,
  );
  final drew = Member(
    id: drewId,
    name: 'Drew',
    createdAt: DateTime(2025, 1, 1),
    isActive: true,
  );
  final eli = Member(
    id: eliId,
    name: 'Eli',
    createdAt: DateTime(2025, 1, 1),
    isActive: true,
  );
  final faye = Member(
    id: fayeId,
    name: 'Faye',
    createdAt: DateTime(2025, 1, 1),
    isActive: true,
  );
  final conversation = Conversation(
    id: 'conv-1',
    participantIds: const [aliceId, bobId],
    createdAt: DateTime(2025, 1, 1),
    lastActivityAt: DateTime(2025, 1, 1),
    isDirectMessage: false,
  );

  Widget buildSubject(
    Stream<List<Member>> membersStream, {
    Conversation? testConversation,
    ChatNotifier Function()? chatNotifierFactory,
  }) {
    return ProviderScope(
      overrides: [
        systemSettingsProvider.overrideWith(
          (ref) => Stream.value(const SystemSettings()),
        ),
        gifServiceConfigProvider.overrideWith(
          (ref) async => const GifServiceConfig.disabled(),
        ),
        speakingAsProvider.overrideWith(
          () => _FixedSpeakingAsNotifier(aliceId),
        ),
        activeMembersProvider.overrideWith((ref) => membersStream),
        allGroupsProvider.overrideWith(
          (ref) => Stream.value(const <MemberGroup>[]),
        ),
        allGroupEntriesProvider.overrideWith(
          (ref) => Stream.value(const <MemberGroupEntry>[]),
        ),
        conversationByIdProvider(
          'conv-1',
        ).overrideWith((ref) => Stream.value(testConversation ?? conversation)),
        if (chatNotifierFactory != null)
          chatNotifierProvider.overrideWith(chatNotifierFactory),
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

  testWidgets('mention menu stays constrained and inserts selected member', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(buildSubject(Stream.value([alice, bob, casey])));
    await tester.pumpAndSettle();

    final textFieldTopLeftBefore = tester.getTopLeft(find.byType(TextField));

    await tester.enterText(find.byType(TextField), '@A');
    await tester.pumpAndSettle();

    expect(find.byType(MentionOverlay), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Casey'), findsOneWidget);
    expect(find.text('Bob'), findsNothing);
    expect(tester.getTopLeft(find.byType(TextField)), textFieldTopLeftBefore);

    final overlaySize = tester.getSize(
      find.byKey(const Key('mentionOverlaySurface')),
    );
    expect(overlaySize.width, lessThan(400));
    expect(overlaySize.height, lessThanOrEqualTo(240));
    expect(
      tester.getTopRight(find.byKey(const Key('mentionOverlaySurface'))).dx,
      lessThanOrEqualTo(
        tester.view.physicalSize.width / tester.view.devicePixelRatio,
      ),
    );

    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, '@[$aliceId] ');
    expect(find.byType(MentionOverlay), findsNothing);
    final semanticsNode = tester.getSemantics(find.byType(EditableText));
    final semanticsData = semanticsNode.getSemanticsData();
    expect(semanticsData.value, '@Alice ');
    semantics.dispose();
  });

  testWidgets('mention menu inserts broadcast aliases literally', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject(Stream.value([alice, bob, casey])));
    await tester.pumpAndSettle();

    final textField = find.byType(TextField);

    await tester.enterText(textField, '@a');
    await tester.pumpAndSettle();
    expect(find.text('@all'), findsOneWidget);

    await tester.tap(find.text('@all'));
    await tester.pumpAndSettle();

    var field = tester.widget<TextField>(textField);
    expect(field.controller?.text, '@all ');
    expect(find.byType(MentionOverlay), findsNothing);

    await tester.enterText(textField, '@e');
    await tester.pumpAndSettle();
    expect(find.text('@everyone'), findsOneWidget);

    await tester.tap(find.text('@everyone'));
    await tester.pumpAndSettle();

    field = tester.widget<TextField>(textField);
    expect(field.controller?.text, '@everyone ');
    expect(find.byType(MentionOverlay), findsNothing);
  });

  testWidgets(
    'keyboard selection prefers member matches over broadcast aliases',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await tester.pumpWidget(
          buildSubject(Stream.value([alice, bob, casey])),
        );
        await tester.pumpAndSettle();

        final textField = find.byType(TextField);

        await tester.tap(textField);
        await tester.pumpAndSettle();
        await tester.enterText(textField, '@A');
        await tester.pumpAndSettle();

        expect(find.text('Alice'), findsOneWidget);
        expect(find.text('@all'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        final field = tester.widget<TextField>(textField);
        expect(field.controller?.text, '@[$aliceId] ');
        expect(find.byType(MentionOverlay), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('mention menu repopulates when members load after typing @', (
    tester,
  ) async {
    final membersController = StreamController<List<Member>>();
    addTearDown(membersController.close);

    await tester.pumpWidget(buildSubject(membersController.stream));
    membersController.add(const []);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '@Ali');
    await tester.pumpAndSettle();

    expect(find.byType(MentionOverlay), findsNothing);

    membersController.add([alice, bob]);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(MentionOverlay), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
  });

  for (final alias in ['@all', '@everyone']) {
    testWidgets('sending $alias asks for confirmation with five recipients', (
      tester,
    ) async {
      final notifier = _RecordingChatNotifier();
      final largeConversation = conversation.copyWith(
        participantIds: const [aliceId, bobId, caseyId, drewId, eliId, fayeId],
      );

      await tester.pumpWidget(
        buildSubject(
          Stream.value([alice, bob, casey, drew, eli, faye]),
          testConversation: largeConversation,
          chatNotifierFactory: () => notifier,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '$alias hello');
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Send message'));
      await tester.pumpAndSettle();

      expect(find.text('Mention everyone in this chat?'), findsOneWidget);
      expect(
        find.text('This will notify all 5 other participants in this chat.'),
        findsOneWidget,
      );
      expect(notifier.sentContents, isEmpty);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(notifier.sentContents, isEmpty);

      await tester.tap(find.bySemanticsLabel('Send message'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(notifier.sentContents, ['$alias hello']);
    });
  }

  for (final entry in {
    'parenthesized @all': 'Heads up (@all)',
    'bracketed @everyone': 'Heads up [@everyone]',
    'mixed-case @All': 'Heads up @All',
  }.entries) {
    testWidgets('${entry.key} asks for confirmation with five recipients', (
      tester,
    ) async {
      final notifier = _RecordingChatNotifier();
      final largeConversation = conversation.copyWith(
        participantIds: const [aliceId, bobId, caseyId, drewId, eliId, fayeId],
      );

      await tester.pumpWidget(
        buildSubject(
          Stream.value([alice, bob, casey, drew, eli, faye]),
          testConversation: largeConversation,
          chatNotifierFactory: () => notifier,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), entry.value);
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Send message'));
      await tester.pumpAndSettle();

      expect(find.text('Mention everyone in this chat?'), findsOneWidget);
      expect(notifier.sentContents, isEmpty);
    });
  }

  testWidgets('broadcast mention below threshold sends without confirmation', (
    tester,
  ) async {
    final notifier = _RecordingChatNotifier();

    await tester.pumpWidget(
      buildSubject(
        Stream.value([alice, bob]),
        chatNotifierFactory: () => notifier,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '@all hello');
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Send message'));
    await tester.pumpAndSettle();

    expect(find.text('Mention everyone in this chat?'), findsNothing);
    expect(notifier.sentContents, ['@all hello']);
  });

  testWidgets(
    'broadcast mention with four recipients sends without confirmation',
    (tester) async {
      final notifier = _RecordingChatNotifier();
      final mediumConversation = conversation.copyWith(
        participantIds: const [aliceId, bobId, caseyId, drewId, eliId],
      );

      await tester.pumpWidget(
        buildSubject(
          Stream.value([alice, bob, casey, drew, eli]),
          testConversation: mediumConversation,
          chatNotifierFactory: () => notifier,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '@everyone hello');
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Send message'));
      await tester.pumpAndSettle();

      expect(find.text('Mention everyone in this chat?'), findsNothing);
      expect(notifier.sentContents, ['@everyone hello']);
    },
  );

  testWidgets('draft mention resolves again after members reload', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final membersController = StreamController<List<Member>>();
    addTearDown(membersController.close);

    await tester.pumpWidget(buildSubject(membersController.stream));
    membersController.add([alice, bob]);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '@[$aliceId] ');
    await tester.pumpAndSettle();

    var data = tester
        .getSemantics(find.byType(EditableText))
        .getSemanticsData();
    expect(data.value, '@Alice ');

    membersController.add(const []);
    await tester.pump();
    await tester.pumpAndSettle();

    membersController.add([alice, bob]);
    await tester.pump();
    await tester.pumpAndSettle();

    data = tester.getSemantics(find.byType(EditableText)).getSemanticsData();
    expect(data.value, '@Alice ');
    semantics.dispose();
  });
}

class _RecordingChatNotifier extends ChatNotifier {
  final sentContents = <String>[];

  @override
  Future<String> sendMessage({
    required String conversationId,
    required String content,
    required String authorId,
    String? messageId,
    String? replyToId,
    String? replyToAuthorId,
    String? replyToContent,
  }) async {
    sentContents.add(content);
    return 'message-id-${sentContents.length}';
  }
}
