import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/chat/widgets/chat_markdown_editing_controller.dart';

void main() {
  Widget buildApp(ChatMarkdownEditingController controller) {
    return MaterialApp(
      home: Scaffold(
        body: TextField(controller: controller),
      ),
    );
  }

  /// Helper to pump, call updateTheme, and return the built TextSpan children.
  Future<List<InlineSpan>?> getSpanChildren(
    WidgetTester tester,
    ChatMarkdownEditingController controller, {
    bool callUpdateTheme = true,
  }) async {
    await tester.pumpWidget(buildApp(controller));
    if (callUpdateTheme) {
      final context = tester.element(find.byType(TextField));
      controller.updateTheme(context);
    }
    await tester.pump();

    final context = tester.element(find.byType(TextField));
    final span = controller.buildTextSpan(
      context: context,
      style: const TextStyle(fontSize: 14),
      withComposing: false,
    );
    return span.children;
  }

  group('ChatMarkdownEditingController', () {
    group('fallback cases', () {
      testWidgets('empty text falls back to super.buildTextSpan',
          (tester) async {
        final controller = ChatMarkdownEditingController(text: '');
        final children = await getSpanChildren(tester, controller);

        // super.buildTextSpan returns a TextSpan with no children for empty
        // text, so children is null.
        expect(children, isNull);
      });

      testWidgets(
          'before updateTheme is called falls back to super.buildTextSpan',
          (tester) async {
        final controller = ChatMarkdownEditingController(text: '**bold**');
        final children = await getSpanChildren(
          tester,
          controller,
          callUpdateTheme: false,
        );

        // Without updateTheme, _themeReady is false, so it falls back.
        expect(children, isNull);
      });
    });

    group('plain text', () {
      testWidgets('renders single span for plain text', (tester) async {
        final controller = ChatMarkdownEditingController(text: 'hello');
        final children = await getSpanChildren(tester, controller);

        expect(children, isNotNull);
        expect(children!.length, 1);
        expect((children[0] as TextSpan).text, 'hello');
      });
    });

    group('bold stars', () {
      testWidgets('parses **bold** into 3 children', (tester) async {
        final controller = ChatMarkdownEditingController(text: '**bold**');
        final children = await getSpanChildren(tester, controller);

        expect(children, isNotNull);
        expect(children!.length, 3);
        expect((children[0] as TextSpan).text, '**');
        expect((children[1] as TextSpan).text, 'bold');
        expect(
          (children[1] as TextSpan).style!.fontWeight,
          FontWeight.bold,
        );
        expect((children[2] as TextSpan).text, '**');
      });

      testWidgets('parses hello **world** into 4 children', (tester) async {
        final controller =
            ChatMarkdownEditingController(text: 'hello **world**');
        final children = await getSpanChildren(tester, controller);

        expect(children, isNotNull);
        expect(children!.length, 4);
        expect((children[0] as TextSpan).text, 'hello ');
        expect((children[1] as TextSpan).text, '**');
        expect((children[2] as TextSpan).text, 'world');
        expect(
          (children[2] as TextSpan).style!.fontWeight,
          FontWeight.bold,
        );
        expect((children[3] as TextSpan).text, '**');
      });
    });

    group('bold underscores (__bold__ = bold in chat, not underline)', () {
      testWidgets('parses __bold__ into 3 children with FontWeight.bold',
          (tester) async {
        final controller = ChatMarkdownEditingController(text: '__bold__');
        final children = await getSpanChildren(tester, controller);

        expect(children, isNotNull);
        expect(children!.length, 3);
        expect((children[0] as TextSpan).text, '__');
        expect((children[1] as TextSpan).text, 'bold');
        expect(
          (children[1] as TextSpan).style!.fontWeight,
          FontWeight.bold,
        );
        expect((children[2] as TextSpan).text, '__');
      });

      testWidgets('__bold__ content has no underline decoration',
          (tester) async {
        final controller = ChatMarkdownEditingController(text: '__bold__');
        final children = await getSpanChildren(tester, controller);

        expect(children, isNotNull);
        final contentSpan = children![1] as TextSpan;
        expect(contentSpan.style!.decoration, isNot(TextDecoration.underline));
      });
    });

    group('italic star', () {
      testWidgets('parses *italic* into 3 children', (tester) async {
        final controller = ChatMarkdownEditingController(text: '*italic*');
        final children = await getSpanChildren(tester, controller);

        expect(children, isNotNull);
        expect(children!.length, 3);
        expect((children[0] as TextSpan).text, '*');
        expect((children[1] as TextSpan).text, 'italic');
        expect(
          (children[1] as TextSpan).style!.fontStyle,
          FontStyle.italic,
        );
        expect((children[2] as TextSpan).text, '*');
      });
    });

    group('italic underscore', () {
      testWidgets('parses _italic_ into 3 children', (tester) async {
        final controller = ChatMarkdownEditingController(text: '_italic_');
        final children = await getSpanChildren(tester, controller);

        expect(children, isNotNull);
        expect(children!.length, 3);
        expect((children[0] as TextSpan).text, '_');
        expect((children[1] as TextSpan).text, 'italic');
        expect(
          (children[1] as TextSpan).style!.fontStyle,
          FontStyle.italic,
        );
        expect((children[2] as TextSpan).text, '_');
      });
    });

    group('no heading or horizontal rule handling', () {
      testWidgets('# foo renders as plain text (1 child)', (tester) async {
        final controller = ChatMarkdownEditingController(text: '# foo');
        final children = await getSpanChildren(tester, controller);

        expect(children, isNotNull);
        expect(children!.length, 1);
        expect((children[0] as TextSpan).text, '# foo');
      });

      testWidgets('## foo renders as plain text (1 child)', (tester) async {
        final controller = ChatMarkdownEditingController(text: '## foo');
        final children = await getSpanChildren(tester, controller);

        expect(children, isNotNull);
        expect(children!.length, 1);
        expect((children[0] as TextSpan).text, '## foo');
      });

      testWidgets('--- renders as plain text (1 child)', (tester) async {
        final controller = ChatMarkdownEditingController(text: '---');
        final children = await getSpanChildren(tester, controller);

        expect(children, isNotNull);
        expect(children!.length, 1);
        expect((children[0] as TextSpan).text, '---');
      });
    });

    group('precedence and overlap exclusion', () {
      testWidgets('**foo** does not also trip single-star italic',
          (tester) async {
        final controller = ChatMarkdownEditingController(text: '**foo**');
        final children = await getSpanChildren(tester, controller);

        // Only 3 children: marker, content (bold), marker.
        // The inner *foo* must NOT produce italic children.
        expect(children, isNotNull);
        expect(children!.length, 3);
        expect(
          (children[1] as TextSpan).style!.fontWeight,
          FontWeight.bold,
        );
        expect(
          (children[1] as TextSpan).style!.fontStyle,
          isNot(FontStyle.italic),
        );
      });

      testWidgets('__foo__ does not also trip single-underscore italic',
          (tester) async {
        final controller = ChatMarkdownEditingController(text: '__foo__');
        final children = await getSpanChildren(tester, controller);

        expect(children, isNotNull);
        expect(children!.length, 3);
        expect(
          (children[1] as TextSpan).style!.fontWeight,
          FontWeight.bold,
        );
        expect(
          (children[1] as TextSpan).style!.fontStyle,
          isNot(FontStyle.italic),
        );
      });
    });

    group('caching', () {
      testWidgets('second buildTextSpan call returns same children list',
          (tester) async {
        final controller = ChatMarkdownEditingController(text: '**cached**');
        await tester.pumpWidget(buildApp(controller));
        final context = tester.element(find.byType(TextField));
        controller.updateTheme(context);
        await tester.pump();

        final span1 = controller.buildTextSpan(
          context: context,
          style: const TextStyle(fontSize: 14),
          withComposing: false,
        );
        final span2 = controller.buildTextSpan(
          context: context,
          style: const TextStyle(fontSize: 14),
          withComposing: false,
        );

        // Same list identity on second call.
        expect(identical(span1.children, span2.children), isTrue);
      });
    });

    group('marker color', () {
      testWidgets('markers use softer muted color (alpha 180)', (tester) async {
        final controller = ChatMarkdownEditingController(text: '**bold**');
        final children = await getSpanChildren(tester, controller);

        expect(children, isNotNull);
        final openMarker = children![0] as TextSpan;
        final closeMarker = children[2] as TextSpan;
        final content = children[1] as TextSpan;

        // Both markers share the same muted color.
        expect(openMarker.style!.color, closeMarker.style!.color);
        // Content color differs from marker color.
        expect(content.style!.color, isNot(openMarker.style!.color));
        // Marker alpha should be 180 (softer than notes' 102).
        expect(
          (openMarker.style!.color!.a * 255.0).round().clamp(0, 255),
          180,
        );
      });
    });
  });
}
