import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_outbox_drainer.dart';
import 'package:prism_plurality/core/sync/sync_quarantine.dart';
import 'package:prism_plurality/core/sync/sync_runtime_state.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/features/migration/services/migration_sync_repair_service.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'e2e_fixture.dart';

class SyntheticPluralKitClient implements PluralKitClient {
  SyntheticPluralKitClient({required this.members, required this.switches});
  final List<PKMember> members;
  List<PKSwitch> switches;
  PKSwitch? current;
  final List<List<String>> createdSwitchMembers = [];
  final List<String> calls = [];
  final List<String> deletedMembers = [];
  final List<String> deletedSwitches = [];

  @override
  String get currentToken => 'synthetic-token';
  @override
  Future<PKSystem> getSystem() async {
    calls.add('getSystem');
    return const PKSystem(id: 'sys01', name: 'Synthetic');
  }

  @override
  Future<List<PKMember>> getMembers() async {
    calls.add('getMembers');
    return members;
  }

  @override
  Future<PKMember> getMember(String ref) async =>
      members.firstWhere((m) => m.id == ref || m.uuid == ref);
  @override
  Future<List<PKGroup>> getGroups({bool withMembers = true}) async => const [];
  @override
  Future<List<String>> getGroupMembers(String ref) async => const [];
  @override
  Future<List<PKSwitch>> getSwitches({
    DateTime? before,
    int limit = 100,
  }) async {
    calls.add('getSwitches');
    final eligible = before == null
        ? switches
        : switches.where((s) => s.timestamp.isBefore(before)).toList();
    return (eligible.toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp)))
        .take(limit)
        .toList();
  }

  @override
  Future<PKSwitch> getSwitch(String ref) async =>
      switches.firstWhere((s) => s.id == ref);
  @override
  Future<PKSwitch?> getCurrentFronters() async {
    calls.add('getCurrentFronters');
    return current;
  }

  @override
  Future<PKMember> createMember(Map<String, dynamic> data) async =>
      throw UnimplementedError();
  @override
  Future<PKMember> updateMember(String id, Map<String, dynamic> data) async =>
      getMember(id);
  @override
  Future<void> deleteMember(String id) async => deletedMembers.add(id);
  @override
  Future<PKSwitch> createSwitch(
    List<String> memberIds, {
    DateTime? timestamp,
  }) async {
    createdSwitchMembers.add(List.of(memberIds));
    return PKSwitch(
      id: 'created-${createdSwitchMembers.length}',
      timestamp: timestamp ?? DateTime.now().toUtc(),
      members: memberIds,
    );
  }

  @override
  Future<PKSwitch> updateSwitch(
    String id, {
    required DateTime timestamp,
  }) async => throw UnimplementedError();
  @override
  Future<PKSwitch> updateSwitchMembers(
    String id,
    List<String> memberIds,
  ) async => throw UnimplementedError();
  @override
  Future<void> deleteSwitch(String id) async => deletedSwitches.add(id);
  @override
  Future<List<int>> downloadBytes(String url) async => const [];
  @override
  Future<void> addMembersToGroup(String groupRef, List<String> refs) async {}
  @override
  Future<void> removeMembersFromGroup(
    String groupRef,
    List<String> refs,
  ) async {}
  @override
  void dispose() {}
}

class PkServicePeer {
  PkServicePeer._(
    this.device,
    this.db,
    this.client,
    this.members,
    this.fronts,
    this.service,
    this.outbox,
    this.adapter,
    this.quarantine,
  );
  final E2EDevice device;
  final AppDatabase db;
  final SyntheticPluralKitClient client;
  final DriftMemberRepository members;
  final DriftFrontingSessionRepository fronts;
  final PluralKitSyncService service;
  final SyncOutboxDrainer outbox;
  final SyncAdapterWithCompletion adapter;
  final SyncQuarantineService quarantine;

  static Future<PkServicePeer> open(
    E2EDevice device,
    Directory dir,
    String name,
    SyntheticPluralKitClient client,
  ) async {
    final db = AppDatabase(NativeDatabase(File('${dir.path}/$name.sqlite')));
    final members = DriftMemberRepository(
      db.membersDao,
      device.handle,
      pkSyncDao: db.pluralKitSyncDao,
    );
    final fronts = DriftFrontingSessionRepository(
      db.frontingSessionsDao,
      device.handle,
      pkSyncDao: db.pluralKitSyncDao,
    );
    return PkServicePeer._(
      device,
      db,
      client,
      members,
      fronts,
      PluralKitSyncService(
        memberRepository: members,
        frontingSessionRepository: fronts,
        syncDao: db.pluralKitSyncDao,
        bus: PkSyncEventBus(),
        tokenOverride: 'synthetic-token',
        clientFactory: (_) => client,
      ),
      SyncOutboxDrainer(db),
      buildSyncAdapterWithCompletion(db),
      SyncQuarantineService(db.syncQuarantineDao),
    );
  }

  Future<void> activate() async {
    syncCredentialsPersisted.value = true;
    syncCurrentHandle.value = device.handle;
    SyncRecordMixin.debugInstallOutboxRuntimeForTesting(
      db: db,
      drainTrigger: (_) async {},
    );
  }

  Future<void> importAll() async {
    await activate();
    await service.performOneTimeFullImport(token: 'synthetic-token');
    await outbox.drain(device.handle);
  }

  Future<void> connectAndImport() async {
    await activate();
    await service.setToken('synthetic-token');
    await service.confirmDirection();
    await service.acknowledgeMapping();
    await service.performFullImport();
    await outbox.drain(device.handle);
  }

  Future<void> pollAndDrain() async {
    await activate();
    final outcome = await service.pollFrontersOnly();
    if (outcome != PkPollOutcome.ok) {
      throw StateError('PK poll did not run: $outcome');
    }
    await outbox.drain(device.handle);
  }

  Future<void> syncAndApply() async {
    await activate();
    final result = await device.sync();
    if (result['error'] != null && result['error'] != '') {
      throw StateError(jsonEncode(result));
    }
    await drainRemoteDeliveries(
      device.handle,
      db: db,
      syncAdapter: adapter,
      quarantine: quarantine,
    );
  }

  Future<List<dynamic>> liveMembers() => members.getAllMembers();
  Future<List<dynamic>> sessions() => fronts.getAllSessions();

  Future<List<Map<String, dynamic>>> runRepair() async {
    final emitted = <Map<String, dynamic>>[];
    await MigrationSyncRepairService(
      db: db,
      recordReconcile:
          ({required table, required entityId, required fields}) async {
            emitted.add({'table': table, 'entity': entityId, 'fields': fields});
            await ffi.recordReconcile(
              handle: device.handle,
              table: table,
              entityId: entityId,
              fieldsJson: jsonEncode(fields),
              divergentFreshHlc: true,
            );
          },
    ).drain();
    return emitted;
  }

  Future<void> close() => db.close();
}
