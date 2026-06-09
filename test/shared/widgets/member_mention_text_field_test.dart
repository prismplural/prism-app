import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/shared/widgets/member_mention_text_field.dart';

void main() {
  const aliceId = '11111111-2222-3333-4444-555555555555';
  final alice = Member(id: aliceId, name: 'Alice', createdAt: DateTime(2026));

  testWidgets('shows member suggestions and inserts durable token', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 360,
                child: MemberMentionTextField(
                  controller: controller,
                  focusNode: focusNode,
                  mentionCandidates: [alice],
                  hintText: 'Body',
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'hi @al');
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('memberMentionOverlaySurface')),
      findsOneWidget,
    );
    expect(find.text('Alice'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(controller.text, 'hi @[$aliceId] ');
    expect(find.byKey(const Key('memberMentionOverlaySurface')), findsNothing);
  });
}
