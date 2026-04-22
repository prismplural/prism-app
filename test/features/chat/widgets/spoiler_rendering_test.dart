import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:prism_plurality/features/chat/utils/chat_markdown_syntax.dart';
import 'package:prism_plurality/features/chat/widgets/chat_message_text.dart';

void main() {
  List<double> _spoilerOpacities(WidgetTester tester) {
    return tester
        .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
        .map((w) => w.opacity)
        .toList();
  }

  Widget _harness({
    required SpoilerRevealController controller,
    required int start,
    ThemeData? theme,
  }) {
    final element = md.Element.text('spoiler', 'secret')
      ..attributes['start'] = start.toString();
    return MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Builder(
          builder: (context) {
            final builder = SpoilerBuilder(theme: Theme.of(context));
            return SpoilerRevealScope(
              notifier: controller,
              child: builder.visitElementAfterWithContext(
                context,
                element,
                null,
                const TextStyle(),
              )!,
            );
          },
        ),
      ),
    );
  }

  BoxDecoration _hiddenDecoration(WidgetTester tester) {
    final hiddenLayer = find.byType(AnimatedOpacity).first;
    final hiddenContainer = find.descendant(
      of: hiddenLayer,
      matching: find.byWidgetPredicate(
        (w) => w is Container && w.decoration is BoxDecoration,
      ),
    );
    final container = tester.widget<Container>(hiddenContainer);
    return container.decoration! as BoxDecoration;
  }

  testWidgets('renders pill when not revealed', (tester) async {
    final controller = SpoilerRevealController();
    await tester.pumpWidget(_harness(controller: controller, start: 0));
    expect(_spoilerOpacities(tester), [1.0, 0.0]);
    controller.dispose();
  });

  testWidgets('renders revealed state when flag is true', (tester) async {
    final controller = SpoilerRevealController()..toggle(0);
    await tester.pumpWidget(_harness(controller: controller, start: 0));
    expect(_spoilerOpacities(tester), [0.0, 1.0]);
    controller.dispose();
  });

  testWidgets('tap toggles reveal via controller', (tester) async {
    final controller = SpoilerRevealController();
    await tester.pumpWidget(_harness(controller: controller, start: 7));
    await tester.tap(find.byType(GestureDetector));
    expect(controller.isRevealed(7), isTrue);
    controller.dispose();
  });

  testWidgets('hidden pill stays dark in dark theme', (tester) async {
    final controller = SpoilerRevealController();
    await tester.pumpWidget(
      _harness(
        controller: controller,
        start: 0,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: const ColorScheme.dark(),
        ),
      ),
    );
    final decoration = _hiddenDecoration(tester);
    expect(decoration.color, isNotNull);
    expect(decoration.color!.computeLuminance(), lessThan(0.05));
    expect(decoration.border, isNotNull);
    controller.dispose();
  });

  group('ChatMessageText integration', () {
    Widget _mount(String content) {
      return MaterialApp(
        home: Scaffold(
          body: ChatMessageText(
            content: content,
            authorMap: null,
            baseStyle: const TextStyle(),
            defaultColor: Colors.black,
          ),
        ),
      );
    }

    testWidgets('renders a spoiler pill in a message', (tester) async {
      await tester.pumpWidget(_mount('hi ||secret|| world'));
      expect(_spoilerOpacities(tester), [1.0, 0.0]);
    });

    testWidgets('tapping pill reveals the spoiler', (tester) async {
      await tester.pumpWidget(_mount('say ||hi|| now'));
      // Find and tap the GestureDetector inside the spoiler span.
      final spoilerGesture = find.byWidgetPredicate(
        (w) => w is GestureDetector && w.behavior == HitTestBehavior.opaque,
      );
      expect(spoilerGesture, findsOneWidget);
      await tester.tap(spoilerGesture);
      await tester.pump();
      expect(_spoilerOpacities(tester), [0.0, 1.0]);
      // Tap again to re-hide.
      await tester.tap(spoilerGesture);
      await tester.pump();
      expect(_spoilerOpacities(tester), [1.0, 0.0]);
    });

    testWidgets('multiple spoilers have independent reveal state', (
      tester,
    ) async {
      await tester.pumpWidget(_mount('first ||a|| second ||bb||'));
      final gestures = find.byWidgetPredicate(
        (w) => w is GestureDetector && w.behavior == HitTestBehavior.opaque,
      );
      expect(gestures, findsNWidgets(2));
      // Reveal only the first.
      await tester.tap(gestures.first);
      await tester.pump();
      expect(_spoilerOpacities(tester), [0.0, 1.0, 1.0, 0.0]);
    });

    testWidgets('reveal state resets when content prop changes', (
      tester,
    ) async {
      await tester.pumpWidget(_mount('say ||hi|| now'));
      final gesture = find.byWidgetPredicate(
        (w) => w is GestureDetector && w.behavior == HitTestBehavior.opaque,
      );
      await tester.tap(gesture);
      await tester.pump();
      // Rebuild with different content — reveal state should clear.
      await tester.pumpWidget(_mount('new ||hello|| msg'));
      expect(
        _spoilerOpacities(tester),
        [1.0, 0.0],
        reason: 'didUpdateWidget should clear reveals on content change',
      );
    });

    testWidgets('animates opacity over 150ms on reveal', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatMessageText(
              content: 'hi ||secret|| ok',
              authorMap: null,
              baseStyle: const TextStyle(),
              defaultColor: Colors.black,
            ),
          ),
        ),
      );
      final gesture = find.byWidgetPredicate(
        (w) => w is GestureDetector && w.behavior == HitTestBehavior.opaque,
      );
      await tester.tap(gesture);
      // Pump once to start the animation tick.
      await tester.pump();
      expect(_spoilerOpacities(tester), [0.0, 1.0]);

      final hiddenOpacity = find.byType(AnimatedOpacity).at(0);
      final revealedOpacity = find.byType(AnimatedOpacity).at(1);
      final hiddenFade = find.descendant(
        of: hiddenOpacity,
        matching: find.byType(FadeTransition),
      );
      final revealedFade = find.descendant(
        of: revealedOpacity,
        matching: find.byType(FadeTransition),
      );
      await tester.pump(const Duration(milliseconds: 75));
      final hiddenFadeMid = tester.widget<FadeTransition>(hiddenFade);
      final revealedFadeMid = tester.widget<FadeTransition>(revealedFade);
      expect(hiddenFadeMid.opacity.value, greaterThan(0.0));
      expect(hiddenFadeMid.opacity.value, lessThan(1.0));
      expect(revealedFadeMid.opacity.value, greaterThan(0.0));
      expect(revealedFadeMid.opacity.value, lessThan(1.0));
      // Let the animation settle.
      await tester.pumpAndSettle();
      final hiddenFadeSettled = tester.widget<FadeTransition>(hiddenFade);
      final revealedFadeSettled = tester.widget<FadeTransition>(revealedFade);
      expect(hiddenFadeSettled.opacity.value, 0.0);
      expect(revealedFadeSettled.opacity.value, 1.0);
    });
  });
}
