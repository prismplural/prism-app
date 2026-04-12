import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';

void main() {
  Widget buildApp({required Widget child}) {
    return ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: child,
      ),
    );
  }

  testWidgets('PrismDialog.confirm renders title, message, and buttons', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        child: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              PrismDialog.confirm(
                context: context,
                title: 'Delete Session',
                message: 'This action cannot be undone.',
                confirmLabel: 'Delete',
                destructive: true,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Delete Session'), findsOneWidget);
    expect(find.text('This action cannot be undone.'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('PrismDialog.confirm returns true on confirm tap', (
    tester,
  ) async {
    bool? result;

    await tester.pumpWidget(
      buildApp(
        child: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await PrismDialog.confirm(
                context: context,
                title: 'Confirm?',
                confirmLabel: 'Yes',
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('PrismDialog.confirm returns false on cancel tap', (
    tester,
  ) async {
    bool? result;

    await tester.pumpWidget(
      buildApp(
        child: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await PrismDialog.confirm(
                context: context,
                title: 'Confirm?',
                confirmLabel: 'Yes',
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('PrismDialog.show renders custom actions', (tester) async {
    var actionTapped = false;

    await tester.pumpWidget(
      buildApp(
        child: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              PrismDialog.show(
                context: context,
                title: 'Edit',
                actions: [
                  PrismButton(
                    label: 'Cancel',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  PrismButton(
                    label: 'Save',
                    tone: PrismButtonTone.filled,
                    onPressed: () {
                      actionTapped = true;
                      Navigator.of(context).pop();
                    },
                  ),
                ],
                builder: (context) => const Text('Dialog body'),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Dialog body'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(actionTapped, isTrue);
  });

  testWidgets('PrismDialog.show renders custom content with title', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        child: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              PrismDialog.show(
                context: context,
                title: 'Custom Dialog',
                message: 'A description',
                builder: (context) => const Text('Custom content'),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Custom Dialog'), findsOneWidget);
    expect(find.text('A description'), findsOneWidget);
    expect(find.text('Custom content'), findsOneWidget);
  });

  testWidgets('PrismDialog.confirm renders icon when provided', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        child: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              PrismDialog.confirm(
                context: context,
                title: 'Delete?',
                icon: AppIcons.warningAmber,
                destructive: true,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byIcon(AppIcons.warningAmber), findsOneWidget);
    expect(find.text('Delete?'), findsOneWidget);
  });

  testWidgets('PrismDialog.confirm returns false on barrier dismiss', (
    tester,
  ) async {
    bool? result;

    await tester.pumpWidget(
      buildApp(
        child: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await PrismDialog.confirm(
                context: context,
                title: 'Confirm?',
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Tap outside the dialog (on the barrier)
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });
}
