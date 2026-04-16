import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_mnemonic_field.dart';

Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: child,
        ),
      ),
    ),
  );
}

// A canonical BIP39 12-word mnemonic with a valid checksum.
const _validPhrase =
    'abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon about';

void main() {
  group('PrismMnemonicField', () {
    testWidgets('counter increments as valid BIP39 words are typed', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _wrap(PrismMnemonicField(controller: controller)),
      );

      // Type 5 valid words.
      await tester.enterText(
        find.byType(TextField),
        'abandon ability able about above',
      );
      await tester.pumpAndSettle();

      // Counter should report 5/12.
      expect(find.text('5 of 12 words'), findsOneWidget);
    });

    testWidgets('invalid words do not count toward the valid total', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _wrap(PrismMnemonicField(controller: controller)),
      );

      // Two valid words + one bogus word => 2 valid total.
      await tester.enterText(
        find.byType(TextField),
        'abandon ability xyznotaword',
      );
      await tester.pumpAndSettle();

      expect(find.text('2 of 12 words'), findsOneWidget);
      // The invalid word renders as a chip with the word text.
      expect(find.text('xyznotaword'), findsOneWidget);
    });

    testWidgets('visibility toggle flips obscureText on the textarea', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _wrap(PrismMnemonicField(controller: controller)),
      );

      // Default is visible (obscureText: false).
      TextField field = tester.widget(find.byType(TextField));
      expect(field.obscureText, isFalse);

      // Tap the visibility toggle. Use its tooltip to locate it.
      await tester.tap(find.byTooltip('Hide words'));
      await tester.pumpAndSettle();

      field = tester.widget(find.byType(TextField));
      expect(field.obscureText, isTrue);

      // Tap again to flip back.
      await tester.tap(find.byTooltip('Show words'));
      await tester.pumpAndSettle();

      field = tester.widget(find.byType(TextField));
      expect(field.obscureText, isFalse);
    });

    testWidgets('paste button appears and fills field when clipboard is valid',
        (tester) async {
      // Seed the clipboard with a valid 12-word phrase.
      TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.getData') {
            return <String, dynamic>{'text': _validPhrase};
          }
          if (call.method == 'Clipboard.setData') {
            return null;
          }
          if (call.method == 'Clipboard.hasStrings') {
            return <String, dynamic>{'value': true};
          }
          return null;
        },
      );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding
            .instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _wrap(PrismMnemonicField(controller: controller)),
      );
      await tester.pumpAndSettle();

      // Paste button should be visible.
      final pasteButton = find.byTooltip('Paste phrase');
      expect(pasteButton, findsOneWidget);

      await tester.tap(pasteButton);
      await tester.pumpAndSettle();

      // All 12 words now in the controller.
      expect(controller.text, _validPhrase);
      expect(find.text('12 of 12 words'), findsOneWidget);
    });

    testWidgets(
      'autocomplete suggestion inserts full word and trailing space',
      (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          _wrap(PrismMnemonicField(controller: controller, autofocus: true)),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'abou');
        await tester.pumpAndSettle();

        // The autocomplete strip should show "about" as a suggestion.
        final aboutChip = find.text('about');
        expect(aboutChip, findsWidgets);

        await tester.tap(aboutChip.first);
        await tester.pumpAndSettle();

        // Field now contains the full word + a trailing space.
        expect(controller.text, 'about ');
      },
    );
  });

  group('PrismMnemonicField.normalize', () {
    test('trims, lowercases, and collapses whitespace', () {
      expect(
        PrismMnemonicField.normalize('  Abandon\nABANDON\tabout  '),
        'abandon abandon about',
      );
    });

    test('returns empty string for whitespace-only input', () {
      expect(PrismMnemonicField.normalize('   \n\t   '), '');
    });
  });
}
