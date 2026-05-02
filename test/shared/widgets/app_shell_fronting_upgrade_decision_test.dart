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

    test('needsModal + null raw mode (loading/error) still shows the '
        'modal — fail-safe', () {
      // The gate provider classifies stream loading/error as `needsModal`,
      // and at the same instant `rawMode` may still be null. The decision
      // must err toward presenting the modal: we'd rather over-prompt than
      // skip the migration.
      final decision = frontingUpgradeSheetDecision(
        gate: FrontingMigrationGateStatus.needsModal,
        rawMode: null,
      );
      expect(decision.shouldShow, isTrue);
      expect(decision.isDismissible, isFalse);
    });
  });
}
