import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_bidirectional_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_push_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_request_queue.dart';
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
  final List<Call> calls = [];
  int _idCounter = 0;

  @override
  Future<PKMember> createMember(Map<String, dynamic> data) async {
    _idCounter++;
    final id = 'pk${_idCounter.toString().padLeft(3, '0')}';
    calls.add(Call('createMember', [data]));
    return PKMember(
      id: id,
      uuid: 'uuid-$id',
      name: data['name'] as String? ?? '',
    );
  }

  @override
  Future<PKMember> updateMember(String id, Map<String, dynamic> data) async {
    calls.add(Call('updateMember', [id, data]));
    return PKMember(id: id, uuid: 'uuid-$id', name: data['name'] as String? ?? '');
  }

  @override
  Future<PKSwitch> createSwitch(List<String> memberIds,
      {DateTime? timestamp}) async {
    calls.add(Call('createSwitch', [memberIds]));
    return PKSwitch(
      id: 'sw-1',
      timestamp: timestamp ?? DateTime.now(),
      members: memberIds,
    );
  }

  @override
  Future<PKSwitch> updateSwitch(String switchId,
          {required DateTime timestamp}) =>
      throw UnimplementedError();

  @override
  Future<PKSwitch> updateSwitchMembers(
          String switchId, List<String> memberIds) =>
      throw UnimplementedError();

  @override
  Future<void> deleteSwitch(String switchId) => throw UnimplementedError();

  @override
  Future<PKSystem> getSystem() => throw UnimplementedError();
  @override
  Future<List<PKMember>> getMembers() => throw UnimplementedError();
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
  Future<List<domain.Member>> getAllMembers() async => _members.values.toList();
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
  Future<int> getCount() async => _members.length;

  @override
  Future<List<domain.Member>> getDeletedLinkedMembers() async => const [];
  @override
  Future<void> clearPluralKitLink(String id) async {}
  @override
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) async {}
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
  String? birthday,
  String? proxyTagsJson,
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
    birthday: birthday,
    proxyTagsJson: proxyTagsJson,
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
    service = PkBidirectionalService(
      pushService: PkPushService(queue: PkRequestQueue()),
    );
  });

  group('pullOnly direction', () {
    test('only counts pulls, does not push', () async {
      // A PK member with no local counterpart
      final pkMembers = [_pkMember(id: 'pk001', uuid: 'uuid-pk001', name: 'Remote')];

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
      final pkMembers = [_pkMember(id: 'pk001', uuid: 'uuid-pk001', name: 'Remote')];

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

    test('new local member pushed and pkId stored', () async {
      final localMembers = [
        _localMember(id: 'local-1', name: 'NewMember'),
      ];

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
      expect(
        fakeClient.calls.any((c) => c.method == 'createMember'),
        isTrue,
      );
      // Should have stored the PK ID back via memberRepository.updateMember
      expect(
        fakeRepo.calls.any((c) => c.method == 'updateMember'),
        isTrue,
      );
      final updatedMember =
          (fakeRepo.calls.first.args[0] as domain.Member);
      expect(updatedMember.pluralkitId, isNotNull);
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
    test('pulls name difference and writes via updateMember', () async {
      final local = _localMember(
        id: 'local-1',
        name: 'OldName',
        pluralkitId: 'pk001',
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

      expect(summary.membersPulled, 1);
      expect(summary.membersSkipped, 0);
      final calls =
          fakeRepo.calls.where((c) => c.method == 'updateMember').toList();
      expect(calls.length, 1);
      final written = calls.first.args[0] as domain.Member;
      expect(written.name, 'NewName');
    });

    test('pulls displayName', () async {
      final local = _localMember(
        id: 'local-1',
        pluralkitId: 'pk001',
        displayName: null,
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

      final written = fakeRepo.calls
          .firstWhere((c) => c.method == 'updateMember')
          .args[0] as domain.Member;
      expect(written.displayName, 'Ali');
    });

    test('pulls birthday', () async {
      final local = _localMember(
        id: 'local-1',
        pluralkitId: 'pk001',
      );
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

      final written = fakeRepo.calls
          .firstWhere((c) => c.method == 'updateMember')
          .args[0] as domain.Member;
      expect(written.birthday, '2020-01-15');
    });

    test('pulls year-0004 birthday sentinel unchanged', () async {
      final local = _localMember(
        id: 'local-1',
        pluralkitId: 'pk001',
      );
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

      final written = fakeRepo.calls
          .firstWhere((c) => c.method == 'updateMember')
          .args[0] as domain.Member;
      expect(written.birthday, '0004-03-21');
    });

    test('pulls proxyTagsJson (pull-only, regardless of direction)', () async {
      final local = _localMember(
        id: 'local-1',
        pluralkitId: 'pk001',
      );
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

      final written = fakeRepo.calls
          .firstWhere((c) => c.method == 'updateMember')
          .args[0] as domain.Member;
      expect(written.proxyTagsJson, '[{"prefix":"A:","suffix":null}]');
    });

    test('bidirectional: PK proxyTagsJson overwrites divergent local value',
        () async {
      // Proxy tags are pull-only by design. Even in bidirectional mode, a
      // local edit to proxyTagsJson loses to PK on the next sync — this
      // locks current behavior and protects against silent regressions.
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

      final written = fakeRepo.calls
          .firstWhere((c) => c.method == 'updateMember')
          .args[0] as domain.Member;
      expect(written.proxyTagsJson, '[{"prefix":"PK:","suffix":null}]');
    });

    test('push payload never includes proxy_tags', () async {
      // A local displayName change forces a push. The request sent to
      // PK must not carry a proxy_tags key, even if the local value
      // differs from PK's.
      final local = _localMember(
        id: 'local-1',
        pluralkitId: 'pk001',
        displayName: 'NewDisplay',
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
        fieldConfigs: {},
        direction: PkSyncDirection.bidirectional,
        lastSyncDate: null,
        memberRepository: fakeRepo,
        client: fakeClient,
      );

      final updateCall = fakeClient.calls
          .firstWhere((c) => c.method == 'updateMember');
      final payload = updateCall.args[1] as Map<String, dynamic>;
      expect(payload.containsKey('proxy_tags'), isFalse);
    });

    test('no-op when nothing differs', () async {
      final local = _localMember(
        id: 'local-1',
        name: 'Same',
        pronouns: 'she/her',
        bio: 'hello',
        pluralkitId: 'pk001',
        displayName: 'SameDisplay',
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

      final written = fakeRepo.calls
          .firstWhere((c) => c.method == 'updateMember')
          .args[0] as domain.Member;
      expect(written.pronouns, isNull);
    });

    test('respects per-field pull=disabled: does not pull that field',
        () async {
      final local = _localMember(
        id: 'local-1',
        pluralkitId: 'pk001',
        displayName: 'LocalOnly',
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

      // displayName shouldn't have been pulled. The push path will fire
      // instead because local has a different value and push is enabled.
      // But that's fine — the point is memberRepository.updateMember was
      // NOT called with a changed displayName.
      final updateMemberCalls =
          fakeRepo.calls.where((c) => c.method == 'updateMember');
      for (final c in updateMemberCalls) {
        final m = c.args[0] as domain.Member;
        expect(m.displayName, 'LocalOnly');
      }
    });
  });

  // -------------------------------------------------------------------------
  // _memberToPayload null-clearing (via pk_push_service's PATCH)
  // -------------------------------------------------------------------------

  group('push null-clear safety (plan 08 first-link semantics)', () {
    test('does NOT push when local pronouns null and PK has a value',
        () async {
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
      final updateCall = fakeClient.calls
          .firstWhere((c) => c.method == 'updateMember');
      final payload = updateCall.args[1] as Map<String, dynamic>;
      expect(payload['pronouns'], 'they/them');
    });
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
  // Silent-rename migration — pre-phase-3 fallback (pk.displayName ?? pk.name)
  // -------------------------------------------------------------------------

  group('displayName migration from legacy local.name', () {
    test(
        'local.displayName null + local.name == pk.displayName → promote, do NOT rename',
        () async {
      // Pre-phase-3, local.name was set from pk.displayName (fallback).
      // Phase 3 must promote that to displayName, not silently rename.
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
      expect(updated.displayName, 'Alice ✨',
          reason: 'Legacy local.name must migrate into displayName');
      expect(updated.name, 'alice',
          reason: 'local.name then follows pk.name');
    });

    test('non-legacy case: local.displayName already set → normal pull',
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

      final updated = fakeRepo.calls
          .where((c) => c.method == 'updateMember')
          .last
          .args[0] as domain.Member;
      expect(updated.name, 'alice');
      expect(updated.displayName, 'Alice 🌟');
    });
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

      final updateCall = fakeClient.calls
          .firstWhere((c) => c.method == 'updateMember');
      final payload = updateCall.args[1] as Map<String, dynamic>;
      expect(payload.containsKey('color'), isFalse,
          reason:
              'customColorEnabled=false must OMIT color, never send null to clear PK');
    });
  });
}
