import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart' as database;

void main() {
  test(
    'system_settings schema includes pk_group_sync_v2_enabled with default false',
    () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final columns = await db
          .customSelect('PRAGMA table_info(system_settings)')
          .get();
      expect(
        columns
            .map((row) => row.data['name'])
            .contains('pk_group_sync_v2_enabled'),
        isTrue,
      );

      final settings = await db.systemSettingsDao.getSettings();
      expect(settings.pkGroupSyncV2Enabled, isFalse);

      await db.systemSettingsDao.updatePkGroupSyncV2Enabled(true);
      final updated = await db.systemSettingsDao.getSettings();
      expect(updated.pkGroupSyncV2Enabled, isTrue);
    },
  );
}
