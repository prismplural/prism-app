import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/widgets/markdown_editing_controller.dart';

void main() {
  Widget buildApp(MarkdownEditingController controller) {
    return MaterialApp(
      home: Scaffold(
        body: TextField(controller: controller),
      ),
    );
  }

  /// Helper to pump, call updateTheme, and return the built TextSpan children.
  Future<List<InlineSpan>?> getSpanChildren(
    WidgetTester tester,
    MarkdownEditingController controller, {
    bool callUpdateTheme = true,
  }) async {
    await tester.pumpWidget(buildApp(controller));
    if (callUpdateTheme) {
      final context = tester.element(find.byType(TextField));
      controller.updateTheme(context);
    }
    // Rebuild to pick up the theme.
    await tester.pump();

    final context = tester.element(find.byType(TextField));
    final span = controller.buildTextSpan(
      context: context,
      style: const TextStyle(fontSize: 14),
      withComposing: false,
    );
    return span.children;
  }

  group('MarkdownEditingController', () {
    group('plain text', () {
      testWidgets('renders single span for plain text', (tester) async {
        final controller = MarkdownEditingController(text: 'hello world');
        final children = await getSpanChildren(tester, controller);

        expect(children, isNotNull);
        expect(children!.length, 1);
        expect((children[0] as TextSpan).text, 'hello world');
      });
    });

    group('bold', () {
      testWidgets('parses **bold text** into 3 children', (tester) async {
        final controller = MarkdownEditingController(text: '**bold text**');
        final children = await getSpanChildren(tester, controller);

        expect(children, isNotNull);
        expect(children!.length, 3);
        expect((children[0] as TextSpan).text, '**');
        expect((children[1] as TextSpan).text, 'bold text');
        expect(
          (children[1] as TextSpan).style!.fontWeight,
          FontWeight.bold,
        );
        expect((children[2] as TextSpan).text, '**');
      });
    });

    group('italic', () {
      testWidgets('parses *italic text* into 3 children', (tester) async {
        final controller = MarkdownEditingController(text: '*italic text*');
        final children = await getSpanChildren(tester, controller);

        expect(children, isNotNull);
        expect(children!.length, 3);
        expect((children[0] as TextSpan).text, '*');
        expect((children[1] as TextSpan).text, 'italic text');
        expect(
          (children[1] as TextSpan).style!.fontStyle,
          FontStyle.italic,
        );
        expect((children[2] as TextSpan).text, '*');
      });
    });

    group('underline', () {
      testWidgets('parses __underlined__ into 3 children', (tester) async {
        final controller = MarkdownEditingController(text: '__underlined__');
        final children = await getSpanChildren(tester, controller);

        expect(children, isNotNull);
        expect(children!.length, 3);
        expect((children[0] as TextSpan).text, '__');
        expect((children[1] as TextSpan).text, 'underlined');
        expect(
          (children[1] as TextSpan).style!.decoration,
          TextDecoration.underline,
        );
        expect((children[2] as TextSpan).text, '__');
      });
    });

    group('headings', () {
      testWidgets('parses # Heading into 2 children', (tester) async {
        final controller = MarkdownEditingController(text: '# Heading');
        final children = await getSpanChildren(tester, controller);

        expect(children, isNotNull);
        expect(children!.length, 2);
        expect((children[0] as TextSpan).text, '# ');
        expect((children[1] as TextSpan).text, 'Heading');
        expect((children[1] as TextSpan).style!.fontSize, 20);
        expect(
          (children[1] as TextSpan).style!.fontWeight,
          FontWeight.bold,
        );
      });

      testWidgets('parses ## Subheading into 2 children', (tester) async {
        final controller = MarkdownEditingController(text: '## Subheading');
        final children = await getSpanChildren(tester, controller);

        expect(children, isNotNull);
        expect(children!.length, 2);
        expect((children[0] as TextSpan).text, '## ');
        expect((children[1] as TextSpan).text, 'Subheading');
        expect((children[1] as TextSpan).style!.fontSize, 18);
        expect(
          (children[1] as TextSpan).style!.fontWeight,
          FontWeight.w600,
        );
      });
    });

    group('horizontal rule', () {
      testWidgets('parses --- as muted smaller text', (tester) async {
        final controller = MarkdownEditingController(text: '---');
        final children = await getSpanChildren(tester, controller);

        expect(children, isNotNull);
        expect(children!.length, 1);
        expect((children[0] as TextSpan).text, '---');
        expect(
          (children[0] as TextSpan).style!.fontSize,
          14 * 0.85,
        );
      });
    });

    group('mixed content', () {
      testWidgets('parses hello **bold** world into 5 children',
          (tester) async {
        final controller =
            MarkdownEditingController(text: 'hello **bold** world');
        final children = await getSpanChildren(tester, controller);

        expect(children, isNotNull);
        expect(children!.length, 5);
        expect((children[0] as TextSpan).text, 'hello ');
        expect((children[1] as TextSpan).text, '**');
        expect((children[2] as TextSpan).text, 'bold');
        expect(
          (children[2] as TextSpan).style!.fontWeight,
          FontWeight.bold,
        );
        expect((children[3] as TextSpan).text, '**');
        expect((children[4] as TextSpan).text, ' world');
      });
    });

    group('unclosed markers', () {
      testWidgets('renders unclosed **not closed as plain text',
          (tester) async {
        final controller =
            MarkdownEditingController(text: '**not closed');
        final children = await getSpanChildren(tester, controller);

        expect(children, isNotNull);
        expect(children!.length, 1);
        expect((children[0] as TextSpan).text, '**not closed');
      });
    });

    group('fallback cases', () {
      testWidgets('empty text falls back to super.buildTextSpan',
          (tester) async {
        final controller = MarkdownEditingController(text: '');
        final children = await getSpanChildren(tester, controller);

        // super.buildTextSpan returns a TextSpan with no children for empty
        // text, so children is null.
        expect(children, isNull);
      });

      testWidgets(
          'before updateTheme is called falls back to super.buildTextSpan',
          (tester) async {
        final controller = MarkdownEditingController(text: '**bold**');
        final children = await getSpanChildren(
          tester,
          controller,
          callUpdateTheme: false,
        );

        // Without updateTheme, _themeReady is false, so it falls back.
        expect(children, isNull);
      });
    });

    group('marker color', () {
      testWidgets('markers use muted color from theme', (tester) async {
        final controller = MarkdownEditingController(text: '**bold**');
        final children = await getSpanChildren(tester, controller);

        expect(children, isNotNull);
        final markerSpan = children![0] as TextSpan;
        final closingMarkerSpan = children[2] as TextSpan;

        // Both markers should have the same muted color.
        expect(markerSpan.style!.color, closingMarkerSpan.style!.color);
        // The content span should not have the marker color.
        final contentSpan = children[1] as TextSpan;
        expect(contentSpan.style!.color, isNot(markerSpan.style!.color));
      });
    });
  });
}
