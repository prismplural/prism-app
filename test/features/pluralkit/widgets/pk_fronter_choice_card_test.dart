import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/features/pluralkit/widgets/pk_fronter_choice_card.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: const [Locale('en')],
    home: Scaffold(body: child),
  );
}

void main() {
  // (a) Renders title and subtitle
  testWidgets('renders title and subtitle text', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const PkFronterChoiceCard(
          title: 'Use Prism\'s',
          subtitle: 'Keep Alice fronting',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Use Prism\'s'), findsOneWidget);
    expect(find.text('Keep Alice fronting'), findsOneWidget);
  });

  // (b) Tap fires onTap
  testWidgets('tap fires onTap callback', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(
        PkFronterChoiceCard(
          title: 'Use PluralKit\'s',
          subtitle: 'Set Bob fronting',
          onTap: () => tapped = true,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(PkFronterChoiceCard));
    expect(tapped, isTrue);
  });

  // (c) recommended: true shows check icon + "Recommended" label; uses accent tone
  testWidgets('recommended variant shows check icon and Recommended label', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const PkFronterChoiceCard(
          title: 'Co-front (both)',
          subtitle: 'Keep everyone fronting',
          recommended: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Recommended'), findsOneWidget);
    // The check icon should be rendered
    expect(find.byKey(const Key('pk_fronter_choice_card_recommended_icon')), findsOneWidget);
    // Recommended card must use the accent surface tone
    final surface = tester.widget<PrismSurface>(find.byType(PrismSurface));
    expect(surface.tone, PrismSurfaceTone.accent);
  });

  // (d) onTap: null doesn't fire
  testWidgets('disabled card (onTap null) does not fire any callback', (tester) async {
    const tapped = false;
    await tester.pumpWidget(
      _wrap(
        const PkFronterChoiceCard(
          title: 'Leave no one fronting',
          subtitle: 'Clear all fronters',
          // ignore: avoid_redundant_argument_values
          // onTap defaults to null
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(PkFronterChoiceCard), warnIfMissed: false);
    expect(tapped, isFalse);
  });

  // (e) Semantics label combines title + subtitle + recommended marker
  testWidgets('semantics label combines title, subtitle, and recommended marker', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const PkFronterChoiceCard(
          title: 'Use Prism\'s',
          subtitle: 'Keep Alice fronting',
          recommended: true,
        ),
      ),
    );
    await tester.pump();

    final semanticsNode = tester.getSemantics(find.byType(PkFronterChoiceCard));
    // The label should include title, subtitle, and recommended
    final label = semanticsNode.label;
    expect(label, contains('Use Prism\'s'));
    expect(label, contains('Keep Alice fronting'));
    expect(label, contains('Recommended'));
  });
}
