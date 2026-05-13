/// Task 1 — Precondition regression test.
///
/// Asserts: when [PluralKitSyncService.importSwitchesAfterLink] runs an
/// initial pull where PK's current switch contains members [B] only, and
/// the local Prism DB already has two open fronting sessions (A and B,
/// both mapped to PK UUIDs), A's session is NOT ended after the pull.
///
/// This validates the spec's assumption that a pull-only sync preserves
/// Prism-only sessions (sessions whose [pluralkitUuid] is null or not a
/// PK switch UUID). If this test fails the "Co-front" pull-only option
/// described in the spec must be dropped from Task 14.
library;

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart' as domain;
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';

// ---------------------------------------------------------------------------
// Secure-storage mock (same pattern as other PK service tests)
// ---------------------------------------------------------------------------

class _SecureStorageStub {
  final Map<String, String?> _store = {};

  void setup() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async {
            switch (call.method) {
              case 'write':
                _store[call.arguments['key'] as String] =
                    call.arguments['value'] as String?;
                return null;
              case 'read':
                return _store[call.arguments['key'] as String];
              case 'delete':
                _store.remove(call.arguments['key'] as String);
                return null;
              case 'containsKey':
                return _store.containsKey(call.arguments['key'] as String);
              default:
                return null;
            }
          },
        );
  }

  void teardown() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
    _store.clear();
  }
}

// ---------------------------------------------------------------------------
// Fake PluralKitClient — returns a single switch page containing only [B]
// ---------------------------------------------------------------------------

class _FakeClient implements PluralKitClient {
  final List<List<PKSwitch>> switchPages;

  _FakeClient(this.switchPages);

  @override
  String get currentToken => 'fake-token';

  @override
  Future<PKSystem> getSystem() async =>
      const PKSystem(id: 'sys-test', name: 'Test System');

  @override
  Future<List<PKMember>> getMembers() async => const [];

  @override
  Future<PKMember> getMember(String memberRef) => throw UnimplementedError();

  @override
  Future<List<PKSwitch>> getSwitches({
    DateTime? before,
    int limit = 100,
  }) async {
    if (switchPages.isEmpty) return const [];
    return switchPages.removeAt(0);
  }

  @override
  Future<List<PKGroup>> getGroups({bool withMembers = true}) async => const [];

  @override
  Future<List<String>> getGroupMembers(String groupRef) async => const [];

  @override
  Future<void> addMembersToGroup(
    String groupRef,
    List<String> memberRefs,
  ) async => throw UnimplementedError();

  @override
  Future<void> removeMembersFromGroup(
    String groupRef,
    List<String> memberRefs,
  ) async => throw UnimplementedError();

  @override
  Future<PKMember> createMember(Map<String, dynamic> data) =>
      throw UnimplementedError();

  @override
  Future<PKMember> updateMember(String id, Map<String, dynamic> data) =>
      throw UnimplementedError();

  @override
  Future<PKSwitch> createSwitch(
    List<String> memberIds, {
    DateTime? timestamp,
  }) => throw UnimplementedError();

  @override
  Future<PKSwitch> updateSwitch(
    String switchId, {
    required DateTime timestamp,
  }) => throw UnimplementedError();

  @override
  Future<PKSwitch> updateSwitchMembers(
    String switchId,
    List<String> memberIds,
  ) => throw UnimplementedError();

  @override
  Future<void> deleteSwitch(String switchId) => throw UnimplementedError();

  @override
  Future<void> deleteMember(String id) => throw UnimplementedError();

  @override
  Future<List<int>> downloadBytes(String url) async => const [];

  @override
  Future<PKSwitch?> getCurrentFronters() async => null;

  @override
  void dispose() {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

domain.Member _member({
  required String localId,
  required String pkShortId,
  required String pkUuid,
  String name = 'Member',
}) => domain.Member(
  id: localId,
  name: name,
  emoji: '❔',
  isActive: true,
  createdAt: DateTime(2026, 1, 1),
  pluralkitId: pkShortId,
  pluralkitUuid: pkUuid,
);

PluralKitSyncService _makeService({
  required AppDatabase db,
  required _FakeClient client,
  DriftMemberRepository? memberRepo,
  DriftFrontingSessionRepository? sessionRepo,
}) {
  memberRepo ??= DriftMemberRepository(db.membersDao, null);
  sessionRepo ??= DriftFrontingSessionRepository(db.frontingSessionsDao, null);
  return PluralKitSyncService(
    memberRepository: memberRepo,
    frontingSessionRepository: sessionRepo,
    syncDao: db.pluralKitSyncDao,
    bus: PkSyncEventBus(),
    secureStorage: const FlutterSecureStorage(),
    clientFactory: (_) => client,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storageStub = _SecureStorageStub();

  setUp(storageStub.setup);
  tearDown(storageStub.teardown);

  test(
    'initial pull with PK switch [B-only] does not end local-only session for A',
    () async {
      // Scenario:
      //   - Members A and B are both mapped (have pluralkitId + pluralkitUuid).
      //   - Before the PK link, Prism already has two open local fronting
      //     sessions: one for A and one for B. Both are "local-only" (no
      //     pluralkitUuid on the session row — they were created in Prism,
      //     not imported from PK).
      //   - The PK switch history has exactly one switch containing [B] only.
      //   - After importSwitchesAfterLink:
      //       * A's local session must still be open (endTime == null).
      //       * B's local session must still be open (the diff sweep does not
      //         end non-PK sessions; it creates a new PK-linked session for B).
      //       * A new PK-linked session for B is created (endTime == null,
      //         pluralkitUuid == switch UUID pattern).

      final db = _makeDb();
      addTearDown(db.close);

      // Seed members A and B — both mapped to PK.
      final memberRepo = DriftMemberRepository(db.membersDao, null);
      await memberRepo.createMember(
        _member(
          localId: 'local-a',
          pkShortId: 'pkA',
          pkUuid: '00000000-0000-0000-0000-000000000aaa',
          name: 'Alice',
        ),
      );
      await memberRepo.createMember(
        _member(
          localId: 'local-b',
          pkShortId: 'pkB',
          pkUuid: '00000000-0000-0000-0000-000000000bbb',
          name: 'Bea',
        ),
      );

      // Seed two open local fronting sessions (no pluralkitUuid → local-only).
      final sessionRepo = DriftFrontingSessionRepository(
        db.frontingSessionsDao,
        null,
      );
      const sessionAId = 'local-session-a';
      const sessionBId = 'local-session-b';
      final sessionStart = DateTime.utc(2026, 1, 1, 8, 0);

      await sessionRepo.createSession(
        domain.FrontingSession(
          id: sessionAId,
          startTime: sessionStart,
          memberId: 'local-a',
          // pluralkitUuid is null — this is a local-only session.
        ),
      );
      await sessionRepo.createSession(
        domain.FrontingSession(
          id: sessionBId,
          startTime: sessionStart,
          memberId: 'local-b',
          // pluralkitUuid is null — local-only.
        ),
      );

      // PK has one switch: only [B] is fronting, starting at 10:00.
      final pkSwitch = PKSwitch(
        id: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        timestamp: DateTime.utc(2026, 1, 1, 10, 0),
        members: const ['pkB'],
      );

      // The fake client returns one page then terminates pagination.
      final client = _FakeClient([
        [pkSwitch], // newest-first (only one page)
        [], // end of pagination
      ]);

      final service = _makeService(
        db: db,
        client: client,
        memberRepo: memberRepo,
        sessionRepo: sessionRepo,
      );

      // Connect and acknowledge mapping (mirrors the production setup path).
      await service.setToken('fake-pk-token');
      await service.acknowledgeMapping();

      // Run the initial pull.
      await service.importSwitchesAfterLink();

      // ---------- Assertions ----------

      final allSessions = await sessionRepo.getAllSessions();

      // Find each session by ID.
      final sessionA = allSessions.firstWhere((s) => s.id == sessionAId);
      final sessionB = allSessions.firstWhere((s) => s.id == sessionBId);

      // A's local-only session must NOT have been ended by the diff sweep.
      expect(
        sessionA.endTime,
        isNull,
        reason: 'The diff sweep must not end A\'s local-only session even '
            'though A is absent from PK\'s current switch. If this fails, '
            'drop the pull-only "Co-front" option from Task 14.',
      );

      // B's local-only session must also be untouched (the sweep creates a
      // new PK-linked row for B; it does not close the unlinked one).
      expect(
        sessionB.endTime,
        isNull,
        reason: 'B\'s local-only session must remain open after the pull.',
      );

      // The diff sweep should have created exactly one new PK-linked session
      // for B (the PK switch entry). Verify at least one open B session now
      // has a pluralkitUuid matching a UUID pattern (the switch id).
      final pkLinkedBSessions = allSessions.where(
        (s) =>
            s.memberId == 'local-b' &&
            s.pluralkitUuid == pkSwitch.id &&
            s.endTime == null,
      );
      expect(
        pkLinkedBSessions,
        isNotEmpty,
        reason: 'importSwitchesAfterLink must create a PK-linked open session '
            'for B corresponding to the current PK switch.',
      );

      // A should have no PK-linked sessions (it wasn't in the switch).
      final pkLinkedASessions = allSessions.where(
        (s) =>
            s.memberId == 'local-a' &&
            s.pluralkitUuid != null,
      );
      expect(
        pkLinkedASessions,
        isEmpty,
        reason: 'No PK-linked session should be created for A since A was '
            'not in the PK switch.',
      );
    },
  );
}
