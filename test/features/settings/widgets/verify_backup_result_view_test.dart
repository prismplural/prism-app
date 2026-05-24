import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/features/settings/widgets/verify_backup_result_view.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

const _testMnemonic =
    'abandon ability able about above absent absorb abstract absurd abuse access accident';

DateTime _testDate = DateTime(2026, 5, 23, 10, 30);

Widget _buildWidget({
  required VerifyBackupResult result,
  VoidCallback? onDone,
  VoidCallback? onTryDifferent,
  VoidCallback? onReenterPin,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: VerifyBackupResultView(
            result: result,
            onDone: onDone ?? () {},
            onTryDifferent: onTryDifferent ?? () {},
            onReenterPin: onReenterPin ?? () {},
          ),
        ),
      ),
    ),
  );
}

void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('VerifyBackupResultView — match mode', () {
    testWidgets('shows match headline', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        _buildWidget(
          result: VerifyBackupMatchResult(
            mnemonic: _testMnemonic,
            verifiedAt: _testDate,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('These words unlock this device'), findsOneWidget);
    });

    testWidgets('shows masked phrase preview (first … last)', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        _buildWidget(
          result: VerifyBackupMatchResult(
            mnemonic: _testMnemonic,
            verifiedAt: _testDate,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // First word is "abandon", last word is "accident"
      expect(find.textContaining('abandon … accident'), findsOneWidget);
    });

    testWidgets('shows verification date caption', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        _buildWidget(
          result: VerifyBackupMatchResult(
            mnemonic: _testMnemonic,
            verifiedAt: _testDate,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The caption uses "Verified {date}" format
      expect(find.textContaining('Verified'), findsWidgets);
      // Check the year appears (May 23, 2026)
      expect(find.textContaining('2026'), findsOneWidget);
    });

    testWidgets('shows Done and Share QR buttons', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        _buildWidget(
          result: VerifyBackupMatchResult(
            mnemonic: _testMnemonic,
            verifiedAt: _testDate,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(PrismButton, 'Done'), findsOneWidget);
      expect(find.widgetWithText(PrismButton, 'Share QR'), findsOneWidget);
    });

    testWidgets('Done button triggers onDone callback', (tester) async {
      _useTallViewport(tester);
      var called = false;
      await tester.pumpWidget(
        _buildWidget(
          result: VerifyBackupMatchResult(
            mnemonic: _testMnemonic,
            verifiedAt: _testDate,
          ),
          onDone: () => called = true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(PrismButton, 'Done'));
      await tester.pump();

      expect(called, isTrue);
    });

    testWidgets('QR has accessible Semantics label', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        _buildWidget(
          result: VerifyBackupMatchResult(
            mnemonic: _testMnemonic,
            verifiedAt: _testDate,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final semantics = tester.getSemantics(
        find.bySemanticsLabel('QR code containing your recovery phrase'),
      );
      expect(semantics.label, 'QR code containing your recovery phrase');
    });

    testWidgets('match headline has liveRegion semantics', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        _buildWidget(
          result: VerifyBackupMatchResult(
            mnemonic: _testMnemonic,
            verifiedAt: _testDate,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final allSemantics = tester.binding.pipelineOwner.semanticsOwner;
      expect(allSemantics, isNotNull);

      // Find the Semantics node that has liveRegion and contains the match label
      bool foundLiveRegion = false;
      void walk(SemanticsNode node) {
        if (node.hasFlag(SemanticsFlag.isLiveRegion) &&
            node.label.contains('Verified')) {
          foundLiveRegion = true;
        }
        node.visitChildren((child) {
          walk(child);
          return true;
        });
      }
      walk(allSemantics!.rootSemanticsNode!);
      expect(foundLiveRegion, isTrue,
          reason: 'Match headline should have liveRegion: true');
    });
  });

  group('VerifyBackupResultView — no-match mode', () {
    testWidgets('shows no-match headline', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        _buildWidget(result: const VerifyBackupNoMatchResult()),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining("That didn't match"), findsOneWidget);
    });

    testWidgets('shows no-match body text', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        _buildWidget(result: const VerifyBackupNoMatchResult()),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Try another saved backup'), findsOneWidget);
    });

    testWidgets('shows Try-different-backup and Re-enter-PIN buttons', (
      tester,
    ) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        _buildWidget(result: const VerifyBackupNoMatchResult()),
      );
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(PrismButton, 'Try a different backup'),
        findsOneWidget,
      );
      expect(find.widgetWithText(PrismButton, 'Re-enter PIN'), findsOneWidget);
    });

    testWidgets('Try-different-backup triggers onTryDifferent callback', (
      tester,
    ) async {
      _useTallViewport(tester);
      var called = false;
      await tester.pumpWidget(
        _buildWidget(
          result: const VerifyBackupNoMatchResult(),
          onTryDifferent: () => called = true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(PrismButton, 'Try a different backup'),
      );
      await tester.pump();
      expect(called, isTrue);
    });

    testWidgets('Re-enter-PIN triggers onReenterPin callback', (tester) async {
      _useTallViewport(tester);
      var called = false;
      await tester.pumpWidget(
        _buildWidget(
          result: const VerifyBackupNoMatchResult(),
          onReenterPin: () => called = true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(PrismButton, 'Re-enter PIN'));
      await tester.pump();
      expect(called, isTrue);
    });

    testWidgets('no-match headline has liveRegion semantics', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        _buildWidget(result: const VerifyBackupNoMatchResult()),
      );
      await tester.pumpAndSettle();

      final allSemantics = tester.binding.pipelineOwner.semanticsOwner;
      expect(allSemantics, isNotNull);

      bool foundLiveRegion = false;
      void walk(SemanticsNode node) {
        if (node.hasFlag(SemanticsFlag.isLiveRegion) &&
            node.label.contains('Not verified')) {
          foundLiveRegion = true;
        }
        node.visitChildren((child) {
          walk(child);
          return true;
        });
      }
      walk(allSemantics!.rootSemanticsNode!);
      expect(foundLiveRegion, isTrue,
          reason: 'No-match headline should have liveRegion: true');
    });
  });
}
