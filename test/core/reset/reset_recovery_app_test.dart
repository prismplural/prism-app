import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/reset/reset_recovery_app.dart';
import 'package:prism_plurality/core/services/secure_storage_diagnostic.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('restart-required recovery screen tells user to reopen Prism', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ResetRecoveryScreen(
          mode: ResetRecoveryScreenMode.restartRequired,
        ),
      ),
    );

    expect(find.text('Reset complete'), findsOneWidget);
    expect(
      find.text('Close Prism completely, then reopen it to start fresh.'),
      findsOneWidget,
    );

    final button = tester.widget<PrismButton>(
      find.widgetWithText(PrismButton, 'Close and reopen Prism'),
    );
    expect(button.enabled, isFalse);
  });

  group('keychainUnreadable mode', () {
    testWidgets('renders the title and one-line body copy', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ResetRecoveryScreen(
            mode: ResetRecoveryScreenMode.keychainUnreadable,
            syncHistoryHintReader: () async => false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Local data cannot be unlocked'), findsOneWidget);
      expect(
        find.textContaining("Prism can't read the encryption key"),
        findsOneWidget,
      );
    });

    testWidgets('leads with Reset, then Re-pair, then text-link actions', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ResetRecoveryScreen(
            mode: ResetRecoveryScreenMode.keychainUnreadable,
            syncHistoryHintReader: () async => false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The resolving action leads as the filled primary button.
      expect(
        find.widgetWithText(PrismButton, 'Reset local data and start fresh'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(PrismButton, 'Re-pair from another device'),
        findsOneWidget,
      );
      // The old no-op primary is now a demoted text link.
      expect(
        find.widgetWithText(TextButton, 'Try again after restarting'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(PrismButton, 'Try again after restarting'),
        findsNothing,
      );
      expect(find.text('Save diagnostic report'), findsOneWidget);
    });

    testWidgets('checklist shows data-present + key-unreadable from diagnostic', (
      tester,
    ) async {
      final diag = SecureStorageDiagnostic(
        recoveredVia: null,
        slotOutcomes: const <String, String>{
          DiagnosticSlotIds.appDbPrimary: 'cipher',
          DiagnosticSlotIds.appDbSync: 'missing',
        },
        appDbState: DbStartupStateName.unrecoverable,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ResetRecoveryScreen(
            mode: ResetRecoveryScreenMode.keychainUnreadable,
            diagnostic: diag,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Encrypted data is on this device, locked'),
        findsOneWidget,
      );
      expect(find.text('Encryption key can be read'), findsOneWidget);

      // Per-slot breakdown lives behind the Details expander.
      expect(find.text('app_db_primary: cipher'), findsNothing);
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(find.text('app_db_primary: cipher'), findsOneWidget);
      expect(find.text('app_db_sync: missing'), findsOneWidget);
    });

    testWidgets('checklist reports no data when only the fresh key write failed', (
      tester,
    ) async {
      final diag = SecureStorageDiagnostic(
        recoveredVia: null,
        slotOutcomes: const <String, String>{
          DiagnosticSlotIds.appDbFresh: 'threw: write-failed (unknown)',
        },
        appDbState: DbStartupStateName.unrecoverable,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ResetRecoveryScreen(
            mode: ResetRecoveryScreenMode.keychainUnreadable,
            diagnostic: diag,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('No saved data found on this device'),
        findsOneWidget,
      );
    });

    testWidgets('checklist reports unknown data state on a probe throw', (
      tester,
    ) async {
      // _safeProbeAppDb synthesises this when the probe throws: it stamps
      // appDbState=unrecoverable but only a generic 'probe' slot, so we can't
      // know whether a DB file exists. Don't assert one way or the other.
      final diag = SecureStorageDiagnostic(
        recoveredVia: null,
        slotOutcomes: const <String, String>{
          'probe': 'threw: Exception: boom',
        },
        appDbState: DbStartupStateName.unrecoverable,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ResetRecoveryScreen(
            mode: ResetRecoveryScreenMode.keychainUnreadable,
            diagnostic: diag,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text("Couldn't determine local data on this device"),
        findsOneWidget,
      );
      expect(
        find.text('Encrypted data is on this device, locked'),
        findsNothing,
      );
    });

    // Re-pair is offered unconditionally (no longer gated on a sync hint —
    // the old `syncHistoryHintReader` / `kPrismHadSyncSetup` signals were
    // never wired up). One test covers the actual behavior.
    testWidgets('re-pair action is always offered', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ResetRecoveryScreen(
            mode: ResetRecoveryScreenMode.keychainUnreadable,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(PrismButton, 'Re-pair from another device'),
        findsOneWidget,
      );
    });

    testWidgets(
      'key row stays ❌ even if recoveredVia leaked from the sync probe',
      (tester) async {
        // Regression: a healthy sync DB can leave `recoveredVia` non-null after
        // the diagnostic merge while the app DB key is genuinely gone. The key
        // row must reflect the app DB outcome, not the merged value — no green
        // check on the "cannot be unlocked" screen.
        final diag = SecureStorageDiagnostic(
          recoveredVia: 'sync',
          slotOutcomes: const <String, String>{
            DiagnosticSlotIds.appDbPrimary: 'cipher',
          },
          appDbState: DbStartupStateName.unrecoverable,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: ResetRecoveryScreen(
              mode: ResetRecoveryScreenMode.keychainUnreadable,
              diagnostic: diag,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // No success check anywhere in the collapsed checklist (the only
        // 'ok'-able row is the key row, and it must be ❌ here).
        expect(find.byIcon(Icons.check_circle), findsNothing);
        expect(find.byIcon(Icons.cancel), findsWidgets);
      },
    );

    testWidgets('tapping "Reset local data" surfaces a confirmation dialog', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ResetRecoveryScreen(
            mode: ResetRecoveryScreenMode.keychainUnreadable,
            syncHistoryHintReader: () async => false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(PrismButton, 'Reset local data and start fresh'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reset local data?'), findsOneWidget);
      expect(
        find.text(
          'This will erase all local Prism data on this device. Continue?',
        ),
        findsOneWidget,
      );
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Erase'), findsOneWidget);

      // Cancel keeps us on the recovery screen — no wipe attempt.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Local data cannot be unlocked'), findsOneWidget);
    });

    testWidgets('tapping "Save diagnostic report" invokes the share handler', (
      tester,
    ) async {
      String? capturedPayload;
      final diag = SecureStorageDiagnostic(
        recoveredVia: null,
        slotOutcomes: const <String, String>{
          DiagnosticSlotIds.appDbPrimary: 'cipher',
        },
        appDbState: DbStartupStateName.unrecoverable,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ResetRecoveryScreen(
            mode: ResetRecoveryScreenMode.keychainUnreadable,
            syncHistoryHintReader: () async => false,
            diagnostic: diag,
            shareDiagnostic: (payload) async {
              capturedPayload = payload;
              return DiagnosticReportShareResult.shared;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Save diagnostic report'));
      await tester.tap(find.text('Save diagnostic report'));
      await tester.pumpAndSettle();

      expect(capturedPayload, isNotNull);
      // §10 — JSON shape uses snake_case for readability.
      expect(capturedPayload, contains('"slot_outcomes"'));
      expect(capturedPayload, contains('"app_db_primary": "cipher"'));
      expect(capturedPayload, contains('"app_db_state": "unrecoverable"'));
      expect(capturedPayload, contains('"prism_diagnostic_version": 1'));
      expect(find.textContaining('Diagnostic report saved'), findsOneWidget);
    });

    testWidgets(
      'Save diagnostic report falls back to bootSecureStorageDiagnosticProvider',
      (tester) async {
        String? capturedPayload;
        final providerDiag = SecureStorageDiagnostic(
          recoveredVia: 'sync',
          slotOutcomes: const <String, String>{
            DiagnosticSlotIds.appDbPrimary: 'cipher',
            DiagnosticSlotIds.appDbSync: 'ok',
          },
          appDbState: DbStartupStateName.ready,
          keychainRepairPendingBeforeBoot: false,
          keychainRepairWritebackAttemptedThisBoot: true,
          keychainRepairWritebackResult: KeychainRepairWritebackResult.ok,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              bootSecureStorageDiagnosticProvider.overrideWithValue(
                providerDiag,
              ),
            ],
            child: MaterialApp(
              home: ResetRecoveryScreen(
                mode: ResetRecoveryScreenMode.keychainUnreadable,
                syncHistoryHintReader: () async => false,
                // Intentionally omit `diagnostic:` so the screen falls
                // back to the provider.
                shareDiagnostic: (payload) async {
                  capturedPayload = payload;
                  return DiagnosticReportShareResult.shared;
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Save diagnostic report'));
        await tester.tap(find.text('Save diagnostic report'));
        await tester.pumpAndSettle();

        expect(capturedPayload, isNotNull);
        expect(capturedPayload, contains('"recovered_via": "sync"'));
        expect(capturedPayload, contains('"app_db_sync": "ok"'));
        expect(
          capturedPayload,
          contains('"keychain_repair_writeback_result": "ok"'),
        );
      },
    );

    testWidgets('Save diagnostic report reports clipboard fallback', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ResetRecoveryScreen(
            mode: ResetRecoveryScreenMode.keychainUnreadable,
            syncHistoryHintReader: () async => false,
            shareDiagnostic: (_) async => DiagnosticReportShareResult.copied,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Save diagnostic report'));
      await tester.tap(find.text('Save diagnostic report'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Diagnostic report copied'), findsOneWidget);
    });

    testWidgets('Save diagnostic report reports total handoff failure', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ResetRecoveryScreen(
            mode: ResetRecoveryScreenMode.keychainUnreadable,
            syncHistoryHintReader: () async => false,
            shareDiagnostic: (_) async => DiagnosticReportShareResult.failed,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Save diagnostic report'));
      await tester.tap(find.text('Save diagnostic report'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not save or copy'), findsOneWidget);
    });

    testWidgets(
      'tapping "Try again after restarting" invokes the exit hook',
      (tester) async {
        var exitCalls = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: ResetRecoveryScreen(
              mode: ResetRecoveryScreenMode.keychainUnreadable,
              syncHistoryHintReader: () async => false,
              appExit: () async {
                exitCalls += 1;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.widgetWithText(TextButton, 'Try again after restarting'),
        );
        await tester.pumpAndSettle();

        expect(exitCalls, 1);
      },
    );
  });
}
