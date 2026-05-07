import 'dart:async';

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
  final conversation = Conversation(
    id: 'conv-1',
    participantIds: const [aliceId, bobId],
    createdAt: DateTime(2025, 1, 1),
    lastActivityAt: DateTime(2025, 1, 1),
    isDirectMessage: false,
  );

  Widget buildSubject(Stream<List<Member>> membersStream) {
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
        ).overrideWith((ref) => Stream.value(conversation)),
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

  testWidgets('mention menu repopulates when members load after typing @', (
    tester,
  ) async {
    final membersController = StreamController<List<Member>>();
    addTearDown(membersController.close);

    await tester.pumpWidget(buildSubject(membersController.stream));
    membersController.add(const []);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '@A');
    await tester.pumpAndSettle();

    expect(find.byType(MentionOverlay), findsNothing);

    membersController.add([alice, bob]);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(MentionOverlay), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
  });

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
