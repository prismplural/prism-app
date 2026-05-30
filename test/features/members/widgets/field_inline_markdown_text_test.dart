import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/members/widgets/custom_field_display_widgets.dart';
import 'package:prism_plurality/shared/markdown/spoiler_syntax.dart';

void main() {
  Widget host(String data) => MaterialApp(
    home: Scaffold(body: FieldInlineMarkdownText(data)),
  );

  List<double> spoilerOpacities(WidgetTester tester) => tester
      .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
      .map((w) => w.opacity)
      .toList();

  testWidgets('plain text renders without a spoiler pill', (tester) async {
    await tester.pumpWidget(host('just text'));
    expect(find.byType(SpoilerPill), findsNothing);
    expect(find.text('just text'), findsOneWidget);
  });

  testWidgets('||spoiler|| renders a hidden pill, not literal pipes', (
    tester,
  ) async {
    await tester.pumpWidget(host('value: ||hidden||'));
    expect(find.byType(SpoilerPill), findsOneWidget);
    // Hidden layer opaque, revealed layer transparent.
    expect(spoilerOpacities(tester), [1.0, 0.0]);
    // No literal pipe markers leak into any Text.
    final visible = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join('\n');
    expect(visible, isNot(contains('||')));
  });

  testWidgets('tapping the pill reveals it', (tester) async {
    await tester.pumpWidget(host('||secret||'));
    expect(spoilerOpacities(tester), [1.0, 0.0]);
    await tester.tap(find.byType(SpoilerPill));
    await tester.pumpAndSettle();
    expect(spoilerOpacities(tester), [0.0, 1.0]);
  });

  testWidgets('two spoilers reveal independently', (tester) async {
    await tester.pumpWidget(host('||a|| and ||b||'));
    expect(find.byType(SpoilerPill), findsNWidgets(2));
    expect(spoilerOpacities(tester), [1.0, 0.0, 1.0, 0.0]);
    await tester.tap(find.byType(SpoilerPill).first);
    await tester.pumpAndSettle();
    // Only the first reveals.
    expect(spoilerOpacities(tester), [0.0, 1.0, 1.0, 0.0]);
  });

  testWidgets('spoiler locks out bold inside it', (tester) async {
    await tester.pumpWidget(host('||**x**||'));
    // The pill's inner text keeps the literal ** (not parsed as bold).
    expect(find.byType(SpoilerPill), findsOneWidget);
    final pill = tester.widget<SpoilerPill>(find.byType(SpoilerPill));
    expect(pill.text, '**x**');
  });
}
