import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';

/// idx_custom_field_values_field_member and
/// idx_member_profile_pref_member_key are created in migrations/onCreate,
/// but a DB that reached currentSchemaVersion via divergent (renumbered) or
/// interrupted migration numbering can boot with them absent, letting
/// duplicate live rows accumulate. beforeOpen re-ensures them, mirroring
/// the PK-index backstop.
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
          'SELECT name FROM sqlite_master WHERE name = ?',
          variables: [Variable<String>(name)],
        )
        .getSingleOrNull();
    return row?.read<String?>('name');
  }

  test(
      'beforeOpen re-ensures an absent idx_custom_field_values_field_member',
      () async {
    final dbFile = dbFileIn('prism_cfv_reensure_');

    final db1 = AppDatabase(NativeDatabase(dbFile));
    await db1.customSelect('SELECT 1').get();
    await db1.customStatement(
      'DROP INDEX IF EXISTS idx_custom_field_values_field_member',
    );
    expect(
      await indexNamed(db1, 'idx_custom_field_values_field_member'),
      isNull,
    );
    await db1.close();

    // Reopen — beforeOpen must re-ensure the index.
    final db2 = AppDatabase(NativeDatabase(dbFile));
    addTearDown(db2.close);
    await db2.customSelect('SELECT 1').get();
    expect(
      await indexNamed(db2, 'idx_custom_field_values_field_member'),
      'idx_custom_field_values_field_member',
      reason: 'the absent field/member backstop index is re-created on boot',
    );
  });

  test(
      'boot folds duplicate live (custom_field_id, member_id) rows and then '
      'forms the custom_field_values index', () async {
    final dbFile = dbFileIn('prism_cfv_dup_');

    final db1 = AppDatabase(NativeDatabase(dbFile));
    await db1.customSelect('SELECT 1').get();
    await db1.customStatement(
      'DROP INDEX IF EXISTS idx_custom_field_values_field_member',
    );
    // Two live rows sharing (custom_field_id, member_id) — the UNIQUE
    // re-ensure fails until the fold runs.
    for (final id in ['v-a', 'v-b']) {
      await db1.into(db1.customFieldValues).insert(
            CustomFieldValuesCompanion.insert(
              id: id,
              customFieldId: 'field-1',
              memberId: 'member-1',
              value: id,
            ),
          );
    }
    await db1.close();

    // Reopen must fold the duplicates (survivor = highest minted id, the
    // same total order the sync apply path uses) and form the index.
    final db2 = AppDatabase(NativeDatabase(dbFile));
    addTearDown(db2.close);
    await db2.customSelect('SELECT 1').get(); // boot survives
    expect(
      await indexNamed(db2, 'idx_custom_field_values_field_member'),
      'idx_custom_field_values_field_member',
      reason: 'duplicates are folded so the index can form',
    );
    final active = await (db2.select(db2.customFieldValues)
          ..where((v) => v.isDeleted.equals(false)))
        .get();
    expect(active.map((r) => r.id), ['v-b']);
    final folded = await (db2.select(db2.customFieldValues)
          ..where((v) => v.id.equals('v-a')))
        .getSingle();
    expect(folded.isDeleted, isTrue);
  });

  test('beforeOpen re-ensures an absent idx_member_profile_pref_member_key',
      () async {
    final dbFile = dbFileIn('prism_pref_reensure_');

    final db1 = AppDatabase(NativeDatabase(dbFile));
    await db1.customSelect('SELECT 1').get();
    await db1.customStatement(
      'DROP INDEX IF EXISTS idx_member_profile_pref_member_key',
    );
    expect(
      await indexNamed(db1, 'idx_member_profile_pref_member_key'),
      isNull,
    );
    await db1.close();

    // Reopen — beforeOpen must re-ensure the index.
    final db2 = AppDatabase(NativeDatabase(dbFile));
    addTearDown(db2.close);
    await db2.customSelect('SELECT 1').get();
    expect(
      await indexNamed(db2, 'idx_member_profile_pref_member_key'),
      'idx_member_profile_pref_member_key',
      reason: 'the absent member/key backstop index is re-created on boot',
    );
  });

  test(
      'boot does not brick when a pre-existing duplicate live '
      '(member_id, key) pair blocks the preference re-ensure', () async {
    final dbFile = dbFileIn('prism_pref_dup_');

    final db1 = AppDatabase(NativeDatabase(dbFile));
    await db1.customSelect('SELECT 1').get();
    await db1.customStatement(
      'DROP INDEX IF EXISTS idx_member_profile_pref_member_key',
    );
    // Two live rows sharing (member_id, key) — the UNIQUE re-ensure will fail.
    for (final id in ['p-a', 'p-b']) {
      await db1.into(db1.memberProfilePreferenceValues).insert(
            MemberProfilePreferenceValuesCompanion.insert(
              id: id,
              memberId: 'member-1',
              key: 'pronouns',
              valueType: 'string',
            ),
          );
    }
    await db1.close();

    // Reopen must NOT throw despite the duplicate blocking the index.
    final db2 = AppDatabase(NativeDatabase(dbFile));
    addTearDown(db2.close);
    await db2.customSelect('SELECT 1').get(); // boot survives
    expect(
      await indexNamed(db2, 'idx_member_profile_pref_member_key'),
      isNull,
      reason: 'the index cannot form over duplicates, but boot is not bricked',
    );
  });
}
