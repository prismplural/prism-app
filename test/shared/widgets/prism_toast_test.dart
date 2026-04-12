import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

void main() {
  tearDown(PrismToast.resetForTest);

  testWidgets(
    'toast host shows toasts triggered from nested overlay contexts',
    (tester) async {
      late BuildContext nestedOverlayContext;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          home: PrismToastHost(
            child: NavBarInset(
              bottomInset: 1,
              child: Scaffold(
                body: Overlay(
                  initialEntries: [
                    OverlayEntry(
                      builder: (context) {
                        nestedOverlayContext = context;
                        return const SizedBox.expand();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      PrismToast.show(nestedOverlayContext, message: 'First toast');
      await tester.pump();

      expect(find.text('First toast'), findsOneWidget);

      PrismToast.show(nestedOverlayContext, message: 'Second toast');
      await tester.pump();

      expect(find.text('First toast'), findsNothing);
      expect(find.text('Second toast'), findsOneWidget);

      PrismToast.dismiss();
      await tester.pump();
    },
  );

  testWidgets('toast exposes a dismiss action and removes itself when tapped', (
    tester,
  ) async {
    late BuildContext context;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: PrismToastHost(
          child: NavBarInset(
            bottomInset: 1,
            child: Scaffold(
              body: Builder(
                builder: (builderContext) {
                  context = builderContext;
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        ),
      ),
    );

    PrismToast.show(context, message: 'Dismiss me');
    await tester.pumpAndSettle();

    expect(find.text('Dismiss me'), findsOneWidget);
    expect(find.byTooltip('Dismiss notification'), findsOneWidget);

    await tester.tap(find.byTooltip('Dismiss notification'));
    await tester.pumpAndSettle();

    expect(find.text('Dismiss me'), findsNothing);
  });
}
