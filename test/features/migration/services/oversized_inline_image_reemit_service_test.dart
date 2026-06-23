import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/features/migration/services/oversized_inline_image_reemit_service.dart';

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

Uint8List _bytes(int len, {int fill = 7}) =>
    Uint8List.fromList(List<int>.filled(len, fill));

Future<void> _insertMember(
  AppDatabase db, {
  required String id,
  Uint8List? avatar,
  Uint8List? header,
  Uint8List? pkBanner,
  bool isDeleted = false,
}) async {
  await db.into(db.members).insert(
        MembersCompanion.insert(
          id: id,
          name: 'M $id',
          createdAt: DateTime.utc(2026, 6, 4),
          avatarImageData: Value(avatar),
          profileHeaderImageData: Value(header),
          pkBannerImageData: Value(pkBanner),
          isDeleted: Value(isDeleted),
        ),
      );
}

class _Captured {
  _Captured(this.table, this.entityId, this.fields);
  final String table;
  final String entityId;
  final Map<String, dynamic> fields;
}

void main() {
  late AppDatabase db;
  late List<_Captured> updates;

  // Stand-in encoders: avoid real image decode in a unit test. The service only
  // cares that the result is under budget and smaller than the input.
  Future<Uint8List?> fakeAvatar(Uint8List input) async =>
      _bytes(8 * 1024, fill: 1);
  Future<Uint8List> fakeHeader(Uint8List input) async => _bytes(16 * 1024, fill: 2);

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    db = _makeDb();
    updates = [];
  });

  tearDown(() async {
    await db.close();
  });

  OversizedInlineImageReemitService service() {
    return OversizedInlineImageReemitService(
      db: db,
      recordUpdate: ({required table, required entityId, required fields}) async {
        updates.add(_Captured(table, entityId, fields));
      },
      avatarNormalizer: fakeAvatar,
      headerNormalizer: fakeHeader,
    );
  }

  test('re-normalizes an oversized avatar, writes it back, and re-emits',
      () async {
    final big = _bytes(700 * 1024); // > 512 KB budget
    await _insertMember(db, id: 'big-avatar', avatar: big);

    final result = await service().runOnce();

    expect(result.membersRepaired, 1);
    expect(result.fieldsReemitted, 1);
    expect(updates, hasLength(1));
    expect(updates.single.table, 'members');
    expect(updates.single.entityId, 'big-avatar');
    expect(
      updates.single.fields['avatar_image_data'],
      base64Encode(_bytes(8 * 1024, fill: 1)),
    );

    // Local DB now holds the shrunk avatar, not the oversized one.
    final stored = await (db.select(db.members)
          ..where((t) => t.id.equals('big-avatar')))
        .getSingle();
    expect(stored.avatarImageData, _bytes(8 * 1024, fill: 1));
  });

  test('repairs oversized header and pk banner fields too', () async {
    await _insertMember(
      db,
      id: 'big-banners',
      header: _bytes(900 * 1024),
      pkBanner: _bytes(600 * 1024),
    );

    final result = await service().runOnce();

    expect(result.membersRepaired, 1);
    expect(result.fieldsReemitted, 2);
    final fields = updates.single.fields;
    expect(fields.containsKey('profile_header_image_data'), isTrue);
    expect(fields.containsKey('pk_banner_image_data'), isTrue);
    expect(fields.containsKey('avatar_image_data'), isFalse);
  });

  test('leaves in-budget images untouched', () async {
    await _insertMember(db, id: 'small', avatar: _bytes(200 * 1024));
    await _insertMember(db, id: 'header-at-cap', header: _bytes(512 * 1024));

    final result = await service().runOnce();

    expect(result.membersRepaired, 0);
    expect(updates, isEmpty);
  });

  test('skips deleted members', () async {
    await _insertMember(
      db,
      id: 'gone',
      avatar: _bytes(700 * 1024),
      isDeleted: true,
    );

    final result = await service().runOnce();

    expect(result.membersRepaired, 0);
    expect(updates, isEmpty);
  });

  test('runs once: second invocation is a no-op', () async {
    await _insertMember(db, id: 'big-avatar', avatar: _bytes(700 * 1024));

    final first = await service().runOnce();
    expect(first.membersRepaired, 1);

    updates.clear();
    final second = await service().runOnce();
    expect(second.alreadyCompleted, isTrue);
    expect(second.membersRepaired, 0);
    expect(updates, isEmpty);
  });

  test('does not make a row worse if re-encode fails to shrink it', () async {
    // Normalizer returns something still over budget -> field is skipped.
    final svc = OversizedInlineImageReemitService(
      db: db,
      recordUpdate: ({required table, required entityId, required fields}) async {
        updates.add(_Captured(table, entityId, fields));
      },
      avatarNormalizer: (input) async => _bytes(800 * 1024), // still oversized
      headerNormalizer: fakeHeader,
    );
    await _insertMember(db, id: 'stubborn', avatar: _bytes(700 * 1024));

    final result = await svc.runOnce();

    expect(result.membersRepaired, 0);
    expect(updates, isEmpty);
    // Original bytes preserved (not overwritten with a still-oversized blob).
    final stored = await (db.select(db.members)
          ..where((t) => t.id.equals('stubborn')))
        .getSingle();
    expect(stored.avatarImageData!.length, 700 * 1024);
  });
}
