import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:prism_plurality/features/chat/utils/chat_markdown_syntax.dart';

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
}
