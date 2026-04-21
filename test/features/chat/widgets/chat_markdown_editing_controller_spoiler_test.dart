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

  group('ChatMarkdownEditingController spoilers', () {
    testWidgets('empty text does not crash', (tester) async {
      final controller = ChatMarkdownEditingController(text: '');
      final children = await getSpanChildren(tester, controller);
      expect(children, isNull);
    });

    testWidgets('plain text around spoiler renders 5 spans', (tester) async {
      final controller =
          ChatMarkdownEditingController(text: 'say ||hi|| ok');
      final children = await getSpanChildren(tester, controller);

      expect(children, isNotNull);
      expect(children!.length, 5);
      expect((children[0] as TextSpan).text, 'say ');
      expect((children[1] as TextSpan).text, '||');
      expect((children[2] as TextSpan).text, 'hi');
      expect((children[3] as TextSpan).text, '||');
      expect((children[4] as TextSpan).text, ' ok');
    });

    testWidgets('spoiler content has tinted backgroundColor', (tester) async {
      final controller = ChatMarkdownEditingController(text: '||hi||');
      final children = await getSpanChildren(tester, controller);

      expect(children, isNotNull);
      expect(children!.length, 3);
      final content = children[1] as TextSpan;
      expect(content.text, 'hi');
      expect(content.style!.backgroundColor, isNotNull);
      // Alpha should be 40.
      expect(
        (content.style!.backgroundColor!.a * 255.0).round().clamp(0, 255),
        40,
      );
    });

    testWidgets('spoiler markers use dimmed muted color', (tester) async {
      final controller = ChatMarkdownEditingController(text: '||hi||');
      final children = await getSpanChildren(tester, controller);

      expect(children, isNotNull);
      final openMarker = children![0] as TextSpan;
      final closeMarker = children[2] as TextSpan;
      final content = children[1] as TextSpan;
      expect(openMarker.style!.color, closeMarker.style!.color);
      expect(content.style!.color, isNot(openMarker.style!.color));
    });

    testWidgets('caching: same text returns identical children list',
        (tester) async {
      final controller = ChatMarkdownEditingController(text: '||secret||');
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

      expect(identical(span1.children, span2.children), isTrue);
    });

    testWidgets('cache invalidates when text changes', (tester) async {
      final controller = ChatMarkdownEditingController(text: '||one||');
      await tester.pumpWidget(buildApp(controller));
      final context = tester.element(find.byType(TextField));
      controller.updateTheme(context);
      await tester.pump();

      final span1 = controller.buildTextSpan(
        context: context,
        style: const TextStyle(fontSize: 14),
        withComposing: false,
      );
      final firstChildren = span1.children;

      controller.text = '||two||';
      await tester.pump();

      final span2 = controller.buildTextSpan(
        context: context,
        style: const TextStyle(fontSize: 14),
        withComposing: false,
      );

      expect(identical(firstChildren, span2.children), isFalse);
      expect((span2.children![1] as TextSpan).text, 'two');
    });

    testWidgets(
        '**||hidden||** renders as dimmed bold markers wrapping tinted spoiler '
        '(bold does NOT apply — matches Discord)', (tester) async {
      final controller =
          ChatMarkdownEditingController(text: '**||hidden||**');
      final children = await getSpanChildren(tester, controller);

      expect(children, isNotNull);
      // Expected layout:
      //   [0] '**'     (plain baseStyle — bold skipped because inner
      //                 spoiler was already matched)
      //   [1] '||'     (dimmed spoiler marker)
      //   [2] 'hidden' (tinted spoiler content, NOT bold)
      //   [3] '||'     (dimmed spoiler marker)
      //   [4] '**'     (plain baseStyle)
      expect(children!.length, 5);
      expect((children[0] as TextSpan).text, '**');
      expect((children[1] as TextSpan).text, '||');
      expect((children[2] as TextSpan).text, 'hidden');
      expect((children[3] as TextSpan).text, '||');
      expect((children[4] as TextSpan).text, '**');

      // Content is spoiler-tinted, not bold.
      final content = children[2] as TextSpan;
      expect(content.style!.backgroundColor, isNotNull);
      expect(content.style!.fontWeight, isNot(FontWeight.bold));

      // Outer '**' runs are plain text (no marker dimming, no bold styling).
      final outerOpen = children[0] as TextSpan;
      final outerClose = children[4] as TextSpan;
      expect(outerOpen.style!.fontWeight, isNot(FontWeight.bold));
      expect(outerClose.style!.fontWeight, isNot(FontWeight.bold));
    });
  });
}
