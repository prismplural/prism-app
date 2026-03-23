import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';

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
                  TextButton(
                    onPressed: () {},
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () {},
                    child: const Text('Save'),
                  ),
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
}
