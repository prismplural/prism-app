import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/member_groups_dao.dart';
import 'package:prism_plurality/data/repositories/drift_member_groups_repository.dart';
import 'package:prism_plurality/domain/models/member_group.dart' as domain;
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/domain/models/member.dart' as member_domain;
import 'package:prism_plurality/shared/utils/avatar_normalizer.dart';

/// Minimal recording repo that suppresses sync emissions.
class _RecordingRepo extends DriftMemberGroupsRepository {
  _RecordingRepo(MemberGroupsDao dao)
      : super(dao, null, memberRepository: const _NoopMemberRepository());

  @override
  Future<void> syncRecordCreate(
    String table,
    String entityId,
    Map<String, dynamic> fields,
  ) async {}

  @override
  Future<void> syncRecordUpdate(
    String table,
    String entityId,
    Map<String, dynamic> fields,
  ) async {}

  @override
  Future<void> syncRecordDelete(String table, String entityId) async {}
}

class _NoopMemberRepository implements MemberRepository {
  const _NoopMemberRepository();

  @override
  Future<member_domain.Member?> getMemberById(String id) async => null;

  @override
  Future<List<member_domain.Member>> getMembersByIds(List<String> ids) async =>
      const [];

  @override
  Future<void> clearPluralKitLink(String id) async =>
      throw UnimplementedError();
  @override
  Future<void> createMember(member_domain.Member member) async =>
      throw UnimplementedError();
  @override
  Future<void> deleteMember(String id) async => throw UnimplementedError();
  @override
  Future<List<member_domain.Member>> getAllMembers() async =>
      throw UnimplementedError();
  @override
  Future<List<member_domain.Member>> getAllMembersIncludingDeleted() async =>
      throw UnimplementedError();
  @override
  Future<int> getCount() async => throw UnimplementedError();
  @override
  Future<List<member_domain.Member>> getDeletedLinkedMembers() async =>
      throw UnimplementedError();
  @override
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) async =>
      throw UnimplementedError();
  @override
  Future<void> updateMember(member_domain.Member member) async =>
      throw UnimplementedError();
  @override
  Stream<List<member_domain.Member>> watchActiveMembers() =>
      throw UnimplementedError();
  @override
  Stream<List<member_domain.Member>> watchAllMembers() =>
      throw UnimplementedError();
  @override
  Stream<member_domain.Member?> watchMemberById(String id) =>
      throw UnimplementedError();
  @override
  Stream<List<member_domain.Member>> watchMembersByIds(List<String> ids) =>
      throw UnimplementedError();
  @override
  Future<({member_domain.Member member, bool wasCreated})>
      ensureUnknownSentinelMember() => throw UnimplementedError();
}

/// Generates image bytes well over [AvatarNormalizer.targetMaxBytes].
///
/// Solid-color PNG compresses too well to exceed 256 KB, so we generate a
/// pseudo-noise image encoded as a high-quality JPEG (which produces large
/// files for noisy content) instead of a PNG. The normalizer accepts any
/// format that `img.decodeImage` handles.
Uint8List _oversizedBytes({int width = 900, int height = 900}) {
  final source = img.Image(width: width, height: height);
  // Pseudo-random pixel pattern defeats JPEG DCT compression.
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      source.setPixelRgb(
        x,
        y,
        (x * 7 + y * 3 + 13) % 256,
        (x * 11 + y * 5 + 37) % 256,
        (x * 3 + y * 17 + 71) % 256,
      );
    }
  }
  return Uint8List.fromList(img.encodeJpg(source, quality: 100));
}

/// Generates a small JPEG within both dimension and byte limits.
Uint8List _smallJpeg() {
  final source = img.Image(width: 64, height: 64);
  img.fill(source, color: img.ColorRgb8(100, 150, 200));
  final bytes = Uint8List.fromList(img.encodeJpg(source, quality: 85));
  // Verify the fixture is already conforming so idempotent-path tests are valid.
  assert(
    bytes.length <= AvatarNormalizer.targetMaxBytes,
    'Small JPEG fixture exceeds targetMaxBytes — adjust size',
  );
  assert(
    bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF,
    'Fixture must be a JPEG',
  );
  return bytes;
}

domain.MemberGroup _group({required String id, Uint8List? avatar}) =>
    domain.MemberGroup(
      id: id,
      name: id,
      createdAt: DateTime.utc(2026, 1, 1),
      avatarImageData: avatar,
    );

Future<Uint8List?> _readStoredAvatar(AppDatabase db, String groupId) async {
  final row = await (db.select(db.memberGroups)
        ..where((g) => g.id.equals(groupId)))
      .getSingleOrNull();
  return row?.avatarImageData;
}

void main() {
  late AppDatabase db;
  late MemberGroupsDao dao;
  late _RecordingRepo repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = db.memberGroupsDao;
    repo = _RecordingRepo(dao);
  });

  tearDown(() async {
    await db.close();
  });

  group('avatar normalization — createGroup', () {
    test('large raw image normalizes to ≤ targetMaxBytes JPEG', () async {
      final pngBytes = _oversizedBytes();
      // Sanity: the raw bytes must exceed the budget for the test to be meaningful.
      expect(pngBytes.length, greaterThan(AvatarNormalizer.targetMaxBytes));

      await repo.createGroup(_group(id: 'g1', avatar: pngBytes));

      final stored = await _readStoredAvatar(db, 'g1');
      expect(stored, isNotNull);
      expect(
        stored!.length,
        lessThanOrEqualTo(AvatarNormalizer.targetMaxBytes),
      );
      // Must be JPEG after normalization.
      expect(stored[0], 0xFF);
      expect(stored[1], 0xD8);
      expect(stored[2], 0xFF);
    });

    test('null avatar stores null', () async {
      await repo.createGroup(_group(id: 'g2', avatar: null));

      final stored = await _readStoredAvatar(db, 'g2');
      expect(stored, isNull);
    });

    test('already-conforming JPEG stores byte-identical bytes (idempotent fast-path)',
        () async {
      final jpeg = _smallJpeg();

      await repo.createGroup(_group(id: 'g3', avatar: jpeg));

      final stored = await _readStoredAvatar(db, 'g3');
      expect(stored, isNotNull);
      expect(stored!.length, jpeg.length);
      // Byte-for-byte identical — no re-encoding occurred.
      expect(stored, equals(jpeg));
    });
  });

  group('avatar normalization — updateGroup', () {
    test('over-sized blob normalizes on update', () async {
      // Create with null avatar first.
      await repo.createGroup(_group(id: 'g4', avatar: null));

      final pngBytes = _oversizedBytes(width: 1024, height: 768);
      expect(pngBytes.length, greaterThan(AvatarNormalizer.targetMaxBytes));

      final withAvatar = _group(id: 'g4', avatar: pngBytes);
      // Assign the display_order that the repo would have assigned on create.
      final storedInitial = await (db.select(db.memberGroups)
            ..where((g) => g.id.equals('g4')))
          .getSingle();
      await repo.updateGroup(
        withAvatar.copyWith(displayOrder: storedInitial.displayOrder),
      );

      final stored = await _readStoredAvatar(db, 'g4');
      expect(stored, isNotNull);
      expect(
        stored!.length,
        lessThanOrEqualTo(AvatarNormalizer.targetMaxBytes),
      );
      expect(stored[0], 0xFF);
      expect(stored[1], 0xD8);
      expect(stored[2], 0xFF);
    });
  });
}
