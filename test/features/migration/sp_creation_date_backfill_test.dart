import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/migration/services/sp_creation_date_backfill_service.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';

// =============================================================================
// Helpers
// =============================================================================

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

/// A minimal [SpMember] with only the fields the service cares about.
SpMember _spMember(String id, {String name = 'Member'}) =>
    SpMember(id: id, name: name);

/// Build a bare-minimum [SpExportData] with the given members.
SpExportData _export(List<SpMember> members) => SpExportData(
      members: members,
      customFronts: const [],
      frontHistory: const [],
      groups: const [],
      channels: const [],
      messages: const [],
      polls: const [],
    );

/// Minimal [domain.Member] domain object for test seeding.
domain.Member _member(
  String id, {
  String name = 'Member',
  DateTime? createdAt,
}) => domain.Member(
      id: id,
      name: name,
      createdAt: createdAt ?? DateTime.utc(2024, 1, 1),
    );

// =============================================================================
// Fake MemberRepository that captures updateMemberFields calls
// =============================================================================

class _FakeMemberRepository implements MemberRepository {
  final Map<String, domain.Member> _members = {};

  /// Calls recorded as (id, changedFields) pairs.
  final List<({String id, Map<String, dynamic> fields})> updateFieldsCalls = [];

  void seed(domain.Member member) => _members[member.id] = member;

  @override
  Future<domain.Member?> getMemberById(String id) async => _members[id];

  @override
  Future<int> updateMemberFields(
    String id,
    Map<String, dynamic> changedFields,
  ) async {
    updateFieldsCalls.add((id: id, fields: changedFields));
    final member = _members[id];
    if (member == null) return 0;
    if (changedFields.containsKey('created_at')) {
      _members[id] =
          member.copyWith(createdAt: changedFields['created_at'] as DateTime);
    }
    return 1;
  }

  // ── Unused stubs ────────────────────────────────────────────────────────────
  @override
  Future<List<domain.Member>> getAllMembers() async =>
      _members.values.toList();
  @override
  Future<List<domain.Member>> getAllMembersIncludingDeleted() async =>
      _members.values.toList();
  @override
  Stream<List<domain.Member>> watchAllMembers() =>
      Stream.value(_members.values.toList());
  @override
  Stream<List<domain.Member>> watchActiveMembers() =>
      Stream.value(_members.values.toList());
  @override
  Stream<domain.Member?> watchMemberById(String id) =>
      Stream.value(_members[id]);
  @override
  Future<void> createMember(domain.Member member) async =>
      _members[member.id] = member;
  @override
  Future<void> updateMember(domain.Member member) async =>
      _members[member.id] = member;
  @override
  Future<void> deleteMember(String id) async => _members.remove(id);
  @override
  Future<List<domain.Member>> getMembersByIds(List<String> ids) async =>
      ids.map((id) => _members[id]).whereType<domain.Member>().toList();
  @override
  Stream<List<domain.Member>> watchMembersByIds(List<String> ids) {
    final result =
        ids.map((id) => _members[id]).whereType<domain.Member>().toList();
    return Stream.value(result);
  }
  @override
  Future<int> getCount() async => _members.length;
  @override
  Future<int> applyPluralKitLink(String id, Map<String, dynamic> patch) async =>
      0;
  @override
  Future<int> recordPluralKitIdentity(
    String id,
    Map<String, dynamic> patch,
  ) async => 0;
  @override
  Future<int> excludePluralKitSync(String id) async => 0;
  @override
  Future<int> resumePluralKitSync(String id) async => 0;
  @override
  Future<List<domain.Member>> getDeletedLinkedMembers() async => const [];
  @override
  Future<void> clearPluralKitLink(String id) async {}
  @override
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) async {}
  @override
  Future<({domain.Member member, bool wasCreated})>
  ensureUnknownSentinelMember() async {
    throw UnimplementedError();
  }
}

// =============================================================================
// Tests
// =============================================================================

void main() {
  late AppDatabase db;
  late _FakeMemberRepository memberRepo;
  late SpCreationDateBackfillService service;

  setUp(() {
    db = _makeDb();
    memberRepo = _FakeMemberRepository();
    service = SpCreationDateBackfillService(
      db: db,
      spImportDao: db.spImportDao,
      memberRepo: memberRepo,
    );
  });

  tearDown(() async {
    await db.close();
  });

  // ── Helpers ─────────────────────────────────────────────────────────────────

  Future<void> insertMapping(String spId, String prismId) =>
      db.spImportDao.upsertMapping(
        SpIdMapTableCompanion(
          spId: Value(spId),
          entityType: const Value('member'),
          prismId: Value(prismId),
        ),
      );

  // ── Test cases ──────────────────────────────────────────────────────────────

  group('preview', () {
    test('returns matches for SP members with valid ObjectIds and mappings',
        () async {
      // A valid 24-char MongoDB ObjectId whose first 4 bytes encode
      // seconds since epoch (0x5F000000 = 2020-07-02T00:00:00Z).
      const spId = '5f0000000000000000000000';
      const prismId = 'prism-uuid-alice';

      await insertMapping(spId, prismId);
      memberRepo.seed(_member(prismId, name: 'Alice'));

      final preview = await service.preview(_export([_spMember(spId)]));

      expect(preview.matches, hasLength(1));
      expect(preview.unmatchedCount, 0);
      expect(preview.matches.first.prismId, prismId);
      expect(preview.matches.first.memberName, 'Alice');
      expect(preview.matches.first.newCreatedAt.year, 2020);
    });

    test('returns zero matches when sp_id_map is empty', () async {
      const spId = '5f0000000000000000000000';
      memberRepo.seed(_member('prism-uuid-alice'));

      final preview = await service.preview(_export([_spMember(spId)]));

      expect(preview.matches, isEmpty);
      expect(preview.unmatchedCount, 1);
    });

    test('counts members with no mapping as unmatched', () async {
      // mapped member
      const spIdA = '5f0000000000000000000000';
      const prismIdA = 'prism-alice';
      await insertMapping(spIdA, prismIdA);
      memberRepo.seed(_member(prismIdA, name: 'Alice'));

      // unmapped member (ObjectId valid but no entry in sp_id_map)
      const spIdB = '5f0000000000000000000001';

      final preview = await service.preview(
        _export([_spMember(spIdA), _spMember(spIdB)]),
      );

      expect(preview.matches, hasLength(1));
      expect(preview.unmatchedCount, 1);
      expect(preview.matches.first.prismId, prismIdA);
    });

    test('counts SP members with invalid ObjectIds as unmatched', () async {
      // 'short-id' is not a valid 24-char ObjectId.
      const spId = 'short-id';
      const prismId = 'prism-bob';
      await insertMapping(spId, prismId);
      memberRepo.seed(_member(prismId, name: 'Bob'));

      final preview = await service.preview(_export([_spMember(spId)]));

      expect(preview.matches, isEmpty);
      expect(preview.unmatchedCount, 1);
    });

    test('skips members deleted from Prism (getMemberById returns null)',
        () async {
      const spId = '5f0000000000000000000000';
      const prismId = 'prism-deleted';
      await insertMapping(spId, prismId);
      // Do NOT seed prismId in memberRepo → getMemberById returns null.

      final preview = await service.preview(_export([_spMember(spId)]));

      expect(preview.matches, isEmpty);
      expect(preview.unmatchedCount, 1);
    });

    test('records currentCreatedAt from the stored member', () async {
      const spId = '5f0000000000000000000000';
      const prismId = 'prism-charlie';
      final existingDate = DateTime.utc(2022, 6, 15);

      await insertMapping(spId, prismId);
      memberRepo.seed(_member(prismId, createdAt: existingDate));

      final preview = await service.preview(_export([_spMember(spId)]));

      expect(preview.matches.first.currentCreatedAt, existingDate);
    });
  });

  group('apply', () {
    test('calls updateMemberFields with created_at for each match', () async {
      final newDate1 = DateTime.utc(2020, 7, 2);
      final newDate2 = DateTime.utc(2021, 3, 10);
      final preview = SpCreationDateBackfillPreview(
        matches: [
          SpCreationDateMatch(
            prismId: 'prism-alpha',
            memberName: 'Alpha',
            currentCreatedAt: DateTime.utc(2024, 1, 1),
            newCreatedAt: newDate1,
          ),
          SpCreationDateMatch(
            prismId: 'prism-beta',
            memberName: 'Beta',
            currentCreatedAt: DateTime.utc(2024, 1, 1),
            newCreatedAt: newDate2,
          ),
        ],
        unmatchedCount: 0,
      );

      memberRepo
        ..seed(_member('prism-alpha'))
        ..seed(_member('prism-beta'));

      final count = await service.apply(preview);

      expect(count, 2);
      expect(memberRepo.updateFieldsCalls, hasLength(2));

      final call1 = memberRepo.updateFieldsCalls.firstWhere(
        (c) => c.id == 'prism-alpha',
      );
      expect(call1.fields['created_at'], newDate1);

      final call2 = memberRepo.updateFieldsCalls.firstWhere(
        (c) => c.id == 'prism-beta',
      );
      expect(call2.fields['created_at'], newDate2);
    });

    test('returns 0 and makes no calls when preview has no matches', () async {
      const preview = SpCreationDateBackfillPreview(
        matches: [],
        unmatchedCount: 3,
      );

      final count = await service.apply(preview);

      expect(count, 0);
      expect(memberRepo.updateFieldsCalls, isEmpty);
    });
  });
}
