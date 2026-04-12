import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/onboarding/widgets/recovery_phrase_step.dart';

const _testWords = [
  'apple', 'banana', 'cherry', 'date',
  'elderberry', 'fig', 'grape', 'honeydew',
  'kiwi', 'lemon', 'mango', 'nectarine',
];

Widget _buildWidget({required VoidCallback onContinue}) {
  return MaterialApp(
    home: Scaffold(
      body: RecoveryPhraseStep(
        words: _testWords,
        onContinue: onContinue,
      ),
    ),
  );
}

void main() {
  testWidgets('words are blurred by default', (tester) async {
    await tester.pumpWidget(_buildWidget(onContinue: () {}));

    // "Tap to reveal" overlay is visible.
    expect(find.text('Tap to reveal'), findsOneWidget);

    // Words are in the widget tree (rendered under blur), so text exists.
    expect(find.text('apple'), findsOneWidget);

    // Copy button is hidden until revealed.
    expect(find.text('Copy to clipboard'), findsNothing);
  });

  testWidgets('tap reveals words', (tester) async {
    await tester.pumpWidget(_buildWidget(onContinue: () {}));

    // Tap the overlay to reveal.
    await tester.tap(find.text('Tap to reveal'));
    await tester.pump();

    // Overlay is gone.
    expect(find.text('Tap to reveal'), findsNothing);

    // Words are now shown without blur overlay.
    expect(find.text('apple'), findsOneWidget);
    expect(find.text('mango'), findsOneWidget);

    // Copy button appears after reveal.
    expect(find.text('Copy to clipboard'), findsOneWidget);
  });

  testWidgets('continue button disabled until revealed', (tester) async {
    await tester.pumpWidget(_buildWidget(onContinue: () {}));

    // Button is present but disabled.
    final button = find.text("I've written it down");
    expect(button, findsOneWidget);

    // Tapping a disabled PrismButton should do nothing.
    var tapped = false;
    await tester.pumpWidget(
      _buildWidget(onContinue: () => tapped = true),
    );
    await tester.tap(button, warnIfMissed: false);
    await tester.pump();
    expect(tapped, isFalse);
  });

  testWidgets('continue button calls onContinue when revealed', (tester) async {
    var continued = false;

    await tester.pumpWidget(_buildWidget(onContinue: () => continued = true));

    // Reveal first.
    await tester.tap(find.text('Tap to reveal'));
    await tester.pump();

    // Now tap the enabled button.
    await tester.tap(find.text("I've written it down"));
    await tester.pump();

    expect(continued, isTrue);
  });
}
