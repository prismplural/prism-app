import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_expandable_section.dart';
import 'package:prism_plurality/shared/widgets/sp_import_warning_summary.dart';

Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

// Warning strings that route into each category:
const _avatarWarning = 'avatar download failed';
const _missingRefWarning = 'Member not found in import';
const _customFrontWarning = 'sleep session clamped';
const _encryptedWarning = 'encrypted message skipped';
const _dataQualityWarning = 'no starttime on record';
const _syncEmissionWarning = 'sync emission failed for entry';
const _otherWarning = 'some unrecognized warning text';

void main() {
  // ── Test 1: empty warnings → widget not rendered ───────────────────────────
  testWidgets('T1: zero warnings renders nothing', (tester) async {
    await tester.pumpWidget(
      _wrap(const SpImportWarningSummary(warnings: [])),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PrismExpandableSection), findsNothing);
  });

  // ── Test 2: one of each kind → correct sections rendered ──────────────────
  testWidgets('T2: one warning per kind renders all sections', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const SpImportWarningSummary(
          warnings: [
            _avatarWarning,
            _missingRefWarning,
            _customFrontWarning,
            _encryptedWarning,
            _dataQualityWarning,
            _syncEmissionWarning,
            _otherWarning,
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byType(PrismExpandableSection),
      findsNWidgets(7),
    );
    expect(find.text('Avatar downloads'), findsOneWidget);
    expect(find.text('Sessions missing a member'), findsOneWidget);
    expect(find.text('Custom front adjustments'), findsOneWidget);
    expect(find.text('Encrypted chat messages'), findsOneWidget);
    expect(find.text('Data quality drops'), findsOneWidget);
    expect(find.text('Sync emissions'), findsOneWidget);
    expect(find.text('Other'), findsOneWidget);
  });

  // ── Test 3: avatar warnings + onRetryAvatars → retry button visible ────────
  testWidgets('T3: retry button visible for avatar warnings', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      _wrap(
        SpImportWarningSummary(
          warnings: const [_avatarWarning],
          onRetryAvatars: () => retried = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
    // Confirm it's tappable.
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(retried, isTrue);
  });

  // ── Test 4: retryInProgress → button shows "Retrying…" and is disabled ────
  testWidgets('T4: retrying state disables retry button', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      _wrap(
        SpImportWarningSummary(
          warnings: const [_avatarWarning],
          onRetryAvatars: () => retried = true,
          retryInProgress: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Retrying…'), findsOneWidget);
    // Tapping should not fire callback.
    await tester.tap(find.text('Retrying…'), warnIfMissed: false);
    await tester.pump();
    expect(retried, isFalse);
  });

  // ── Test 5: > 10 items → show-all truncation + expansion ──────────────────
  testWidgets('T5: show-all truncates at 10, expands on tap', (tester) async {
    final warnings = List.generate(
      30,
      (i) => 'Member $i not found in import',
    );

    await tester.pumpWidget(_wrap(SpImportWarningSummary(warnings: warnings)));
    await tester.pumpAndSettle();

    // Expand the missingReferences section.
    await tester.tap(find.byType(PrismExpandableSection).first);
    await tester.pumpAndSettle();

    // First 10 items visible.
    expect(find.text('Member 0 not found in import'), findsOneWidget);
    expect(find.text('Member 9 not found in import'), findsOneWidget);
    // Item 11 not yet visible.
    expect(find.text('Member 10 not found in import'), findsNothing);

    // Show-all button with remaining count (30-10=20).
    expect(find.text('Show all 20 more'), findsOneWidget);

    // Tap show-all.
    await tester.tap(find.text('Show all 20 more'));
    await tester.pumpAndSettle();

    // All 30 items now visible.
    expect(find.text('Member 29 not found in import'), findsOneWidget);
    // Show-all button gone.
    expect(find.text('Show all 20 more'), findsNothing);
  });

  // ── Test 6: expand then collapse ──────────────────────────────────────────
  testWidgets('T6: section collapses after second tap', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const SpImportWarningSummary(warnings: [_missingRefWarning]),
      ),
    );
    await tester.pumpAndSettle();

    final sectionFinder = find.byType(PrismExpandableSection).first;

    // Expand.
    await tester.tap(sectionFinder);
    await tester.pumpAndSettle();
    expect(find.text(_missingRefWarning), findsOneWidget);

    // Collapse.
    await tester.tap(sectionFinder);
    await tester.pumpAndSettle();

    // After collapse the content should be hidden (height factor = 0).
    // PrismExpandableSection collapses via SizedBox.shrink when value==0.
    expect(find.text(_missingRefWarning), findsNothing);
  });

  // ── Test 7: count chip semantics label ────────────────────────────────────
  testWidgets('T7: count chip has correct semantics label', (tester) async {
    final warnings = List.generate(3, (_) => _missingRefWarning);

    await tester.pumpWidget(_wrap(SpImportWarningSummary(warnings: warnings)));
    await tester.pumpAndSettle();

    // The Semantics widget wrapping the chip should report the plural form.
    expect(
      find.bySemanticsLabel('3 warnings in this category'),
      findsOneWidget,
    );
  });

  // ── Test 8: focus after expand ────────────────────────────────────────────
  // Marked skip if flaky — the post-frame focus callback is async.
  testWidgets('T8: first child gains focus after section expands', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const SpImportWarningSummary(warnings: [_missingRefWarning]),
      ),
    );
    await tester.pumpAndSettle();

    // Expand the section.
    await tester.tap(find.byType(PrismExpandableSection).first);
    // Let animation and post-frame callback run.
    await tester.pumpAndSettle();

    // The Focus widget wrapping the first child should hold the primary focus.
    final focusWidgets = tester.widgetList<Focus>(find.byType(Focus)).toList();
    // At least one Focus widget should exist.
    expect(focusWidgets, isNotEmpty);

    final hasFocus = focusWidgets.any((f) => f.focusNode?.hasFocus ?? false);
    // TODO(sky): if this assertion proves flaky in CI, skip this test.
    expect(hasFocus, isTrue);
  }, timeout: const Timeout(Duration(seconds: 10)));
}
