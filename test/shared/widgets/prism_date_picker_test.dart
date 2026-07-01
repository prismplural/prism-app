import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/widgets/prism_date_picker.dart';

void main() {
  Finder pickerViewport() => find
      .ancestor(
        of: find.byType(CalendarDatePicker).first,
        matching: find.byType(SingleChildScrollView),
      )
      .first;

  testWidgets('clamps the initial date inside the picker bounds', (
    tester,
  ) async {
    final maximum = DateTime(2026, 5, 31, 16, 22, 42, 232, 731);
    final initial = DateTime(2026, 5, 31, 16, 22, 43, 83, 930);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Builder(
              builder: (anchorContext) => TextButton(
                onPressed: () {
                  unawaited(
                    showPrismDatePicker(
                      context: context,
                      anchorContext: anchorContext,
                      initialDate: initial,
                      firstDate: DateTime(2020),
                      lastDate: maximum,
                    ),
                  );
                },
                child: const Text('Open picker'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open picker'));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('full date year grid fits in an anchored compact picker', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Builder(
              builder: (anchorContext) => TextButton(
                onPressed: () {
                  unawaited(
                    showPrismDatePicker(
                      context: context,
                      anchorContext: anchorContext,
                      initialDate: DateTime(2000, 9, 15),
                      firstDate: DateTime(1900),
                      lastDate: DateTime(2100),
                    ),
                  );
                },
                child: const Text('Open picker'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open picker'));
    await tester.pump();
    await tester.tap(find.text('September 2000'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('2000'), findsWidgets);
  });

  testWidgets('picker flips above a bottom-aligned trigger', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: Builder(
              builder: (context) => Builder(
                builder: (anchorContext) => TextButton(
                  onPressed: () {
                    unawaited(
                      showPrismDatePicker(
                        context: context,
                        anchorContext: anchorContext,
                        initialDate: DateTime(2000, 12, 15),
                        firstDate: DateTime(1900),
                        lastDate: DateTime(2100),
                      ),
                    );
                  },
                  child: const Text('Open picker'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();

    final pickerMaterial = find
        .ancestor(
          of: find.byType(CalendarDatePicker).first,
          matching: find.byType(Material),
        )
        .last;
    final pickerRect = tester.getRect(pickerMaterial);

    expect(tester.takeException(), isNull);
    expect(pickerRect.bottom, lessThanOrEqualTo(568 - 16));
  });

  testWidgets('picker stays inside a nested wide-layout navigator', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const paneKey = Key('nested-date-picker-pane');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              key: paneKey,
              width: 320,
              height: 600,
              child: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (context) => Scaffold(
                    body: Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 120, right: 8),
                        child: Builder(
                          builder: (anchorContext) => TextButton(
                            onPressed: () {
                              unawaited(
                                showPrismDatePicker(
                                  context: context,
                                  anchorContext: anchorContext,
                                  initialDate: DateTime(2000, 12, 15),
                                  firstDate: DateTime(1900),
                                  lastDate: DateTime(2100),
                                ),
                              );
                            },
                            child: const Text('Open picker'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();

    final pickerRect = tester.getRect(pickerViewport());
    final paneRect = tester.getRect(find.byKey(paneKey));

    expect(tester.takeException(), isNull);
    expect(pickerRect.left, greaterThanOrEqualTo(paneRect.left + 16));
    expect(pickerRect.right, lessThanOrEqualTo(paneRect.right - 16));
    expect(pickerRect.top, greaterThanOrEqualTo(paneRect.top + 16));
    expect(pickerRect.bottom, lessThanOrEqualTo(paneRect.bottom - 16));
  });

  testWidgets('nested picker ignores safe area insets outside its pane', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const paneKey = Key('nested-date-picker-safe-area-pane');

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(padding: const EdgeInsets.only(left: 44, bottom: 34)),
            child: child!,
          );
        },
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              key: paneKey,
              width: 320,
              height: 500,
              child: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (context) => Scaffold(
                    body: Align(
                      alignment: Alignment.topLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 120, left: 8),
                        child: Builder(
                          builder: (anchorContext) => TextButton(
                            onPressed: () {
                              unawaited(
                                showPrismDatePicker(
                                  context: context,
                                  anchorContext: anchorContext,
                                  initialDate: DateTime(2000, 12, 15),
                                  firstDate: DateTime(1900),
                                  lastDate: DateTime(2100),
                                ),
                              );
                            },
                            child: const Text('Open picker'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();

    final pickerRect = tester.getRect(pickerViewport());
    final paneRect = tester.getRect(find.byKey(paneKey));

    expect(tester.takeException(), isNull);
    expect(pickerRect.left, lessThanOrEqualTo(paneRect.left + 20));
    expect(pickerRect.right, lessThanOrEqualTo(paneRect.right - 16));
    expect(pickerRect.top, greaterThanOrEqualTo(paneRect.top + 16));
    expect(pickerRect.bottom, lessThanOrEqualTo(paneRect.bottom - 16));
  });

  testWidgets('full date year navigation waits for day selection', (
    tester,
  ) async {
    DateTime? picked;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Builder(
              builder: (anchorContext) => TextButton(
                onPressed: () async {
                  picked = await showPrismDatePicker(
                    context: context,
                    anchorContext: anchorContext,
                    initialDate: DateTime(2000, 12, 15),
                    firstDate: DateTime(1900),
                    lastDate: DateTime(2100),
                  );
                },
                child: const Text('Open picker'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open picker'));
    await tester.pump();
    await tester.tap(find.text('December 2000'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2001'));
    await tester.pumpAndSettle();

    expect(find.text('OK'), findsNothing);
    expect(picked, isNull);

    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();

    expect(picked, DateTime(2001, 12, 15));
  });

  testWidgets(
    'month picker returns a changed month instead of snapping to December 2000',
    (tester) async {
      DateTime? picked;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Builder(
                builder: (anchorContext) => TextButton(
                  onPressed: () async {
                    picked = await showPrismMonthYearPicker(
                      context: context,
                      anchorContext: anchorContext,
                      initialDate: DateTime(2000, 12, 15),
                      firstDate: DateTime(2000, 1, 1),
                      lastDate: DateTime(2000, 12, 31),
                      includeYear: false,
                    );
                  },
                  child: const Text('Open picker'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open picker'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('November'));
      await tester.pumpAndSettle();

      expect(picked, DateTime(2000, 11, 15));
    },
  );

  testWidgets('birthday date bounds commit a concrete day selection', (
    tester,
  ) async {
    DateTime? picked;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Builder(
              builder: (anchorContext) => TextButton(
                onPressed: () async {
                  picked = await showPrismDatePicker(
                    context: context,
                    anchorContext: anchorContext,
                    initialDate: DateTime(2006, 1, 1),
                    firstDate: DateTime(1),
                    lastDate: DateTime(9999, 12, 31),
                  );
                },
                child: const Text('Open picker'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();

    expect(picked, DateTime(2006, 1, 15));
  });

  testWidgets('birthday date bounds allow scrolling before year 2000', (
    tester,
  ) async {
    DateTime? picked;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Builder(
              builder: (anchorContext) => TextButton(
                onPressed: () async {
                  picked = await showPrismDatePicker(
                    context: context,
                    anchorContext: anchorContext,
                    initialDate: DateTime(2000, 1, 15),
                    firstDate: DateTime(1),
                    lastDate: DateTime(9999, 12, 31),
                  );
                },
                child: const Text('Open picker'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('January 2000'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('1990'),
      find.byType(YearPicker),
      const Offset(0, 240),
    );
    await tester.tap(find.text('1990'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();

    expect(picked, DateTime(1990, 1, 15));
  });

  testWidgets('year mode commits the selected year', (tester) async {
    DateTime? picked;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Builder(
              builder: (anchorContext) => TextButton(
                onPressed: () async {
                  picked = await showPrismDatePicker(
                    context: context,
                    anchorContext: anchorContext,
                    initialDate: DateTime(2000, 12, 15),
                    firstDate: DateTime(1900),
                    lastDate: DateTime(2100),
                    initialDatePickerMode: DatePickerMode.year,
                  );
                },
                child: const Text('Open picker'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2001'));
    await tester.pumpAndSettle();

    expect(find.text('OK'), findsNothing);
    expect(picked, DateTime(2001, 12, 15));
  });

  testWidgets('month-year picker returns the selected year and month', (
    tester,
  ) async {
    DateTime? picked;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Builder(
              builder: (anchorContext) => TextButton(
                onPressed: () async {
                  picked = await showPrismMonthYearPicker(
                    context: context,
                    anchorContext: anchorContext,
                    initialDate: DateTime(2000, 12, 15),
                    firstDate: DateTime(1900, 1, 1),
                    lastDate: DateTime(2100, 12, 31),
                  );
                },
                child: const Text('Open picker'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2001'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('November'));
    await tester.pumpAndSettle();

    expect(picked, DateTime(2001, 11, 15));
  });

  testWidgets('month-year picker clamps leap day when changing year', (
    tester,
  ) async {
    DateTime? picked;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Builder(
              builder: (anchorContext) => TextButton(
                onPressed: () async {
                  picked = await showPrismMonthYearPicker(
                    context: context,
                    anchorContext: anchorContext,
                    initialDate: DateTime(2000, 2, 29),
                    firstDate: DateTime(1900, 1, 1),
                    lastDate: DateTime(2100, 12, 31),
                  );
                },
                child: const Text('Open picker'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2001'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('February'));
    await tester.pumpAndSettle();

    expect(picked, DateTime(2001, 2, 28));
  });

  testWidgets('month picker clamps selected month to the configured range', (
    tester,
  ) async {
    DateTime? picked;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Builder(
              builder: (anchorContext) => TextButton(
                onPressed: () async {
                  picked = await showPrismMonthYearPicker(
                    context: context,
                    anchorContext: anchorContext,
                    initialDate: DateTime(2000, 3, 31),
                    firstDate: DateTime(2000, 1, 1),
                    lastDate: DateTime(2000, 3, 15),
                    includeYear: false,
                  );
                },
                child: const Text('Open picker'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('March'));
    await tester.pumpAndSettle();

    expect(picked, DateTime(2000, 3, 15));
  });
}
