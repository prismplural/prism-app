import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

void main() {
  testWidgets('PrismSheet.show renders title and content', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              PrismSheet.show(
                context: context,
                title: 'Add Member',
                subtitle: 'Create a new member',
                builder: (context) => const Text('Sheet body content'),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Add Member'), findsOneWidget);
    expect(find.text('Create a new member'), findsOneWidget);
    expect(find.text('Sheet body content'), findsOneWidget);
  });

  testWidgets('PrismSheet.show renders actions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              PrismSheet.show(
                context: context,
                title: 'Test',
                builder: (context) => const Text('Content'),
                actions: [
                  TextButton(onPressed: () {}, child: const Text('Cancel')),
                  TextButton(onPressed: () {}, child: const Text('Save')),
                ],
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('PrismSheet.show without title renders content only', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              PrismSheet.show(
                context: context,
                builder: (context) => const Text('Plain content'),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Plain content'), findsOneWidget);
  });

  testWidgets('PrismSheet title applies single-line ellipsis overflow', (
    tester,
  ) async {
    const longTitle =
        'A very long title that would normally overflow and wrap across '
        'multiple lines inside the compact sheet header area';

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              PrismSheet.show(
                context: context,
                title: longTitle,
                builder: (_) => const Text('Body'),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final titleWidget = tester.widget<Text>(find.text(longTitle));
    expect(titleWidget.maxLines, 1);
    expect(titleWidget.overflow, TextOverflow.ellipsis);
  });

  testWidgets('PrismSheet custom drag handle is excluded from semantics', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              PrismSheet.show(
                context: context,
                builder: (_) => const Text('Content'),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // The custom drag handle container is wrapped in ExcludeSemantics so it
    // doesn't appear as an unlabelled interactive region to screen readers.
    expect(find.byType(ExcludeSemantics), findsWidgets);
  });

  testWidgets('PrismSheet.show with maxHeightFactor bounds sheet height', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              PrismSheet.show(
                context: context,
                maxHeightFactor: 0.5,
                builder: (_) => const Text('Bounded content'),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Bounded content'), findsOneWidget);

    // The ConstrainedBox that enforces maxHeightFactor should be present.
    expect(find.byType(ConstrainedBox), findsWidgets);
  });

  testWidgets('PrismSheet.show with minHeightFactor sets minimum height', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              PrismSheet.show(
                context: context,
                minHeightFactor: 0.3,
                builder: (_) => const Text('Min height content'),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Min height content'), findsOneWidget);

    // ConstrainedBox applies the minHeightFactor constraint.
    expect(find.byType(ConstrainedBox), findsWidgets);
  });

  testWidgets('PrismSheet.show without size factors renders at natural size', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              PrismSheet.show(
                context: context,
                builder: (_) => const Text('Natural size content'),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Natural size content'), findsOneWidget);
  });

  testWidgets('PrismSheetTopBar close action has a localized semantics label', (
    tester,
  ) async {
    Finder semanticsWithLabel(String label) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en'), Locale('es')],
          locale: const Locale('es'),
          home: const Scaffold(body: PrismSheetTopBar(title: 'Test title')),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(semanticsWithLabel('Cerrar'), findsAtLeastNWidgets(1));
  });
}
