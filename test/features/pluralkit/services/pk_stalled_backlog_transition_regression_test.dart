/// Release qualification for the reported "remove all, then add all" PK front
/// burst. This uses the production PluralKitSyncService with real in-memory
/// Drift repositories and a credential-free recording client.
///
/// The first front projection is held in flight while a profile-only edit and a
/// trailing front trigger arrive, modeling work released together after a sync
/// notification stall. The PK front is already the same three-member set. The
/// only permitted external write is the member profile PATCH: no empty-front
/// POST, replacement POST, switch member PATCH, or DELETE may occur.
library;

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart'
    as domain_fs;
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

class _RecordingClient implements PluralKitClient {
  _RecordingClient({required this.current});

  PKSwitch current;
  Completer<void>? frontReadGate;
  int frontReads = 0;
  final List<Map<String, dynamic>> memberPatches = [];
  final List<List<String>> switchPosts = [];
  final List<({String id, List<String> members})> switchMemberPatches = [];
  final List<String> switchDeletes = [];

  @override
  String get currentToken => 'qualification-token';

  @override
  Future<PKSwitch?> getCurrentFronters() async {
    frontReads++;
    final gate = frontReadGate;
    if (gate != null && !gate.isCompleted) await gate.future;
    return current;
  }

  @override
  Future<PKMember> updateMember(String id, Map<String, dynamic> data) async {
    memberPatches.add(<String, dynamic>{'id': id, ...data});
    return PKMember(
      id: id,
      uuid: 'uuid-$id',
      name: data['name'] as String? ?? id,
    );
  }

  @override
  Future<PKSwitch> createSwitch(
    List<String> memberIds, {
    DateTime? timestamp,
  }) async {
    switchPosts.add(List<String>.from(memberIds));
    current = PKSwitch(
      id: 'replacement-${switchPosts.length}',
      timestamp: timestamp ?? DateTime.now().toUtc(),
      members: List<String>.from(memberIds),
    );
    return current;
  }

  @override
  Future<PKSwitch> updateSwitchMembers(
    String switchId,
    List<String> memberIds,
  ) async {
    switchMemberPatches.add((id: switchId, members: List.from(memberIds)));
    current = PKSwitch(
      id: switchId,
      timestamp: current.timestamp,
      members: List<String>.from(memberIds),
    );
    return current;
  }

  @override
  Future<void> deleteSwitch(String switchId) async {
    switchDeletes.add(switchId);
  }

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'Unused by PK stalled-backlog qualification: ${invocation.memberName}',
  );
}

domain.Member _member(String suffix) => domain.Member(
  id: 'local-$suffix',
  name: 'Member $suffix',
  emoji: '❔',
  isActive: true,
  createdAt: DateTime.utc(2026, 1, 1),
  pluralkitId: 'pk$suffix',
  pluralkitUuid: 'uuid-$suffix',
);

Future<PluralKitSyncService> _readyService({
  required AppDatabase db,
  required DriftMemberRepository members,
  required DriftFrontingSessionRepository fronts,
  required _RecordingClient client,
}) async {
  await db.pluralKitSyncDao.upsertSyncState(
    PluralKitSyncStateCompanion(
      id: const Value('pk_config'),
      isConnected: const Value(true),
      directionConfirmed: const Value(true),
      mappingAcknowledged: const Value(true),
      linkedAt: Value(DateTime.utc(2026, 1, 1)),
      fieldSyncConfig: Value(
        serializeFieldSyncConfig(
          const {},
          globalDirection: PkSyncDirection.bidirectional,
        ),
      ),
    ),
  );
  final service = PluralKitSyncService(
    memberRepository: members,
    frontingSessionRepository: fronts,
    syncDao: db.pluralKitSyncDao,
    bus: PkSyncEventBus(),
    tokenOverride: 'qualification-token',
    clientFactory: (_) => client,
  );
  await service.loadState();
  expect(service.state.canAutoSync, isTrue);
  return service;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'profile edit released with stalled front triggers emits no destructive PK transition',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final members = DriftMemberRepository(db.membersDao, null);
      final fronts = DriftFrontingSessionRepository(
        db.frontingSessionsDao,
        null,
        pkSyncDao: db.pluralKitSyncDao,
      );

      for (final suffix in const ['A', 'B', 'C']) {
        await members.createMember(_member(suffix));
        await fronts.createSession(
          domain_fs.FrontingSession(
            id: 'front-$suffix',
            startTime: DateTime.utc(2026, 1, 1, 10),
            memberId: 'local-$suffix',
            pluralkitUuid: 'current-switch',
          ),
        );
      }

      final client = _RecordingClient(
        current: PKSwitch(
          id: 'current-switch',
          timestamp: DateTime.utc(2026, 1, 1, 10),
          members: const ['pkA', 'pkB', 'pkC'],
        ),
      );
      final service = await _readyService(
        db: db,
        members: members,
        fronts: fronts,
        client: client,
      );

      // Establish the production order baseline with an already-converged set.
      await service.pushPendingSwitches();
      expect(client.switchPosts, isEmpty);
      expect(client.switchMemberPatches, isEmpty);

      // Hold the next front comparison in flight, like a backlog drain whose
      // trigger was delayed behind a silent notification connection.
      final gate = Completer<void>();
      client.frontReadGate = gate;
      final firstFrontTrigger = service.pushPendingSwitches();
      await Future<void>.delayed(Duration.zero);

      final changed = _member('B').copyWith(name: 'Member B updated');
      await members.updateMember(changed);
      final profilePush = service.pushMemberUpdate(changed);

      // A second front trigger arrives while the first is blocked. Production's
      // dirty-follow-up logic must coalesce it without manufacturing a switch.
      final trailingFrontTrigger = service.pushPendingSwitches();
      gate.complete();
      await Future.wait([firstFrontTrigger, trailingFrontTrigger, profilePush]);

      expect(client.memberPatches, hasLength(1));
      expect(client.memberPatches.single['id'], 'pkB');
      expect(client.memberPatches.single['name'], 'Member B updated');
      expect(
        client.switchPosts,
        isEmpty,
        reason: 'a profile-only change must not POST any new switch',
      );
      expect(
        client.switchMemberPatches,
        isEmpty,
        reason: 'profile-only changes must not PATCH switch membership/order',
      );
      expect(
        client.switchDeletes,
        isEmpty,
        reason: 'profile-only changes must never delete PK switches',
      );
      expect(
        (await fronts.getActiveSessions())
            .map((session) => session.memberId)
            .toSet(),
        {'local-A', 'local-B', 'local-C'},
      );
    },
  );
}
