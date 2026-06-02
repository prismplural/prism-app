import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/polls/views/create_poll_sheet.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

void main() {
  late ScrollController scrollController;

  setUp(() => scrollController = ScrollController());
  tearDown(() => scrollController.dispose());

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        // Fixed record value so the sheet builds standalone.
        terminologySettingProvider.overrideWithValue((
          term: SystemTerminology.members,
          customSingular: null,
          customPlural: null,
          useEnglish: true,
        )),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Widget buildSubject(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          body: CreatePollSheet(scrollController: scrollController),
        ),
      ),
    );
  }

  // Tap the first option's color dot to open its popover (must be closed first
  // — an open popover's barrier covers the anchors).
  Future<void> openFirstColorPopover(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Option color').first);
    await tester.pumpAndSettle();
  }

  Finder checkInside(String swatchTooltip) => find.descendant(
    of: find.byTooltip(swatchTooltip),
    matching: find.byIcon(AppIcons.check),
  );

  testWidgets(
    'color popover offers named swatches, a no-color option, and a custom tile',
    (tester) async {
      await tester.pumpWidget(buildSubject(makeContainer()));
      await tester.pumpAndSettle();

      // Two default options, each with its own color dot.
      expect(find.byTooltip('Option color'), findsNWidgets(2));

      await openFirstColorPopover(tester);

      // Named swatches, a no-color option, and the custom-picker tile.
      expect(find.byTooltip('No color'), findsOneWidget);
      expect(find.byTooltip('Red'), findsOneWidget);
      expect(find.byTooltip('Custom color'), findsOneWidget);
    },
  );

  testWidgets('picking a quick swatch closes the popover and marks it selected', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject(makeContainer()));
    await tester.pumpAndSettle();

    await openFirstColorPopover(tester);

    // Nothing selected yet.
    expect(checkInside('Red'), findsNothing);

    await tester.tap(find.byTooltip('Red'));
    await tester.pumpAndSettle();

    // Selecting a swatch dismisses the popover.
    expect(find.byTooltip('Red'), findsNothing);

    // Reopen: the chosen swatch now shows the selected check.
    await openFirstColorPopover(tester);
    expect(checkInside('Red'), findsOneWidget);
  });
}
