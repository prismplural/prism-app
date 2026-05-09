import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/glass_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_emoji_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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
}
