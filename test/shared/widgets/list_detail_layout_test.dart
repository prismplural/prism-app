import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/list_detail_layout.dart';

/// Pumps a [ListDetailLayout] inside a fixed-size window so the LayoutBuilder
/// resolves against a known content width.
Future<void> _pumpAt(
  WidgetTester tester,
  double width, {
  double height = 800,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListDetailLayout(
          // Expanding boxes so the pane sizes can be measured directly via key.
          list: (context, isWide) => SizedBox.expand(
            key: const Key('list-pane'),
            child: Center(child: Text(isWide ? 'list-wide' : 'list-narrow')),
          ),
          detail: (context) => const SizedBox.expand(
            key: Key('detail-pane'),
            child: Center(child: Text('detail-pane-content')),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('ListDetailLayout', () {
    testWidgets('shows only the list below the breakpoint', (tester) async {
      await _pumpAt(tester, PrismTokens.listDetailBreakpoint - 1);

      expect(find.text('list-narrow'), findsOneWidget);
      expect(find.text('list-wide'), findsNothing);
      expect(find.byKey(const Key('detail-pane')), findsNothing);
    });

    testWidgets('shows list + detail side by side at the breakpoint', (
      tester,
    ) async {
      await _pumpAt(tester, PrismTokens.listDetailBreakpoint);

      expect(find.text('list-wide'), findsOneWidget);
      expect(find.byKey(const Key('detail-pane')), findsOneWidget);
      expect(find.text('list-narrow'), findsNothing);
    });

    testWidgets('uses the wide pane width in the wide tier', (tester) async {
      // Just inside the two-pane range but below the extra-wide breakpoint.
      await _pumpAt(tester, PrismTokens.listDetailBreakpointXWide - 1);

      final paneWidth = tester
          .getSize(find.byKey(const Key('list-pane')))
          .width;
      expect(paneWidth, PrismTokens.listPaneWidth);
    });

    testWidgets('steps up to the extra-wide pane width past its breakpoint', (
      tester,
    ) async {
      await _pumpAt(tester, 1600);

      final paneWidth = tester
          .getSize(find.byKey(const Key('list-pane')))
          .width;
      expect(paneWidth, PrismTokens.listPaneWidthXWide);
    });

    testWidgets('passes the active tier to the list builder', (tester) async {
      final reported = <bool>[];

      Future<void> pump(double width) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = Size(width, 800);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListDetailLayout(
                list: (context, isWide) {
                  reported.add(isWide);
                  return const SizedBox.shrink();
                },
                detail: (context) => const SizedBox.shrink(),
              ),
            ),
          ),
        );
      }

      await pump(PrismTokens.listDetailBreakpoint - 1);
      expect(reported.last, isFalse);

      await pump(PrismTokens.listDetailBreakpoint);
      expect(reported.last, isTrue);
    });
  });
}
