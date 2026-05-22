import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/emoji/prism_emoji_set.dart';
import 'package:prism_plurality/shared/widgets/glass_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_emoji_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows clear affordance and clears without opening picker', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    var cleared = 0;
    var selected = 0;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: PrismEmojiPicker(
                emoji: '🌸',
                onSelected: (_) => selected++,
                onCleared: () => cleared++,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byTooltip('Clear emoji'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear emoji'));
    await tester.pumpAndSettle();

    expect(cleared, 1);
    expect(selected, 0);
    expect(find.byIcon(Icons.search), findsNothing);
  });

  testWidgets('hides clear affordance when there is no clear callback', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: PrismEmojiPicker(emoji: '🌸', onSelected: (_) {}),
          ),
        ),
      ),
    );

    expect(find.byTooltip('Clear emoji'), findsNothing);
  });

  test('includes the latest custom emoji search data', () {
    final allEmoji = prismEmojiSet.expand((category) => category.emoji);

    expect(
      allEmoji.any((emoji) => emoji.emoji == '🫩'),
      isTrue,
      reason: 'Emoji 16 face with bags under eyes should be available.',
    );
    expect(
      allEmoji.any(
        (emoji) => emoji.emoji == '🫪' && emoji.keywords.contains('flush'),
      ),
      isTrue,
      reason: 'Emoji 17 distorted face should be available via flush search.',
    );
  });

  testWidgets('shows a search affordance when the picker opens', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: PrismEmojiPicker(emoji: '🌸', onSelected: (_) {}),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(PrismEmojiPicker));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(tester.widget<GlassSurface>(find.byType(GlassSurface)).height, 360);

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<GlassSurface>(find.byType(GlassSurface)).height,
      lessThan(140),
    );
  });

  testWidgets('keeps emoji search focused when keyboard insets change', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: PrismEmojiPicker(emoji: '🌸', onSelected: (_) {}),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(PrismEmojiPicker));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    final focusNode = tester
        .widget<EditableText>(find.byType(EditableText))
        .focusNode;

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode,
      same(focusNode),
    );
  });
}
