import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/reset/full_reset_service.dart';
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
    testWidgets('renders the title and body copy', (tester) async {
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
        find.textContaining("Prism's encryption keys for this device"),
        findsOneWidget,
      );
    });

    testWidgets('renders primary, reset, and diagnostic actions', (
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

      expect(
        find.widgetWithText(
          PrismButton,
          'Restart and unlock once and try again',
        ),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(PrismButton, 'Reset local data'),
        findsOneWidget,
      );
      expect(find.text('Save diagnostic report'), findsOneWidget);
    });

    testWidgets('re-pair action is hidden when no sync hint exists', (
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

      expect(
        find.widgetWithText(PrismButton, 'Re-pair from another device'),
        findsNothing,
      );
    });

    testWidgets('re-pair action is shown when sync hint exists', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ResetRecoveryScreen(
            mode: ResetRecoveryScreenMode.keychainUnreadable,
            syncHistoryHintReader: () async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(PrismButton, 'Re-pair from another device'),
        findsOneWidget,
      );
    });

    testWidgets('re-pair action is shown when kPrismHadSyncSetup is set', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kPrismHadSyncSetup: true,
      });
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

    testWidgets('re-pair action is shown when any prism_sync.* pref exists', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'prism_sync.relay_hint': 'something',
      });
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

      await tester.tap(find.widgetWithText(PrismButton, 'Reset local data'));
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

      await tester.tap(find.text('Save diagnostic report'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not save or copy'), findsOneWidget);
    });

    testWidgets(
      'tapping "Restart and unlock once and try again" invokes the exit hook',
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
          find.widgetWithText(
            PrismButton,
            'Restart and unlock once and try again',
          ),
        );
        await tester.pumpAndSettle();

        expect(exitCalls, 1);
      },
    );
  });
}
