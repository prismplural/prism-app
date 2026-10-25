import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/shared/theme/app_theme.dart';
import 'package:prism_plurality/shared/widgets/markdown_text.dart';

void main() {
  const aliceId = '11111111-2222-3333-4444-555555555555';
  const ghostId = 'abcdef12-3456-7890-abcd-ef1234567890';
  final alice = Member(id: aliceId, name: 'Alice', createdAt: DateTime(2026));

  testWidgets('renders member mention tokens as display names', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownText(
            data: 'Hi @[$aliceId] and @[$ghostId]',
            memberMap: {alice.id: alice},
          ),
        ),
      ),
    );

    expect(find.textContaining('@Alice'), findsOneWidget);
    expect(find.textContaining('@Unknown'), findsOneWidget);
    expect(find.textContaining('@[$aliceId]'), findsNothing);
    expect(find.textContaining('@[$ghostId]'), findsNothing);
  });

  for (final spacing in <double?>[null, 2]) {
    testWidgets(
      spacing == null
          ? 'keeps tappable member mentions inline with surrounding text'
          : 'keeps mention glyphs tappable with adjusted letter spacing',
      (tester) async {
        String? tappedMemberId;
        var tapCount = 0;

        await tester.pumpWidget(
          MaterialApp(
            theme: spacing == null
                ? null
                : AppTheme.withLetterSpacing(ThemeData(), spacing),
            home: Scaffold(
              body: MarkdownText(
                data: 'hello @[$aliceId]',
                memberMap: {alice.id: alice},
                onTapMember: (id) {
                  tappedMemberId = id;
                  tapCount++;
                },
              ),
            ),
          ),
        );

        expect(find.textContaining('hello @Alice'), findsOneWidget);

        // The whole paragraph's center can fall on unlinked prose. Hit the
        // rendered glyph ranges instead, and ensure only the mention responds.
        await _tapGlyphs(tester, 'hello @Alice', 'hello');
        expect(tappedMemberId, isNull);
        expect(tapCount, 0);

        await _tapGlyphs(tester, 'hello @Alice', '@Alice');
        expect(tappedMemberId, aliceId);
        expect(tapCount, 1);
      },
    );
  }
}

Future<void> _tapGlyphs(
  WidgetTester tester,
  String paragraphText,
  String target,
) async {
  final richFinder = find.byWidgetPredicate(
    (widget) =>
        widget is RichText && widget.text.toPlainText() == paragraphText,
  );
  expect(richFinder, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(richFinder);
  final start = paragraphText.indexOf(target);
  expect(start, greaterThanOrEqualTo(0));
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: start + target.length),
  );
  expect(boxes, isNotEmpty);
  await tester.tapAt(paragraph.localToGlobal(boxes.first.toRect().center));
}
