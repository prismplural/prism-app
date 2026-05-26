import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_live_fronters_notice.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_live_fronter_resolution_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';

class _FakeMemberRepository implements MemberRepository {
  final Map<String, domain.Member> _members = {};
  int createCount = 0;
  int updateCount = 0;

  _FakeMemberRepository(Iterable<domain.Member> seed) {
    for (final member in seed) {
      _members[member.id] = member;
    }
  }

  @override
  Future<List<domain.Member>> getAllMembers() async =>
      _members.values.where((member) => !member.isDeleted).toList();

  @override
  Future<List<domain.Member>> getAllMembersIncludingDeleted() async =>
      _members.values.toList();

  @override
  Future<domain.Member?> getMemberById(String id) async => _members[id];

  @override
  Future<void> createMember(domain.Member member) async {
    createCount++;
    _members[member.id] = member;
  }

  @override
  Future<void> updateMember(domain.Member member) async {
    updateCount++;
    _members[member.id] = member;
  }

  @override
  Future<int> updateMemberFields(
    String id,
    Map<String, dynamic> changedFields,
  ) async => throw UnimplementedError();

  @override
  Future<void> deleteMember(String id) async {
    final member = _members[id];
    if (member != null) {
      _members[id] = member.copyWith(isDeleted: true);
    }
  }

  @override
  Future<int> getCount() async => _members.length;

  @override
  Future<List<domain.Member>> getMembersByIds(List<String> ids) async =>
      ids.map((id) => _members[id]).whereType<domain.Member>().toList();

  @override
  Stream<List<domain.Member>> watchAllMembers() =>
      Stream.value(_members.values.toList());

  @override
  Stream<List<domain.Member>> watchActiveMembers() =>
      Stream.value(_members.values.where((member) => member.isActive).toList());

  @override
  Stream<domain.Member?> watchMemberById(String id) =>
      Stream.value(_members[id]);

  @override
  Stream<List<domain.Member>> watchMembersByIds(List<String> ids) =>
      Stream.value(
        ids.map((id) => _members[id]).whereType<domain.Member>().toList(),
      );

  @override
  Future<List<domain.Member>> getDeletedLinkedMembers() async => _members.values
      .where(
        (member) =>
            member.isDeleted &&
            ((member.pluralkitId ?? '').isNotEmpty ||
                (member.pluralkitUuid ?? '').isNotEmpty),
      )
      .toList();

  @override
  Future<void> clearPluralKitLink(String id) async {
    final member = _members[id];
    if (member != null) {
      _members[id] = member.copyWith(pluralkitId: null, pluralkitUuid: null);
    }
  }

  @override
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) async {}

  @override
  Future<({domain.Member member, bool wasCreated})>
  ensureUnknownSentinelMember() => throw UnimplementedError();
}

class _FakePluralKitClient extends PluralKitClient {
  final List<PKMember> members;
  final Map<String, List<int>> avatarBytes;
  final List<String> getMemberRefs = [];
  final List<String> downloadedUrls = [];
  int getMembersCallCount = 0;

  _FakePluralKitClient({
    this.members = const <PKMember>[],
    this.avatarBytes = const <String, List<int>>{},
  }) : super(token: 'fake', httpClient: http.Client());

  @override
  Future<PKMember> getMember(String memberRef) async {
    getMemberRefs.add(memberRef);
    return members.firstWhere(
      (member) => member.id == memberRef || member.uuid == memberRef,
    );
  }

  @override
  Future<List<PKMember>> getMembers() async {
    getMembersCallCount++;
    throw StateError('getMembers must not be called for live-fronter resolve');
  }

  @override
  Future<List<int>> downloadBytes(String url) async {
    downloadedUrls.add(url);
    return avatarBytes[url] ?? const <int>[];
  }
}

domain.Member _local({
  required String id,
  required String name,
  String? pluralkitId,
  String? pluralkitUuid,
  String? pluralkitDisplayName,
  String? pronouns,
  String? bio,
  bool ignored = false,
  bool isDeleted = false,
}) {
  return domain.Member(
    id: id,
    name: name,
    pronouns: pronouns,
    bio: bio,
    createdAt: DateTime.utc(2026),
    pluralkitId: pluralkitId,
    pluralkitUuid: pluralkitUuid,
    pluralkitDisplayName: pluralkitDisplayName,
    pluralkitSyncIgnored: ignored,
    isDeleted: isDeleted,
  );
}

void main() {
  test(
    'link fetches missing UUID and writes only PK mapping metadata',
    () async {
      final repo = _FakeMemberRepository([
        _local(
          id: 'local-1',
          name: 'Local Name',
          pronouns: 'local pronouns',
          bio: 'local bio',
          ignored: true,
        ),
      ]);
      final client = _FakePluralKitClient(
        members: const [
          PKMember(
            id: 'abcde',
            uuid: 'pk-uuid-1',
            name: 'PK Name',
            displayName: 'PK Display',
            pronouns: 'pk pronouns',
            description: 'pk bio',
            avatarUrl: 'https://cdn.example/avatar.png',
          ),
        ],
      );
      final service = PkLiveFronterResolutionService(
        memberRepository: repo,
        client: client,
      );

      final result = await service.linkCurrentFronterToLocal(
        const PkUnmappedFronterRef(pkId: 'abcde'),
        'local-1',
      );

      expect(client.getMemberRefs, ['abcde']);
      expect(client.getMembersCallCount, 0);
      expect(client.downloadedUrls, isEmpty);
      expect(result.id, 'local-1');

      final updated = (await repo.getMemberById('local-1'))!;
      expect(updated.name, 'Local Name');
      expect(updated.pronouns, 'local pronouns');
      expect(updated.bio, 'local bio');
      expect(updated.pluralkitId, 'abcde');
      expect(updated.pluralkitUuid, 'pk-uuid-1');
      expect(updated.pluralkitDisplayName, 'PK Display');
      expect(updated.pluralkitSyncIgnored, isFalse);
    },
  );

  test(
    'import fetches missing UUID and creates one minimal local member',
    () async {
      final repo = _FakeMemberRepository(const []);
      final client = _FakePluralKitClient(
        members: const [
          PKMember(
            id: 'abcde',
            uuid: 'pk-uuid-1',
            name: 'PK Name',
            displayName: 'PK Display',
            pronouns: 'pk pronouns',
            description: 'pk bio',
            color: 'ff00ff',
            avatarUrl: 'https://cdn.example/avatar.png',
            bannerUrl: 'https://cdn.example/banner.png',
            hasBannerField: true,
          ),
        ],
      );
      final service = PkLiveFronterResolutionService(
        memberRepository: repo,
        client: client,
        now: () => DateTime.utc(2026, 5, 1),
      );

      final result = await service.importCurrentFronter(
        const PkUnmappedFronterRef(pkId: 'abcde'),
      );

      expect(client.getMemberRefs, ['abcde']);
      expect(client.downloadedUrls, isEmpty);
      expect(repo.createCount, 1);
      expect((await repo.getAllMembers()), hasLength(1));
      expect(result.name, 'PK Name');
      expect(result.pluralkitId, 'abcde');
      expect(result.pluralkitUuid, 'pk-uuid-1');
      expect(result.pluralkitDisplayName, 'PK Display');
      expect(result.pronouns, isNull);
      expect(result.bio, isNull);
      expect(result.customColorHex, isNull);
      expect(result.pkBannerUrl, isNull);
      expect(result.avatarImageData, isNull);
    },
  );

  test('fallback fetch must return UUID before any local write', () async {
    final repo = _FakeMemberRepository([
      _local(id: 'local-1', name: 'Local Name'),
    ]);
    final client = _FakePluralKitClient(
      members: const [PKMember(id: 'abcde', uuid: '', name: 'PK Name')],
    );
    final service = PkLiveFronterResolutionService(
      memberRepository: repo,
      client: client,
    );

    await expectLater(
      service.linkCurrentFronterToLocal(
        const PkUnmappedFronterRef(pkId: 'abcde'),
        'local-1',
      ),
      throwsStateError,
    );

    expect(repo.createCount, 0);
    expect(repo.updateCount, 0);
    final local = (await repo.getMemberById('local-1'))!;
    expect(local.pluralkitId, isNull);
    expect(local.pluralkitUuid, isNull);
  });

  test(
    'import does not fetch or download avatar by default when ref is full',
    () async {
      final repo = _FakeMemberRepository(const []);
      final client = _FakePluralKitClient();
      final service = PkLiveFronterResolutionService(
        memberRepository: repo,
        client: client,
      );

      final result = await service.importCurrentFronter(
        const PkUnmappedFronterRef(
          pkId: 'abcde',
          pkUuid: 'pk-uuid-1',
          name: 'PK Name',
          displayName: 'PK Display',
          avatarUrl: 'https://cdn.example/avatar.png',
        ),
      );

      expect(client.getMemberRefs, isEmpty);
      expect(client.downloadedUrls, isEmpty);
      expect(result.avatarImageData, isNull);
    },
  );

  test('import downloads avatar only when opted in', () async {
    final repo = _FakeMemberRepository(const []);
    final client = _FakePluralKitClient(
      avatarBytes: const {
        'https://cdn.example/avatar.png': [1, 2, 3],
      },
    );
    final service = PkLiveFronterResolutionService(
      memberRepository: repo,
      client: client,
    );

    final result = await service.importCurrentFronter(
      const PkUnmappedFronterRef(
        pkId: 'abcde',
        pkUuid: 'pk-uuid-1',
        name: 'PK Name',
        avatarUrl: 'https://cdn.example/avatar.png',
      ),
      includeAvatar: true,
    );

    expect(client.downloadedUrls, ['https://cdn.example/avatar.png']);
    expect(result.avatarImageData, [1, 2, 3]);
  });

  test(
    'import completes an existing short-id collision without duplicating',
    () async {
      final repo = _FakeMemberRepository([
        _local(id: 'existing', name: 'Existing', pluralkitId: 'abcde'),
      ]);
      final client = _FakePluralKitClient(
        members: const [
          PKMember(
            id: 'abcde',
            uuid: 'pk-uuid-1',
            name: 'PK Name',
            displayName: 'PK Display',
          ),
        ],
      );
      final service = PkLiveFronterResolutionService(
        memberRepository: repo,
        client: client,
      );

      final result = await service.importCurrentFronter(
        const PkUnmappedFronterRef(pkId: 'abcde'),
      );

      expect(result.id, 'existing');
      expect(repo.createCount, 0);
      expect(repo.updateCount, 1);
      expect((await repo.getAllMembers()), hasLength(1));
      final existing = (await repo.getMemberById('existing'))!;
      expect(existing.pluralkitUuid, 'pk-uuid-1');
      expect(existing.pluralkitDisplayName, 'PK Display');
    },
  );

  test(
    'link fails on UUID/ID collision and leaves selected target unchanged',
    () async {
      final repo = _FakeMemberRepository([
        _local(id: 'owner', name: 'Owner', pluralkitId: 'abcde'),
        _local(id: 'target', name: 'Target'),
      ]);
      final client = _FakePluralKitClient();
      final service = PkLiveFronterResolutionService(
        memberRepository: repo,
        client: client,
      );

      await expectLater(
        service.linkCurrentFronterToLocal(
          const PkUnmappedFronterRef(
            pkId: 'abcde',
            pkUuid: 'pk-uuid-1',
            name: 'PK Name',
            displayName: 'PK Display',
          ),
          'target',
        ),
        throwsA(isA<StateError>()),
      );

      final owner = (await repo.getMemberById('owner'))!;
      final target = (await repo.getMemberById('target'))!;
      expect(owner.pluralkitUuid, isNull);
      expect(owner.pluralkitDisplayName, isNull);
      expect(target.pluralkitId, isNull);
      expect(target.pluralkitUuid, isNull);
      expect(repo.updateCount, 0);
    },
  );

  test('import fails when a deleted member still owns the PK link', () async {
    final repo = _FakeMemberRepository([
      _local(
        id: 'deleted-owner',
        name: 'Deleted',
        pluralkitUuid: 'pk-uuid-1',
        isDeleted: true,
      ),
    ]);
    final client = _FakePluralKitClient();
    final service = PkLiveFronterResolutionService(
      memberRepository: repo,
      client: client,
    );

    await expectLater(
      service.importCurrentFronter(
        const PkUnmappedFronterRef(
          pkId: 'abcde',
          pkUuid: 'pk-uuid-1',
          name: 'PK Name',
        ),
      ),
      throwsA(isA<StateError>()),
    );
    expect(repo.createCount, 0);
    expect(repo.updateCount, 0);
  });
}
