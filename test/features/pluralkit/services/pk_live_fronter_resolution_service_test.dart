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
  Future<int> applyPluralKitLink(
    String id,
    Map<String, dynamic> patch,
  ) async {
    final existing = _members[id];
    if (existing == null) return 0;
    updateCount++;
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
    final existing = _members[id];
    if (existing == null) return 0;
    updateCount++;
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
    final existing = _members[id];
    if (existing == null) return 0;
    _members[id] = existing.copyWith(pluralkitSyncIgnored: true);
    return 1;
  }

  @override
  Future<int> resumePluralKitSync(String id) async {
    final existing = _members[id];
    if (existing == null) return 0;
    _members[id] = existing.copyWith(pluralkitSyncIgnored: false);
    return 1;
  }

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

  // ───────────────────────────────────────────────────────────────────────
  // 2026-06 PK audit H12a — ownership validation on fetched members.
  //
  // A stale/foreign short id can resolve to ANOTHER system's member
  // (live-verified: GET /members/zzzzz → 200, system "venus"). When the
  // fetched member declares a `system` that differs from the connected one,
  // the resolver must refuse to link/import it.
  // ───────────────────────────────────────────────────────────────────────

  group('H12a ownership validation', () {
    test('link refuses a fetched member owned by a different system', () async {
      final repo = _FakeMemberRepository([
        _local(id: 'local-1', name: 'Local Name'),
      ]);
      final client = _FakePluralKitClient(
        members: const [
          PKMember(
            id: 'zzzzz',
            uuid: 'pk-uuid-foreign',
            name: 'Stranger',
            system: 'venus', // owned by a DIFFERENT system
          ),
        ],
      );
      final service = PkLiveFronterResolutionService(
        memberRepository: repo,
        client: client,
        connectedSystemId: 'pktchv', // our connected system
      );

      await expectLater(
        service.linkCurrentFronterToLocal(
          const PkUnmappedFronterRef(pkId: 'zzzzz'),
          'local-1',
        ),
        throwsA(isA<StateError>()),
      );

      // Nothing was written — the foreign member was treated as stale.
      expect(repo.updateCount, 0);
      final local = (await repo.getMemberById('local-1'))!;
      expect(local.pluralkitId, isNull);
      expect(local.pluralkitUuid, isNull);
    });

    test('import refuses a fetched member owned by a different system',
        () async {
      final repo = _FakeMemberRepository(const []);
      final client = _FakePluralKitClient(
        members: const [
          PKMember(
            id: 'zzzzz',
            uuid: 'pk-uuid-foreign',
            name: 'Stranger',
            system: 'venus',
          ),
        ],
      );
      final service = PkLiveFronterResolutionService(
        memberRepository: repo,
        client: client,
        connectedSystemId: 'pktchv',
      );

      await expectLater(
        service.importCurrentFronter(
          const PkUnmappedFronterRef(pkId: 'zzzzz'),
        ),
        throwsA(isA<StateError>()),
      );
      // No foreign member was imported.
      expect(repo.createCount, 0);
      expect((await repo.getAllMembers()), isEmpty);
    });

    test('link proceeds when the fetched member is owned by the connected '
        'system', () async {
      final repo = _FakeMemberRepository([
        _local(id: 'local-1', name: 'Local Name'),
      ]);
      final client = _FakePluralKitClient(
        members: const [
          PKMember(
            id: 'abcde',
            uuid: 'pk-uuid-1',
            name: 'PK Name',
            displayName: 'PK Display',
            system: 'pktchv', // SAME system → ownership OK
          ),
        ],
      );
      final service = PkLiveFronterResolutionService(
        memberRepository: repo,
        client: client,
        connectedSystemId: 'pktchv',
      );

      final result = await service.linkCurrentFronterToLocal(
        const PkUnmappedFronterRef(pkId: 'abcde'),
        'local-1',
      );

      expect(result.id, 'local-1');
      final local = (await repo.getMemberById('local-1'))!;
      expect(local.pluralkitUuid, 'pk-uuid-1');
    });

    test('ownership comparison is case-insensitive (PK hids are)', () async {
      // PK accepts uppercase hids; an uppercase `system` echo must not be
      // mistaken for a foreign owner (wave-3 nit: H2 lowercase convention).
      final repo = _FakeMemberRepository([
        _local(id: 'local-1', name: 'Local Name'),
      ]);
      final client = _FakePluralKitClient(
        members: const [
          PKMember(
            id: 'abcde',
            uuid: 'pk-uuid-1',
            name: 'PK Name',
            system: 'PKTCHV', // uppercase echo of the same system
          ),
        ],
      );
      final service = PkLiveFronterResolutionService(
        memberRepository: repo,
        client: client,
        connectedSystemId: 'pktchv',
      );

      final result = await service.linkCurrentFronterToLocal(
        const PkUnmappedFronterRef(pkId: 'abcde'),
        'local-1',
      );
      expect(result.id, 'local-1');
      expect((await repo.getMemberById('local-1'))!.pluralkitUuid, 'pk-uuid-1');
    });

    test('link proceeds when connectedSystemId is unknown (null) even if a '
        'system field is present', () async {
      // Ownership is unknowable → keep current behavior, do not block.
      final repo = _FakeMemberRepository([
        _local(id: 'local-1', name: 'Local Name'),
      ]);
      final client = _FakePluralKitClient(
        members: const [
          PKMember(
            id: 'abcde',
            uuid: 'pk-uuid-1',
            name: 'PK Name',
            system: 'venus',
          ),
        ],
      );
      final service = PkLiveFronterResolutionService(
        memberRepository: repo,
        client: client,
        // connectedSystemId omitted → null.
      );

      final result = await service.linkCurrentFronterToLocal(
        const PkUnmappedFronterRef(pkId: 'abcde'),
        'local-1',
      );
      expect(result.id, 'local-1');
      expect((await repo.getMemberById('local-1'))!.pluralkitUuid, 'pk-uuid-1');
    });
  });

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

  // ───────────────────────────────────────────────────────────────────────
  // PR 2 — Part 1.5 guard + Part 1.7 method routing on live-fronter paths.
  //
  // Plan: docs/plans/2026-05-26-pluralkit-link-management.md
  // ───────────────────────────────────────────────────────────────────────

  group('PR 2: importCurrentFronter on excluded matched local', () {
    test('skips excluded linked local entirely (no method write, returns '
        'existing member)', () async {
      final excludedLocal = _local(
        id: 'local-excluded',
        name: 'Excluded',
        pluralkitId: 'abcde',
        pluralkitUuid: 'pk-uuid-1',
        ignored: true,
      );
      final repo = _RecordingMemberRepository([excludedLocal]);
      final client = _FakePluralKitClient(
        members: const [
          PKMember(
            id: 'abcde',
            uuid: 'pk-uuid-1',
            name: 'Updated PK Name',
            displayName: 'Updated PK Display',
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

      expect(result.id, 'local-excluded');
      // No new identifier writes — guard fired before the method call.
      expect(repo.applyLinkCalls, isEmpty);
      expect(repo.recordIdentityCalls, isEmpty);
      // Exclude marker preserved.
      final stored = await repo.getMemberById('local-excluded');
      expect(stored!.pluralkitSyncIgnored, isTrue);
    });
  });

  group(
    'PR 2: importCurrentFronter on non-excluded partial link uses '
    'recordPluralKitIdentity',
    () {
      test('completes partial link without flipping sync_ignored', () async {
        // Local has the short PK id but no UUID — needs completion. Was NOT
        // excluded, so completion proceeds. importCurrentFronter passes
        // clearIgnored: false → routes through recordPluralKitIdentity.
        final partialLocal = _local(
          id: 'local-1',
          name: 'Partial',
          pluralkitId: 'abcde',
          // no UUID — _completeIdentityIfNeeded will fill it.
        );
        final repo = _RecordingMemberRepository([partialLocal]);
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

        await service.importCurrentFronter(
          const PkUnmappedFronterRef(pkId: 'abcde'),
        );

        // Goes through recordPluralKitIdentity (preserves sync state).
        expect(repo.applyLinkCalls, isEmpty);
        expect(repo.recordIdentityCalls, hasLength(1));
        expect(repo.recordIdentityCalls.single.memberId, 'local-1');
        final patch = repo.recordIdentityCalls.single.patch;
        // Always-include-uuid pattern: uuid is in every patch.
        expect(patch['pluralkit_uuid'], 'pk-uuid-1');
        // No sync_ignored key — the method asserts against any value.
        expect(patch.containsKey('pluralkit_sync_ignored'), isFalse);
      });
    },
  );

  group('PR 2: linkCurrentFronterToLocal (user-driven)', () {
    test('uses applyPluralKitLink and resumes sync', () async {
      final local = _local(id: 'local-1', name: 'Local');
      final repo = _RecordingMemberRepository([local]);
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

      await service.linkCurrentFronterToLocal(
        const PkUnmappedFronterRef(pkId: 'abcde'),
        'local-1',
      );

      // applyPluralKitLink (NOT recordPluralKitIdentity).
      expect(repo.applyLinkCalls, hasLength(1));
      expect(repo.recordIdentityCalls, isEmpty);
      final stored = await repo.getMemberById('local-1');
      expect(stored!.pluralkitSyncIgnored, isFalse);
    });

    test('on previously-excluded member resumes sync WITHOUT triggering '
        'applyPluralKitLink no-sync_ignored assert (v7 narrow-patch '
        'migration)', () async {
      // Local was excluded — link should resume sync via the explicit user
      // action. The v7 migration uses an explicit narrow patch so the
      // assert on sync_ignored doesn't fire on a stale-Member full-domain
      // diff path.
      final excluded = _local(
        id: 'local-1',
        name: 'Was Excluded',
        pluralkitId: 'abcde',
        pluralkitUuid: 'old-uuid',
        ignored: true,
      );
      final repo = _RecordingMemberRepository([excluded]);
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

      // Should NOT throw the assertion. The narrow patch from
      // _completeIdentityIfNeeded omits pluralkit_sync_ignored so the
      // method's force-injection is the sole writer.
      await service.linkCurrentFronterToLocal(
        const PkUnmappedFronterRef(pkId: 'abcde'),
        'local-1',
      );

      expect(repo.applyLinkCalls, hasLength(1));
      final patch = repo.applyLinkCalls.single.patch;
      expect(patch.containsKey('pluralkit_sync_ignored'), isFalse,
          reason: 'narrow patch must not pass sync_ignored to the method');
      final stored = await repo.getMemberById('local-1');
      expect(stored!.pluralkitSyncIgnored, isFalse);
    });

    test(
      'on previously-excluded member where uuid/id/displayName ALL already '
      'match PK still resumes sync (v8 always-include-pluralkit_uuid fix)',
      () async {
        // Setup: an excluded local that's already fully linked to the PK
        // member; nothing to update except sync_ignored. Without v8's
        // "always include uuid" fix, the conditional diff patch would be
        // empty and applyPluralKitLink's "requires uuid or id" assert
        // would fire (v7 Bug A regressed silently).
        final fullyMatching = _local(
          id: 'local-1',
          name: 'Local',
          pluralkitId: 'abcde',
          pluralkitUuid: 'pk-uuid-1',
          pluralkitDisplayName: 'PK Display',
          ignored: true,
        );
        final repo = _RecordingMemberRepository([fullyMatching]);
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

        await service.linkCurrentFronterToLocal(
          const PkUnmappedFronterRef(pkId: 'abcde'),
          'local-1',
        );

        // applyPluralKitLink was called (no silent no-op).
        expect(repo.applyLinkCalls, hasLength(1));
        final patch = repo.applyLinkCalls.single.patch;
        // pluralkit_uuid is always included so the patch never empties out.
        expect(patch['pluralkit_uuid'], 'pk-uuid-1');
        // Conditional keys absent because they already match (the diff
        // condition was false).
        expect(patch.containsKey('pluralkit_id'), isFalse);
        expect(patch.containsKey('pluralkit_display_name'), isFalse);
        // Sync resumed.
        final stored = await repo.getMemberById('local-1');
        expect(stored!.pluralkitSyncIgnored, isFalse);
      },
    );
  });
}

/// Subclass of _FakeMemberRepository that records calls to the PR 2
/// PK-link methods so tests can assert which method handled a given write.
class _RecordingMemberRepository extends _FakeMemberRepository {
  _RecordingMemberRepository(super.seed);

  final List<({String memberId, Map<String, dynamic> patch})> applyLinkCalls =
      [];
  final List<({String memberId, Map<String, dynamic> patch})>
  recordIdentityCalls = [];

  @override
  Future<int> applyPluralKitLink(
    String id,
    Map<String, dynamic> patch,
  ) async {
    applyLinkCalls.add((memberId: id, patch: Map.of(patch)));
    return super.applyPluralKitLink(id, patch);
  }

  @override
  Future<int> recordPluralKitIdentity(
    String id,
    Map<String, dynamic> patch,
  ) async {
    recordIdentityCalls.add((memberId: id, patch: Map.of(patch)));
    return super.recordPluralKitIdentity(id, patch);
  }
}
