import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/providers/visual_effects_provider.dart';
import 'package:prism_plurality/shared/widgets/pin_numpad_button.dart';

/// Wraps [child] in ProviderScope + MaterialApp so ConsumerWidgets resolve.
Widget _testApp(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: Center(child: child),
      ),
    ),
  );
}

/// Like [_testApp] but with provider overrides.
Widget _testAppWithOverrides(Widget child, List overrides) {
  return ProviderScope(
    overrides: List.from(overrides),
    child: MaterialApp(
      home: Scaffold(
        body: Center(child: child),
      ),
    ),
  );
}

void main() {
  group('PinNumpadButton', () {
    testWidgets('onTap fires on tap, not onTapDown', (tester) async {
      var tapCount = 0;
      await tester.pumpWidget(_testApp(
        PinNumpadButton(label: '5', onTap: () => tapCount++),
      ));

      await tester.tap(find.byType(PinNumpadButton));
      await tester.pump();

      expect(tapCount, 1);
    });

    testWidgets('default size is 72', (tester) async {
      await tester.pumpWidget(_testApp(
        PinNumpadButton(label: '5', onTap: () {}),
      ));

      // The GestureDetector wraps a SizedBox(72×72) as the outermost size constraint.
      final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
      final match = sizedBoxes.any((b) => b.width == 72 && b.height == 72);
      expect(match, isTrue, reason: 'Expected a 72×72 SizedBox');
    });

    testWidgets('explicit size 64 produces a 64×64 SizedBox', (tester) async {
      await tester.pumpWidget(_testApp(
        PinNumpadButton(label: '5', onTap: () {}, size: 64),
      ));

      final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
      final match = sizedBoxes.any((b) => b.width == 64 && b.height == 64);
      expect(match, isTrue, reason: 'Expected a 64×64 SizedBox');
    });

    testWidgets('semantics label for digit button', (tester) async {
      await tester.pumpWidget(_testApp(
        PinNumpadButton(label: '7', onTap: () {}),
      ));

      // The merged label includes both the Semantics.label and the Text child
      // (e.g. "7\n7"). We verify the declared label is present.
      final semantics = tester.getSemantics(find.byType(PinNumpadButton));
      expect(semantics.label, contains('7'));
    });

    testWidgets('semantics label for icon-only button', (tester) async {
      await tester.pumpWidget(_testApp(
        PinNumpadButton(
          icon: Icons.backspace,
          semanticLabel: 'Delete',
          onTap: () {},
        ),
      ));

      final semantics = tester.getSemantics(find.byType(PinNumpadButton));
      expect(semantics.label, contains('Delete'));
    });

    testWidgets('reduced motion: AnimatedOpacity present when accessible mode',
        (tester) async {
      // `disableAnimations: true` maps to VisualEffectsMode.reduced (not accessible),
      // and reduced.useAnimations is true — so we must explicitly override the
      // provider to VisualEffectsMode.accessible to trigger the AnimatedOpacity path.
      await tester.pumpWidget(
        _testAppWithOverrides(
          PinNumpadButton(label: '1', onTap: () {}),
          [
            visualEffectsPreferenceProvider
                .overrideWith(_AccessibleVisualEffectsNotifier.new),
          ],
        ),
      );

      await tester.pump();

      expect(find.byType(AnimatedOpacity), findsOneWidget);
    });
  });
}

/// Notifier that always returns [VisualEffectsMode.accessible].
class _AccessibleVisualEffectsNotifier
    extends VisualEffectsPreferenceNotifier {
  @override
  VisualEffectsMode? build() => VisualEffectsMode.accessible;
}
