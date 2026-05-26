// Regression test: local avatar_image_data must survive PK metadata pulls.
//
// Drift's Value.absent() semantics mean that columns omitted from a companion
// passed to .write() are left unchanged in the database. The PK pull companions
// (both insert and update paths) never mention avatarImageData, so the field is
// always absent — and therefore always preserved. This test pins that guarantee
// so future edits to those companions cannot silently regress it.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_groups_importer.dart';

// ─── Minimal fake member repository (mirrors pk_groups_importer_test.dart) ──

class _FakeMemberRepo implements MemberRepository {
  final List<domain.Member> members;
  _FakeMemberRepo(this.members);

  @override
  Future<List<domain.Member>> getAllMembers() async => members;

  @override
  Future<List<domain.Member>> getAllMembersIncludingDeleted() async => members;

  @override
  Future<domain.Member?> getMemberById(String id) async =>
      members.cast<domain.Member?>().firstWhere(
        (m) => m!.id == id,
        orElse: () => null,
      );

  @override
  Future<List<domain.Member>> getMembersByIds(List<String> ids) async =>
      members.where((m) => ids.contains(m.id)).toList();

  @override
  Stream<List<domain.Member>> watchMembersByIds(List<String> ids) =>
      throw UnimplementedError();

  @override
  Future<void> createMember(domain.Member m) async => members.add(m);

  @override
  Future<void> updateMember(domain.Member m) async {
    final i = members.indexWhere((x) => x.id == m.id);
    if (i >= 0) members[i] = m;
  }

  @override
  Future<int> updateMemberFields(
    String id,
    Map<String, dynamic> changedFields,
  ) async => throw UnimplementedError();

  @override
  Future<void> deleteMember(String id) async =>
      members.removeWhere((m) => m.id == id);

  @override
  Stream<List<domain.Member>> watchAllMembers() => throw UnimplementedError();

  @override
  Stream<List<domain.Member>> watchActiveMembers() =>
      throw UnimplementedError();

  @override
  Stream<domain.Member?> watchMemberById(String id) =>
      throw UnimplementedError();

  @override
  Future<int> getCount() async => members.length;

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

// ─── Test constants ──────────────────────────────────────────────────────────

/// A recognisable JPEG-like header used as a fixed avatar blob throughout
/// these tests. The bytes are intentionally distinct so debugging a mismatch
/// is obvious.
final _avatarBlob = Uint8List.fromList([
  0xFF, 0xD8, 0xFF, 0xE0, // JPEG SOI + APP0 marker
  0x01, 0x02, 0x03, 0x04, // Sentinel payload bytes
]);

const _groupId = 'pk-group-00000000-0000-0000-0000-000000000001';
const _pkUuid = '00000000-0000-0000-0000-000000000001';
const _pkId = 'ab123';

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    await db.systemSettingsDao.getSettings();
    await db.systemSettingsDao.updatePkGroupSyncV2Enabled(true);
  });

  tearDown(() async {
    await db.close();
  });

  // Helper: seed a group row directly via the DAO with a non-null avatar blob.
  Future<void> seedGroupWithAvatar() async {
    await db.into(db.memberGroups).insert(
      MemberGroupsCompanion.insert(
        id: _groupId,
        name: 'Original Name',
        createdAt: DateTime.utc(2026, 1, 1),
        pluralkitId: const Value(_pkId),
        pluralkitUuid: const Value(_pkUuid),
        avatarImageData: Value(_avatarBlob),
      ),
    );
  }

  test(
    'avatar_image_data is byte-identical after PK metadata overwrite '
    '(overwriteMetadata=true)',
    () async {
      // Seed a locally-stored avatar blob.
      await seedGroupWithAvatar();

      final importer = PkGroupsImporter(
        db: db,
        memberRepository: _FakeMemberRepo(const []),
      );

      // Pull a PK payload with different name/description/color and NO
      // avatar_image_data. overwriteMetadata=true triggers the companion
      // that overwrites name/description/colorHex. avatarImageData is absent
      // from that companion, so it must survive unchanged.
      await importer.importGroups(
        [
          const PKGroup(
            id: _pkId,
            uuid: _pkUuid,
            name: 'PK Name After Pull',
            description: 'PK description',
            color: 'aabbcc',
            memberIds: [],
          ),
        ],
        overwriteMetadata: true,
      );

      final stored = await db.memberGroupsDao.getGroupById(_groupId);
      expect(stored, isNotNull);

      // Metadata fields were overwritten as expected (sanity check).
      expect(stored!.name, 'PK Name After Pull');
      expect(stored.colorHex, '#aabbcc');

      // avatarImageData must be byte-identical to the seeded blob.
      expect(
        stored.avatarImageData,
        equals(_avatarBlob),
        reason:
            'PK pull must never clobber local avatar_image_data — '
            'avatarImageData must be absent from the update companion',
      );
    },
  );

  test(
    'avatar_image_data is byte-identical after background sync pull '
    '(overwriteMetadata=false)',
    () async {
      // Seed a locally-stored avatar blob.
      await seedGroupWithAvatar();

      final importer = PkGroupsImporter(
        db: db,
        memberRepository: _FakeMemberRepo(const []),
      );

      // Background sync — only last_seen_from_pk_at and PK linkage fields
      // are written. avatarImageData must also survive here.
      await importer.importGroups(
        [
          const PKGroup(
            id: _pkId,
            uuid: _pkUuid,
            name: 'PK Name Background',
            description: 'ignored in background sync',
            color: 'ffffff',
            memberIds: [],
          ),
        ],
        overwriteMetadata: false,
      );

      final stored = await db.memberGroupsDao.getGroupById(_groupId);
      expect(stored, isNotNull);

      // Name is preserved (background sync doesn't overwrite metadata).
      expect(stored!.name, 'Original Name');

      // avatarImageData must be byte-identical to the seeded blob.
      expect(
        stored.avatarImageData,
        equals(_avatarBlob),
        reason:
            'Background sync must not touch avatar_image_data — '
            'avatarImageData must be absent from the update companion',
      );
    },
  );
}
