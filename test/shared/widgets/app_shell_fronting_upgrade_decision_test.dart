// WS1 step 4 (PR B): the app shell auto-surfaces the per-member fronting
// upgrade modal when the migration gate is not `complete`. The gate ↔
// modal mapping lives in the pure helper `frontingUpgradeSheetDecision`;
// the listener in `AppShell` is a thin adapter around it. These tests
// pin the helper rather than spinning up the full shell — same approach
// as the other `app_shell_*` tests.

import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/features/fronting/migration/fronting_migration_service.dart';
import 'package:prism_plurality/features/fronting/migration/providers/fronting_migration_providers.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';

void main() {
  group('frontingUpgradeSheetDecision', () {
    test('complete gate hides the modal regardless of raw mode', () {
      final decision = frontingUpgradeSheetDecision(
        gate: FrontingMigrationGateStatus.complete,
        rawMode: FrontingMigrationService.modeComplete,
      );
      expect(decision.shouldShow, isFalse);
    });

    test('blocked gate forces a non-dismissible modal', () {
      final decision = frontingUpgradeSheetDecision(
        gate: FrontingMigrationGateStatus.blocked,
        rawMode: FrontingMigrationService.modeBlocked,
      );
      expect(decision.shouldShow, isTrue);
      expect(decision.isDismissible, isFalse);
    });

    test('inProgress gate forces a non-dismissible modal', () {
      final decision = frontingUpgradeSheetDecision(
        gate: FrontingMigrationGateStatus.inProgress,
        rawMode: FrontingMigrationService.modeInProgress,
      );
      expect(decision.shouldShow, isTrue);
      expect(decision.isDismissible, isFalse);
    });

    test('needsModal + notStarted forces a non-dismissible modal', () {
      final decision = frontingUpgradeSheetDecision(
        gate: FrontingMigrationGateStatus.needsModal,
        rawMode: FrontingMigrationService.modeNotStarted,
      );
      expect(decision.shouldShow, isTrue);
      expect(decision.isDismissible, isFalse);
    });

    test('needsModal + crash-retry sentinel (upgradeAndKeep) forces a '
        'non-dismissible modal', () {
      final decision = frontingUpgradeSheetDecision(
        gate: FrontingMigrationGateStatus.needsModal,
        rawMode: FrontingMigrationService.modeUpgradeAndKeep,
      );
      expect(decision.shouldShow, isTrue);
      expect(decision.isDismissible, isFalse);
    });

    test('needsModal + crash-retry sentinel (startFresh) forces a '
        'non-dismissible modal', () {
      final decision = frontingUpgradeSheetDecision(
        gate: FrontingMigrationGateStatus.needsModal,
        rawMode: FrontingMigrationService.modeStartFresh,
      );
      expect(decision.shouldShow, isTrue);
      expect(decision.isDismissible, isFalse);
    });

    test('needsModal + legacy deferred mode forces the mandatory modal', () {
      final decision = frontingUpgradeSheetDecision(
        gate: FrontingMigrationGateStatus.needsModal,
        rawMode: FrontingMigrationService.modeDeferred,
      );
      expect(decision.shouldShow, isTrue);
      expect(decision.isDismissible, isFalse);
    });

    test('needsModal + null raw mode waits for the settings row', () {
      // The gate provider classifies stream loading/error as `needsModal`
      // to block writes while the DAO stream is resolving. The modal must
      // wait for a concrete raw mode so a normal `complete` install does not
      // flash the upgrade flow during a slow cold start.
      final decision = frontingUpgradeSheetDecision(
        gate: FrontingMigrationGateStatus.needsModal,
        rawMode: null,
      );
      expect(decision.shouldShow, isFalse);
      expect(decision.isDismissible, isFalse);
    });

    test('needsModal + complete raw mode waits for the refreshed gate', () {
      // Riverpod reloads can temporarily expose an AsyncLoading/AsyncError
      // gate while keeping the last concrete stream value. If that stale
      // value is `complete`, this is not a real migration prompt.
      final decision = frontingUpgradeSheetDecision(
        gate: FrontingMigrationGateStatus.needsModal,
        rawMode: FrontingMigrationService.modeComplete,
      );
      expect(decision.shouldShow, isFalse);
      expect(decision.isDismissible, isFalse);
    });
  });
}
