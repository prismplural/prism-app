import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart' as database;
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';

void main() {
  test(
    'system_settings.pk_group_sync_v2_enabled round-trips through sync adapter',
    () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await db.systemSettingsDao.getSettings();
      await db.systemSettingsDao.updatePkGroupSyncV2Enabled(true);

      final syncAdapter = buildSyncAdapterWithCompletion(db);
      final settings = syncAdapter.adapter.entities.singleWhere(
        (e) => e.tableName == 'system_settings',
      );

      final packed = settings.toSyncFields(
        await db.systemSettingsDao.getSettings(),
      );
      expect(packed['pk_group_sync_v2_enabled'], isTrue);

      await settings.applyFields('singleton', {
        'pk_group_sync_v2_enabled': false,
        'is_deleted': false,
      });

      final row = await db.systemSettingsDao.getSettings();
      expect(row.pkGroupSyncV2Enabled, isFalse);

      final fields = await settings.readRow('singleton');
      expect(fields, isNotNull);
      expect(fields!['pk_group_sync_v2_enabled'], isFalse);
    },
  );
}
