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

  testWidgets(
    'PrismDialog.show shifts content above the on-screen keyboard',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                PrismDialog.show(
                  context: context,
                  title: 'Keyboard Test',
                  builder: (context) => const SizedBox(
                    height: 200,
                    child: TextField(),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final titleFinder = find.text('Keyboard Test');
      final centerBefore = tester.getCenter(titleFinder).dy;

      // Simulate iOS keyboard appearing — without the inset-aware wrapper the
      // dialog stays centered in the full screen and the keyboard covers
      // anything in the bottom half.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);

      await tester.pumpAndSettle();

      final centerAfter = tester.getCenter(titleFinder).dy;
      expect(
        centerAfter,
        lessThan(centerBefore),
        reason: 'Dialog should shift up when the keyboard is visible',
      );
    },
  );

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

  testWidgets(
    'PrismDialog pins actions and scrolls body when content overflows',
    (tester) async {
      // 500px height forces the shell's 560px cap to clip a naive Column.
      await tester.binding.setSurfaceSize(const Size(600, 500));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var confirmed = false;

      await tester.pumpWidget(
        buildApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                PrismDialog.show(
                  context: context,
                  title: 'Tall Dialog',
                  message: 'This dialog has a body taller than the shell cap.',
                  actions: [
                    PrismButton(
                      label: 'Cancel',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    PrismButton(
                      label: 'Confirm',
                      tone: PrismButtonTone.filled,
                      onPressed: () {
                        confirmed = true;
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                  builder: (_) => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: List.generate(
                      30,
                      (i) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text('Body row $i'),
                      ),
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'Body should scroll instead of overflowing the dialog',
      );

      final dialogRect = tester.getRect(find.byType(PrismDialog));
      final confirmRect = tester.getRect(
        find.widgetWithText(PrismButton, 'Confirm'),
      );
      final cancelRect = tester.getRect(
        find.widgetWithText(PrismButton, 'Cancel'),
      );

      bool dialogContainsRect(Rect r) =>
          r.left >= dialogRect.left &&
          r.right <= dialogRect.right &&
          r.top >= dialogRect.top &&
          r.bottom <= dialogRect.bottom;

      expect(
        dialogContainsRect(confirmRect),
        isTrue,
        reason:
            'Confirm button rect $confirmRect should be fully inside dialog $dialogRect',
      );
      expect(
        dialogContainsRect(cancelRect),
        isTrue,
        reason:
            'Cancel button rect $cancelRect should be fully inside dialog $dialogRect',
      );

      await tester.tap(find.widgetWithText(PrismButton, 'Confirm'));
      await tester.pumpAndSettle();

      expect(confirmed, isTrue);
    },
  );
}
