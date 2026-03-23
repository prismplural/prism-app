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

class _Call {
  final String method;
  final List<dynamic> args;
  _Call(this.method, this.args);
}

class FakePluralKitClient implements PluralKitClient {
  final List<_Call> calls = [];
  int _idCounter = 0;

  @override
  Future<PKMember> createMember(Map<String, dynamic> data) async {
    _idCounter++;
    final id = 'pk${_idCounter.toString().padLeft(3, '0')}';
    calls.add(_Call('createMember', [data]));
    return PKMember(
      id: id,
      uuid: 'uuid-$id',
      name: data['name'] as String? ?? '',
    );
  }

  @override
  Future<PKMember> updateMember(String id, Map<String, dynamic> data) async {
    calls.add(_Call('updateMember', [id, data]));
    return PKMember(id: id, uuid: 'uuid-$id', name: data['name'] as String? ?? '');
  }

  @override
  Future<PKSwitch> createSwitch(List<String> memberIds,
      {DateTime? timestamp}) async {
    calls.add(_Call('createSwitch', [memberIds]));
    return PKSwitch(
      id: 'sw-1',
      timestamp: timestamp ?? DateTime.now(),
      members: memberIds,
    );
  }

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
  void dispose() {}
}

class FakeMemberRepository implements MemberRepository {
  final List<_Call> calls = [];
  final Map<String, domain.Member> _members = {};

  @override
  Future<void> updateMember(domain.Member member) async {
    calls.add(_Call('updateMember', [member]));
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
}) {
  return PKMember(
    id: id,
    uuid: uuid,
    name: name,
    displayName: displayName,
    pronouns: pronouns,
    description: description,
    color: color,
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
}
