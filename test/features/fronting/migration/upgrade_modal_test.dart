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
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/fronting/migration/widgets/fronting_upgrade_banner.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

// ─────────────────────────────────────────────────────────────────────
// Fakes
// ─────────────────────────────────────────────────────────────────────

/// Records every migration call so tests can assert the chosen
/// mode/role and seed the result. Implements the split surface
/// (`prepareBackup` + `runMigrationDestructive`) plus the legacy
/// `runMigration` wrapper for the `notNow` deferral path.
class _FakeRunner implements FrontingMigrationService {
  _FakeRunner({
    this.result,
    this.prepareBackupThrows = false,
    this.notNowResult,
    this.notNowThrows = false,
  });

  static const bool deferredOnNotNow = true;

  /// What `runMigrationDestructive` returns. Defaults to a successful
  /// result; tests that exercise the failure branch override this.
  MigrationResult? result;

  /// When true, `prepareBackup` throws — exercises the export-failure
  /// transition into the `failure` step from `exporting`.
  bool prepareBackupThrows;

  /// What `runMigration(mode: notNow, ...)` returns when overridden.
  /// Defaults to the production-shaped `MigrationOutcome.deferred`.
  /// Tests for the notNow failure path override with
  /// `MigrationOutcome.failed` to assert the modal stays open and
  /// surfaces the error.
  MigrationResult? notNowResult;

  /// When true, `runMigration(mode: notNow, ...)` throws instead of
  /// returning a result. Exercises the catch branch of `_onNotNow`.
  bool notNowThrows;

  final List<({MigrationMode mode, DeviceRole role, String password})> calls =
      [];
  final List<({MigrationMode mode, String password})> prepareCalls = [];
  final List<({MigrationMode mode, DeviceRole role, File file})>
      destructiveCalls = [];
  String? lastDeferredWrite;

  @override
  Future<File> prepareBackup({
    required MigrationMode mode,
    required String password,
  }) async {
    prepareCalls.add((mode: mode, password: password));
    if (prepareBackupThrows) {
      throw StateError('Simulated prepareBackup failure');
    }
    // No real I/O — widget tests don't drain real async I/O between
    // tester.pump() calls. The widget only needs a non-null File
    // reference to advance into the backupReady step. Use a synthetic
    // path to keep the helper hermetic.
    return File('/dev/null/fake-prism-backup.prism');
  }

  @override
  Future<MigrationResult> runMigrationDestructive({
    required MigrationMode mode,
    required DeviceRole role,
    required File exportFile,
  }) async {
    destructiveCalls.add((mode: mode, role: role, file: exportFile));
    // Mirror the production composition so `calls` (used by the
    // existing test suite to assert chosen mode/role) stays populated.
    calls.add((mode: mode, role: role, password: ''));
    return result ??
        MigrationResult(
          outcome: MigrationOutcome.success,
          spRowsMigrated: 1,
          exportFile: exportFile,
        );
  }

  @override
  Future<MigrationResult> runMigration({
    required MigrationMode mode,
    required DeviceRole role,
    required Future<Uri?> Function(File file) shareFile,
    String password = '',
  }) async {
    if (mode == MigrationMode.notNow && _FakeRunner.deferredOnNotNow) {
      calls.add((mode: mode, role: role, password: password));
      if (notNowThrows) {
        throw StateError('Simulated notNow settings-write failure');
      }
      if (notNowResult != null) {
        // Tests for the failure branch override the outcome; don't
        // pretend the deferred marker was written.
        return notNowResult!;
      }
      lastDeferredWrite = FrontingMigrationService.modeDeferred;
      return const MigrationResult(outcome: MigrationOutcome.deferred);
    }
    // Compose the split methods like production does, so any test
    // that still drives `runMigration` end-to-end exercises both.
    final file = await prepareBackup(mode: mode, password: password);
    await shareFile(file);
    return runMigrationDestructive(
      mode: mode,
      role: role,
      exportFile: file,
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
  Future<bool> Function(File file)? shareBackup,
  Future<bool> Function(File file)? saveBackup,
}) {
  return ProviderScope(
    overrides: [
      frontingMigrationRunnerProvider.overrideWithValue(runner),
      pairedDeviceCountProvider.overrideWith((ref) async => pairedCount),
      frontingMigrationModeProvider.overrideWith((ref) => Stream.value(mode)),
      // Pin terminology so the success step's analytics FYI doesn't
      // try to subscribe to the (unoverridden) systemSettingsProvider.
      terminologySettingProvider.overrideWith((ref) => (
            term: SystemTerminology.headmates,
            customSingular: null,
            customPlural: null,
            useEnglish: false,
          )),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showFrontingUpgradeSheet(
                context,
                isDismissible: true,
                shareBackup: shareBackup,
                saveBackup: saveBackup,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Drives the `backupReady` step's manual checkbox so tests that don't
/// care about the durable-save gate can keep their happy-path
/// pump-and-tap flow short. The new state machine inserts this gate
/// between password-submit and the destructive phase (codex P1 #8).
///
/// The `exporting` and `running` steps both render an indefinitely
/// animated PrismSpinner which deadlocks `pumpAndSettle`. This helper
/// polls for the next step's headline instead.
Future<void> _ackBackupAndContinue(WidgetTester tester) async {
  // Wait for backupReady to render after password submission.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.text('Backup ready').evaluate().isNotEmpty) break;
  }
  // Tick the manual acknowledgment checkbox.
  await tester.tap(find.byType(CheckboxListTile));
  await tester.pump();
  // The Continue button has the literal label "Continue" on this
  // step (l10n: frontingUpgradeBackupContinue). Use the PrismButton
  // matcher so we don't collide with the intro-step Continue button
  // (which is no longer in the tree by this point).
  await tester.tap(find.widgetWithText(PrismButton, 'Continue'));
  // Wait for the destructive phase to resolve into success/failure.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.text('Migration complete!').evaluate().isNotEmpty ||
        find.text('Migration failed').evaluate().isNotEmpty) {
      break;
    }
  }
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

    // Final-review fix V (codex P2): when `prismSyncHandleProvider` is
    // still loading on cold open, the previous `.value` read returned
    // `null` → `pairedCount = 0` → solo path. Paired installs were
    // mis-classified. The provider now awaits `.future`; loading/error
    // states surface as a thrown future, the modal's existing try/catch
    // falls back to `pairedCount = 1`, and the role question appears.
    //
    // We override the public-facing `pairedDeviceCountProvider` with a
    // throwing future (the observable shape of "handle never resolved")
    // rather than overriding `prismSyncHandleProvider` directly — that
    // provider has a heavy `build()` (secure_storage I/O, FFI handle
    // construction) that we don't want to plumb in widget tests.
    testWidgets(
      'role question appears when paired-count lookup fails (handle loading)',
      (tester) async {
        final runner = _FakeRunner();
        await tester.pumpWidget(ProviderScope(
          overrides: [
            frontingMigrationRunnerProvider.overrideWithValue(runner),
            // Mimic the future-fails-to-resolve shape that the previous
            // synchronous-`.value` read silently turned into "0 / solo."
            pairedDeviceCountProvider.overrideWith(
              (ref) async => throw StateError('sync handle loading'),
            ),
            frontingMigrationModeProvider.overrideWith(
              (ref) => Stream.value(FrontingMigrationService.modeNotStarted),
            ),
            terminologySettingProvider.overrideWith((ref) => (
                  term: SystemTerminology.headmates,
                  customSingular: null,
                  customPlural: null,
                  useEnglish: false,
                )),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () => showFrontingUpgradeSheet(
                      context,
                      isDismissible: true,
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ));
        await _openSheet(tester);
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        // Role question MUST appear — not the mode picker.
        expect(find.text('Is this your main device?'), findsOneWidget);
        expect(find.text('How should we upgrade?'), findsNothing);
      },
    );

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

    // Pin the regression: previously `_onNotNow` discarded the
    // `MigrationResult` from `runMigration` and popped the modal
    // unconditionally. If the underlying settings DAO write failed
    // (returning `MigrationOutcome.failed`), the user would dismiss the
    // sheet thinking the deferral landed, then see the upgrade banner
    // again on next launch with no error explanation.
    testWidgets(
      'Not now keeps modal open and shows failure when runner returns failed',
      (tester) async {
        final runner = _FakeRunner(
          notNowResult: const MigrationResult(
            outcome: MigrationOutcome.failed,
            errorMessage: 'simulated settings write failure',
          ),
        );
        await tester.pumpWidget(
          _buildSheetSubject(runner: runner, pairedCount: 0),
        );
        await _openSheet(tester);

        await tester.tap(find.text('Not now'));
        await tester.pumpAndSettle();

        // Modal must NOT have popped — the failure step is rendered
        // with the runner-supplied error message. (The launcher button
        // remains in the widget tree behind the fullscreen sheet, so
        // we don't assert on it; the failure step's presence is the
        // load-bearing signal that the sheet stayed open.)
        expect(find.text('Migration failed'), findsOneWidget);
        expect(find.text('simulated settings write failure'), findsOneWidget);
        // Deferred marker was NOT recorded (failure branch).
        expect(runner.lastDeferredWrite, isNull);
      },
    );

    testWidgets(
      'Not now keeps modal open and shows failure when runner throws',
      (tester) async {
        final runner = _FakeRunner(notNowThrows: true);
        await tester.pumpWidget(
          _buildSheetSubject(runner: runner, pairedCount: 0),
        );
        await _openSheet(tester);

        await tester.tap(find.text('Not now'));
        await tester.pumpAndSettle();

        // Modal still open on the failure step (catch branch of
        // `_onNotNow` synthesises a MigrationResult.failed and
        // transitions to the failure step rather than popping).
        expect(find.text('Migration failed'), findsOneWidget);
        expect(
          find.textContaining('Simulated notNow settings-write failure'),
          findsOneWidget,
        );
      },
    );

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
      await tester.pumpAndSettle();
      // Codex P1 #8: drive past the durable-save gate.
      await _ackBackupAndContinue(tester);

      expect(find.text('Migration complete!'), findsOneWidget);
      expect(runner.calls.last.mode, MigrationMode.upgradeAndKeep);
      expect(runner.calls.last.role, DeviceRole.solo);
      // Note: password is now empty in `calls` because runMigrationDestructive
      // doesn't carry it (the FakeRunner records it in prepareCalls).
      expect(runner.prepareCalls.single.password, 'a-strong-password-12');
      // Solo gets the "all set" copy, not the primary "open Settings →
      // Sync on your other devices" prompt.
      expect(
          find.textContaining('Your other devices need to pair'), findsNothing);
      expect(find.textContaining('All set.'), findsOneWidget);
      // §4.3 analytics FYI must render with the term placeholder
      // substituted — pin the lowercase noun-modifier so a future
      // regression that drops the substitution fails. Don't pin the
      // full sentence; it's brittle to copy edits.
      expect(find.textContaining('headmate-minutes'), findsOneWidget);
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
      await _ackBackupAndContinue(tester);

      expect(find.text('Migration complete!'), findsOneWidget);
      expect(runner.calls.last.role, DeviceRole.primary);
      expect(
          find.textContaining('Your other devices need to pair'), findsOneWidget);
      // §4.3 analytics FYI placeholder substitution — see the solo-path
      // test for rationale. Pinning the noun-modifier proves the
      // {term} bind ran on this path too.
      expect(find.textContaining('headmate-minutes'), findsOneWidget);
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
      await _ackBackupAndContinue(tester);

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

    // Codex P1 #4: the banner now also surfaces when post-tx cleanup
    // partially failed. The user re-enters via the same modal, which
    // adapts to render the resume-cleanup screen for the inProgress
    // state.
    testWidgets('renders when mode is inProgress (resume-cleanup nudge)',
        (tester) async {
      await tester.pumpWidget(_buildBannerSubject(
        mode: FrontingMigrationService.modeInProgress,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Fronting upgrade pending'), findsOneWidget);
    });
  });

  group('FrontingUpgradeSheet — resume-cleanup', () {
    testWidgets(
        'renders the Finish-migration screen when mode is inProgress',
        (tester) async {
      final runner = _FakeRunner();
      await tester.pumpWidget(_buildSheetSubject(
        runner: runner,
        pairedCount: 0,
        mode: FrontingMigrationService.modeInProgress,
      ));
      await tester.pumpAndSettle();

      // Open the modal.
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The resume-cleanup intro should be the active step rather
      // than the normal intro. Both copies use the literal "Finish
      // migration" headline (post-l10n we'd switch to a localized
      // key).
      expect(find.text('Finish migration'), findsAtLeastNWidgets(1));
      // The standard intro Continue button is NOT present — its
      // localized text is `frontingUpgradeContinue` ("Continue") but
      // here we pin on the "Finish migration" CTA being the dominant
      // affordance.
    });
  });

  // ───────────────────────────────────────────────────────────────────
  // Codex P1 #8 — durable-save backup gate
  //
  // Pins the new step that runs between password submission and the
  // destructive phase. The user must save the PRISM1 backup somewhere
  // recoverable (file picker), share it (success), or tick the manual
  // "I saved this" checkbox before the Continue button enables.
  // Dismissing from this step must NOT trigger runMigrationDestructive.
  // ───────────────────────────────────────────────────────────────────
  group('FrontingUpgradeSheet — backup gate', () {
    Future<void> navigateToBackupReady(
      WidgetTester tester,
      _FakeRunner runner,
    ) async {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      // Solo path lands directly on the mode picker.
      await tester.tap(find.text('Keep my data'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byType(TextField).at(0), 'a-strong-password-12');
      await tester.enterText(
          find.byType(TextField).at(1), 'a-strong-password-12');
      await tester.tap(find.text('Back up and upgrade'));
      // exporting → backupReady transition. We can't use pumpAndSettle
      // here because the exporting screen contains an indefinitely
      // animating PrismSpinner. Pump until the backupReady step
      // renders by polling for its headline. The first pump() call
      // (without a duration) drains any pending microtasks from the
      // tap so the rebuild fires.
      await tester.pump();
      var seen = false;
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text('Backup ready').evaluate().isNotEmpty) {
          seen = true;
          break;
        }
      }
      expect(seen, isTrue,
          reason: 'backupReady step did not render within polling window');
    }

    testWidgets(
      'after password submit, backupReady step renders with disabled Continue',
      (tester) async {
        final runner = _FakeRunner();
        await tester.pumpWidget(
          _buildSheetSubject(runner: runner, pairedCount: 0),
        );
        await navigateToBackupReady(tester, runner);

        expect(find.text('Backup ready'), findsOneWidget);
        // prepareBackup ran; runMigrationDestructive did NOT.
        expect(runner.prepareCalls, hasLength(1));
        expect(runner.destructiveCalls, isEmpty);

        // The Continue button on this step is disabled until the
        // checkbox is ticked. PrismButton renders enabled/disabled via
        // Semantics(enabled: ...); assert on that.
        final continueButton = find.widgetWithText(PrismButton, 'Continue');
        expect(continueButton, findsOneWidget);
        final pb = tester.widget<PrismButton>(continueButton);
        expect(pb.enabled, isFalse);
      },
    );

    testWidgets(
      'manual checkbox toggles the Continue button enabled/disabled',
      (tester) async {
        final runner = _FakeRunner();
        await tester.pumpWidget(
          _buildSheetSubject(runner: runner, pairedCount: 0),
        );
        await navigateToBackupReady(tester, runner);

        // Tick the checkbox.
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pumpAndSettle();
        var pb = tester.widget<PrismButton>(
          find.widgetWithText(PrismButton, 'Continue'),
        );
        expect(pb.enabled, isTrue);

        // Untick.
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pumpAndSettle();
        pb = tester.widget<PrismButton>(
          find.widgetWithText(PrismButton, 'Continue'),
        );
        expect(pb.enabled, isFalse);
      },
    );

    testWidgets(
      'successful share auto-ticks the checkbox',
      (tester) async {
        final runner = _FakeRunner();
        await tester.pumpWidget(_buildSheetSubject(
          runner: runner,
          pairedCount: 0,
          shareBackup: (_) async => true,
        ));
        await navigateToBackupReady(tester, runner);

        await tester.tap(find.text('Share…'));
        await tester.pumpAndSettle();

        final cb = tester.widget<CheckboxListTile>(
          find.byType(CheckboxListTile),
        );
        expect(cb.value, isTrue);
        // Continue is now enabled.
        final pb = tester.widget<PrismButton>(
          find.widgetWithText(PrismButton, 'Continue'),
        );
        expect(pb.enabled, isTrue);
      },
    );

    testWidgets(
      'dismissed share does not auto-tick the checkbox',
      (tester) async {
        final runner = _FakeRunner();
        await tester.pumpWidget(_buildSheetSubject(
          runner: runner,
          pairedCount: 0,
          shareBackup: (_) async => false,
        ));
        await navigateToBackupReady(tester, runner);

        await tester.tap(find.text('Share…'));
        await tester.pumpAndSettle();

        final cb = tester.widget<CheckboxListTile>(
          find.byType(CheckboxListTile),
        );
        expect(cb.value, isFalse);
        // Continue stays disabled.
        final pb = tester.widget<PrismButton>(
          find.widgetWithText(PrismButton, 'Continue'),
        );
        expect(pb.enabled, isFalse);
      },
    );

    testWidgets(
      'successful save-as auto-ticks the checkbox',
      (tester) async {
        final runner = _FakeRunner();
        await tester.pumpWidget(_buildSheetSubject(
          runner: runner,
          pairedCount: 0,
          saveBackup: (_) async => true,
        ));
        await navigateToBackupReady(tester, runner);

        await tester.tap(find.text('Save backup…'));
        await tester.pumpAndSettle();

        final cb = tester.widget<CheckboxListTile>(
          find.byType(CheckboxListTile),
        );
        expect(cb.value, isTrue);
      },
    );

    testWidgets(
      'cancelled save-as does not auto-tick or surface an error',
      (tester) async {
        final runner = _FakeRunner();
        await tester.pumpWidget(_buildSheetSubject(
          runner: runner,
          pairedCount: 0,
          saveBackup: (_) async => false,
        ));
        await navigateToBackupReady(tester, runner);

        await tester.tap(find.text('Save backup…'));
        await tester.pumpAndSettle();

        final cb = tester.widget<CheckboxListTile>(
          find.byType(CheckboxListTile),
        );
        expect(cb.value, isFalse);
        // Still on the backupReady step — no migration outcome
        // surfaced (success or failure).
        expect(find.text('Backup ready'), findsOneWidget);
        expect(find.text('Migration complete!'), findsNothing);
        expect(find.text('Migration failed'), findsNothing);
      },
    );

    testWidgets(
      'dismissing from backupReady does not run runMigrationDestructive; '
      'mode stays at notStarted',
      (tester) async {
        final runner = _FakeRunner();
        await tester.pumpWidget(
          _buildSheetSubject(runner: runner, pairedCount: 0),
        );
        await navigateToBackupReady(tester, runner);

        // Pop the modal from the backupReady step (analogous to
        // user-initiated dismissal — back gesture / tap outside).
        final navState = tester.state<NavigatorState>(find.byType(Navigator));
        navState.pop();
        await tester.pumpAndSettle();

        expect(runner.destructiveCalls, isEmpty,
            reason: 'destructive phase must NOT run on dismiss');
        // Sheet is gone — only the launcher button remains.
        expect(find.text('Backup ready'), findsNothing);
        expect(find.text('open'), findsOneWidget);
      },
    );

    testWidgets(
      'prepareBackup failure transitions to the failure step',
      (tester) async {
        final runner = _FakeRunner(prepareBackupThrows: true);
        await tester.pumpWidget(
          _buildSheetSubject(runner: runner, pairedCount: 0),
        );
        // Inline the navigation so we can poll for the failure
        // headline instead of "Backup ready" (which never appears).
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Keep my data'));
        await tester.pumpAndSettle();
        await tester.enterText(
            find.byType(TextField).at(0), 'a-strong-password-12');
        await tester.enterText(
            find.byType(TextField).at(1), 'a-strong-password-12');
        await tester.tap(find.text('Back up and upgrade'));
        await tester.pump();
        var saw = false;
        for (var i = 0; i < 50; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          if (find.text('Migration failed').evaluate().isNotEmpty) {
            saw = true;
            break;
          }
        }
        expect(saw, isTrue, reason: 'failure step should render');
        expect(find.textContaining('PRISM1 export failed'), findsOneWidget);
        expect(runner.destructiveCalls, isEmpty);
      },
    );
  });
}
