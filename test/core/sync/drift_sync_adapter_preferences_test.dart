import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';

void main() {
  test('app preference sync apply preserves unknown keys as rows', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final entity = buildSyncAdapterWithCompletion(
      db,
    ).adapter.entityForTable('app_preference_values')!;

    await entity.applyFields('future.pref', {
      'value_type': 'string',
      'value_json': '"hello"',
      'is_deleted': false,
    });

    final row = await (db.select(
      db.appPreferenceValues,
    )..where((p) => p.key.equals('future.pref'))).getSingle();
    expect(row.valueType, 'string');
    expect(row.valueJson, '"hello"');
  });

  test(
    'member profile preference sync apply accepts delayed parent rows',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final entity = buildSyncAdapterWithCompletion(
        db,
      ).adapter.entityForTable('member_profile_preference_values')!;

      await entity.applyFields('bTE:profile.future', {
        'member_id': 'm1',
        'key': 'profile.future',
        'value_type': 'bool',
        'value_json': 'true',
        'is_deleted': false,
      });

      final row = await (db.select(
        db.memberProfilePreferenceValues,
      )..where((p) => p.id.equals('bTE:profile.future'))).getSingle();
      expect(row.memberId, 'm1');
      expect(row.key, 'profile.future');
    },
  );
}
