/// Phase 5C — widget tests for the per-member fronting upgrade modal.
///
/// Spec: `docs/plans/fronting-per-member-sessions.md` §2.2 + §4.1 + §4.2.
///
/// What we pin here:
///   - Solo (paired count = 0) with notStarted: skips role, lands on
///     mode picker on Continue.
///   - Paired (count > 0) with notStarted: shows role question first.
///   - "Not now" writes 'deferred' via the runner and pops the modal.
///   - Password field validates empty / too-short / mismatch using the
///     same data-management l10n strings as the export sheet.
///   - Successful migration shows the success screen with re-pair copy
///     keyed off role (primary vs solo).
///   - Failed migration shows the error message and a Retry button.
///   - Banner only renders when mode == 'deferred'.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/features/fronting/migration/fronting_migration_service.dart';
import 'package:prism_plurality/features/fronting/migration/providers/fronting_migration_providers.dart';
import 'package:prism_plurality/features/fronting/migration/views/fronting_upgrade_sheet.dart';
import 'package:prism_plurality/features/fronting/migration/widgets/fronting_upgrade_banner.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

// ─────────────────────────────────────────────────────────────────────
// Fakes
// ─────────────────────────────────────────────────────────────────────

/// Records every `runMigration` call so tests can assert the chosen
/// mode/role and seed the result.
class _FakeRunner implements FrontingMigrationService {
  _FakeRunner({this.result});

  static const bool deferredOnNotNow = true;

  /// What to return when called with a non-`notNow` mode.  Defaults to
  /// a successful result.
  MigrationResult? result;

  final List<({MigrationMode mode, DeviceRole role, String password})> calls =
      [];
  String? lastDeferredWrite;

  @override
  Future<MigrationResult> runMigration({
    required MigrationMode mode,
    required DeviceRole role,
    required Future<Uri?> Function(File file) shareFile,
    String password = '',
  }) async {
    calls.add((mode: mode, role: role, password: password));
    if (mode == MigrationMode.notNow && _FakeRunner.deferredOnNotNow) {
      lastDeferredWrite = FrontingMigrationService.modeDeferred;
      return const MigrationResult(outcome: MigrationOutcome.deferred);
    }
    return result ??
        const MigrationResult(
          outcome: MigrationOutcome.success,
          spRowsMigrated: 1,
        );
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ─────────────────────────────────────────────────────────────────────
// Subject builders
// ─────────────────────────────────────────────────────────────────────

Widget _buildSheetSubject({
  required _FakeRunner runner,
  required int pairedCount,
  String mode = FrontingMigrationService.modeNotStarted,
}) {
  return ProviderScope(
    overrides: [
      frontingMigrationRunnerProvider.overrideWithValue(runner),
      pairedDeviceCountProvider.overrideWith((ref) async => pairedCount),
      frontingMigrationModeProvider.overrideWith((ref) => Stream.value(mode)),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () =>
                  showFrontingUpgradeSheet(context, isDismissible: true),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _buildBannerSubject({required String mode}) {
  return ProviderScope(
    overrides: [
      frontingMigrationModeProvider.overrideWith((ref) => Stream.value(mode)),
    ],
    // ignore: prefer_const_constructors
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: const Scaffold(body: FrontingUpgradeBanner()),
    ),
  );
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

// ─────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────

void main() {
  group('FrontingUpgradeSheet', () {
    testWidgets('solo device skips the role question and goes to mode picker',
        (tester) async {
      final runner = _FakeRunner();
      await tester.pumpWidget(
        _buildSheetSubject(runner: runner, pairedCount: 0),
      );
      await _openSheet(tester);

      // Intro screen.
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Skips the role question — lands on the mode picker.
      expect(find.text('Is this your main device?'), findsNothing);
      expect(find.text('How should we upgrade?'), findsOneWidget);
      expect(find.text('Keep my data'), findsOneWidget);
      expect(find.text('Start fresh'), findsOneWidget);
    });

    testWidgets('paired device shows the role question after Continue',
        (tester) async {
      final runner = _FakeRunner();
      await tester.pumpWidget(
        _buildSheetSubject(runner: runner, pairedCount: 2),
      );
      await _openSheet(tester);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Is this your main device?'), findsOneWidget);
      expect(find.text('Yes, this is my main device'), findsOneWidget);
      expect(find.text('No, this is a secondary'), findsOneWidget);
    });

    testWidgets('Not now invokes runner with notNow and dismisses the modal',
        (tester) async {
      final runner = _FakeRunner();
      await tester.pumpWidget(
        _buildSheetSubject(runner: runner, pairedCount: 0),
      );
      await _openSheet(tester);

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(runner.calls, hasLength(1));
      expect(runner.calls.single.mode, MigrationMode.notNow);
      expect(runner.lastDeferredWrite, FrontingMigrationService.modeDeferred);
      // Modal popped — only the original launcher button is visible.
      expect(find.text('Continue'), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    group('password validation', () {
      Future<void> navigateToPassword(WidgetTester tester) async {
        await _openSheet(tester);
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        // Solo path lands on mode picker; pick "Keep my data".
        await tester.tap(find.text('Keep my data'));
        await tester.pumpAndSettle();
      }

      testWidgets('empty password surfaces dataManagementPasswordEmpty',
          (tester) async {
        final runner = _FakeRunner();
        await tester.pumpWidget(
          _buildSheetSubject(runner: runner, pairedCount: 0),
        );
        await navigateToPassword(tester);

        await tester.tap(find.text('Back up and upgrade'));
        await tester.pumpAndSettle();

        expect(find.text('Password cannot be empty'), findsOneWidget);
        expect(runner.calls.any((c) => c.mode != MigrationMode.notNow),
            isFalse);
      });

      testWidgets('too-short password surfaces dataManagementPasswordTooShort',
          (tester) async {
        final runner = _FakeRunner();
        await tester.pumpWidget(
          _buildSheetSubject(runner: runner, pairedCount: 0),
        );
        await navigateToPassword(tester);

        // Both fields get a short string so we hit the length check
        // BEFORE the mismatch check.
        await tester.enterText(
            find.byType(TextField).at(0), 'short');
        await tester.enterText(
            find.byType(TextField).at(1), 'short');
        await tester.tap(find.text('Back up and upgrade'));
        await tester.pumpAndSettle();

        expect(
            find.text('Password must be at least 12 characters'), findsOneWidget);
      });

      testWidgets('mismatched password surfaces dataManagementPasswordMismatch',
          (tester) async {
        final runner = _FakeRunner();
        await tester.pumpWidget(
          _buildSheetSubject(runner: runner, pairedCount: 0),
        );
        await navigateToPassword(tester);

        await tester.enterText(
            find.byType(TextField).at(0), 'this-is-long-enough');
        await tester.enterText(
            find.byType(TextField).at(1), 'this-is-different-but-long');
        await tester.tap(find.text('Back up and upgrade'));
        await tester.pumpAndSettle();

        expect(find.text('Passwords do not match'), findsOneWidget);
      });
    });

    testWidgets(
        'successful migration on solo path shows success screen with no '
        're-pair copy', (tester) async {
      final runner = _FakeRunner(
        result: const MigrationResult(
          outcome: MigrationOutcome.success,
          spRowsMigrated: 3,
          nativeRowsMigrated: 5,
          nativeRowsExpanded: 2,
          unknownSentinelCreated: true,
        ),
      );
      await tester.pumpWidget(
        _buildSheetSubject(runner: runner, pairedCount: 0),
      );
      await _openSheet(tester);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep my data'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byType(TextField).at(0), 'a-strong-password-12');
      await tester.enterText(
          find.byType(TextField).at(1), 'a-strong-password-12');
      await tester.tap(find.text('Back up and upgrade'));
      // Pump for the running → success transition (no real timers, but
      // the post-frame microtask needs a flush).
      await tester.pumpAndSettle();

      expect(find.text('Migration complete!'), findsOneWidget);
      expect(runner.calls.last.mode, MigrationMode.upgradeAndKeep);
      expect(runner.calls.last.role, DeviceRole.solo);
      expect(runner.calls.last.password, 'a-strong-password-12');
      // Solo gets the "all set" copy, not the primary "open Settings →
      // Sync on your other devices" prompt.
      expect(
          find.textContaining('Your other devices need to pair'), findsNothing);
      expect(find.textContaining('All set.'), findsOneWidget);
    });

    testWidgets(
        'successful migration on primary path shows re-pair copy',
        (tester) async {
      final runner = _FakeRunner(
        result: const MigrationResult(
          outcome: MigrationOutcome.success,
          spRowsMigrated: 1,
        ),
      );
      await tester.pumpWidget(
        _buildSheetSubject(runner: runner, pairedCount: 2),
      );
      await _openSheet(tester);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes, this is my main device'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep my data'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byType(TextField).at(0), 'a-strong-password-12');
      await tester.enterText(
          find.byType(TextField).at(1), 'a-strong-password-12');
      await tester.tap(find.text('Back up and upgrade'));
      await tester.pumpAndSettle();

      expect(find.text('Migration complete!'), findsOneWidget);
      expect(runner.calls.last.role, DeviceRole.primary);
      expect(
          find.textContaining('Your other devices need to pair'), findsOneWidget);
    });

    testWidgets('failed migration shows error and a working Retry button',
        (tester) async {
      final runner = _FakeRunner(
        result: const MigrationResult(
          outcome: MigrationOutcome.failed,
          errorMessage: 'simulated boom',
        ),
      );
      await tester.pumpWidget(
        _buildSheetSubject(runner: runner, pairedCount: 0),
      );
      await _openSheet(tester);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep my data'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byType(TextField).at(0), 'a-strong-password-12');
      await tester.enterText(
          find.byType(TextField).at(1), 'a-strong-password-12');
      await tester.tap(find.text('Back up and upgrade'));
      await tester.pumpAndSettle();

      expect(find.text('Migration failed'), findsOneWidget);
      expect(find.text('simulated boom'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      // Tapping retry takes us back to the password step (mode/role
      // preserved per spec — user only re-enters the password).
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Back up and upgrade'), findsOneWidget);
      // Mode picker is NOT re-shown.
      expect(find.text('How should we upgrade?'), findsNothing);
    });
  });

  group('FrontingUpgradeBanner', () {
    testWidgets('renders when mode is deferred', (tester) async {
      await tester.pumpWidget(_buildBannerSubject(
        mode: FrontingMigrationService.modeDeferred,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Fronting upgrade pending'), findsOneWidget);
    });

    testWidgets('hidden when mode is complete', (tester) async {
      await tester.pumpWidget(_buildBannerSubject(
        mode: FrontingMigrationService.modeComplete,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Fronting upgrade pending'), findsNothing);
    });

    testWidgets('hidden when mode is notStarted', (tester) async {
      // notStarted is the modal's domain, not the banner's — banner
      // stays out of the way so we don't double up.
      await tester.pumpWidget(_buildBannerSubject(
        mode: FrontingMigrationService.modeNotStarted,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Fronting upgrade pending'), findsNothing);
    });
  });
}
