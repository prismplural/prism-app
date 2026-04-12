import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/onboarding/widgets/confirm_phrase_step.dart';

// Deterministic test words. With these words, Random(words.join('').hashCode)
// selects challenge positions 4, 6, 9 (1-indexed: 5, 7, 10):
//   Blank 1 → word #5  "elderberry"
//   Blank 2 → word #7  "grape"
//   Blank 3 → word #10 "lemon"
const _testWords = [
  'apple', 'banana', 'cherry', 'date',        // 1-4
  'elderberry', 'fig', 'grape', 'honeydew',   // 5-8
  'kiwi', 'lemon', 'mango', 'nectarine',      // 9-12
];

Widget _buildWidget({required VoidCallback onConfirmed}) {
  return MaterialApp(
    home: Scaffold(
      body: ConfirmPhraseStep(
        words: _testWords,
        onConfirmed: onConfirmed,
      ),
    ),
  );
}

void main() {
  testWidgets('shows first blank initially', (tester) async {
    await tester.pumpWidget(_buildWidget(onConfirmed: () {}));

    // The prompt for word #5.
    expect(find.text('Select word #5'), findsOneWidget);

    // Continue button is disabled.
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('correct answer advances to next blank', (tester) async {
    await tester.pumpWidget(_buildWidget(onConfirmed: () {}));

    // Blank 1 expects "elderberry" (word #5).
    expect(find.text('Select word #5'), findsOneWidget);
    await tester.tap(find.text('elderberry'));
    await tester.pumpAndSettle();

    // Should now show blank 2 (word #7 "grape").
    expect(find.text('Select word #7'), findsOneWidget);
    expect(find.text('Select word #5'), findsNothing);
  });

  testWidgets('wrong answer shows error and allows retry', (tester) async {
    await tester.pumpWidget(_buildWidget(onConfirmed: () {}));

    // Blank 1: pick a wrong option (not elderberry).
    // Options from seed: [fig, grape, lemon, elderberry] — pick 'fig'.
    await tester.tap(find.text('fig'));
    await tester.pumpAndSettle();

    // Still on blank 1 — wrong choice turns red (chip still visible).
    expect(find.text('Select word #5'), findsOneWidget);
    expect(find.text('fig'), findsOneWidget);

    // We should still be able to tap the correct answer.
    await tester.tap(find.text('elderberry'));
    await tester.pumpAndSettle();

    // Now advanced to blank 2.
    expect(find.text('Select word #7'), findsOneWidget);
  });

  testWidgets('all correct enables continue button', (tester) async {
    var confirmed = false;

    await tester.pumpWidget(_buildWidget(onConfirmed: () => confirmed = true));

    // Answer all 3 blanks correctly.
    // Blank 1 → elderberry (word #5)
    await tester.tap(find.text('elderberry'));
    await tester.pumpAndSettle();

    // Blank 2 → grape (word #7)
    await tester.tap(find.text('grape'));
    await tester.pumpAndSettle();

    // Blank 3 → lemon (word #10)
    await tester.tap(find.text('lemon'));
    await tester.pumpAndSettle();

    // "Phrase verified" shown.
    expect(find.text('Phrase verified'), findsOneWidget);

    // Continue button now enabled.
    await tester.tap(find.text('Continue'));
    await tester.pump();

    expect(confirmed, isTrue);
  });
}
