import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';

void main() {
  testWidgets('BlurPopupAnchor blocks background semantics while open', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    try {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en'), Locale('es')],
          locale: const Locale('es'),
          home: Scaffold(
            body: Stack(
              children: [
                Center(
                  child: Semantics(
                    label: 'Background action',
                    button: true,
                    child: ElevatedButton(
                      onPressed: () {},
                      child: const Text('Background action'),
                    ),
                  ),
                ),
                Center(
                  child: BlurPopupAnchor(
                    semanticLabel: 'Open popup',
                    itemCount: 1,
                    itemBuilder: (context, index, close) => Semantics(
                      label: 'Popup item',
                      button: true,
                      child: TextButton(
                        onPressed: close,
                        child: const Text('Popup item'),
                      ),
                    ),
                    child: const Text('Open popup'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open popup'));
      await tester.pumpAndSettle();

      final closeFinder = find.semantics.byLabel('Cerrar');
      final popupItemFinder = find.semantics.byLabel('Popup item');
      final backgroundFinder = find.semantics.byLabel('Background action');

      expect(closeFinder, findsOne);
      expect(
        closeFinder,
        matchesSemantics(label: 'Cerrar', isButton: true, hasTapAction: true),
      );
      expect(popupItemFinder, findsAtLeastNWidgets(1));
      expect(backgroundFinder, findsNothing);
    } finally {
      handle.dispose();
    }
  });
}
