import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_avatar_cache_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_bidirectional_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_push_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class Call {
  final String method;
  final List<dynamic> args;
  Call(this.method, this.args);
}

class FakePluralKitClient implements PluralKitClient {
  @override
  Future<PKSwitch> getSwitch(String switchRef) =>
      throw UnimplementedError();
  final List<Call> calls = [];
  int _idCounter = 0;
  // When set, createMember throws this instead of returning — simulates a POST
  // failure (transport error, validation rejection, …).
  Object? createError;

  @override
  String get currentToken => 'fake-token';

  @override
  Future<PKMember> createMember(Map<String, dynamic> data) async {
    calls.add(Call('createMember', [data]));
    if (createError != null) throw createError!;
    _idCounter++;
    final id = 'pk${_idCounter.toString().padLeft(3, '0')}';
    return PKMember(
      id: id,
      uuid: 'uuid-$id',
      name: data['name'] as String? ?? '',
    );
  }

  @override
  Future<PKMember> updateMember(String id, Map<String, dynamic> data) async {
    calls.add(Call('updateMember', [id, data]));
    return PKMember(
      id: id,
      uuid: 'uuid-$id',
      name: data['name'] as String? ?? '',
    );
  }

  @override
  Future<PKSwitch> createSwitch(
    List<String> memberIds, {
    DateTime? timestamp,
  }) async {
    calls.add(Call('createSwitch', [memberIds]));
    return PKSwitch(
      id: 'sw-1',
      timestamp: timestamp ?? DateTime.now(),
      members: memberIds,
    );
  }

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
  Future<PKSystem> getSystem() => throw UnimplementedError();
  @override
  Future<List<PKMember>> getMembers() => throw UnimplementedError();
  @override
  Future<PKMember> getMember(String memberRef) => throw UnimplementedError();
  @override
  Future<List<PKSwitch>> getSwitches({DateTime? before, int limit = 100}) =>
      throw UnimplementedError();
  @override
  Future<void> deleteMember(String id) => throw UnimplementedError();
  @override
  Future<List<int>> downloadBytes(String url) => throw UnimplementedError();
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
  Future<PKSwitch?> getCurrentFronters() => throw UnimplementedError();
  @override
  void dispose() {}
}

class FakeMemberRepository implements MemberRepository {
  final List<Call> calls = [];
  final Map<String, domain.Member> _members = {};

  @override
  Future<void> updateMember(domain.Member member) async {
    calls.add(Call('updateMember', [member]));
    _members[member.id] = member;
  }

  @override
  Future<int> updateMemberFields(
    String id,
    Map<String, dynamic> changedFields,
  ) async {
    calls.add(Call('updateMemberFields', [id, changedFields]));
    return 0;
  }

  @override
  Future<int> applyPluralKitLink(String id, Map<String, dynamic> patch) async {
    calls.add(Call('applyPluralKitLink', [id, patch]));
    final existing = _members[id];
    if (existing == null) return 0;
    _members[id] = existing.copyWith(
      pluralkitUuid: patch.containsKey('pluralkit_uuid')
          ? patch['pluralkit_uuid'] as String?
          : existing.pluralkitUuid,
      pluralkitId: patch.containsKey('pluralkit_id')
          ? patch['pluralkit_id'] as String?
          : existing.pluralkitId,
      pluralkitDisplayName: patch.containsKey('pluralkit_display_name')
          ? patch['pluralkit_display_name'] as String?
          : existing.pluralkitDisplayName,
      pluralkitSyncIgnored: false,
    );
    return 1;
  }

  @override
  Future<int> recordPluralKitIdentity(
    String id,
    Map<String, dynamic> patch,
  ) async {
    calls.add(Call('recordPluralKitIdentity', [id, patch]));
    final existing = _members[id];
    if (existing == null) return 0;
    _members[id] = existing.copyWith(
      pluralkitUuid: patch.containsKey('pluralkit_uuid')
          ? patch['pluralkit_uuid'] as String?
          : existing.pluralkitUuid,
      pluralkitId: patch.containsKey('pluralkit_id')
          ? patch['pluralkit_id'] as String?
          : existing.pluralkitId,
      pluralkitDisplayName: patch.containsKey('pluralkit_display_name')
          ? patch['pluralkit_display_name'] as String?
          : existing.pluralkitDisplayName,
    );
    return 1;
  }

  @override
  Future<int> excludePluralKitSync(String id) async {
    calls.add(Call('excludePluralKitSync', [id]));
    final existing = _members[id];
    if (existing == null) return 0;
    _members[id] = existing.copyWith(pluralkitSyncIgnored: true);
    return 1;
  }

  @override
  Future<int> resumePluralKitSync(String id) async {
    calls.add(Call('resumePluralKitSync', [id]));
    final existing = _members[id];
    if (existing == null) return 0;
    _members[id] = existing.copyWith(pluralkitSyncIgnored: false);
    return 1;
  }

  @override
  Future<List<domain.Member>> getAllMembers() async => _members.values.toList();

  @override
  Future<List<domain.Member>> getAllMembersIncludingDeleted() async =>
      _members.values.toList();
  @override
  Stream<List<domain.Member>> watchAllMembers() => throw UnimplementedError();
  @override
  Stream<List<domain.Member>> watchActiveMembers() =>
      throw UnimplementedError();
  @override
  Future<domain.Member?> getMemberById(String id) async => _members[id];
  @override
  Stream<domain.Member?> watchMemberById(String id) =>
      throw UnimplementedError();
  @override
  Future<void> createMember(domain.Member member) async {
    _members[member.id] = member;
  }

  @override
  Future<void> deleteMember(String id) async {
    _members.remove(id);
  }

  @override
  Future<List<domain.Member>> getMembersByIds(List<String> ids) async =>
      ids.map((id) => _members[id]).whereType<domain.Member>().toList();
  @override
  Stream<List<domain.Member>> watchMembersByIds(List<String> ids) =>
      throw UnimplementedError();
  @override
  Future<int> getCount() async => _members.length;

  @override
  Future<List<domain.Member>> getDeletedLinkedMembers() async => _members.values
      .where((m) => m.isDeleted && (m.pluralkitUuid ?? '').trim().isNotEmpty)
      .toList();
  @override
  Future<void> clearPluralKitLink(String id) async {}
  @override
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) async {}

  @override
  Future<void> stampCreatePushStartedAt(String id, int timestampMs) async {
    calls.add(Call('stampCreatePushStartedAt', [id, timestampMs]));
    final existing = _members[id];
    if (existing != null) {
      _members[id] = existing.copyWith(createPushStartedAt: timestampMs);
    }
  }

  @override
  Future<void> clearCreatePushStartedAt(String id) async {
    calls.add(Call('clearCreatePushStartedAt', [id]));
    final existing = _members[id];
    if (existing != null) {
      _members[id] = existing.copyWith(createPushStartedAt: null);
    }
  }

  @override
  Future<({domain.Member member, bool wasCreated})>
  ensureUnknownSentinelMember() => throw UnimplementedError();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

domain.Member _localMember({
  String id = 'local-1',
  String name = 'Alice',
  String? pronouns,
  String? bio,
  String? pluralkitId,
  String? pluralkitUuid,
  String? customColorHex,
  bool customColorEnabled = false,
  String? displayName,
  String? pluralkitDisplayName,
  String? birthday,
  String? proxyTagsJson,
  Uint8List? avatarImageData,
  String? pkAvatarCachedUrl,
  bool pluralkitSyncIgnored = false,
}) {
  return domain.Member(
    id: id,
    name: name,
    pronouns: pronouns,
    bio: bio,
    pluralkitId: pluralkitId,
    pluralkitUuid: pluralkitUuid,
    customColorHex: customColorHex,
    customColorEnabled: customColorEnabled,
    displayName: displayName,
    pluralkitDisplayName: pluralkitDisplayName,
    birthday: birthday,
    proxyTagsJson: proxyTagsJson,
    avatarImageData: avatarImageData,
    pkAvatarCachedUrl: pkAvatarCachedUrl,
    pluralkitSyncIgnored: pluralkitSyncIgnored,
    createdAt: DateTime(2026, 1, 1),
  );
}

PKMember _pkMember({
  String id = 'pk001',
  String uuid = 'uuid-pk001',
  String name = 'Alice',
  String? displayName,
  String? pronouns,
  String? description,
  String? color,
  String? birthday,
  String? proxyTagsJson,
  String? avatarUrl,
}) {
  return PKMember(
    id: id,
    uuid: uuid,
    name: name,
    displayName: displayName,
    pronouns: pronouns,
    description: description,
    color: color,
    birthday: birthday,
    proxyTagsJson: proxyTagsJson,
    avatarUrl: avatarUrl,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late FakePluralKitClient fakeClient;
  late FakeMemberRepository fakeRepo;
  late PkBidirectionalService service;

  setUp(() {
    fakeClient = FakePluralKitClient();
    fakeRepo = FakeMemberRepository();
    service = PkBidirectionalService(pushService: const PkPushService());
  });

  group('pullOnly direction', () {
    test('only counts pulls, does not push', () async {
      // A PK member with no local counterpart
      final pkMembers = [
        _pkMember(id: 'pk001', uuid: 'uuid-pk001', name: 'Remote'),
      ];

      final summary = await service.syncMembers(
        localMembers: [],
        pkMembers: pkMembers,
        fieldConfigs: {},
        direction: PkSyncDirection.pullOnly,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );

      expect(summary.membersPulled, 1);
      expect(summary.membersPushed, 0);
      // No create/update calls should have been made to PK
      expect(fakeClient.calls, isEmpty);
    });

    test('does not push unmatched local members', () async {
      final localMembers = [_localMember(id: 'local-1', name: 'OnlyLocal')];

      final summary = await service.syncMembers(
        localMembers: localMembers,
        pkMembers: [],
        fieldConfigs: {},
        direction: PkSyncDirection.pullOnly,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );

      expect(summary.membersPushed, 0);
      expect(fakeClient.calls, isEmpty);
    });
  });

  group('pushOnly direction', () {
    test('only pushes, does not pull', () async {
      // A PK member with no local match — should be skipped (not pulled)
      final pkMembers = [
        _pkMember(id: 'pk001', uuid: 'uuid-pk001', name: 'Remote'),
      ];

      final summary = await service.syncMembers(
        localMembers: [],
        pkMembers: pkMembers,
        fieldConfigs: {},
        direction: PkSyncDirection.pushOnly,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );

      expect(summary.membersPulled, 0);
      expect(summary.membersSkipped, 1);
    });

    test('new local member pushed and PK identifiers stored', () async {
      final localMembers = [_localMember(id: 'local-1', name: 'NewMember')];

      final summary = await service.syncMembers(
        localMembers: localMembers,
        pkMembers: [],
        fieldConfigs: {},
        direction: PkSyncDirection.pushOnly,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );

      expect(summary.membersPushed, 1);
      // Should have called createMember on the PK client
      expect(fakeClient.calls.any((c) => c.method == 'createMember'), isTrue);
      // PR 2: push-unlinked-locals routes through applyPluralKitLink (Part 1.7
      // site 5). The PK identifiers land on the local row via that method.
      final applyCall = fakeRepo.calls.firstWhere(
        (c) => c.method == 'applyPluralKitLink',
        orElse: () => throw StateError(
          'expected applyPluralKitLink call, got: '
          '${fakeRepo.calls.map((c) => c.method).toList()}',
        ),
      );
      final patch = applyCall.args[1] as Map<String, dynamic>;
      expect(patch['pluralkit_id'], 'pk001');
      expect(patch['pluralkit_uuid'], 'uuid-pk001');
    });
  });

  group('F4/F5 create-push lease', () {
    domain.Member leaseMember(String id, String name, int? leaseMs) =>
        domain.Member(
          id: id,
          name: name,
          createdAt: DateTime(2026, 1, 1),
          createPushStartedAt: leaseMs,
        );

    test('F4: a FRESH create lease defers the push (no duplicate POST)',
        () async {
      final fresh = DateTime.now().millisecondsSinceEpoch;
      final summary = await service.syncMembers(
        localMembers: [leaseMember('local-1', 'Pending', fresh)],
        pkMembers: [],
        fieldConfigs: {},
        direction: PkSyncDirection.pushOnly,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );
      expect(
        fakeClient.calls.where((c) => c.method == 'createMember'),
        isEmpty,
        reason: 'a fresh lease means another device is mid-POST — do not POST',
      );
      expect(
        fakeRepo.calls.where((c) => c.method == 'stampCreatePushStartedAt'),
        isEmpty,
      );
      expect(summary.membersPushed, 0);
      expect(summary.membersSkipped, 1);
    });

    test('F4: stamps the lease before POST and clears it after link-back',
        () async {
      final summary = await service.syncMembers(
        localMembers: [_localMember(id: 'local-1', name: 'NewMember')],
        pkMembers: [],
        fieldConfigs: {},
        direction: PkSyncDirection.pushOnly,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );
      expect(summary.membersPushed, 1);
      final methods = fakeRepo.calls.map((c) => c.method).toList();
      final stampIdx = methods.indexOf('stampCreatePushStartedAt');
      final clearIdx = methods.indexOf('clearCreatePushStartedAt');
      expect(stampIdx, greaterThanOrEqualTo(0),
          reason: 'the lease must be stamped before the POST');
      expect(clearIdx, greaterThan(stampIdx),
          reason: 'the lease must be cleared after the link-back');
      expect(fakeClient.calls.any((c) => c.method == 'createMember'), isTrue);
    });

    test('F5: a STALE lease adopts a matching orphaned PK member instead of '
        're-POSTing', () async {
      final stale = DateTime.now()
          .subtract(const Duration(minutes: 20))
          .millisecondsSinceEpoch;
      final summary = await service.syncMembers(
        localMembers: [leaseMember('local-1', 'Orphaned', stale)],
        pkMembers: [_pkMember(id: 'po1', uuid: 'uuid-orphan', name: 'Orphaned')],
        fieldConfigs: {},
        direction: PkSyncDirection.pushOnly,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );
      expect(
        fakeClient.calls.where((c) => c.method == 'createMember'),
        isEmpty,
        reason: 'the orphan from a prior interrupted push is adopted, not '
            're-created',
      );
      final applyCall = fakeRepo.calls.firstWhere(
        (c) => c.method == 'applyPluralKitLink',
        orElse: () => throw StateError('expected an adoption link'),
      );
      expect((applyCall.args[1] as Map)['pluralkit_uuid'], 'uuid-orphan');
      expect(
        fakeRepo.calls.any((c) => c.method == 'clearCreatePushStartedAt'),
        isTrue,
      );
      expect(summary.membersPushed, 1);
    });

    test('F5: a STALE lease with NO matching orphan re-POSTs (re-stamps)',
        () async {
      final stale = DateTime.now()
          .subtract(const Duration(minutes: 20))
          .millisecondsSinceEpoch;
      final summary = await service.syncMembers(
        localMembers: [leaseMember('local-1', 'Lonely', stale)],
        pkMembers: [],
        fieldConfigs: {},
        direction: PkSyncDirection.pushOnly,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );
      expect(fakeClient.calls.any((c) => c.method == 'createMember'), isTrue,
          reason: 'no orphan to adopt — a stale lease re-POSTs');
      expect(
        fakeRepo.calls.any((c) => c.method == 'stampCreatePushStartedAt'),
        isTrue,
      );
      expect(summary.membersPushed, 1);
    });

    test('F5 safety: a FAILED POST releases the lease (no phantom orphan to '
        'adopt later)', () async {
      // The POST never reaches PK and mints no member; leaving the lease set
      // would falsely authorize adopting an unrelated same-named PK member.
      fakeClient.createError = Exception('simulated transport failure');
      final local = _localMember(id: 'local-1', name: 'Pending');
      await fakeRepo.createMember(local);

      await service.syncMembers(
        localMembers: [local],
        pkMembers: [],
        fieldConfigs: {},
        direction: PkSyncDirection.pushOnly,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );

      expect(fakeClient.calls.any((c) => c.method == 'createMember'), isTrue,
          reason: 'the POST was attempted and threw');
      final after = await fakeRepo.getMemberById('local-1');
      expect(after!.createPushStartedAt, isNull,
          reason: 'a failed POST must release the lease, not leave it set');
      expect(after.pluralkitUuid, isNull, reason: 'the member stays unlinked');
    });

    test('F5 safety: adoption does not steal a soft-deleted same-named '
        'member\'s PK identity', () async {
      // A soft-deleted member still owns uuid-twin on PK (delete-push not done).
      await fakeRepo.createMember(domain.Member(
        id: 'deleted-twin',
        name: 'Twin',
        createdAt: DateTime(2026, 1, 1),
        pluralkitUuid: 'uuid-twin',
        pluralkitId: 'tw1',
        isDeleted: true,
      ));
      // A brand-new active member of the same name with a stale lease.
      final stale = DateTime.now()
          .subtract(const Duration(minutes: 20))
          .millisecondsSinceEpoch;
      final newTwin = domain.Member(
        id: 'new-twin',
        name: 'Twin',
        createdAt: DateTime(2026, 2, 1),
        createPushStartedAt: stale,
      );
      await fakeRepo.createMember(newTwin);

      await service.syncMembers(
        localMembers: [newTwin],
        pkMembers: [_pkMember(id: 'tw1', uuid: 'uuid-twin', name: 'Twin')],
        fieldConfigs: {},
        direction: PkSyncDirection.pushOnly,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );

      // The new member must NOT adopt the deleted member's PK uuid.
      for (final c
          in fakeRepo.calls.where((c) => c.method == 'applyPluralKitLink')) {
        expect((c.args[1] as Map)['pluralkit_uuid'], isNot('uuid-twin'),
            reason: 'a deleted member\'s live PK identity is not adoptable');
      }
      // It re-POSTs a fresh PK member instead.
      expect(fakeClient.calls.any((c) => c.method == 'createMember'), isTrue);
    });
  });

  group('identity repair', () {
    test('fills missing UUID on short-id-only local link', () async {
      final local = _localMember(pluralkitId: 'pk001');
      final pk = _pkMember(id: 'pk001', uuid: 'uuid-pk001');

      final summary = await service.syncMembers(
        localMembers: [local],
        pkMembers: [pk],
        fieldConfigs: {},
        direction: PkSyncDirection.bidirectional,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );

      final updates = fakeRepo.calls
          .where((c) => c.method == 'updateMember')
          .map((c) => c.args[0] as domain.Member)
          .toList();
      expect(updates, isNotEmpty);
      expect(updates.first.pluralkitId, 'pk001');
      expect(updates.first.pluralkitUuid, 'uuid-pk001');
      expect(summary.membersPulled, 1);
    });
  });

  group('new PK member (no local match)', () {
    test('counted as pulled when pullOnly', () async {
      final pkMembers = [
        _pkMember(id: 'pk999', uuid: 'uuid-pk999', name: 'Brand New'),
      ];

      final summary = await service.syncMembers(
        localMembers: [],
        pkMembers: pkMembers,
        fieldConfigs: {},
        direction: PkSyncDirection.pullOnly,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );

      expect(summary.membersPulled, 1);
    });
  });

  group('_normalizeColor (tested via sync behavior)', () {
    test('strips # and lowercases for comparison', () async {
      // Local member has color #7C3AED, PK member has 7c3aed (same color).
      // With pushOnly, if colors match after normalization there should be
      // no push for color changes.
      final local = _localMember(
        id: 'local-1',
        name: 'Same',
        pluralkitId: 'pk001',
        customColorHex: '#7C3AED',
        customColorEnabled: true,
      );
      final pk = _pkMember(
        id: 'pk001',
        uuid: 'uuid-pk001',
        name: 'Same',
        color: '7c3aed',
      );

      final summary = await service.syncMembers(
        localMembers: [local],
        pkMembers: [pk],
        fieldConfigs: {},
        direction: PkSyncDirection.pushOnly,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );

      // Colors are the same after normalization, so no push should happen
      expect(summary.membersSkipped, 1);
      expect(summary.membersPushed, 0);
    });
  });

  // -------------------------------------------------------------------------
  // _applyPkChanges — pull behavior
  // -------------------------------------------------------------------------

  group('_applyPkChanges (via syncMembers, pullOnly)', () {
    test('does not pull PK internal name into Prism Name', () async {
      final local = _localMember(
        id: 'local-1',
        name: 'OldName',
        pluralkitId: 'pk001',
        pluralkitUuid: 'uuid-pk001',
      );
      final pk = _pkMember(id: 'pk001', name: 'NewName');

      final summary = await service.syncMembers(
        localMembers: [local],
        pkMembers: [pk],
        fieldConfigs: {},
        direction: PkSyncDirection.pullOnly,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );

      expect(summary.membersPulled, 0);
      expect(summary.membersSkipped, 1);
      expect(fakeRepo.calls, isEmpty);
    });

    test(
      'pulls PluralKit displayName into the PK display name field',
      () async {
        final local = _localMember(
          id: 'local-1',
          pluralkitId: 'pk001',
          displayName: 'Local Full Name',
          pluralkitDisplayName: null,
        );
        final pk = _pkMember(id: 'pk001', displayName: 'Ali');

        await service.syncMembers(
          localMembers: [local],
          pkMembers: [pk],
          fieldConfigs: {},
          direction: PkSyncDirection.pullOnly,
          lastSyncDate: null,
          memberRepository: fakeRepo,
          client: fakeClient,
        );

        final written =
            fakeRepo.calls.firstWhere((c) => c.method == 'updateMember').args[0]
                as domain.Member;
        expect(written.name, 'Alice');
        expect(written.displayName, 'Local Full Name');
        expect(written.pluralkitDisplayName, 'Ali');
      },
    );

    test('pulls birthday', () async {
      final local = _localMember(id: 'local-1', pluralkitId: 'pk001');
      final pk = _pkMember(id: 'pk001', birthday: '2020-01-15');

      await service.syncMembers(
        localMembers: [local],
        pkMembers: [pk],
        fieldConfigs: {},
        direction: PkSyncDirection.pullOnly,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );

      final written =
          fakeRepo.calls.firstWhere((c) => c.method == 'updateMember').args[0]
              as domain.Member;
      expect(written.birthday, '2020-01-15');
    });

    test('pulls year-0004 birthday sentinel unchanged', () async {
      final local = _localMember(id: 'local-1', pluralkitId: 'pk001');
      final pk = _pkMember(id: 'pk001', birthday: '0004-03-21');

      await service.syncMembers(
        localMembers: [local],
        pkMembers: [pk],
        fieldConfigs: {},
        direction: PkSyncDirection.pullOnly,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );

      final written =
          fakeRepo.calls.firstWhere((c) => c.method == 'updateMember').args[0]
              as domain.Member;
      expect(written.birthday, '0004-03-21');
    });

    test('pulls proxyTagsJson in pull direction', () async {
      final local = _localMember(id: 'local-1', pluralkitId: 'pk001');
      final pk = _pkMember(
        id: 'pk001',
        proxyTagsJson: '[{"prefix":"A:","suffix":null}]',
      );

      await service.syncMembers(
        localMembers: [local],
        pkMembers: [pk],
        fieldConfigs: {},
        direction: PkSyncDirection.pullOnly,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );

      final written =
          fakeRepo.calls.firstWhere((c) => c.method == 'updateMember').args[0]
              as domain.Member;
      expect(written.proxyTagsJson, '[{"prefix":"A:","suffix":null}]');
    });

    test('baselines legacy avatar URL without replacing local bytes', () async {
      final localAvatar = Uint8List.fromList([1, 2, 3]);
      final local = _localMember(
        id: 'local-1',
        pluralkitId: 'pk001',
        avatarImageData: localAvatar,
      );
      final pk = _pkMember(
        id: 'pk001',
        avatarUrl: 'https://cdn.example/avatar.png',
      );
      final avatarService = PkAvatarCacheService(
        fetcher: (_) async => fail('legacy avatar should not refetch'),
        normalizer: (bytes) => bytes,
      );

      await PkBidirectionalService(
        pushService: const PkPushService(),
        avatarCacheService: avatarService,
      ).syncMembers(
        localMembers: [local],
        pkMembers: [pk],
        fieldConfigs: {},
        direction: PkSyncDirection.pullOnly,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );

      final written =
          fakeRepo.calls.firstWhere((c) => c.method == 'updateMember').args[0]
              as domain.Member;
      expect(written.avatarImageData, localAvatar);
      expect(written.pkAvatarCachedUrl, 'https://cdn.example/avatar.png');
    });

    test('pulls avatar bytes when the PK avatar URL changes', () async {
      final oldAvatar = Uint8List.fromList([1, 2, 3]);
      final newAvatar = Uint8List.fromList([9, 8, 7]);
      final local = _localMember(
        id: 'local-1',
        pluralkitId: 'pk001',
        avatarImageData: oldAvatar,
        pkAvatarCachedUrl: 'https://cdn.example/old.png',
      );
      final pk = _pkMember(
        id: 'pk001',
        avatarUrl: 'https://cdn.example/new.png',
      );
      final avatarService = PkAvatarCacheService(
        fetcher: (url) async {
          expect(url, 'https://cdn.example/new.png');
          return newAvatar;
        },
        normalizer: (bytes) => bytes,
      );

      await PkBidirectionalService(
        pushService: const PkPushService(),
        avatarCacheService: avatarService,
      ).syncMembers(
        localMembers: [local],
        pkMembers: [pk],
        fieldConfigs: {},
        direction: PkSyncDirection.pullOnly,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );

      final written =
          fakeRepo.calls.firstWhere((c) => c.method == 'updateMember').args[0]
              as domain.Member;
      expect(written.avatarImageData, newAvatar);
      expect(written.pkAvatarCachedUrl, 'https://cdn.example/new.png');
    });

    test(
      'bidirectional default pushes explicit proxy tag clear when sync proceeds',
      () async {
        final local = _localMember(
          id: 'local-1',
          pluralkitId: 'pk001',
          proxyTagsJson: '[]',
        );
        final pk = _pkMember(
          id: 'pk001',
          proxyTagsJson: '[{"prefix":"FIXED:","suffix":null}]',
        );

        final summary = await service.syncMembers(
          localMembers: [local],
          pkMembers: [pk],
          fieldConfigs: {},
          direction: PkSyncDirection.bidirectional,
          lastSyncDate: null,
          memberRepository: fakeRepo,
          client: fakeClient,
        );

        expect(summary.membersPushed, 1);
        final updateCall = fakeClient.calls.firstWhere(
          (c) => c.method == 'updateMember',
        );
        final payload = updateCall.args[1] as Map<String, dynamic>;
        expect(payload['proxy_tags'], isEmpty);
      },
    );

    test(
      'bidirectional default proxy tag config pushes divergent value',
      () async {
        final local = _localMember(
          id: 'local-1',
          pluralkitId: 'pk001',
          proxyTagsJson: '[{"prefix":"LOCAL:","suffix":null}]',
        );
        final pk = _pkMember(
          id: 'pk001',
          proxyTagsJson: '[{"prefix":"PK:","suffix":null}]',
        );

        await service.syncMembers(
          localMembers: [local],
          pkMembers: [pk],
          fieldConfigs: {},
          direction: PkSyncDirection.bidirectional,
          lastSyncDate: null,
          memberRepository: fakeRepo,
          client: fakeClient,
        );

        final updateCall = fakeClient.calls.firstWhere(
          (c) => c.method == 'updateMember',
        );
        final payload = updateCall.args[1] as Map<String, dynamic>;
        expect(payload['proxy_tags'], [
          {'prefix': 'LOCAL:', 'suffix': null},
        ]);
      },
    );

    test(
      'pull-only proxy tag config omits proxy_tags when pushing other changes',
      () async {
        final local = _localMember(
          id: 'local-1',
          pluralkitId: 'pk001',
          pluralkitDisplayName: 'NewDisplay',
          proxyTagsJson: '[{"prefix":"LOCAL:","suffix":null}]',
        );
        final pk = _pkMember(
          id: 'pk001',
          displayName: 'OldDisplay',
          proxyTagsJson: '[{"prefix":"PK:","suffix":null}]',
        );

        await service.syncMembers(
          localMembers: [local],
          pkMembers: [pk],
          fieldConfigs: {
            'local-1': const PkFieldSyncConfig(
              proxyTags: PkSyncDirection.pullOnly,
            ),
          },
          direction: PkSyncDirection.bidirectional,
          lastSyncDate: null,
          memberRepository: fakeRepo,
          client: fakeClient,
        );

        final updateCall = fakeClient.calls.firstWhere(
          (c) => c.method == 'updateMember',
        );
        final payload = updateCall.args[1] as Map<String, dynamic>;
        expect(payload['display_name'], 'NewDisplay');
        expect(payload.containsKey('proxy_tags'), isFalse);
      },
    );

    test(
      'pushOnly does not clear PK proxy tags when local value is null',
      () async {
        final local = _localMember(
          id: 'local-1',
          pluralkitId: 'pk001',
          proxyTagsJson: null,
        );
        final pk = _pkMember(
          id: 'pk001',
          proxyTagsJson: '[{"prefix":"PK:","suffix":null}]',
        );

        final summary = await service.syncMembers(
          localMembers: [local],
          pkMembers: [pk],
          fieldConfigs: {},
          direction: PkSyncDirection.pushOnly,
          lastSyncDate: null,
          memberRepository: fakeRepo,
          client: fakeClient,
        );

        expect(summary.membersPushed, 0);
        expect(
          fakeClient.calls.any((c) => c.method == 'updateMember'),
          isFalse,
        );
      },
    );

    test(
      'pushOnly clears PK proxy tags when local value is explicit empty list',
      () async {
        final local = _localMember(
          id: 'local-1',
          pluralkitId: 'pk001',
          proxyTagsJson: '[]',
        );
        final pk = _pkMember(
          id: 'pk001',
          proxyTagsJson: '[{"prefix":"PK:","suffix":null}]',
        );

        final summary = await service.syncMembers(
          localMembers: [local],
          pkMembers: [pk],
          fieldConfigs: {},
          direction: PkSyncDirection.pushOnly,
          lastSyncDate: null,
          memberRepository: fakeRepo,
          client: fakeClient,
        );

        expect(summary.membersPushed, 1);
        final updateCall = fakeClient.calls.firstWhere(
          (c) => c.method == 'updateMember',
        );
        final payload = updateCall.args[1] as Map<String, dynamic>;
        expect(payload['proxy_tags'], isEmpty);
      },
    );

    test('no-op when nothing differs', () async {
      final local = _localMember(
        id: 'local-1',
        name: 'Same',
        pronouns: 'she/her',
        bio: 'hello',
        pluralkitId: 'pk001',
        pluralkitUuid: 'uuid-pk001',
        displayName: 'Local Full Name',
        pluralkitDisplayName: 'SameDisplay',
        birthday: '2020-01-15',
      );
      final pk = _pkMember(
        id: 'pk001',
        name: 'Same',
        pronouns: 'she/her',
        description: 'hello',
        displayName: 'SameDisplay',
        birthday: '2020-01-15',
      );

      final summary = await service.syncMembers(
        localMembers: [local],
        pkMembers: [pk],
        fieldConfigs: {},
        direction: PkSyncDirection.pullOnly,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );

      expect(summary.membersPulled, 0);
      expect(summary.membersSkipped, 1);
      expect(fakeRepo.calls, isEmpty);
    });

    test('explicit null clears local field when PK is null (pull)', () async {
      final local = _localMember(
        id: 'local-1',
        pluralkitId: 'pk001',
        pronouns: 'he/him',
      );
      // PK has pronouns = null; pulling should clear local.
      final pk = _pkMember(id: 'pk001', pronouns: null);

      await service.syncMembers(
        localMembers: [local],
        pkMembers: [pk],
        fieldConfigs: {},
        direction: PkSyncDirection.pullOnly,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );

      final written =
          fakeRepo.calls.firstWhere((c) => c.method == 'updateMember').args[0]
              as domain.Member;
      expect(written.pronouns, isNull);
    });

    test('respects per-field pull=disabled: does not pull that field', () async {
      final local = _localMember(
        id: 'local-1',
        pluralkitId: 'pk001',
        displayName: 'Local Full Name',
        pluralkitDisplayName: 'LocalOnly',
      );
      final pk = _pkMember(id: 'pk001', displayName: 'PkWins');

      // Force displayName direction = pushOnly (so pull for that field is off).
      final configs = {
        'local-1': const PkFieldSyncConfig(
          displayName: PkSyncDirection.pushOnly,
        ),
      };

      await service.syncMembers(
        localMembers: [local],
        pkMembers: [pk],
        fieldConfigs: configs,
        direction: PkSyncDirection.bidirectional,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );

      // PluralKit Display Name shouldn't have been pulled. The push path will fire
      // instead because local has a different value and push is enabled.
      // But that's fine — the point is memberRepository.updateMember was
      // NOT called with a changed PluralKit Display Name.
      final updateMemberCalls = fakeRepo.calls.where(
        (c) => c.method == 'updateMember',
      );
      for (final c in updateMemberCalls) {
        final m = c.args[0] as domain.Member;
        expect(m.displayName, 'Local Full Name');
        expect(m.pluralkitDisplayName, 'LocalOnly');
      }
    });
  });

  // -------------------------------------------------------------------------
  // _memberToPayload null-clearing (via pk_push_service's PATCH)
  // -------------------------------------------------------------------------

  group('push null-clear safety (plan 08 first-link semantics)', () {
    test('does NOT push when local pronouns null and PK has a value', () async {
      // Per plan 08 "Conflict semantics on link", an empty local value must
      // never null-clear PK — that would be a destructive first-link push.
      final local = _localMember(
        id: 'local-1',
        name: 'Alice',
        pluralkitId: 'pk001',
        pronouns: null,
      );
      final pk = _pkMember(id: 'pk001', name: 'Alice', pronouns: 'he/him');

      final summary = await service.syncMembers(
        localMembers: [local],
        pkMembers: [pk],
        fieldConfigs: {},
        direction: PkSyncDirection.pushOnly,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );

      expect(summary.membersPushed, 0);
      expect(
        fakeClient.calls.any((c) => c.method == 'updateMember'),
        isFalse,
        reason: 'Null local must not clear PK via push',
      );
    });

    test('does NOT push when local bio empty and PK has a value', () async {
      final local = _localMember(
        id: 'local-1',
        name: 'Alice',
        pluralkitId: 'pk001',
        bio: null,
      );
      final pk = _pkMember(id: 'pk001', name: 'Alice', description: 'hi');

      final summary = await service.syncMembers(
        localMembers: [local],
        pkMembers: [pk],
        fieldConfigs: {},
        direction: PkSyncDirection.pushOnly,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );

      expect(summary.membersPushed, 0);
    });

    test('still pushes when local is populated and differs', () async {
      final local = _localMember(
        id: 'local-1',
        name: 'Alice',
        pluralkitId: 'pk001',
        pronouns: 'they/them',
      );
      final pk = _pkMember(id: 'pk001', name: 'Alice', pronouns: 'he/him');

      final summary = await service.syncMembers(
        localMembers: [local],
        pkMembers: [pk],
        fieldConfigs: {},
        direction: PkSyncDirection.pushOnly,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );

      expect(summary.membersPushed, 1);
      final updateCall = fakeClient.calls.firstWhere(
        (c) => c.method == 'updateMember',
      );
      final payload = updateCall.args[1] as Map<String, dynamic>;
      expect(payload['pronouns'], 'they/them');
    });
  });

  // -------------------------------------------------------------------------
  // H1: PATCH payload is per-field gated — it carries ONLY fields that
  // differ, are push-allowed by direction config, and are not a would-clear.
  // A bio edit must never null-clear PK-only pronouns.
  // -------------------------------------------------------------------------

  group('H1: per-field-gated PATCH payload', () {
    test('bio-only trigger sends description and nothing else', () async {
      final local = _localMember(
        id: 'local-1',
        name: 'Alice',
        pluralkitId: 'pk001',
        bio: 'new bio',
        pronouns: 'she/her',
        birthday: '2020-01-15',
      );
      final pk = _pkMember(
        id: 'pk001',
        name: 'Alice',
        description: 'old bio',
        pronouns: 'she/her',
        birthday: '2020-01-15',
      );

      final summary = await service.syncMembers(
        localMembers: [local],
        pkMembers: [pk],
        fieldConfigs: {},
        direction: PkSyncDirection.pushOnly,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );

      expect(summary.membersPushed, 1);
      final payload =
          fakeClient.calls.firstWhere((c) => c.method == 'updateMember').args[1]
              as Map<String, dynamic>;
      expect(payload['description'], 'new bio');
      expect(payload.keys, ['description']);
    });

    test(
      'local pronouns null + PK pronouns set + bio differs: no pronouns key',
      () async {
        final local = _localMember(
          id: 'local-1',
          name: 'Alice',
          pluralkitId: 'pk001',
          bio: 'new bio',
          pronouns: null,
        );
        final pk = _pkMember(
          id: 'pk001',
          name: 'Alice',
          description: 'old bio',
          pronouns: 'he/him',
        );

        await service.syncMembers(
          localMembers: [local],
          pkMembers: [pk],
          fieldConfigs: {},
          direction: PkSyncDirection.pushOnly,
          lastSyncDate: null,
          memberRepository: fakeRepo,
          client: fakeClient,
        );

        final payload =
            fakeClient.calls
                    .firstWhere((c) => c.method == 'updateMember')
                    .args[1]
                as Map<String, dynamic>;
        expect(payload['description'], 'new bio');
        expect(
          payload.containsKey('pronouns'),
          isFalse,
          reason: 'a bio edit must not null-clear PK-only pronouns (H1)',
        );
      },
    );

    test('local pronouns null vs PK pronouns empty string: nothing to push', () async {
      // PK treats '' and null both as "cleared" — the asymmetry must not
      // count as a difference, or the field enters the pushable set only for
      // the payload builder to omit it (risking an empty `{}` PATCH → 400).
      final local = _localMember(
        id: 'local-1',
        name: 'Alice',
        pluralkitId: 'pk001',
        pronouns: null,
      );
      final pk = _pkMember(id: 'pk001', name: 'Alice', pronouns: '');

      final summary = await service.syncMembers(
        localMembers: [local],
        pkMembers: [pk],
        fieldConfigs: {},
        direction: PkSyncDirection.pushOnly,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );

      expect(summary.membersPushed, 0);
      expect(
        fakeClient.calls.where((c) => c.method == 'updateMember'),
        isEmpty,
        reason: "''-vs-null is not a pushable difference",
      );
    });

    test('local pronouns empty string vs PK null: no perpetual clear-push', () async {
      // The mirror case: PK stores null, so pushing '' (a PK clear) would
      // "differ" again on every later sync — a destructive write loop.
      final local = _localMember(
        id: 'local-1',
        name: 'Alice',
        pluralkitId: 'pk001',
        pronouns: '',
      );
      final pk = _pkMember(id: 'pk001', name: 'Alice', pronouns: null);

      final summary = await service.syncMembers(
        localMembers: [local],
        pkMembers: [pk],
        fieldConfigs: {},
        direction: PkSyncDirection.pushOnly,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );

      expect(summary.membersPushed, 0);
      expect(
        fakeClient.calls.where((c) => c.method == 'updateMember'),
        isEmpty,
      );
    });

    test('whitespace-only local pronouns vs populated PK: would-clear, not pushed', () async {
      final local = _localMember(
        id: 'local-1',
        name: 'Alice',
        pluralkitId: 'pk001',
        pronouns: '  ',
      );
      final pk = _pkMember(id: 'pk001', name: 'Alice', pronouns: 'he/him');

      final summary = await service.syncMembers(
        localMembers: [local],
        pkMembers: [pk],
        fieldConfigs: {},
        direction: PkSyncDirection.pushOnly,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );

      expect(summary.membersPushed, 0);
      expect(
        fakeClient.calls.where((c) => c.method == 'updateMember'),
        isEmpty,
        reason: 'whitespace-only local must not overwrite populated PK',
      );
    });

    test(
      'local pronouns empty string + PK set + bio differs: no pronouns key',
      () async {
        final local = _localMember(
          id: 'local-1',
          name: 'Alice',
          pluralkitId: 'pk001',
          bio: 'new bio',
          pronouns: '',
        );
        final pk = _pkMember(
          id: 'pk001',
          name: 'Alice',
          description: 'old bio',
          pronouns: 'he/him',
        );

        await service.syncMembers(
          localMembers: [local],
          pkMembers: [pk],
          fieldConfigs: {},
          direction: PkSyncDirection.pushOnly,
          lastSyncDate: null,
          memberRepository: fakeRepo,
          client: fakeClient,
        );

        final payload =
            fakeClient.calls
                    .firstWhere((c) => c.method == 'updateMember')
                    .args[1]
                as Map<String, dynamic>;
        expect(payload['description'], 'new bio');
        expect(
          payload.containsKey('pronouns'),
          isFalse,
          reason: 'empty-string local is a clear; "" must not be pushed (H1)',
        );
      },
    );

    test(
      'color configured pull-only + color differs + bio differs: no color key',
      () async {
        final local = _localMember(
          id: 'local-1',
          name: 'Alice',
          pluralkitId: 'pk001',
          bio: 'new bio',
          customColorHex: '#abcdef',
          customColorEnabled: true,
        );
        final pk = _pkMember(
          id: 'pk001',
          name: 'Alice',
          description: 'old bio',
          color: '123456',
        );

        await service.syncMembers(
          localMembers: [local],
          pkMembers: [pk],
          fieldConfigs: {
            'local-1': const PkFieldSyncConfig(
              color: PkSyncDirection.pullOnly,
            ),
          },
          direction: PkSyncDirection.bidirectional,
          lastSyncDate: null,
          memberRepository: fakeRepo,
          client: fakeClient,
        );

        final payload =
            fakeClient.calls
                    .firstWhere((c) => c.method == 'updateMember')
                    .args[1]
                as Map<String, dynamic>;
        expect(payload['description'], 'new bio');
        expect(
          payload.containsKey('color'),
          isFalse,
          reason: 'a pull-only field must never appear in a push body (H1)',
        );
      },
    );

    test('all fields differ in pushOnly: payload includes all of them', () async {
      final local = _localMember(
        id: 'local-1',
        name: 'Alice',
        pluralkitId: 'pk001',
        pluralkitDisplayName: 'NewDisplay',
        pronouns: 'they/them',
        bio: 'new bio',
        birthday: '2021-02-02',
        customColorHex: '#abcdef',
        customColorEnabled: true,
      );
      final pk = _pkMember(
        id: 'pk001',
        name: 'Alice',
        displayName: 'OldDisplay',
        pronouns: 'he/him',
        description: 'old bio',
        birthday: '2020-01-15',
        color: '123456',
      );

      await service.syncMembers(
        localMembers: [local],
        pkMembers: [pk],
        fieldConfigs: {},
        direction: PkSyncDirection.pushOnly,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );

      final payload =
          fakeClient.calls.firstWhere((c) => c.method == 'updateMember').args[1]
              as Map<String, dynamic>;
      expect(payload['display_name'], 'NewDisplay');
      expect(payload['pronouns'], 'they/them');
      expect(payload['description'], 'new bio');
      expect(payload['birthday'], '2021-02-02');
      expect(payload['color'], 'abcdef');
    });

    test(
      'no PATCH when the only differing fields are all excluded',
      () async {
        // pronouns differ but are would-clear (local empty); color differs but
        // is pull-only. Nothing includable → service must skip the PATCH (PK
        // 400s on an empty PATCH body).
        final local = _localMember(
          id: 'local-1',
          name: 'Alice',
          pluralkitId: 'pk001',
          bio: 'same',
          pronouns: '',
          customColorHex: '#abcdef',
          customColorEnabled: true,
        );
        final pk = _pkMember(
          id: 'pk001',
          name: 'Alice',
          description: 'same',
          pronouns: 'he/him',
          color: '123456',
        );

        final summary = await service.syncMembers(
          localMembers: [local],
          pkMembers: [pk],
          fieldConfigs: {
            'local-1': const PkFieldSyncConfig(
              color: PkSyncDirection.pullOnly,
            ),
          },
          direction: PkSyncDirection.bidirectional,
          lastSyncDate: null,
          memberRepository: fakeRepo,
          client: fakeClient,
        );

        expect(summary.membersPushed, 0);
        expect(
          fakeClient.calls.any((c) => c.method == 'updateMember'),
          isFalse,
          reason: 'no includable fields → no PATCH (empty body would 400)',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // config.pullEnabled / direction gating
  // -------------------------------------------------------------------------

  group('direction gating', () {
    test('pushOnly does not pull PK-side field changes', () async {
      final local = _localMember(
        id: 'local-1',
        name: 'LocalName',
        pluralkitId: 'pk001',
      );
      final pk = _pkMember(id: 'pk001', name: 'PkName');

      await service.syncMembers(
        localMembers: [local],
        pkMembers: [pk],
        fieldConfigs: {},
        direction: PkSyncDirection.pushOnly,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );

      // In pushOnly, a diff triggers a push — not a pull-write. The local
      // name should never be overwritten to 'PkName'.
      for (final c in fakeRepo.calls.where((c) => c.method == 'updateMember')) {
        final m = c.args[0] as domain.Member;
        expect(m.name, 'LocalName');
      }
    });
  });

  // -------------------------------------------------------------------------
  // PluralKit display-name sync must not rewrite Prism Name or Full Name.
  // -------------------------------------------------------------------------

  group('PluralKit display name field split', () {
    test('legacy local.name == pk.displayName writes PK field only', () async {
      final local = _localMember(
        id: 'local-1',
        name: 'Alice ✨',
        pluralkitId: 'pk001',
        pluralkitUuid: 'uuid-pk001',
        // displayName: null (legacy shape)
      );
      final pk = _pkMember(
        id: 'pk001',
        uuid: 'uuid-pk001',
        name: 'alice',
        displayName: 'Alice ✨',
      );

      await service.syncMembers(
        localMembers: [local],
        pkMembers: [pk],
        fieldConfigs: {},
        direction: PkSyncDirection.pullOnly,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );

      final calls = fakeRepo.calls
          .where((c) => c.method == 'updateMember')
          .toList();
      expect(calls, isNotEmpty);
      final updated = calls.last.args[0] as domain.Member;
      expect(
        updated.pluralkitDisplayName,
        'Alice ✨',
        reason: 'PK display_name must land in the PK-specific field',
      );
      expect(updated.displayName, isNull);
      expect(
        updated.name,
        'Alice ✨',
        reason: 'Prism Name is local-only and must not follow pk.name',
      );
    });

    test(
      'local Full Name already set stays local-only during normal pull',
      () async {
        final local = _localMember(
          id: 'local-1',
          name: 'alice',
          displayName: 'Alice ✨',
          pluralkitId: 'pk001',
          pluralkitUuid: 'uuid-pk001',
        );
        final pk = _pkMember(
          id: 'pk001',
          uuid: 'uuid-pk001',
          name: 'alice',
          displayName: 'Alice 🌟',
        );

        await service.syncMembers(
          localMembers: [local],
          pkMembers: [pk],
          fieldConfigs: {},
          direction: PkSyncDirection.pullOnly,
          lastSyncDate: null,
          memberRepository: fakeRepo,
          client: fakeClient,
        );

        final updated =
            fakeRepo.calls.where((c) => c.method == 'updateMember').last.args[0]
                as domain.Member;
        expect(updated.name, 'alice');
        expect(updated.displayName, 'Alice ✨');
        expect(updated.pluralkitDisplayName, 'Alice 🌟');
      },
    );
  });

  // -------------------------------------------------------------------------
  // Color: customColorEnabled=false must NOT clear PK's color
  // -------------------------------------------------------------------------

  group('color sync respects customColorEnabled', () {
    test(
      'customColorEnabled=false does not push color:null even with local hex set',
      () async {
        final local = _localMember(
          id: 'local-1',
          name: 'Alice',
          pluralkitId: 'pk001',
          pluralkitUuid: 'uuid-pk001',
          customColorHex: '#ff0000',
          customColorEnabled: false,
          // Force a push with a different field so this member reaches the
          // payload path.
          pronouns: 'they/them',
        );
        final pk = _pkMember(
          id: 'pk001',
          uuid: 'uuid-pk001',
          name: 'Alice',
          pronouns: null,
          color: '00ff00',
        );

        await service.syncMembers(
          localMembers: [local],
          pkMembers: [pk],
          fieldConfigs: {},
          direction: PkSyncDirection.pushOnly,
          lastSyncDate: null,
          memberRepository: fakeRepo,
          client: fakeClient,
        );

        final updateCall = fakeClient.calls.firstWhere(
          (c) => c.method == 'updateMember',
        );
        final payload = updateCall.args[1] as Map<String, dynamic>;
        expect(
          payload.containsKey('color'),
          isFalse,
          reason:
              'customColorEnabled=false must OMIT color, never send null to clear PK',
        );
      },
    );

    test(
      'pullOnly preserves local custom color when PK color is absent',
      () async {
        final local = _localMember(
          id: 'local-1',
          name: 'Alice',
          pronouns: null,
          pluralkitId: 'pk001',
          pluralkitUuid: 'uuid-pk001',
          customColorHex: '#ff0000',
          customColorEnabled: true,
        );
        final pk = _pkMember(
          id: 'pk001',
          uuid: 'uuid-pk001',
          name: 'Alice',
          pronouns: 'they/them',
          color: null,
        );

        await service.syncMembers(
          localMembers: [local],
          pkMembers: [pk],
          fieldConfigs: {},
          direction: PkSyncDirection.pullOnly,
          lastSyncDate: null,
          memberRepository: fakeRepo,
          client: fakeClient,
        );

        final updated =
            fakeRepo.calls.where((c) => c.method == 'updateMember').last.args[0]
                as domain.Member;
        expect(updated.pronouns, 'they/them');
        expect(updated.customColorHex, '#ff0000');
        expect(updated.customColorEnabled, isTrue);
      },
    );
  });

  // -------------------------------------------------------------------------
  // Proxy tag canonicalization (#37 / WS3 step 11)
  //
  // Pre-fix: jsonEncode(localTags) != jsonEncode(pkTags) was a raw string
  // compare that drifted on map key order or list element order. That made
  // the bidirectional push-decision return "different" for two semantically
  // equal tag lists → push every sync. These tests pin the canonical-form
  // comparison so equality survives both reorderings.
  // -------------------------------------------------------------------------

  group('proxy tag canonicalization', () {
    test('reordered per-tag map keys are treated as equal (no push)', () async {
      // Local tag is `{"prefix":"X:","suffix":null}`; PK tag is the same
      // payload but with the keys serialized in the opposite order. The
      // raw JSON strings differ but the canonical form must match.
      final local = _localMember(
        id: 'local-1',
        pluralkitId: 'pk001',
        proxyTagsJson: '[{"prefix":"X:","suffix":null}]',
      );
      final pk = _pkMember(
        id: 'pk001',
        proxyTagsJson: '[{"suffix":null,"prefix":"X:"}]',
      );

      final summary = await service.syncMembers(
        localMembers: [local],
        pkMembers: [pk],
        fieldConfigs: {},
        direction: PkSyncDirection.bidirectional,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );

      expect(summary.membersPushed, 0);
      expect(
        fakeClient.calls.any((c) => c.method == 'updateMember'),
        isFalse,
        reason: 'Identical tags with reordered map keys must not trigger push',
      );
    });

    test(
      'reordered outer list elements are treated as equal (no push)',
      () async {
        final local = _localMember(
          id: 'local-1',
          pluralkitId: 'pk001',
          proxyTagsJson:
              '[{"prefix":"A:","suffix":null},{"prefix":"B:","suffix":null}]',
        );
        final pk = _pkMember(
          id: 'pk001',
          proxyTagsJson:
              '[{"prefix":"B:","suffix":null},{"prefix":"A:","suffix":null}]',
        );

        final summary = await service.syncMembers(
          localMembers: [local],
          pkMembers: [pk],
          fieldConfigs: {},
          direction: PkSyncDirection.bidirectional,
          lastSyncDate: null,
          memberRepository: fakeRepo,
          client: fakeClient,
        );

        expect(summary.membersPushed, 0);
        expect(
          fakeClient.calls.any((c) => c.method == 'updateMember'),
          isFalse,
          reason: 'Same tag set in different list order must not trigger push',
        );
      },
    );

    test(
      'explicit bidirectional config pushes genuinely different tags',
      () async {
        final local = _localMember(
          id: 'local-1',
          pluralkitId: 'pk001',
          proxyTagsJson: '[{"prefix":"LOCAL:","suffix":null}]',
        );
        final pk = _pkMember(
          id: 'pk001',
          proxyTagsJson: '[{"prefix":"PK:","suffix":null}]',
        );

        final summary = await service.syncMembers(
          localMembers: [local],
          pkMembers: [pk],
          fieldConfigs: {
            'local-1': const PkFieldSyncConfig(
              proxyTags: PkSyncDirection.bidirectional,
            ),
          },
          direction: PkSyncDirection.bidirectional,
          lastSyncDate: null,
          memberRepository: fakeRepo,
          client: fakeClient,
        );

        expect(summary.membersPushed, 1);
        expect(fakeClient.calls.any((c) => c.method == 'updateMember'), isTrue);
      },
    );
  });

  // -------------------------------------------------------------------------
  // pluralkitSyncIgnored — push-unlinked-locals respects the "Keep local" flag
  // -------------------------------------------------------------------------

  group('pluralkitSyncIgnored on unlinked locals', () {
    test('does not push an unlinked local member flagged Keep local, but still '
        'pushes a non-ignored sibling', () async {
      final ignored = _localMember(
        id: 'local-ignored',
        name: 'KeepLocal',
        pluralkitSyncIgnored: true,
      );
      final pushable = _localMember(id: 'local-pushable', name: 'PushMe');

      final summary = await service.syncMembers(
        localMembers: [ignored, pushable],
        pkMembers: const [],
        fieldConfigs: {},
        direction: PkSyncDirection.bidirectional,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );

      // Exactly one push (the non-ignored sibling).
      expect(summary.membersPushed, 1);

      final createCalls = fakeClient.calls
          .where((c) => c.method == 'createMember')
          .toList();
      expect(createCalls, hasLength(1));
      final payload = createCalls.single.args[0] as Map<String, dynamic>;
      expect(
        payload['name'],
        'PushMe',
        reason: 'Only the non-ignored member should be created in PK',
      );

      // No PK identifiers should have been written back for the ignored
      // member.
      for (final c in fakeRepo.calls.where((c) => c.method == 'updateMember')) {
        final m = c.args[0] as domain.Member;
        expect(
          m.id,
          isNot('local-ignored'),
          reason:
              'Ignored member must not be linked to a freshly-created PK '
              'member',
        );
      }
    });

    test(
      'pushOnly also honors pluralkitSyncIgnored on unlinked locals',
      () async {
        final ignored = _localMember(
          id: 'local-ignored',
          name: 'KeepLocal',
          pluralkitSyncIgnored: true,
        );

        final summary = await service.syncMembers(
          localMembers: [ignored],
          pkMembers: const [],
          fieldConfigs: {},
          direction: PkSyncDirection.pushOnly,
          lastSyncDate: null,
          memberRepository: fakeRepo,
          client: fakeClient,
        );

        expect(summary.membersPushed, 0);
        expect(
          fakeClient.calls.any((c) => c.method == 'createMember'),
          isFalse,
          reason: 'Keep-local members must never be created on PK',
        );
      },
    );
  });

  // ───────────────────────────────────────────────────────────────────────
  // PR 2: per-local loop + PkStaleLinkException clear + metadata writes
  // (plan parts 1.5 + 1.7)
  // ───────────────────────────────────────────────────────────────────────

  group('PR 2: per-local loop skips excluded (push and pull)', () {
    test('excluded local with matching PK member is counted skipped — no '
        'push, no pull write', () async {
      final local = _localMember(
        id: 'local-1',
        name: 'Excluded',
        pluralkitId: 'pk001',
        pluralkitUuid: 'uuid-pk001',
        // Locally have stale name; PK has different. If guard fails this
        // would either push or pull.
        bio: 'old local bio',
        pluralkitSyncIgnored: true,
      );
      final pk = _pkMember(
        id: 'pk001',
        uuid: 'uuid-pk001',
        name: 'Excluded',
        description: 'new PK bio',
      );

      final summary = await service.syncMembers(
        localMembers: [local],
        pkMembers: [pk],
        fieldConfigs: {},
        direction: PkSyncDirection.bidirectional,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );

      expect(summary.membersSkipped, 1);
      expect(summary.membersPushed, 0);
      expect(summary.membersPulled, 0);
      // No PK network calls.
      expect(fakeClient.calls, isEmpty);
      // No repo writes that would re-stamp the excluded row.
      expect(
        fakeRepo.calls.where(
          (c) =>
              c.method == 'updateMember' ||
              c.method == 'applyPluralKitLink' ||
              c.method == 'recordPluralKitIdentity',
        ),
        isEmpty,
      );
    });
  });

  group('PR 2: PkStaleLinkException clear path', () {
    test(
      'still uses generic updateMember on non-excluded (clears nulls)',
      () async {
        final local = _localMember(
          id: 'local-1',
          name: 'WillStale',
          pluralkitId: 'pk001',
          pluralkitUuid: 'uuid-pk001',
          bio: 'local has newer bio',
        );
        final pk = _pkMember(
          id: 'pk001',
          uuid: 'uuid-pk001',
          name: 'WillStale',
          // bio stays absent so local would push.
        );

        final staleService = PkBidirectionalService(
          pushService: _StaleLinkOnPushService(),
        );

        final summary = await staleService.syncMembers(
          localMembers: [local],
          pkMembers: [pk],
          fieldConfigs: {},
          direction: PkSyncDirection.pushOnly,
          lastSyncDate: null,
          memberRepository: fakeRepo,
          client: fakeClient,
        );

        expect(summary.membersSkipped, 1);
        // Clear path went through generic updateMember (NOT through one of
        // the PK-link-specific methods).
        final updateCalls = fakeRepo.calls
            .where((c) => c.method == 'updateMember')
            .map((c) => c.args[0] as domain.Member)
            .toList();
        expect(updateCalls, hasLength(1));
        expect(updateCalls.single.pluralkitId, isNull);
        expect(updateCalls.single.pluralkitUuid, isNull);
        // No applyPluralKitLink — Rule A's null-handling fix means we don't
        // need the bypass.
        expect(
          fakeRepo.calls.where((c) => c.method == 'applyPluralKitLink'),
          isEmpty,
        );
      },
    );

    test('clear path on excluded member writes nulls through (v6 '
        'null-handling fix)', () async {
      // Set up: excluded member already seeded into the repo so the
      // repository invariant (real DB) would normally strip non-null PK
      // writes. The bidirectional service's PkStaleLinkException branch
      // writes nulls; with v6's null-handling fix those pass through.
      // This test mostly verifies the bidirectional service still routes
      // through generic updateMember (the fake doesn't enforce the
      // invariant, but the call shape is what matters here — Rule A's
      // null pass-through is tested in drift_member_repository_test).
      //
      // We exercise the per-local loop's skip first, then a second pass
      // with the local now non-excluded to verify the clear path doesn't
      // double-bounce off applyPluralKitLink. The substantive cross-
      // module invariant lives in drift_member_repository_test's
      // "Null-clearing PK fields on excluded member passes through" test.
      final local = _localMember(
        id: 'local-1',
        name: 'Edge',
        pluralkitId: 'pk001',
        pluralkitUuid: 'uuid-pk001',
        bio: 'local newer',
        // NOT excluded — the bidirectional service skips excluded entirely.
        // The repo-level null pass-through invariant is what we're
        // documenting here for completeness.
      );
      final pk = _pkMember(id: 'pk001', uuid: 'uuid-pk001');

      final staleService = PkBidirectionalService(
        pushService: _StaleLinkOnPushService(),
      );
      await staleService.syncMembers(
        localMembers: [local],
        pkMembers: [pk],
        fieldConfigs: {},
        direction: PkSyncDirection.pushOnly,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );

      // Generic updateMember used (no PK-link methods); patch nulls flow.
      final updateCalls = fakeRepo.calls
          .where((c) => c.method == 'updateMember')
          .map((c) => c.args[0] as domain.Member)
          .toList();
      expect(updateCalls, hasLength(1));
      expect(updateCalls.single.pluralkitId, isNull);
      expect(updateCalls.single.pluralkitUuid, isNull);
    });
  });

  group('PR 2: metadata-only _applyPkChanges writes', () {
    test(
      'non-excluded local with PK-pulled bio uses generic updateMember',
      () async {
        final local = _localMember(
          id: 'local-1',
          name: 'Same',
          pluralkitId: 'pk001',
          pluralkitUuid: 'uuid-pk001',
        );
        // PK has a new bio; pull-direction default for description is
        // bidirectional, so it pulls.
        final pk = _pkMember(
          id: 'pk001',
          uuid: 'uuid-pk001',
          name: 'Same',
          description: 'PK bio',
        );

        await service.syncMembers(
          localMembers: [local],
          pkMembers: [pk],
          fieldConfigs: {},
          direction: PkSyncDirection.pullOnly,
          lastSyncDate: null,
          memberRepository: fakeRepo,
          client: fakeClient,
        );

        // Metadata writes go through generic updateMember — NOT
        // applyPluralKitLink / recordPluralKitIdentity (those are
        // identity-write methods).
        final updateCalls = fakeRepo.calls
            .where((c) => c.method == 'updateMember')
            .toList();
        expect(updateCalls, isNotEmpty);
        expect(
          fakeRepo.calls.where((c) => c.method == 'applyPluralKitLink'),
          isEmpty,
        );
        expect(
          fakeRepo.calls.where((c) => c.method == 'recordPluralKitIdentity'),
          isEmpty,
        );
      },
    );

    test('excluded local with PK-pulled bio is skipped entirely (Part 1.5 '
        'guard); the metadata write never lands', () async {
      final local = _localMember(
        id: 'local-1',
        name: 'Excluded',
        pluralkitId: 'pk001',
        pluralkitUuid: 'uuid-pk001',
        pluralkitSyncIgnored: true,
      );
      final pk = _pkMember(
        id: 'pk001',
        uuid: 'uuid-pk001',
        name: 'Excluded',
        description: 'PK bio that would clobber',
      );

      await service.syncMembers(
        localMembers: [local],
        pkMembers: [pk],
        fieldConfigs: {},
        direction: PkSyncDirection.pullOnly,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );

      // No writes of any kind on the excluded local.
      expect(fakeRepo.calls, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // M10a: per-member push isolation. One member's
  // PluralKitApiError (400 validation, 5xx) must not abort the remaining
  // members — it is counted, classified into pushSkippedMessages, and the
  // loop continues. PluralKitAuthError still aborts (M3 owns the messaging).
  // ---------------------------------------------------------------------------

  group('per-member push isolation (M10a)', () {
    String validation40001Body({
      String field = 'description',
      int max = 1000,
      int actual = 1200,
    }) => jsonEncode({
      'code': 40001,
      'message': 'Validation failed',
      'errors': {
        field: [
          {
            'message': '$field too long.',
            'max_length': max,
            'actual_length': actual,
          },
        ],
      },
    });

    domain.Member linked(String n, {String? pronouns}) => _localMember(
      id: 'local-$n',
      name: 'Member $n',
      pluralkitId: 'pk00$n',
      pluralkitUuid: 'uuid-pk00$n',
      pronouns: pronouns ?? 'pn/$n',
    );

    PKMember pkFor(String n) =>
        _pkMember(id: 'pk00$n', uuid: 'uuid-pk00$n', name: 'Member $n');

    test('one PK 400 skips that member and the rest still push', () async {
      final client = _UpdateFailureClient({
        'pk002': PluralKitApiError(
          400,
          validation40001Body(),
          code: 40001,
        ),
      });
      final callbackMessages = <String>[];

      final summary = await service.syncMembers(
        localMembers: [linked('1'), linked('2'), linked('3')],
        pkMembers: [pkFor('1'), pkFor('2'), pkFor('3')],
        fieldConfigs: {},
        direction: PkSyncDirection.pushOnly,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: client,
        onPushSkipped: callbackMessages.add,
      );

      // All three members were attempted — the pk002 failure did not abort.
      final attempted = client.calls
          .where((c) => c.method == 'updateMember')
          .map((c) => c.args[0])
          .toList();
      expect(attempted, ['pk001', 'pk002', 'pk003']);

      expect(summary.membersPushed, 2);
      expect(summary.membersSkipped, 1);
      expect(summary.pushSkippedMessages, hasLength(1));
      // The classified reason carries the member name AND the parsed 40001
      // per-field errors map (max_length/actual_length).
      final message = summary.pushSkippedMessages.single;
      expect(message, contains("'Member 2'"));
      expect(message, contains('description is 1200 characters (max 1000)'));
      expect(callbackMessages, [message]);
    });

    test('5xx is classified as a server error and isolated', () async {
      final client = _UpdateFailureClient({
        'pk001': const PluralKitApiError(502, 'bad gateway'),
      });

      final summary = await service.syncMembers(
        localMembers: [linked('1'), linked('2')],
        pkMembers: [pkFor('1'), pkFor('2')],
        fieldConfigs: {},
        direction: PkSyncDirection.pushOnly,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: client,
      );

      expect(summary.membersPushed, 1);
      expect(summary.membersSkipped, 1);
      expect(
        summary.pushSkippedMessages.single,
        contains('server error (502)'),
      );
    });

    test('auth error still aborts the whole sync (M3 upstream)', () async {
      final client = _UpdateFailureClient({
        'pk001': const PluralKitAuthError(),
      });

      await expectLater(
        service.syncMembers(
          localMembers: [linked('1'), linked('2')],
          pkMembers: [pkFor('1'), pkFor('2')],
          fieldConfigs: {},
          direction: PkSyncDirection.pushOnly,
          lastSyncDate: null,
          memberRepository: fakeRepo,
          client: client,
        ),
        throwsA(isA<PluralKitAuthError>()),
      );

      // The abort happened on the FIRST member — nothing else was attempted.
      expect(
        client.calls.where((c) => c.method == 'updateMember'),
        hasLength(1),
      );
    });

    test('sustained 429 aborts the whole sync like auth', () async {
      // PluralKitRateLimitError extends PluralKitApiError — without the
      // dedicated rethrow it would be swallowed as a per-member skip and the
      // loop would walk every remaining member into the same rate limit.
      final client = _UpdateFailureClient({
        'pk001': const PluralKitRateLimitError(),
      });

      await expectLater(
        service.syncMembers(
          localMembers: [linked('1'), linked('2')],
          pkMembers: [pkFor('1'), pkFor('2')],
          fieldConfigs: {},
          direction: PkSyncDirection.pushOnly,
          lastSyncDate: null,
          memberRepository: fakeRepo,
          client: client,
        ),
        throwsA(isA<PluralKitRateLimitError>()),
      );

      expect(
        client.calls.where((c) => c.method == 'updateMember'),
        hasLength(1),
      );
    });

    test('unlinked-local create loop isolates a 400 the same way', () async {
      final client = _CreateFailureClient({
        'Bad': PluralKitApiError(
          400,
          validation40001Body(field: 'name', max: 100, actual: 150),
          code: 40001,
        ),
      });
      // 'Bad' comes FIRST to prove the loop continues past the failure.
      final bad = _localMember(id: 'local-bad', name: 'Bad');
      final good = _localMember(id: 'local-good', name: 'Good');

      final summary = await service.syncMembers(
        localMembers: [bad, good],
        pkMembers: [],
        fieldConfigs: {},
        direction: PkSyncDirection.pushOnly,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: client,
      );

      expect(
        client.calls.where((c) => c.method == 'createMember'),
        hasLength(2),
      );
      expect(summary.membersPushed, 1);
      expect(summary.membersSkipped, 1);
      expect(summary.pushSkippedMessages.single, contains("'Bad'"));
      expect(
        summary.pushSkippedMessages.single,
        contains('name is 150 characters (max 100)'),
      );

      // Only the successful create got its PK identifiers linked back.
      final links = fakeRepo.calls
          .where((c) => c.method == 'applyPluralKitLink')
          .map((c) => c.args[0])
          .toList();
      expect(links, ['local-good']);
    });

    test('create loop still aborts on auth errors', () async {
      final client = _CreateFailureClient({
        'First': const PluralKitAuthError(),
      });
      final first = _localMember(id: 'local-1', name: 'First');
      final second = _localMember(id: 'local-2', name: 'Second');

      await expectLater(
        service.syncMembers(
          localMembers: [first, second],
          pkMembers: [],
          fieldConfigs: {},
          direction: PkSyncDirection.pushOnly,
          lastSyncDate: null,
          memberRepository: fakeRepo,
          client: client,
        ),
        throwsA(isA<PluralKitAuthError>()),
      );

      expect(
        client.calls.where((c) => c.method == 'createMember'),
        hasLength(1),
      );
    });

    test('create loop aborts on a sustained 429 like auth', () async {
      final client = _CreateFailureClient({
        'First': const PluralKitRateLimitError(),
      });
      final first = _localMember(id: 'local-1', name: 'First');
      final second = _localMember(id: 'local-2', name: 'Second');

      await expectLater(
        service.syncMembers(
          localMembers: [first, second],
          pkMembers: [],
          fieldConfigs: {},
          direction: PkSyncDirection.pushOnly,
          lastSyncDate: null,
          memberRepository: fakeRepo,
          client: client,
        ),
        throwsA(isA<PluralKitRateLimitError>()),
      );

      expect(
        client.calls.where((c) => c.method == 'createMember'),
        hasLength(1),
      );
    });

    test('client-side cap skip (M10b) surfaces without a network call', () async {
      // Bio over the 1000-char cap: the push service drops the field, the
      // payload empties to a no-op, and the skip reaches the summary. The
      // member still counts as pushed (the call "succeeded" as a no-op).
      final local = _localMember(
        id: 'local-1',
        name: 'Alice',
        pluralkitId: 'pk001',
        pluralkitUuid: 'uuid-pk001',
        bio: 'x' * 1001,
      );
      final pk = _pkMember(
        id: 'pk001',
        uuid: 'uuid-pk001',
        name: 'Alice',
        description: 'short',
      );

      final summary = await service.syncMembers(
        localMembers: [local],
        pkMembers: [pk],
        fieldConfigs: {},
        direction: PkSyncDirection.pushOnly,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );

      expect(fakeClient.calls, isEmpty);
      expect(summary.membersPushed, 1);
      final message = summary.pushSkippedMessages.single;
      expect(message, contains("'Alice'"));
      expect(message, contains('is 1001 characters (PluralKit max 1000)'));
    });

    test('pushSkippedMessages round-trips through PkSyncSummary JSON', () {
      const summary = PkSyncSummary(
        membersSkipped: 1,
        pushSkippedMessages: ['problem'],
      );
      final decoded = PkSyncSummary.fromJson(summary.toJson());
      expect(decoded.pushSkippedMessages, ['problem']);
      expect(decoded.hasSummaryDetails, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // F16: per-member DB-write isolation. A generic (non-PK-API) DB exception on
  // ONE member's link-back / identity-repair / lease write must NOT propagate
  // out of syncMembers and abort the rest of the run. It is classified as a
  // per-member skip (surfaced via pushSkippedMessages) and the loop continues.
  // PluralKitAuthError still aborts (M3 owns the messaging).
  // ---------------------------------------------------------------------------
  group('per-member DB-write isolation (F16)', () {
    domain.Member linked(String n) => _localMember(
      id: 'local-$n',
      name: 'Member $n',
      pluralkitId: 'pk00$n',
      pluralkitUuid: 'uuid-pk00$n',
      pronouns: 'pn/$n',
    );

    // PK side reports a DIFFERENT pronoun than local, forcing a push for each
    // member; the successful push then fires the identity-repair link-back —
    // the exact F16 write site.
    PKMember pkFor(String n) => _pkMember(
      id: 'pk00$n',
      uuid: 'uuid-pk00$n',
      name: 'Member $n',
    );

    test(
      'a generic DB error on one link-back skips that member, the rest sync',
      () async {
        // Member 2's link-back write throws a generic (SQLITE-like) exception;
        // members 1 and 3 must still push. The push fires because PK lacks the
        // local pronoun (a real difference) AND the link identifiers differ
        // (pluralkitUuid mismatch forces needsIdentityRepair → link-back).
        final repo = _LinkFailureRepository({'local-2'});
        final callbackMessages = <String>[];

        // Pre-seed the repo so applyPluralKitLink has rows to mutate, and give
        // each local a STALE pk uuid so needsIdentityRepair → link-back fires
        // on the push-success path.
        final locals = [
          linked('1').copyWith(pluralkitUuid: 'stale-1'),
          linked('2').copyWith(pluralkitUuid: 'stale-2'),
          linked('3').copyWith(pluralkitUuid: 'stale-3'),
        ];
        for (final m in locals) {
          await repo.createMember(m);
        }

        final summary = await service.syncMembers(
          localMembers: locals,
          pkMembers: [pkFor('1'), pkFor('2'), pkFor('3')],
          fieldConfigs: {},
          direction: PkSyncDirection.pushOnly,
          lastSyncDate: null,
          memberRepository: repo,
          client: fakeClient,
          onPushSkipped: callbackMessages.add,
        );

        // (a) syncMembers completed without throwing (we got a summary).
        // (b) the other two members still synced.
        expect(summary.membersPushed, 2);
        // (c) the failing member is counted + surfaced as a skip.
        expect(summary.membersSkipped, 1);
        expect(summary.pushSkippedMessages, hasLength(1));
        final message = summary.pushSkippedMessages.single;
        expect(message, contains("'Member 2'"));
        expect(message, contains('link-back'));
        expect(callbackMessages, [message]);

        // The link-back was attempted for all three — the loop did not abort
        // on member 2.
        final linkAttempts = repo.calls
            .where((c) => c.method == 'applyPluralKitLink')
            .map((c) => c.args[0])
            .toList();
        expect(linkAttempts, ['local-1', 'local-2', 'local-3']);
      },
    );

    test(
      'a PluralKitAuthError from a DB-write site still aborts the whole run',
      () async {
        // Defensive: even if a repository surfaced a global PK condition from a
        // write (a revoked token mid-write), it must propagate, not be
        // swallowed as a per-member skip.
        final repo = _LinkFailureRepository(
          {'local-1'},
          error: const PluralKitAuthError(),
        );
        final locals = [
          linked('1').copyWith(pluralkitUuid: 'stale-1'),
          linked('2').copyWith(pluralkitUuid: 'stale-2'),
        ];
        for (final m in locals) {
          await repo.createMember(m);
        }

        await expectLater(
          service.syncMembers(
            localMembers: locals,
            pkMembers: [pkFor('1'), pkFor('2')],
            fieldConfigs: {},
            direction: PkSyncDirection.pushOnly,
            lastSyncDate: null,
            memberRepository: repo,
            client: fakeClient,
          ),
          throwsA(isA<PluralKitAuthError>()),
        );
      },
    );
  });
}

/// Fake repository whose [applyPluralKitLink] throws for specific local ids
/// (recording the attempt first) and otherwise behaves like the base fake.
/// Exercises the F16 per-member DB-write isolation: a generic DB exception on
/// one member's link-back must not abort the whole sync run. When [error] is a
/// global PK condition (auth / rate limit), it must still propagate.
class _LinkFailureRepository extends FakeMemberRepository {
  _LinkFailureRepository(this.failingLocalIds, {Object? error})
    : error = error ?? Exception('SQLITE_BUSY: database is locked');

  /// Local member ids whose link-back write throws.
  final Set<String> failingLocalIds;

  /// The error thrown for a failing id (a generic DB error by default).
  final Object error;

  @override
  Future<int> applyPluralKitLink(String id, Map<String, dynamic> patch) {
    if (failingLocalIds.contains(id)) {
      calls.add(Call('applyPluralKitLink', [id, patch]));
      return Future.error(error);
    }
    return super.applyPluralKitLink(id, patch);
  }
}

/// Fake client whose updateMember throws a scripted error for specific PK
/// ids (recording the attempt first) and succeeds for everything else.
/// Exercises the M10a per-member isolation paths.
class _UpdateFailureClient extends FakePluralKitClient {
  _UpdateFailureClient(this.failures);

  /// PK short id → error thrown when that member is PATCHed.
  final Map<String, Exception> failures;

  @override
  Future<PKMember> updateMember(String id, Map<String, dynamic> data) {
    final error = failures[id];
    if (error != null) {
      calls.add(Call('updateMember', [id, data]));
      return Future.error(error);
    }
    return super.updateMember(id, data);
  }
}

/// Fake client whose createMember throws a scripted error for specific
/// member names (recording the attempt first). Exercises the M10a isolation
/// in the unlinked-locals create loop.
class _CreateFailureClient extends FakePluralKitClient {
  _CreateFailureClient(this.failures);

  /// Payload `name` → error thrown when that member is POSTed.
  final Map<String, Exception> failures;

  @override
  Future<PKMember> createMember(Map<String, dynamic> data) {
    final error = failures[data['name']];
    if (error != null) {
      calls.add(Call('createMember', [data]));
      return Future.error(error);
    }
    return super.createMember(data);
  }
}

/// Push service stub that immediately throws PkStaleLinkException — used to
/// exercise the per-local loop's stale-link clear branch.
class _StaleLinkOnPushService extends PkPushService {
  _StaleLinkOnPushService() : super();

  @override
  Future<String> pushMember(
    domain.Member member,
    PluralKitClient client, {
    PKMember? pkMember,
    bool includeProxyTags = true,
    Set<String>? allowedFields,
    void Function(String pkField, String reason)? onFieldSkipped,
  }) async {
    throw PkStaleLinkException(
      localId: member.id,
      pkId: member.pluralkitId ?? '',
      kind: PkStaleLinkKind.member,
      cause: const PluralKitApiError(404, 'not found'),
    );
  }
}
