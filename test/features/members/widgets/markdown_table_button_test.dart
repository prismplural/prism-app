import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/features/members/widgets/markdown_image_button.dart';
import 'package:prism_plurality/features/members/widgets/markdown_table_button.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';

void main() {
  testWidgets('matches the image button Prism action size', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          home: Scaffold(
            body: Row(
              children: [
                MarkdownTableButton(controller: controller),
                MarkdownImageButton(
                  controller: controller,
                  sessionId: 'test-session',
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final actions = tester.widgetList<PrismTopBarAction>(
      find.byType(PrismTopBarAction),
    );
    final glassButtons = tester.widgetList<PrismGlassIconButton>(
      find.byType(PrismGlassIconButton),
    );

    expect(actions.map((button) => button.size), [
      PrismTokens.topBarActionSize,
      PrismTokens.topBarActionSize,
    ]);
    expect(glassButtons.map((button) => button.size), [
      PrismTokens.topBarActionSize,
      PrismTokens.topBarActionSize,
    ]);
    expect(
      tester.getSize(find.byType(PrismGlassIconButton).first),
      const Size.square(44),
    );
    expect(
      tester.getSize(find.byType(PrismGlassIconButton).last),
      const Size.square(44),
    );
  });
}
