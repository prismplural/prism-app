import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart'
    show SyncHealthState;
import 'package:prism_plurality/features/fronting/migration/providers/fronting_migration_providers.dart'
    show FrontingMigrationGateStatus;
import 'package:prism_plurality/features/fronting/providers/fronting_session_repair_provider.dart';

void main() {
  // Gate predicate for the once-per-device open-session repair sweep. The key
  // regression: an UNPAIRED device must be allowed to repair (local-only), so a
  // standalone import that landed zombie opens self-heals instead of being
  // stuck "fronting" forever — the original gate required healthy and trapped
  // it.
  group('frontingRepairGateAllows', () {
    bool allows({
      bool autoConfigureInProgress = false,
      SyncHealthState health = SyncHealthState.healthy,
      bool hasHandle = true,
      FrontingMigrationGateStatus migrationGate =
          FrontingMigrationGateStatus.complete,
    }) => frontingRepairGateAllows(
      autoConfigureInProgress: autoConfigureInProgress,
      health: health,
      hasHandle: hasHandle,
      migrationGate: migrationGate,
    );

    test('unpaired device repairs local-only (no handle required)', () {
      expect(
        allows(health: SyncHealthState.unpaired, hasHandle: false),
        isTrue,
      );
    });

    test('healthy device with a handle repairs', () {
      expect(allows(health: SyncHealthState.healthy), isTrue);
    });

    test('reconnecting is treated like healthy', () {
      expect(allows(health: SyncHealthState.reconnecting), isTrue);
    });

    test('synced state without a handle waits', () {
      expect(allows(health: SyncHealthState.healthy, hasHandle: false), isFalse);
      expect(
        allows(health: SyncHealthState.reconnecting, hasHandle: false),
        isFalse,
      );
    });

    test('mid-recovery states block the run', () {
      for (final state in const [
        SyncHealthState.needsPassword,
        SyncHealthState.needsRewrap,
        SyncHealthState.disconnected,
        SyncHealthState.awaitingDeviceUnlock,
        SyncHealthState.runtimeDekRestoreDeferred,
      ]) {
        expect(allows(health: state), isFalse, reason: '$state must wait');
      }
    });

    test('an in-flight migration blocks even when sync is healthy', () {
      expect(
        allows(migrationGate: FrontingMigrationGateStatus.inProgress),
        isFalse,
      );
    });

    test('auto-config in progress blocks the run', () {
      expect(allows(autoConfigureInProgress: true), isFalse);
    });
  });
}
