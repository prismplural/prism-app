import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:prism_plurality/features/chat/utils/chat_markdown_syntax.dart';
import 'package:prism_plurality/features/chat/widgets/chat_message_text.dart';

void main() {
  Widget _harness({required Map<int, bool> reveals, required int start}) {
    final element = md.Element.text('spoiler', 'secret')
      ..attributes['start'] = start.toString();
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            final builder = SpoilerBuilder(
              reveals: reveals,
              onToggle: (s) => reveals[s] = !(reveals[s] ?? false),
              theme: Theme.of(context),
            );
            return builder.visitElementAfterWithContext(
              context,
              element,
              null,
              const TextStyle(),
            )!;
          },
        ),
      ),
    );
  }

  testWidgets('renders pill when not revealed', (tester) async {
    await tester.pumpWidget(_harness(reveals: {}, start: 0));
    // The occluding container should be fully opaque (opacity 1.0).
    final opacity =
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(opacity.opacity, 1.0);
  });

  testWidgets('renders revealed state when flag is true', (tester) async {
    await tester.pumpWidget(_harness(reveals: {0: true}, start: 0));
    final opacity =
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(opacity.opacity, 0.0);
  });

  testWidgets('tap toggles reveal via onToggle callback', (tester) async {
    final reveals = <int, bool>{};
    await tester.pumpWidget(_harness(reveals: reveals, start: 7));
    await tester.tap(find.byType(GestureDetector));
    expect(reveals[7], isTrue);
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
      // Pill is an AnimatedOpacity with opacity 1.0 (hidden state).
      final opacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
      expect(opacity.opacity, 1.0);
    });

    testWidgets('tapping pill reveals the spoiler', (tester) async {
      await tester.pumpWidget(_mount('say ||hi|| now'));
      // Find and tap the GestureDetector inside the spoiler span.
      final spoilerGesture = find.byWidgetPredicate((w) =>
          w is GestureDetector && w.behavior == HitTestBehavior.opaque);
      expect(spoilerGesture, findsOneWidget);
      await tester.tap(spoilerGesture);
      await tester.pump();
      final opacity =
          tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
      expect(opacity.opacity, 0.0);
      // Tap again to re-hide.
      await tester.tap(spoilerGesture);
      await tester.pump();
      final opacityAfter =
          tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
      expect(opacityAfter.opacity, 1.0);
    });

    testWidgets('multiple spoilers have independent reveal state',
        (tester) async {
      await tester.pumpWidget(_mount('first ||a|| second ||bb||'));
      final gestures = find.byWidgetPredicate((w) =>
          w is GestureDetector && w.behavior == HitTestBehavior.opaque);
      expect(gestures, findsNWidgets(2));
      // Reveal only the first.
      await tester.tap(gestures.first);
      await tester.pump();
      final opacities =
          tester.widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity));
      final values = opacities.map((o) => o.opacity).toList();
      // Exactly one should be 0.0 (revealed), the other 1.0 (hidden).
      expect(values.where((v) => v == 0.0), hasLength(1));
      expect(values.where((v) => v == 1.0), hasLength(1));
    });

    testWidgets('reveal state resets when content prop changes',
        (tester) async {
      await tester.pumpWidget(_mount('say ||hi|| now'));
      final gesture = find.byWidgetPredicate((w) =>
          w is GestureDetector && w.behavior == HitTestBehavior.opaque);
      await tester.tap(gesture);
      await tester.pump();
      // Rebuild with different content — reveal state should clear.
      await tester.pumpWidget(_mount('new ||hello|| msg'));
      final opacity =
          tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
      expect(opacity.opacity, 1.0,
          reason: 'didUpdateWidget should clear reveals on content change');
    });
  });
}
