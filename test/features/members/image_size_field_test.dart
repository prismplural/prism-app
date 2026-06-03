import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/members/services/bio_image_insert_spec.dart';
import 'package:prism_plurality/features/members/widgets/image_size_field.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: const [Locale('en')],
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('ImageSizeField', () {
    testWidgets('default mode hides the value field and emits nothing', (
      tester,
    ) async {
      ImageSizeSpec? spec;
      await tester.pumpWidget(_wrap(ImageSizeField(onChanged: (s) => spec = s)));
      await tester.pumpAndSettle();

      // No value field until a sizing mode is chosen.
      expect(find.byType(TextField), findsNothing);
      // No interaction yet → the host keeps its own initial (default).
      expect(spec, isNull);
    });

    testWidgets('choosing px reveals the field and emits a px fragment', (
      tester,
    ) async {
      ImageSizeSpec? spec;
      await tester.pumpWidget(_wrap(ImageSizeField(onChanged: (s) => spec = s)));

      await tester.tap(find.text('px'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), '200');
      expect(spec!.mode, ImageSizeMode.widthPx);
      expect(spec!.fragment, '200');
    });

    testWidgets('em mode emits an em fragment', (tester) async {
      ImageSizeSpec? spec;
      await tester.pumpWidget(_wrap(ImageSizeField(onChanged: (s) => spec = s)));

      await tester.tap(find.text('em'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '8');

      expect(spec!.mode, ImageSizeMode.em);
      expect(spec!.fragment, '8em');
    });

    testWidgets('switching back to default hides the field and clears sizing', (
      tester,
    ) async {
      ImageSizeSpec? spec;
      await tester.pumpWidget(_wrap(ImageSizeField(onChanged: (s) => spec = s)));

      await tester.tap(find.text('px'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '200');

      await tester.tap(find.text('Default'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(spec!.mode, ImageSizeMode.defaultSize);
      expect(spec!.fragment, '');
    });
  });
}
