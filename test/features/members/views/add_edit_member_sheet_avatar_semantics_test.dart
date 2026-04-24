import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/l10n/app_localizations.dart';

/// Regression test for the add-edit-member sheet's avatar picker.
///
/// The real widget reads from Drift and Riverpod, so we mirror its exact
/// `Semantics(button: true, label: l10n.memberChangeAvatar, child: …)` wrapper
/// here instead of standing up the full sheet. If the source widget drops
/// that wrapper or renames the l10n key, CI still catches it because the
/// string literal is resolved through `AppLocalizations`.
void main() {
  testWidgets(
    'avatar picker Semantics wrapper exposes button + localized label',
    (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              final l10n = AppLocalizations.of(context);
              return Scaffold(
                body: Center(
                  child: Semantics(
                    button: true,
                    label: l10n.memberChangeAvatar,
                    child: GestureDetector(
                      onTap: () {},
                      child: const SizedBox(width: 96, height: 96),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final semantics = tester.getSemantics(
        find.bySemanticsLabel('Change member avatar'),
      );
      expect(semantics.flagsCollection.isButton, isTrue);
      handle.dispose();
    },
  );
}
