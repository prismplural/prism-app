import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_runtime_state.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_group_repair_provider.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_group_repair_run_gate.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_group_repair_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePrismSyncHandle implements ffi.PrismSyncHandle {
  const _FakePrismSyncHandle();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CountingPkGroupRepairService extends PkGroupRepairService {
  _CountingPkGroupRepairService(this.db)
    : super(
        memberGroupsDao: db.memberGroupsDao,
        aliasesDao: db.pkGroupSyncAliasesDao,
        hasRepairToken: ({String? token}) async => false,
        fetchRepairReferenceData: ({String? token}) async =>
            throw UnimplementedError(),
      );

  final AppDatabase db;
  int runCalls = 0;

  @override
  Future<List<PkGroupReviewItem>> getPendingReviewItems() async => const [];

  @override
  Future<int> getPendingReviewCount() async => 0;

  @override
  Future<PkGroupRepairReport> run({
    String? token,
    bool allowStoredToken = true,
  }) async {
    runCalls += 1;
    return const PkGroupRepairReport(
      referenceMode: PkGroupRepairReferenceMode.none,
      backfilledEntries: 0,
      canonicalizedEntryIds: 0,
      revivedTombstonesDuringCanonicalization: 0,
      legacyEntriesSoftDeletedDuringCanonicalization: 0,
      duplicateSetsMerged: 0,
      duplicateGroupsSoftDeleted: 0,
      parentReferencesRehomed: 0,
      entriesRehomed: 0,
      entryConflictsSoftDeleted: 0,
      aliasesRecorded: 0,
      ambiguousGroupsSuppressed: 0,
      pendingReviewCount: 0,
    );
  }
}

ProviderContainer _createContainer(_CountingPkGroupRepairService service) {
  return ProviderContainer(
    overrides: [
      pkGroupRepairServiceProvider.overrideWithValue(service),
      prismSyncHandleProvider.overrideWithBuild(
        (ref, notifier) => const _FakePrismSyncHandle(),
      ),
    ],
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    syncAutoConfigureInProgress.value = false;
  });

  test(
    'automatic repair does not run while startup auto-config is still in progress',
    () async {
      syncAutoConfigureInProgress.value = true;

      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final service = _CountingPkGroupRepairService(db);
      final container = _createContainer(service);
      addTearDown(container.dispose);

      final bootstrap = container.listen(
        pkGroupRepairBootstrapProvider,
        (_, _) {},
      );
      addTearDown(bootstrap.close);

      await pumpEventQueue();

      expect(service.runCalls, 0);
      final state = await container.read(
        pkGroupRepairControllerProvider.future,
      );
      expect(state.automaticRunAttempted, isFalse);
    },
  );

  test(
    'the first stable healthy state after startup settles triggers automatic repair once',
    () async {
      syncAutoConfigureInProgress.value = true;

      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final service = _CountingPkGroupRepairService(db);
      final container = _createContainer(service);
      addTearDown(container.dispose);

      final bootstrap = container.listen(
        pkGroupRepairBootstrapProvider,
        (_, _) {},
      );
      addTearDown(bootstrap.close);

      await pumpEventQueue();
      expect(service.runCalls, 0);

      syncAutoConfigureInProgress.value = false;
      await pumpEventQueue();

      expect(service.runCalls, 1);
      expect(
        container
            .read(pkGroupRepairControllerProvider)
            .requireValue
            .automaticRunAttempted,
        isTrue,
      );
    },
  );

  test(
    'later healthy transitions do not rerun automatic repair after the first stable attempt',
    () async {
      syncAutoConfigureInProgress.value = false;

      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final service = _CountingPkGroupRepairService(db);
      final container = _createContainer(service);
      addTearDown(container.dispose);

      final bootstrap = container.listen(
        pkGroupRepairBootstrapProvider,
        (_, _) {},
      );
      addTearDown(bootstrap.close);

      await pumpEventQueue();
      expect(service.runCalls, 1);

      container
          .read(syncHealthProvider.notifier)
          .setState(SyncHealthState.disconnected);
      await pumpEventQueue();

      container
          .read(syncHealthProvider.notifier)
          .setState(SyncHealthState.healthy);
      await pumpEventQueue();

      expect(service.runCalls, 1);
      expect(
        container
            .read(pkGroupRepairControllerProvider)
            .requireValue
            .automaticRunAttempted,
        isTrue,
      );
    },
  );

  test(
    'stable healthy state skips automatic repair when persistent gate is clean',
    () async {
      SharedPreferences.setMockInitialValues({
        PkGroupRepairRunGate.checkedVersionKey:
            PkGroupRepairRunGate.currentVersion,
        PkGroupRepairRunGate.dirtyKey: false,
      });
      syncAutoConfigureInProgress.value = false;

      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final service = _CountingPkGroupRepairService(db);
      final container = _createContainer(service);
      addTearDown(container.dispose);

      final bootstrap = container.listen(
        pkGroupRepairBootstrapProvider,
        (_, _) {},
      );
      addTearDown(bootstrap.close);

      await pumpEventQueue();

      expect(service.runCalls, 0);
      expect(
        container
            .read(pkGroupRepairControllerProvider)
            .requireValue
            .automaticRunAttempted,
        isTrue,
      );
    },
  );

  test(
    'dirty persistent gate forces one automatic repair and clears dirty',
    () async {
      SharedPreferences.setMockInitialValues({
        PkGroupRepairRunGate.checkedVersionKey:
            PkGroupRepairRunGate.currentVersion,
        PkGroupRepairRunGate.dirtyKey: true,
      });
      syncAutoConfigureInProgress.value = false;

      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final service = _CountingPkGroupRepairService(db);
      final container = _createContainer(service);
      addTearDown(container.dispose);

      final bootstrap = container.listen(
        pkGroupRepairBootstrapProvider,
        (_, _) {},
      );
      addTearDown(bootstrap.close);

      await pumpEventQueue();

      expect(service.runCalls, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(PkGroupRepairRunGate.dirtyKey), isFalse);
      expect(
        prefs.getInt(PkGroupRepairRunGate.checkedVersionKey),
        PkGroupRepairRunGate.currentVersion,
      );
      expect(prefs.getString(PkGroupRepairRunGate.checkedAtKey), isNotNull);
    },
  );
}
