import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/pk_mapping_state_dao.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_mapping_applier.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_push_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';

/// In-memory member repo — minimum surface the applier touches.
class FakeMemberRepo implements MemberRepository {
  final Map<String, domain.Member> _byId = {};

  FakeMemberRepo(Iterable<domain.Member> seed) {
    for (final m in seed) {
      _byId[m.id] = m;
    }
  }

  @override
  Future<List<domain.Member>> getAllMembers() async => _byId.values.toList();

  @override
  Future<domain.Member?> getMemberById(String id) async => _byId[id];

  @override
  Future<void> createMember(domain.Member member) async =>
      _byId[member.id] = member;

  @override
  Future<void> updateMember(domain.Member member) async =>
      _byId[member.id] = member;

  @override
  Future<void> deleteMember(String id) async => _byId.remove(id);

  @override
  Future<int> getCount() async => _byId.length;

  @override
  Future<List<domain.Member>> getMembersByIds(List<String> ids) async =>
      ids.map((id) => _byId[id]).whereType<domain.Member>().toList();

  @override
  Stream<List<domain.Member>> watchMembersByIds(List<String> ids) =>
      throw UnimplementedError();

  @override
  Stream<List<domain.Member>> watchActiveMembers() =>
      Stream.value(_byId.values.where((m) => m.isActive).toList());

  @override
  Stream<List<domain.Member>> watchAllMembers() =>
      Stream.value(_byId.values.toList());

  @override
  Stream<domain.Member?> watchMemberById(String id) =>
      Stream.value(_byId[id]);

  @override
  Future<List<domain.Member>> getDeletedLinkedMembers() async => const [];
  @override
  Future<void> clearPluralKitLink(String id) async {}
  @override
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) async {}

  @override
  Future<({domain.Member member, bool wasCreated})>
      ensureUnknownSentinelMember() => throw UnimplementedError();
}

/// Stubs PluralKitClient; we only need createMember + getMembers + updateMember.
class FakePluralKitClient extends PluralKitClient {
  final List<PKMember> allMembers;
  final List<Map<String, dynamic>> createdPayloads = [];
  int createCallCount = 0;
  PKMember Function(Map<String, dynamic>)? onCreate;
  final Map<String, List<int>> avatarBytes;
  final List<String> downloadedUrls = [];
  Object? downloadError;

  FakePluralKitClient({
    List<PKMember>? members,
    this.onCreate,
    Map<String, List<int>>? avatarBytes,
    this.downloadError,
  })  : allMembers = members ?? [],
        avatarBytes = avatarBytes ?? {},
        super(token: 'fake-token', httpClient: http.Client());

  @override
  Future<List<PKMember>> getMembers() async => allMembers;

  @override
  Future<PKMember> createMember(Map<String, dynamic> data) async {
    createCallCount++;
    createdPayloads.add(data);
    final result = onCreate?.call(data) ??
        PKMember(
          id: 'abcde',
          uuid: 'new-uuid-${createdPayloads.length}',
          name: data['name'] as String,
        );
    allMembers.add(result);
    return result;
  }

  @override
  Future<PKMember> updateMember(String id, Map<String, dynamic> data) async {
    return PKMember(id: id, uuid: 'existing-uuid', name: data['name'] as String);
  }

  @override
  Future<List<int>> downloadBytes(String url) async {
    downloadedUrls.add(url);
    if (downloadError != null) throw downloadError!;
    return avatarBytes[url] ?? const [];
  }
}

domain.Member _local({
  required String id,
  required String name,
  String? pluralkitUuid,
  String? pluralkitId,
  bool ignored = false,
}) {
  return domain.Member(
    id: id,
    name: name,
    createdAt: DateTime(2026),
    pluralkitUuid: pluralkitUuid,
    pluralkitId: pluralkitId,
    pluralkitSyncIgnored: ignored,
  );
}

void main() {
  late AppDatabase db;
  late PkMappingStateDao dao;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = PkMappingStateDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  PkMappingApplier buildApplier({
    required FakeMemberRepo repo,
    required FakePluralKitClient client,
  }) {
    return PkMappingApplier(
      members: repo,
      state: dao,
      pushService: const PkPushService(),
      client: client,
    );
  }

  test('link writes pluralkit fields to local member', () async {
    final repo = FakeMemberRepo([_local(id: 'l1', name: 'Alice')]);
    final client = FakePluralKitClient();
    final applier = buildApplier(repo: repo, client: client);

    const pk = PKMember(id: 'abcde', uuid: 'u-1', name: 'Alice');
    final results = await applier.apply([
      const PkLinkDecision(localMemberId: 'l1', pkMember: pk),
    ]);

    expect(results.single.outcome, PkApplyOutcome.applied);
    final updated = await repo.getMemberById('l1');
    expect(updated!.pluralkitUuid, 'u-1');
    expect(updated.pluralkitId, 'abcde');

    final state = await dao.getById('link:u-1');
    expect(state!.status, 'applied');
  });

  test('link is idempotent — re-applying returns alreadyApplied', () async {
    final repo = FakeMemberRepo([_local(id: 'l1', name: 'Alice')]);
    final client = FakePluralKitClient();
    final applier = buildApplier(repo: repo, client: client);
    const pk = PKMember(id: 'abcde', uuid: 'u-1', name: 'Alice');
    final decisions = [
      const PkLinkDecision(localMemberId: 'l1', pkMember: pk),
    ];
    await applier.apply(decisions);
    final results = await applier.apply(decisions);
    expect(results.single.outcome, PkApplyOutcome.alreadyApplied);
  });

  test('import creates new local member with PK fields', () async {
    final repo = FakeMemberRepo([]);
    final client = FakePluralKitClient();
    final applier = buildApplier(repo: repo, client: client);

    const pk = PKMember(
      id: 'abcde',
      uuid: 'u-imp',
      name: 'Imported',
      pronouns: 'they/them',
      description: 'bio here',
      color: 'ff00ff',
    );

    final results = await applier.apply([const PkImportDecision(pkMember: pk)]);
    expect(results.single.outcome, PkApplyOutcome.applied);
    final all = await repo.getAllMembers();
    expect(all, hasLength(1));
    expect(all.single.pluralkitUuid, 'u-imp');
    expect(all.single.pluralkitId, 'abcde');
    expect(all.single.bio, 'bio here');
    expect(all.single.customColorHex, '#ff00ff');
  });

  test('import is idempotent — same UUID skips duplicate create', () async {
    final repo = FakeMemberRepo([]);
    final client = FakePluralKitClient();
    final applier = buildApplier(repo: repo, client: client);
    const pk = PKMember(id: 'abcde', uuid: 'u-imp', name: 'X');

    await applier.apply([const PkImportDecision(pkMember: pk)]);
    // Wipe state so we force a re-run — local member still exists by UUID.
    await dao.clearAll();
    await applier.apply([const PkImportDecision(pkMember: pk)]);

    final all = await repo.getAllMembers();
    expect(all, hasLength(1));
  });

  test('push creates PK member, stores id + uuid locally', () async {
    final repo = FakeMemberRepo([_local(id: 'l1', name: 'Alice')]);
    final client = FakePluralKitClient(
      onCreate: (data) => PKMember(
        id: 'newid',
        uuid: 'new-uuid',
        name: data['name'] as String,
      ),
    );
    final applier = buildApplier(repo: repo, client: client);

    final results = await applier.apply([
      const PkPushNewDecision(localMemberId: 'l1'),
    ]);
    expect(results.single.outcome, PkApplyOutcome.applied);
    expect(client.createCallCount, 1);
    final updated = await repo.getMemberById('l1');
    expect(updated!.pluralkitId, 'newid');
    expect(updated.pluralkitUuid, 'new-uuid');
  });

  test('push is idempotent when local already has both IDs', () async {
    final repo = FakeMemberRepo([
      _local(
        id: 'l1',
        name: 'Alice',
        pluralkitId: 'abcde',
        pluralkitUuid: 'u-1',
      ),
    ]);
    final client = FakePluralKitClient();
    final applier = buildApplier(repo: repo, client: client);

    await applier.apply([const PkPushNewDecision(localMemberId: 'l1')]);
    expect(client.createCallCount, 0);
  });

  test('skip for local sets pluralkitSyncIgnored', () async {
    final repo = FakeMemberRepo([_local(id: 'l1', name: 'Alice')]);
    final client = FakePluralKitClient();
    final applier = buildApplier(repo: repo, client: client);

    final results = await applier.apply([
      const PkSkipDecision(localMemberId: 'l1'),
    ]);
    expect(results.single.outcome, PkApplyOutcome.applied);
    final updated = await repo.getMemberById('l1');
    expect(updated!.pluralkitSyncIgnored, isTrue);
  });

  test('partial failure: one fails, others still apply', () async {
    final repo = FakeMemberRepo([_local(id: 'l1', name: 'Alice')]);
    final client = FakePluralKitClient(
      onCreate: (_) => throw const PluralKitApiError(400, 'bad'),
    );
    final applier = buildApplier(repo: repo, client: client);

    const pk = PKMember(id: 'abcde', uuid: 'u-imp', name: 'Other');
    final results = await applier.apply([
      const PkImportDecision(pkMember: pk), // succeeds (local-only)
      const PkPushNewDecision(localMemberId: 'l1'), // fails (remote)
    ]);

    expect(results[0].outcome, PkApplyOutcome.applied);
    expect(results[1].outcome, PkApplyOutcome.failed);
    expect(results[1].error, contains('bad'));

    final pushState = await dao.getById('push:l1');
    expect(pushState!.status, 'failed');
    expect(pushState.errorMessage, contains('bad'));
  });

  // -------------------------------------------------------------------------
  // Plan 08 "Conflict semantics on link" — default-local fields accept PK
  // -------------------------------------------------------------------------

  test('link: local defaults are replaced by PK values on link', () async {
    // Local member has empty/null fields (Prism defaults). Linking must pull
    // PK's populated values so subsequent syncs don't spuriously push nulls.
    final local = domain.Member(
      id: 'l1',
      name: '',
      createdAt: DateTime(2026),
      // all other fields default: pronouns null, bio null, displayName null,
      // customColorEnabled false, birthday null, proxyTagsJson null.
    );
    final repo = FakeMemberRepo([local]);
    final client = FakePluralKitClient();
    final applier = buildApplier(repo: repo, client: client);

    const pk = PKMember(
      id: 'abcde',
      uuid: 'u-link',
      name: 'Alice',
      displayName: 'Ali ✨',
      pronouns: 'she/her',
      description: 'bio',
      color: '7c3aed',
      birthday: '2020-01-15',
      proxyTagsJson: '[{"prefix":"A:","suffix":null}]',
    );
    final results = await applier.apply([
      const PkLinkDecision(localMemberId: 'l1', pkMember: pk),
    ]);

    expect(results.single.outcome, PkApplyOutcome.applied);
    final updated = (await repo.getMemberById('l1'))!;
    expect(updated.pluralkitUuid, 'u-link');
    expect(updated.name, 'Alice');
    expect(updated.displayName, 'Ali ✨');
    expect(updated.pronouns, 'she/her');
    expect(updated.bio, 'bio');
    expect(updated.birthday, '2020-01-15');
    expect(updated.customColorHex, '#7c3aed');
    expect(updated.customColorEnabled, isTrue);
    expect(updated.proxyTagsJson, '[{"prefix":"A:","suffix":null}]');
  });

  test('link: populated local fields are kept (no overwrite)', () async {
    final local = domain.Member(
      id: 'l1',
      name: 'MyAlice',
      displayName: 'MyDisplay',
      pronouns: 'they/them',
      bio: 'my bio',
      birthday: '1990-05-05',
      customColorEnabled: true,
      customColorHex: '#ff0000',
      createdAt: DateTime(2026),
    );
    final repo = FakeMemberRepo([local]);
    final client = FakePluralKitClient();
    final applier = buildApplier(repo: repo, client: client);

    const pk = PKMember(
      id: 'abcde',
      uuid: 'u-link',
      name: 'PKAlice',
      displayName: 'PKDisplay',
      pronouns: 'she/her',
      description: 'pk bio',
      color: '00ff00',
      birthday: '2020-01-15',
    );
    await applier.apply([
      const PkLinkDecision(localMemberId: 'l1', pkMember: pk),
    ]);

    final updated = (await repo.getMemberById('l1'))!;
    expect(updated.name, 'MyAlice');
    expect(updated.displayName, 'MyDisplay');
    expect(updated.pronouns, 'they/them');
    expect(updated.bio, 'my bio');
    expect(updated.birthday, '1990-05-05');
    expect(updated.customColorHex, '#ff0000');
    // Link fields still get written.
    expect(updated.pluralkitId, 'abcde');
    expect(updated.pluralkitUuid, 'u-link');
  });

  test('link: downloads PK avatar when local has none', () async {
    final repo = FakeMemberRepo([_local(id: 'l1', name: 'Alice')]);
    final client = FakePluralKitClient(avatarBytes: {
      'https://pk/avatar.png': [1, 2, 3, 4],
    });
    final applier = buildApplier(repo: repo, client: client);

    const pk = PKMember(
      id: 'abcde',
      uuid: 'u-link',
      name: 'Alice',
      avatarUrl: 'https://pk/avatar.png',
    );
    await applier.apply([
      const PkLinkDecision(localMemberId: 'l1', pkMember: pk),
    ]);

    expect(client.downloadedUrls, contains('https://pk/avatar.png'));
    final updated = (await repo.getMemberById('l1'))!;
    expect(updated.avatarImageData, isNotNull);
    expect(updated.avatarImageData!, [1, 2, 3, 4]);
  });

  // -------------------------------------------------------------------------
  // Import avatar download — plan S9
  // -------------------------------------------------------------------------

  test('import: downloads avatar when pk.avatarUrl is set', () async {
    final repo = FakeMemberRepo([]);
    final client = FakePluralKitClient(avatarBytes: {
      'https://pk/x.png': [9, 8, 7],
    });
    final applier = buildApplier(repo: repo, client: client);

    const pk = PKMember(
      id: 'abcde',
      uuid: 'u-imp',
      name: 'Imp',
      avatarUrl: 'https://pk/x.png',
    );
    await applier.apply([const PkImportDecision(pkMember: pk)]);

    final all = await repo.getAllMembers();
    expect(all, hasLength(1));
    expect(all.single.avatarImageData, isNotNull);
    expect(all.single.avatarImageData!, [9, 8, 7]);
    expect(client.downloadedUrls, contains('https://pk/x.png'));
  });

  test('import: avatar download failure is non-fatal', () async {
    final repo = FakeMemberRepo([]);
    final client = FakePluralKitClient(
      downloadError: const PluralKitApiError(500, 'server'),
    );
    final applier = buildApplier(repo: repo, client: client);

    const pk = PKMember(
      id: 'abcde',
      uuid: 'u-imp',
      name: 'Imp',
      avatarUrl: 'https://pk/x.png',
    );
    final results = await applier.apply([const PkImportDecision(pkMember: pk)]);
    expect(results.single.outcome, PkApplyOutcome.applied);
    final all = await repo.getAllMembers();
    expect(all.single.avatarImageData, isNull);
  });

  test('retry: failed → successful on second run', () async {
    final repo = FakeMemberRepo([_local(id: 'l1', name: 'Alice')]);
    var shouldFail = true;
    final client = FakePluralKitClient(
      onCreate: (data) {
        if (shouldFail) {
          throw const PluralKitApiError(500, 'server');
        }
        return PKMember(
          id: 'newid',
          uuid: 'new-uuid',
          name: data['name'] as String,
        );
      },
    );
    final applier = buildApplier(repo: repo, client: client);

    var results = await applier
        .apply([const PkPushNewDecision(localMemberId: 'l1')]);
    expect(results.single.outcome, PkApplyOutcome.failed);

    shouldFail = false;
    results = await applier
        .apply([const PkPushNewDecision(localMemberId: 'l1')]);
    expect(results.single.outcome, PkApplyOutcome.applied);
    final updated = await repo.getMemberById('l1');
    expect(updated!.pluralkitUuid, 'new-uuid');
  });
}
