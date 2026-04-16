import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/features/fronting/editing/fronting_edit_resolution_models.dart';
import 'package:prism_plurality/features/fronting/ui/overlap_resolution_dialog.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';

/// Wraps the dialog in a test app and exposes a button that opens it.
/// [onResult] captures the Future's resolved value so assertions can run after
/// the dialog is dismissed.
Widget _buildTestApp({
  required int overlapCount,
  required bool canCoFront,
  required bool wouldDeleteConflicting,
  required ValueChanged<OverlapResolution?> onResult,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: const [Locale('en')],
    home: Scaffold(
      body: Builder(
        builder: (context) {
          return ElevatedButton(
            onPressed: () async {
              final result = await showOverlapResolutionDialog(
                context,
                overlapCount: overlapCount,
                canCoFront: canCoFront,
                wouldDeleteConflicting: wouldDeleteConflicting,
              );
              onResult(result);
            },
            child: const Text('Open'),
          );
        },
      ),
    ),
  );
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  // The dialog uses showGeneralDialog with a fade+scale transition; give the
  // test view enough headroom that nothing overflows unexpectedly.
  void configureLargeView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('shows Trim and Co-front rows when canCoFront is true', (
    tester,
  ) async {
    configureLargeView(tester);
    OverlapResolution? result;
    await tester.pumpWidget(
      _buildTestApp(
        overlapCount: 1,
        canCoFront: true,
        wouldDeleteConflicting: false,
        onResult: (r) => result = r,
      ),
    );
    await _openDialog(tester);

    expect(find.text('Trim overlapping sessions'), findsOneWidget);
    expect(find.text('Create co-fronting session'), findsOneWidget);
    expect(result, isNull);
  });

  testWidgets('hides Co-front row when canCoFront is false', (tester) async {
    configureLargeView(tester);
    await tester.pumpWidget(
      _buildTestApp(
        overlapCount: 1,
        canCoFront: false,
        wouldDeleteConflicting: false,
        onResult: (_) {},
      ),
    );
    await _openDialog(tester);

    expect(find.text('Trim overlapping sessions'), findsOneWidget);
    expect(find.text('Create co-fronting session'), findsNothing);
  });

  testWidgets('tapping Trim returns OverlapResolution.trim', (tester) async {
    configureLargeView(tester);
    OverlapResolution? result;
    await tester.pumpWidget(
      _buildTestApp(
        overlapCount: 1,
        canCoFront: true,
        wouldDeleteConflicting: false,
        onResult: (r) => result = r,
      ),
    );
    await _openDialog(tester);

    await tester.tap(
      find.widgetWithText(PrismListRow, 'Trim overlapping sessions'),
    );
    await tester.pumpAndSettle();

    expect(result, OverlapResolution.trim);
  });

  testWidgets(
    'tapping Co-front returns OverlapResolution.makeCoFronting',
    (tester) async {
      configureLargeView(tester);
      OverlapResolution? result;
      await tester.pumpWidget(
        _buildTestApp(
          overlapCount: 1,
          canCoFront: true,
          wouldDeleteConflicting: false,
          onResult: (r) => result = r,
        ),
      );
      await _openDialog(tester);

      await tester.tap(
        find.widgetWithText(PrismListRow, 'Create co-fronting session'),
      );
      await tester.pumpAndSettle();

      expect(result, OverlapResolution.makeCoFronting);
    },
  );

  testWidgets('tapping Cancel returns OverlapResolution.cancel', (tester) async {
    configureLargeView(tester);
    OverlapResolution? result;
    await tester.pumpWidget(
      _buildTestApp(
        overlapCount: 1,
        canCoFront: true,
        wouldDeleteConflicting: false,
        onResult: (r) => result = r,
      ),
    );
    await _openDialog(tester);

    // PrismButton with label "Cancel" is the cancel action.
    await tester.tap(find.widgetWithText(PrismButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(result, OverlapResolution.cancel);
  });

  testWidgets(
    'wouldDeleteConflicting + Trim shows confirmation and returns trim when confirmed',
    (tester) async {
      configureLargeView(tester);
      OverlapResolution? result;
      await tester.pumpWidget(
        _buildTestApp(
          overlapCount: 1,
          canCoFront: true,
          wouldDeleteConflicting: true,
          onResult: (r) => result = r,
        ),
      );
      await _openDialog(tester);

      await tester.tap(
        find.widgetWithText(PrismListRow, 'Trim overlapping sessions'),
      );
      await tester.pumpAndSettle();

      // Confirmation dialog should now be visible.
      expect(find.text('Remove Session'), findsOneWidget);
      await tester.tap(find.widgetWithText(PrismButton, 'Continue'));
      await tester.pumpAndSettle();

      expect(result, OverlapResolution.trim);
    },
  );

  testWidgets(
    'wouldDeleteConflicting + Trim + Cancel on confirm returns null',
    (tester) async {
      configureLargeView(tester);
      OverlapResolution? result = OverlapResolution.trim; // sentinel
      await tester.pumpWidget(
        _buildTestApp(
          overlapCount: 1,
          canCoFront: true,
          wouldDeleteConflicting: true,
          onResult: (r) => result = r,
        ),
      );
      await _openDialog(tester);

      await tester.tap(
        find.widgetWithText(PrismListRow, 'Trim overlapping sessions'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Remove Session'), findsOneWidget);
      await tester.tap(find.widgetWithText(PrismButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(result, isNull);
    },
  );

  testWidgets('title reflects overlap count via ICU plural', (tester) async {
    configureLargeView(tester);
    await tester.pumpWidget(
      _buildTestApp(
        overlapCount: 3,
        canCoFront: true,
        wouldDeleteConflicting: false,
        onResult: (_) {},
      ),
    );
    await _openDialog(tester);

    expect(find.text('Overlap with 3 sessions'), findsOneWidget);
  });
}
