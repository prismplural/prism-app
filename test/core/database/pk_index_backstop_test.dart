import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';

/// F20: the PK uniqueness backstop indexes are created in migrations/onCreate,
/// but a DB that reached currentSchemaVersion via divergent (renumbered)
/// migration numbering can boot with them absent. beforeOpen re-ensures them.
void main() {
  File dbFileIn(String name) {
    final tempDir = Directory.systemTemp.createTempSync(name);
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });
    return File('${tempDir.path}/db.sqlite');
  }

  Future<String?> indexNamed(AppDatabase db, String name) async {
    final row = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE name = ?",
          variables: [Variable<String>(name)],
        )
        .getSingleOrNull();
    return row?.read<String?>('name');
  }

  test('F20: beforeOpen re-ensures an absent PK uniqueness index', () async {
    final dbFile = dbFileIn('prism_f20_reensure_');

    final db1 = AppDatabase(NativeDatabase(dbFile));
    await db1.customSelect('SELECT 1').get();
    // Simulate the renumbered-DB window: the backstop index is absent.
    await db1.customStatement('DROP INDEX IF EXISTS idx_members_pluralkit_uuid');
    expect(await indexNamed(db1, 'idx_members_pluralkit_uuid'), isNull);
    await db1.close();

    // Reopen — beforeOpen must re-ensure the index.
    final db2 = AppDatabase(NativeDatabase(dbFile));
    addTearDown(db2.close);
    await db2.customSelect('SELECT 1').get();
    expect(
      await indexNamed(db2, 'idx_members_pluralkit_uuid'),
      'idx_members_pluralkit_uuid',
      reason: 'F20: the absent uuid backstop index is re-created on boot',
    );
  });

  test(
      'F20: boot does not brick when pre-existing duplicate uuids block the '
      're-ensure', () async {
    final dbFile = dbFileIn('prism_f20_dup_');

    final db1 = AppDatabase(NativeDatabase(dbFile));
    await db1.customSelect('SELECT 1').get();
    await db1.customStatement('DROP INDEX IF EXISTS idx_members_pluralkit_uuid');
    // Two ACTIVE members sharing a uuid — the UNIQUE re-ensure will fail.
    for (final id in ['m-a', 'm-b']) {
      await db1.into(db1.members).insert(
            MembersCompanion.insert(
              id: id,
              name: id,
              createdAt: DateTime(2026, 1, 1),
              pluralkitUuid: const Value('dup'),
            ),
          );
    }
    await db1.close();

    // Reopen must NOT throw despite the duplicate blocking the index.
    final db2 = AppDatabase(NativeDatabase(dbFile));
    addTearDown(db2.close);
    await db2.customSelect('SELECT 1').get(); // boot survives
    expect(
      await indexNamed(db2, 'idx_members_pluralkit_uuid'),
      isNull,
      reason: 'the index cannot form over duplicates, but boot is not bricked',
    );
  });
}
