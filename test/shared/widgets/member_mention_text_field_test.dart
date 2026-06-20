import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/providers/member_avatar_image_provider.dart';
import 'package:prism_plurality/shared/widgets/member_mention_text_field.dart';

void main() {
  const aliceId = '11111111-2222-3333-4444-555555555555';
  final alice = Member(id: aliceId, name: 'Alice', createdAt: DateTime(2026));
  final longNameMember = Member(
    id: '22222222-3333-4444-5555-666666666666',
    name: 'aaaaaaaaaaaaaaaaaaaaaaaa',
    createdAt: DateTime(2026),
  );

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

  testWidgets('tapping a member suggestion inserts durable token', (
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

    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    expect(controller.text, 'hi @[$aliceId] ');
    expect(find.byKey(const Key('memberMentionOverlaySurface')), findsNothing);
  });

  testWidgets('keeps suggestions visible for tall multiline fields', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 260);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.only(top: 16, left: 16, right: 16),
              child: MemberMentionTextField(
                controller: controller,
                focusNode: focusNode,
                mentionCandidates: [alice],
                minLines: 12,
                maxLines: null,
                hintText: 'Body',
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '@al');
    await tester.pumpAndSettle();

    final overlay = find.byKey(const Key('memberMentionOverlaySurface'));
    expect(overlay, findsOneWidget);
    final topLeft = tester.getTopLeft(overlay);
    final bottomRight = tester.getBottomRight(overlay);
    expect(topLeft.dy, greaterThanOrEqualTo(0));
    expect(bottomRight.dy, lessThanOrEqualTo(260));
  });

  testWidgets('keeps suggestions anchored while typing a mention filter', (
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
    await tester.enterText(find.byType(TextField), '@a');
    await tester.pumpAndSettle();

    final overlay = find.byKey(const Key('memberMentionOverlaySurface'));
    expect(overlay, findsOneWidget);
    final initialTopLeft = tester.getTopLeft(overlay);

    await tester.enterText(find.byType(TextField), '@al');
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(overlay), initialTopLeft);
  });

  testWidgets('refreshes suggestion anchor when the filter wraps lines', (
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
                width: 96,
                child: MemberMentionTextField(
                  controller: controller,
                  focusNode: focusNode,
                  mentionCandidates: [longNameMember],
                  minLines: 3,
                  maxLines: null,
                  hintText: 'Body',
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '@aaaa');
    await tester.pumpAndSettle();

    final overlay = find.byKey(const Key('memberMentionOverlaySurface'));
    expect(overlay, findsOneWidget);
    final initialTop = tester.getTopLeft(overlay).dy;

    await tester.enterText(find.byType(TextField), '@aaaaaaaaaaaaaaaaaaaa');
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(overlay).dy, greaterThan(initialTop));
  });

  testWidgets('hydrates avatar photos for lightweight mention candidates', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          memberAvatarImageDataProvider.overrideWith(
            (ref, memberId) =>
                Stream.value(memberId == aliceId ? _pngBytes() : null),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
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
    await tester.enterText(find.byType(TextField), '@al');
    await tester.pumpAndSettle();

    final overlay = find.byKey(const Key('memberMentionOverlaySurface'));
    expect(overlay, findsOneWidget);
    expect(
      find.descendant(of: overlay, matching: find.byType(Image)),
      findsOneWidget,
    );
  });

  testWidgets('plain companion field does not create a duplicate menu', (
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
            body: Column(
              children: [
                Offstage(child: TextField(controller: controller)),
                SizedBox(
                  width: 360,
                  child: MemberMentionTextField(
                    controller: controller,
                    focusNode: focusNode,
                    mentionCandidates: [alice],
                    hintText: 'Body',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '@a');
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('memberMentionOverlaySurface')),
      findsOneWidget,
    );
  });

  testWidgets(
    'unfocused companion mention field does not create a duplicate menu',
    (tester) async {
      final controller = TextEditingController();
      final inactiveFocusNode = FocusNode();
      final activeFocusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(inactiveFocusNode.dispose);
      addTearDown(activeFocusNode.dispose);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  SizedBox(
                    width: 360,
                    child: ExcludeFocus(
                      child: MemberMentionTextField(
                        controller: controller,
                        focusNode: inactiveFocusNode,
                        mentionCandidates: [alice],
                        hintText: 'Inactive',
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 360,
                    child: MemberMentionTextField(
                      controller: controller,
                      focusNode: activeFocusNode,
                      mentionCandidates: [alice],
                      hintText: 'Active',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.widgetWithText(TextField, 'Active'));
      await tester.enterText(find.widgetWithText(TextField, 'Active'), '@a');
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('memberMentionOverlaySurface')),
        findsOneWidget,
      );
    },
  );

  testWidgets('dismisses suggestions when the field loses focus', (
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
    await tester.enterText(find.byType(TextField), '@a');
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('memberMentionOverlaySurface')),
      findsOneWidget,
    );

    focusNode.unfocus();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('memberMentionOverlaySurface')), findsNothing);
  });

  testWidgets('keyboard arrows jump over durable mention tokens', (
    tester,
  ) async {
    const mention = '@[$aliceId]';
    final controller = TextEditingController(text: 'hi $mention there');
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

    final mentionStart = controller.text.indexOf('@[');
    final mentionEnd = mentionStart + mention.length;

    await tester.tap(find.byType(TextField));
    controller.selection = TextSelection.collapsed(offset: mentionStart);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(controller.selection.baseOffset, mentionEnd);

    controller.selection = TextSelection.collapsed(offset: mentionEnd);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();

    expect(controller.selection.baseOffset, mentionStart);
  });
}

Uint8List _pngBytes() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=',
);
