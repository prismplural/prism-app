import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/pk_mapping_state_dao.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_mapping_applier.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_push_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';
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
  Future<List<domain.Member>> getAllMembersIncludingDeleted() async =>
      _byId.values.toList();

  @override
  Future<domain.Member?> getMemberById(String id) async => _byId[id];

  @override
  Future<void> createMember(domain.Member member) async =>
      _byId[member.id] = member;

  @override
  Future<void> updateMember(domain.Member member) async =>
      _byId[member.id] = member;

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
    final existing = _byId[id];
    if (existing == null) return 0;
    _byId[id] = _applyPatch(
      existing,
      patch,
    ).copyWith(pluralkitSyncIgnored: false);
    return 1;
  }

  @override
  Future<int> recordPluralKitIdentity(
    String id,
    Map<String, dynamic> patch,
  ) async {
    final existing = _byId[id];
    if (existing == null) return 0;
    _byId[id] = _applyPatch(existing, patch);
    return 1;
  }

  /// Apply a (possibly full-domain) patch map back onto a Member. Only
  /// the fields the applier tests actually assert on are mapped; anything
  /// else passes through silently.
  domain.Member _applyPatch(
    domain.Member existing,
    Map<String, dynamic> patch,
  ) {
    return existing.copyWith(
      name: patch['name'] as String? ?? existing.name,
      pronouns: patch.containsKey('pronouns')
          ? patch['pronouns'] as String?
          : existing.pronouns,
      bio: patch.containsKey('bio')
          ? patch['bio'] as String?
          : existing.bio,
      birthday: patch.containsKey('birthday')
          ? patch['birthday'] as String?
          : existing.birthday,
      customColorEnabled:
          patch['custom_color_enabled'] as bool? ??
              existing.customColorEnabled,
      customColorHex: patch.containsKey('custom_color_hex')
          ? patch['custom_color_hex'] as String?
          : existing.customColorHex,
      proxyTagsJson: patch.containsKey('proxy_tags_json')
          ? patch['proxy_tags_json'] as String?
          : existing.proxyTagsJson,
      avatarImageData: patch.containsKey('avatar_image_data')
          ? _bytesOrNull(patch['avatar_image_data'])
          : existing.avatarImageData,
      pkBannerUrl: patch.containsKey('pk_banner_url')
          ? patch['pk_banner_url'] as String?
          : existing.pkBannerUrl,
      pkBannerImageData: patch.containsKey('pk_banner_image_data')
          ? _bytesOrNull(patch['pk_banner_image_data'])
          : existing.pkBannerImageData,
      pkBannerCachedUrl: patch.containsKey('pk_banner_cached_url')
          ? patch['pk_banner_cached_url'] as String?
          : existing.pkBannerCachedUrl,
      profileHeaderSource: patch.containsKey('profile_header_source')
          ? domain.MemberProfileHeaderSource
              .values[patch['profile_header_source'] as int]
          : existing.profileHeaderSource,
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
  }

  Uint8List? _bytesOrNull(Object? value) {
    if (value == null) return null;
    if (value is Uint8List) return value;
    if (value is String) return base64Decode(value);
    return null;
  }

  @override
  Future<int> excludePluralKitSync(String id) async {
    final existing = _byId[id];
    if (existing == null) return 0;
    _byId[id] = existing.copyWith(pluralkitSyncIgnored: true);
    return 1;
  }

  @override
  Future<int> resumePluralKitSync(String id) async {
    final existing = _byId[id];
    if (existing == null) return 0;
    _byId[id] = existing.copyWith(pluralkitSyncIgnored: false);
    return 1;
  }

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
  Stream<domain.Member?> watchMemberById(String id) => Stream.value(_byId[id]);

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
  }) : allMembers = members ?? [],
       avatarBytes = avatarBytes ?? {},
       super(token: 'fake-token', httpClient: http.Client());

  @override
  Future<List<PKMember>> getMembers() async => allMembers;

  @override
  Future<PKMember> createMember(Map<String, dynamic> data) async {
    createCallCount++;
    createdPayloads.add(data);
    final result =
        onCreate?.call(data) ??
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
    return PKMember(
      id: id,
      uuid: 'existing-uuid',
      name: data['name'] as String,
    );
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
    required MemberRepository repo,
    required FakePluralKitClient client,
    PkSyncEventBus? bus,
  }) {
    return PkMappingApplier(
      members: repo,
      state: dao,
      pushService: const PkPushService(),
      client: client,
      bus: bus ?? PkSyncEventBus(),
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

    final state = await dao.getById('link:u-1:l1');
    expect(state!.status, 'applied');
  });

  test('link is idempotent — re-applying returns alreadyApplied', () async {
    final repo = FakeMemberRepo([_local(id: 'l1', name: 'Alice')]);
    final client = FakePluralKitClient();
    final applier = buildApplier(repo: repo, client: client);
    const pk = PKMember(id: 'abcde', uuid: 'u-1', name: 'Alice');
    final decisions = [const PkLinkDecision(localMemberId: 'l1', pkMember: pk)];
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
      displayName: 'Imported Display',
      pronouns: 'they/them',
      description: 'bio here',
      color: 'ff00ff',
    );

    final results = await applier.apply([const PkImportDecision(pkMember: pk)]);
    expect(results.single.outcome, PkApplyOutcome.applied);
    final all = await repo.getAllMembers();
    expect(all, hasLength(1));
    expect(all.single.name, 'Imported');
    expect(all.single.pluralkitDisplayName, 'Imported Display');
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

  test('import completes an existing short-id-only link', () async {
    final repo = FakeMemberRepo([
      _local(id: 'l1', name: 'Existing', pluralkitId: 'abcde'),
    ]);
    final client = FakePluralKitClient();
    final applier = buildApplier(repo: repo, client: client);
    const pk = PKMember(id: 'abcde', uuid: 'u-imp', name: 'Imported');

    final results = await applier.apply([const PkImportDecision(pkMember: pk)]);

    expect(results.single.outcome, PkApplyOutcome.applied);
    final all = await repo.getAllMembers();
    expect(all, hasLength(1));
    expect(all.single.id, 'l1');
    expect(all.single.pluralkitId, 'abcde');
    expect(all.single.pluralkitUuid, 'u-imp');
  });

  test(
    'link fails when a tombstoned row still owns the same pluralkitId',
    () async {
      final repo = DriftMemberRepository(db.membersDao, null);
      await repo.createMember(
        _local(id: 'tomb', name: 'Old', pluralkitId: 'abcde'),
      );
      await repo.deleteMember('tomb');
      await repo.createMember(_local(id: 'l1', name: 'Alice'));

      final client = FakePluralKitClient();
      final applier = buildApplier(repo: repo, client: client);
      const pk = PKMember(id: 'abcde', uuid: 'u-link', name: 'Alice');

      final results = await applier.apply([
        const PkLinkDecision(localMemberId: 'l1', pkMember: pk),
      ]);

      expect(results.single.outcome, PkApplyOutcome.failed);
      expect(
        results.single.error,
        contains('deleted local member still owns this PluralKit link'),
      );

      final local = await repo.getMemberById('l1');
      expect(local!.pluralkitId, isNull);
      expect(local.pluralkitUuid, isNull);
    },
  );

  test(
    'import fails when a tombstoned row still owns the same pluralkitId',
    () async {
      final repo = DriftMemberRepository(db.membersDao, null);
      await repo.createMember(
        _local(id: 'tomb', name: 'Old', pluralkitId: 'abcde'),
      );
      await repo.deleteMember('tomb');

      final client = FakePluralKitClient();
      final applier = buildApplier(repo: repo, client: client);
      const pk = PKMember(id: 'abcde', uuid: 'u-import', name: 'Imported');

      final results = await applier.apply([
        const PkImportDecision(pkMember: pk),
      ]);

      expect(results.single.outcome, PkApplyOutcome.failed);
      expect(
        results.single.error,
        contains('deleted local member still owns this PluralKit link'),
      );

      final allVisible = await repo.getAllMembers();
      expect(allVisible, isEmpty);
    },
  );

  test('push creates PK member, stores id + uuid locally', () async {
    final repo = FakeMemberRepo([_local(id: 'l1', name: 'Alice')]);
    final client = FakePluralKitClient(
      onCreate: (data) =>
          PKMember(id: 'newid', uuid: 'new-uuid', name: data['name'] as String),
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
      // all other fields default: pronouns null, bio null, Full Name null,
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
    expect(updated.displayName, isNull);
    expect(updated.pluralkitDisplayName, 'Ali ✨');
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
    expect(updated.pluralkitDisplayName, 'PKDisplay');
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
    final client = FakePluralKitClient(
      avatarBytes: {
        'https://pk/avatar.png': [1, 2, 3, 4],
      },
    );
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
    final client = FakePluralKitClient(
      avatarBytes: {
        'https://pk/x.png': [9, 8, 7],
      },
    );
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

  // -------------------------------------------------------------------------
  // Network-error classification (offline-friendly errors in _applyOne)
  // -------------------------------------------------------------------------

  test('push: SocketException maps to friendly network message', () async {
    final repo = FakeMemberRepo([_local(id: 'l1', name: 'Alice')]);
    final client = FakePluralKitClient(
      onCreate: (_) =>
          throw const SocketException('Failed host lookup: api.pluralkit.me'),
    );
    final applier = buildApplier(repo: repo, client: client);

    final results = await applier.apply([
      const PkPushNewDecision(localMemberId: 'l1'),
    ]);

    expect(results.single.outcome, PkApplyOutcome.failed);
    expect(results.single.error, kPkApplierNetworkErrorMessage);
    final pushState = await dao.getById('push:l1');
    expect(pushState!.status, 'failed');
    expect(pushState.errorMessage, kPkApplierNetworkErrorMessage);
  });

  test('push: TimeoutException maps to friendly network message', () async {
    final repo = FakeMemberRepo([_local(id: 'l1', name: 'Alice')]);
    final client = FakePluralKitClient(
      onCreate: (_) => throw TimeoutException('stalled'),
    );
    final applier = buildApplier(repo: repo, client: client);

    final results = await applier.apply([
      const PkPushNewDecision(localMemberId: 'l1'),
    ]);

    expect(results.single.outcome, PkApplyOutcome.failed);
    expect(results.single.error, kPkApplierNetworkErrorMessage);
  });

  test('push: StateError keeps raw toString (non-network)', () async {
    final repo = FakeMemberRepo([_local(id: 'l1', name: 'Alice')]);
    final client = FakePluralKitClient(
      onCreate: (_) => throw StateError('foo'),
    );
    final applier = buildApplier(repo: repo, client: client);

    final results = await applier.apply([
      const PkPushNewDecision(localMemberId: 'l1'),
    ]);

    expect(results.single.outcome, PkApplyOutcome.failed);
    expect(results.single.error, 'Bad state: foo');
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

    var results = await applier.apply([
      const PkPushNewDecision(localMemberId: 'l1'),
    ]);
    expect(results.single.outcome, PkApplyOutcome.failed);

    shouldFail = false;
    results = await applier.apply([
      const PkPushNewDecision(localMemberId: 'l1'),
    ]);
    expect(results.single.outcome, PkApplyOutcome.applied);
    final updated = await repo.getMemberById('l1');
    expect(updated!.pluralkitUuid, 'new-uuid');
  });

  // ---------------------------------------------------------------------------
  // Mapping event emission.
  //
  // Every per-decision outcome (applied or failed) emits a structured event on
  // the shared `PkSyncEventBus` so the PK sync log can show the user which
  // mapping decisions ran. setUp flips the main-isolate flag so emits pass the
  // bus's isolate guard; tearDown resets it so the flag doesn't leak across
  // sibling test files.
  // ---------------------------------------------------------------------------
  group('event emission', () {
    setUp(markPkBusMainIsolate);

    tearDown(resetPkBusMainIsolateForTest);

    test('link decision success emits PkMappingDecisionApplied', () async {
      final capture = PkSyncEventBusCapture();
      final repo = FakeMemberRepo([_local(id: 'l1', name: 'Alice')]);
      final client = FakePluralKitClient();
      final applier = buildApplier(
        repo: repo,
        client: client,
        bus: capture.bus,
      );

      const pk = PKMember(id: 'abcde', uuid: 'u-1', name: 'Alice');
      final results = await applier.apply([
        const PkLinkDecision(localMemberId: 'l1', pkMember: pk),
      ]);

      expect(results.single.outcome, PkApplyOutcome.applied);
      expect(capture.events, hasLength(1));
      final event = capture.events.single;
      expect(event, isA<PkMappingDecisionApplied>());
      final applied = event as PkMappingDecisionApplied;
      expect(applied.decisionId, 'link:u-1:l1');
      expect(applied.decisionKind, 'link');
    });

    test('import decision success emits PkMappingDecisionApplied', () async {
      final capture = PkSyncEventBusCapture();
      final repo = FakeMemberRepo([]);
      final client = FakePluralKitClient();
      final applier = buildApplier(
        repo: repo,
        client: client,
        bus: capture.bus,
      );

      const pk = PKMember(id: 'abcde', uuid: 'u-imp', name: 'Imported');
      final results = await applier.apply([
        const PkImportDecision(pkMember: pk),
      ]);

      expect(results.single.outcome, PkApplyOutcome.applied);
      expect(capture.events, hasLength(1));
      final event = capture.events.single;
      expect(event, isA<PkMappingDecisionApplied>());
      final applied = event as PkMappingDecisionApplied;
      expect(applied.decisionId, 'import:u-imp');
      expect(applied.decisionKind, 'import');
    });

    test('push-new decision success emits PkMappingDecisionApplied', () async {
      final capture = PkSyncEventBusCapture();
      final repo = FakeMemberRepo([_local(id: 'l1', name: 'Alice')]);
      final client = FakePluralKitClient(
        onCreate: (data) => PKMember(
          id: 'newid',
          uuid: 'new-uuid',
          name: data['name'] as String,
        ),
      );
      final applier = buildApplier(
        repo: repo,
        client: client,
        bus: capture.bus,
      );

      final results = await applier.apply([
        const PkPushNewDecision(localMemberId: 'l1'),
      ]);

      expect(results.single.outcome, PkApplyOutcome.applied);
      expect(capture.events, hasLength(1));
      final event = capture.events.single;
      expect(event, isA<PkMappingDecisionApplied>());
      final applied = event as PkMappingDecisionApplied;
      expect(applied.decisionId, 'push:l1');
      expect(applied.decisionKind, 'push');
    });

    test('link decision failure emits PkMappingDecisionFailed', () async {
      // Force `_applyLink` to throw by pointing the decision at a local that
      // doesn't exist — the applier throws StateError on the missing lookup.
      final capture = PkSyncEventBusCapture();
      final repo = FakeMemberRepo([]);
      final client = FakePluralKitClient();
      final applier = buildApplier(
        repo: repo,
        client: client,
        bus: capture.bus,
      );

      const pk = PKMember(id: 'abcde', uuid: 'u-1', name: 'Alice');
      final results = await applier.apply([
        const PkLinkDecision(localMemberId: 'missing', pkMember: pk),
      ]);

      expect(results.single.outcome, PkApplyOutcome.failed);
      expect(capture.events, hasLength(1));
      final event = capture.events.single;
      expect(event, isA<PkMappingDecisionFailed>());
      final failed = event as PkMappingDecisionFailed;
      expect(failed.decisionId, 'link:u-1:missing');
      expect(failed.decisionKind, 'link');
      expect(failed.error, contains('missing'));
    });

    test('failure error message is token-redacted before emit', () async {
      // Simulate a typed PK error whose message happens to contain the
      // current bearer token. The emit site must replace the token with
      // [REDACTED] so logs copied out of the device never expose it.
      final capture = PkSyncEventBusCapture();
      final repo = FakeMemberRepo([_local(id: 'l1', name: 'Alice')]);
      final client = FakePluralKitClient(
        onCreate: (_) =>
            throw const PluralKitApiError(500, 'upstream rejected fake-token'),
      );
      final applier = buildApplier(
        repo: repo,
        client: client,
        bus: capture.bus,
      );

      await applier.apply([const PkPushNewDecision(localMemberId: 'l1')]);

      expect(capture.events, hasLength(1));
      final event = capture.events.single as PkMappingDecisionFailed;
      expect(event.error, contains('[REDACTED]'));
      expect(event.error, isNot(contains('fake-token')));
    });

    test(
      'mixed batch emits an applied event followed by a failed event in order',
      () async {
        // Import succeeds (local-only), push fails (createMember throws).
        final capture = PkSyncEventBusCapture();
        final repo = FakeMemberRepo([_local(id: 'l1', name: 'Alice')]);
        final client = FakePluralKitClient(
          onCreate: (_) => throw const PluralKitApiError(400, 'bad request'),
        );
        final applier = buildApplier(
          repo: repo,
          client: client,
          bus: capture.bus,
        );

        const importedPk = PKMember(id: 'abcde', uuid: 'u-imp', name: 'Other');
        final results = await applier.apply([
          const PkImportDecision(pkMember: importedPk), // applied
          const PkPushNewDecision(localMemberId: 'l1'), // failed
        ]);

        expect(results[0].outcome, PkApplyOutcome.applied);
        expect(results[1].outcome, PkApplyOutcome.failed);

        expect(capture.events, hasLength(2));
        expect(capture.events[0], isA<PkMappingDecisionApplied>());
        final applied = capture.events[0] as PkMappingDecisionApplied;
        expect(applied.decisionId, 'import:u-imp');
        expect(applied.decisionKind, 'import');

        expect(capture.events[1], isA<PkMappingDecisionFailed>());
        final failed = capture.events[1] as PkMappingDecisionFailed;
        expect(failed.decisionId, 'push:l1');
        expect(failed.decisionKind, 'push');
        expect(failed.error, contains('bad request'));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // PR 1 (mapping recovery): PkResolutionSnapshot threading into _applyPushNew.
  //
  // The snapshot tells the applier "these are the PK identifiers in the
  // currently-paired system." `_applyPushNew`'s two idempotency shortcuts
  // (already-linked, id-only completion) consult it so stale PK fields from
  // a prior different-system import don't silently no-op the user's Push
  // decision.
  // ---------------------------------------------------------------------------

  group('PR 1: _applyPushNew honors PkResolutionSnapshot', () {
    test(
      'stale PK fields + Push + snapshot excluding those fields → applier '
      'POSTs a new PK member (does not PATCH the stale ID)',
      () async {
        // Local carries PK fields from a prior different-system import. The
        // snapshot does NOT contain them — the "already linked" idempotency
        // shortcut MUST NOT fire (which would silently no-op the user's
        // Push decision). The applier must also clear the stale PK fields
        // before calling pushMemberFull; otherwise PkPushService would
        // treat any non-empty pluralkitId as a PATCH target and 404
        // against the stale id, breaking the recovery flow.
        final repo = FakeMemberRepo([
          _local(
            id: 'l1',
            name: 'Stale',
            pluralkitId: 'zzzzz',
            pluralkitUuid: 'pk-old',
          ),
        ]);
        final client = _RecordingFakePluralKitClient(
          onCreate: (data) => PKMember(
            id: 'newid',
            uuid: 'new-uuid',
            name: data['name'] as String,
          ),
        );
        final applier = buildApplier(repo: repo, client: client);

        final results = await applier.apply(
          [const PkPushNewDecision(localMemberId: 'l1')],
          resolution: const PkResolutionSnapshot(
            fetchedPkUuids: {'pk-alice'},
            fetchedPkIds: {'aaaaa'},
          ),
        );

        expect(results.single.outcome, PkApplyOutcome.applied);
        // Must POST, not PATCH: a PATCH on the stale 'zzzzz' would 404.
        expect(
          client.createCallCount,
          1,
          reason: 'Stale-link Push must take the POST (create) path',
        );
        expect(
          client.updateMemberCallCount,
          0,
          reason: 'Stale-link Push must NOT PATCH the stale pluralkitId',
        );
        // The payload sent to PK must not carry the stale id either.
        expect(
          client.createdPayloads.single.containsKey('id'),
          isFalse,
          reason:
              'PK create payload must not include the stale pluralkitId',
        );
        // pk_mapping_state recorded the push as applied.
        final pushState = await dao.getById('push:l1');
        expect(pushState!.status, 'applied');
        // Local should now have the freshly-created PK identity, not the
        // stale one.
        final updated = await repo.getMemberById('l1');
        expect(updated!.pluralkitId, 'newid');
        expect(updated.pluralkitUuid, 'new-uuid');
      },
    );

    test(
      'resolved PK fields + Push + snapshot including them → no-ops',
      () async {
        // Local IS linked to a PK member that's in the snapshot. Today's
        // behavior preserved: no push, no overwrite.
        final repo = FakeMemberRepo([
          _local(
            id: 'l1',
            name: 'Alice',
            pluralkitId: 'aaaaa',
            pluralkitUuid: 'pk-alice',
          ),
        ]);
        final client = FakePluralKitClient();
        final applier = buildApplier(repo: repo, client: client);

        final results = await applier.apply(
          [const PkPushNewDecision(localMemberId: 'l1')],
          resolution: const PkResolutionSnapshot(
            fetchedPkUuids: {'pk-alice'},
            fetchedPkIds: {'aaaaa'},
          ),
        );

        expect(results.single.outcome, PkApplyOutcome.applied);
        expect(
          client.createCallCount,
          0,
          reason:
              'Already-linked local that resolves in the snapshot must not '
              'be re-pushed',
        );
        final updated = await repo.getMemberById('l1');
        expect(updated!.pluralkitId, 'aaaaa');
        expect(updated.pluralkitUuid, 'pk-alice');
      },
    );

    test(
      'pluralkitId set + uuid empty + snapshot NOT containing the id → push '
      'as new (does NOT call client.getMembers)',
      () async {
        // The "id exists, uuid missing" completion branch must respect the
        // snapshot. If the id is stale (not in snapshot), fall through to
        // push as new — do NOT call getMembers() to look up a member that
        // no longer exists in the connected system.
        final repo = FakeMemberRepo([
          _local(id: 'l1', name: 'Stale', pluralkitId: 'zzzzz'),
        ]);
        final client = _RecordingFakePluralKitClient(
          onCreate: (data) => PKMember(
            id: 'newid',
            uuid: 'new-uuid',
            name: data['name'] as String,
          ),
        );
        final applier = buildApplier(repo: repo, client: client);

        final results = await applier.apply(
          [const PkPushNewDecision(localMemberId: 'l1')],
          resolution: const PkResolutionSnapshot(
            fetchedPkUuids: {'pk-alice'},
            fetchedPkIds: {'aaaaa'},
          ),
        );

        expect(results.single.outcome, PkApplyOutcome.applied);
        expect(
          client.getMembersCallCount,
          0,
          reason:
              'Stale id must not trigger a getMembers() lookup for a member '
              'that no longer exists in the connected system',
        );
        // Applier reached the push service (either PATCH or POST depending
        // on how the push service routes a stale-id local; both are valid
        // "did not short-circuit" outcomes).
        expect(
          client.createCallCount + client.updateMemberCallCount,
          greaterThanOrEqualTo(1),
          reason: 'Push must reach the push service',
        );
      },
    );

    test(
      'pluralkitId set + uuid empty + snapshot containing the id → completes '
      'link via fetch-and-complete path',
      () async {
        // The id is fresh (snapshot contains it). The applier should call
        // getMembers, find the matching PK member, and complete the link
        // by writing its UUID locally. No POST.
        final repo = FakeMemberRepo([
          _local(id: 'l1', name: 'Alice', pluralkitId: 'aaaaa'),
        ]);
        final client = _RecordingFakePluralKitClient(
          members: [
            const PKMember(id: 'aaaaa', uuid: 'pk-alice', name: 'Alice'),
          ],
        );
        final applier = buildApplier(repo: repo, client: client);

        final results = await applier.apply(
          [const PkPushNewDecision(localMemberId: 'l1')],
          resolution: const PkResolutionSnapshot(
            fetchedPkUuids: {'pk-alice'},
            fetchedPkIds: {'aaaaa'},
          ),
        );

        expect(results.single.outcome, PkApplyOutcome.applied);
        expect(
          client.getMembersCallCount,
          1,
          reason: 'Fresh id must trigger getMembers() to complete the link',
        );
        expect(
          client.createCallCount,
          0,
          reason: 'No POST when the id resolves to an existing PK member',
        );
        final updated = await repo.getMemberById('l1');
        expect(updated!.pluralkitId, 'aaaaa');
        expect(updated.pluralkitUuid, 'pk-alice');
      },
    );
  });

  // ───────────────────────────────────────────────────────────────────────
  // PR 2 — Part 1.7: every PK-link-writing applier path routes through
  // applyPluralKitLink, and Skip routes through excludePluralKitSync.
  //
  // Plan: docs/plans/2026-05-26-pluralkit-link-management.md
  // ───────────────────────────────────────────────────────────────────────

  group('PR 2: applier routes through new repo methods', () {
    test('_applyLink uses applyPluralKitLink', () async {
      final repo = _RecordingMemberRepo([_local(id: 'l1', name: 'Alice')]);
      final client = FakePluralKitClient();
      final applier = buildApplier(repo: repo, client: client);

      const pk = PKMember(id: 'abcde', uuid: 'u-1', name: 'Alice');
      await applier.apply([
        const PkLinkDecision(localMemberId: 'l1', pkMember: pk),
      ]);

      expect(repo.applyLinkCalls, hasLength(1));
      expect(repo.applyLinkCalls.single.memberId, 'l1');
      expect(repo.recordIdentityCalls, isEmpty);
      // Excluding excluded keys (delete bookkeeping) — patch carries the
      // PK identifiers at minimum.
      final patch = repo.applyLinkCalls.single.patch;
      expect(patch['pluralkit_uuid'], 'u-1');
      expect(patch['pluralkit_id'], 'abcde');
      expect(patch.containsKey('is_deleted'), isFalse);
      expect(patch.containsKey('delete_intent_epoch'), isFalse);
      expect(patch.containsKey('delete_push_started_at'), isFalse);
    });

    test('_applyPushNew main push path uses applyPluralKitLink', () async {
      final repo = _RecordingMemberRepo([_local(id: 'l1', name: 'Alice')]);
      final client = FakePluralKitClient(
        onCreate: (data) => PKMember(
          id: 'newid',
          uuid: 'new-uuid',
          name: data['name'] as String,
        ),
      );
      final applier = buildApplier(repo: repo, client: client);

      await applier.apply([const PkPushNewDecision(localMemberId: 'l1')]);

      expect(repo.applyLinkCalls, hasLength(1));
      final patch = repo.applyLinkCalls.single.patch;
      expect(patch['pluralkit_uuid'], 'new-uuid');
      expect(patch['pluralkit_id'], 'newid');
    });

    test('_applyPushNew crash-recovery branch uses applyPluralKitLink',
        () async {
      // Seed mapping state as if a prior push completed but the local
      // member write didn't land. The decision id is computed from
      // localMemberId — `push:l1`.
      await dao.upsert(
        PkMappingStateCompanion.insert(
          id: 'push:l1',
          decisionType: 'push',
          pkMemberId: const Value('pkRec'),
          pkMemberUuid: const Value('uuid-pkRec'),
          localMemberId: const Value('l1'),
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      final repo = _RecordingMemberRepo([_local(id: 'l1', name: 'Alice')]);
      final client = FakePluralKitClient();
      final applier = buildApplier(repo: repo, client: client);

      await applier.apply([
        const PkPushNewDecision(localMemberId: 'l1'),
      ]);

      // No POST — crash recovery reuses the prior PK identifiers.
      expect(client.createCallCount, 0);
      expect(repo.applyLinkCalls, hasLength(1));
      final patch = repo.applyLinkCalls.single.patch;
      expect(patch['pluralkit_uuid'], 'uuid-pkRec');
      expect(patch['pluralkit_id'], 'pkRec');
    });

    test('_applyPushNew "id exists, uuid missing" completion uses '
        'applyPluralKitLink', () async {
      final repo = _RecordingMemberRepo([
        _local(id: 'l1', name: 'Partial', pluralkitId: 'aaaaa'),
      ]);
      final client = _RecordingFakePluralKitClient(
        members: [const PKMember(id: 'aaaaa', uuid: 'pk-alice', name: 'A')],
      );
      final applier = buildApplier(repo: repo, client: client);

      await applier.apply(
        [const PkPushNewDecision(localMemberId: 'l1')],
        resolution: const PkResolutionSnapshot(
          fetchedPkUuids: {'pk-alice'},
          fetchedPkIds: {'aaaaa'},
        ),
      );

      // Did NOT POST a new PK member — completed the link through
      // applyPluralKitLink instead.
      expect(client.createCallCount, 0);
      expect(repo.applyLinkCalls, hasLength(1));
      expect(repo.applyLinkCalls.single.patch['pluralkit_uuid'], 'pk-alice');
      expect(repo.applyLinkCalls.single.patch['pluralkit_id'], 'aaaaa');
    });

    test('_applyImport repair branch uses applyPluralKitLink', () async {
      // Seed an existing local with the short PK id only. PK has both
      // identifiers; import should repair by completing the link via
      // applyPluralKitLink.
      final repo = _RecordingMemberRepo([
        _local(id: 'l1', name: 'Existing', pluralkitId: 'abcde'),
      ]);
      final client = FakePluralKitClient();
      final applier = buildApplier(repo: repo, client: client);
      const pk = PKMember(id: 'abcde', uuid: 'u-imp', name: 'Imported');

      await applier.apply([const PkImportDecision(pkMember: pk)]);

      expect(repo.applyLinkCalls, hasLength(1));
      final patch = repo.applyLinkCalls.single.patch;
      expect(patch['pluralkit_uuid'], 'u-imp');
      expect(patch['pluralkit_id'], 'abcde');
    });

    test('Linking an excluded local through the mapping screen clears '
        'sync_ignored', () async {
      final repo = _RecordingMemberRepo([
        _local(id: 'l1', name: 'WasExcluded', ignored: true),
      ]);
      final client = FakePluralKitClient();
      final applier = buildApplier(repo: repo, client: client);

      const pk = PKMember(id: 'abcde', uuid: 'u-1', name: 'PK Name');
      await applier.apply([
        const PkLinkDecision(localMemberId: 'l1', pkMember: pk),
      ]);

      expect(repo.applyLinkCalls, hasLength(1));
      // The fake's applyPluralKitLink force-injects sync_ignored=false
      // (mirroring the real repo).
      final updated = await repo.getMemberById('l1');
      expect(updated!.pluralkitSyncIgnored, isFalse);
    });

    test('_applySkip on a local member uses excludePluralKitSync', () async {
      final repo = _RecordingMemberRepo([_local(id: 'l1', name: 'Alice')]);
      final client = FakePluralKitClient();
      final applier = buildApplier(repo: repo, client: client);

      await applier.apply([const PkSkipDecision(localMemberId: 'l1')]);

      expect(repo.excludeCalls, ['l1']);
      // Updated row reflects the exclude.
      final updated = await repo.getMemberById('l1');
      expect(updated!.pluralkitSyncIgnored, isTrue);
    });

    test(
      'PkLinkDecision id is scoped by (pk uuid, local id) so the '
      'alreadyApplied short-circuit cannot conflate two Links of the '
      'same PK member to different locals',
      () {
        const pk = PKMember(id: 'abcde', uuid: 'u-pk', name: 'PKAlice');
        const decisionA = PkLinkDecision(localMemberId: 'l1', pkMember: pk);
        const decisionB = PkLinkDecision(localMemberId: 'l2', pkMember: pk);
        expect(decisionA.id, 'link:u-pk:l1');
        expect(decisionB.id, 'link:u-pk:l2');
        expect(
          decisionA.id == decisionB.id,
          isFalse,
          reason:
              'Decision ids for same PK + different local must differ so '
              'the alreadyApplied cache cannot conflate them',
        );
      },
    );
  });
}

/// FakeMemberRepo subclass that records calls to PR 2's PK-link methods.
class _RecordingMemberRepo extends FakeMemberRepo {
  _RecordingMemberRepo(super.seed);

  final List<({String memberId, Map<String, dynamic> patch})> applyLinkCalls =
      [];
  final List<({String memberId, Map<String, dynamic> patch})>
  recordIdentityCalls = [];
  final List<String> excludeCalls = [];

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

  @override
  Future<int> excludePluralKitSync(String id) async {
    excludeCalls.add(id);
    return super.excludePluralKitSync(id);
  }
}

/// FakePluralKitClient subclass that also records getMembers and updateMember
/// call counts so the PR 1 tests can assert the "id-only completion" branch
/// was (or wasn't) taken AND the push-vs-no-op path.
class _RecordingFakePluralKitClient extends FakePluralKitClient {
  _RecordingFakePluralKitClient({
    super.members,
    super.onCreate,
  });

  int getMembersCallCount = 0;
  int updateMemberCallCount = 0;

  @override
  Future<List<PKMember>> getMembers() async {
    getMembersCallCount++;
    return super.getMembers();
  }

  @override
  Future<PKMember> updateMember(String id, Map<String, dynamic> data) async {
    updateMemberCallCount++;
    // Override the base fake's strict `data['name'] as String` cast: in
    // PATCH payloads the name key is omitted when unchanged, which would
    // crash the base. Return a synthetic PK member instead.
    return PKMember(
      id: id,
      uuid: 'existing-uuid',
      name: (data['name'] as String?) ?? 'patched',
    );
  }
}
