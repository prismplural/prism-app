import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression guard for the Bug A pairing-apply deadlock fixed 2026-05-04.
///
/// `_frontingSessionsEntity`'s apply gate (in
/// `lib/core/sync/drift_sync_adapter.dart` via the `applyGate` closure built
/// in `lib/core/sync/prism_sync_providers.dart::driftSyncAdapterProvider`)
/// does a per-row `ref.read(frontingMigrationWritesBlockedProvider)` from
/// inside a `db.transaction(...)`. That read traverses
///   frontingMigrationWritesBlockedProvider
///   → frontingMigrationGateProvider
///   → frontingMigrationModeProvider  (StreamProvider over watchSettings)
/// If the chain is cold when the apply transaction reads it, the
/// StreamProvider's build callback fires `dao.watchSettings()` — a Drift
/// query — from inside the open transaction. On the production background-
/// isolate Drift setup that deadlocks the bg-isolate commit-result message
/// (verified Pixel 6 Pro fresh-install pairing).
///
/// The fix is an always-on `ref.listen(frontingMigrationModeProvider, …)`
/// in `lib/app.dart` so the chain is always warm before any sync apply
/// runs. The deadlock only reproduces on bg-isolate Drift, so a runtime
/// test against `NativeDatabase.memory()` would silently pass even if the
/// fix were reverted. This source-level test makes the invariant explicit.
///
/// If you remove the line, also update the apply-gate comment in
/// `prism_sync_providers.dart::driftSyncAdapterProvider`, and re-test
/// fresh-install pairing on a real device with Drift in a background
/// isolate.
void main() {
  test(
    'app.dart keeps frontingMigrationModeProvider always-warm '
    '(Bug A pairing-apply deadlock regression guard)',
    () {
      final appDart = File('lib/app.dart').readAsStringSync();
      expect(
        appDart,
        contains('ref.listen(frontingMigrationModeProvider'),
        reason:
            'lib/app.dart must keep frontingMigrationModeProvider warm via '
            'an always-on ref.listen at the top level of PrismApp.build. '
            'Without it, the sync apply path cold-starts a Drift '
            'StreamProvider from inside db.transaction() and deadlocks the '
            'commit on the background isolate during fresh-install pairing. '
            'See driftSyncAdapterProvider INVARIANT comment in '
            'lib/core/sync/prism_sync_providers.dart for the dependency '
            'chain and reproduction details.',
      );
    },
  );
}
