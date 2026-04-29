import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart' as database;
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';

void main() {
  test(
    '1B prefs (fronting_list_view_mode, add_front_default_behavior, '
    'quick_front_default_behavior) round-trip through sync adapter',
    () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      // Seed the singleton row, then write non-default enum indices for
      // each of the three 1B prefs.
      await db.systemSettingsDao.getSettings();
      // perMemberRows
      await db.systemSettingsDao.updateFrontingListViewMode(1);
      // replace
      await db.systemSettingsDao.updateAddFrontDefaultBehavior(1);
      // replace
      await db.systemSettingsDao.updateQuickFrontDefaultBehavior(1);

      final syncAdapter = buildSyncAdapterWithCompletion(db);
      final settings = syncAdapter.adapter.entities.singleWhere(
        (e) => e.tableName == 'system_settings',
      );

      // toSyncFields emits the three fields with the seeded values.
      final packed = settings.toSyncFields(
        await db.systemSettingsDao.getSettings(),
      );
      expect(packed['fronting_list_view_mode'], 1);
      expect(packed['add_front_default_behavior'], 1);
      expect(packed['quick_front_default_behavior'], 1);

      // applyFields updates the row with new (different) values.
      await settings.applyFields('singleton', {
        'fronting_list_view_mode': 2, // timeline
        'add_front_default_behavior': 0, // additive
        'quick_front_default_behavior': 0, // additive
        'is_deleted': false,
      });

      // The DAO sees the applied values.
      final row = await db.systemSettingsDao.getSettings();
      expect(row.frontingListViewMode, 2);
      expect(row.addFrontDefaultBehavior, 0);
      expect(row.quickFrontDefaultBehavior, 0);

      // readRow returns the same values via the adapter's read path.
      final fields = await settings.readRow('singleton');
      expect(fields, isNotNull);
      expect(fields!['fronting_list_view_mode'], 2);
      expect(fields['add_front_default_behavior'], 0);
      expect(fields['quick_front_default_behavior'], 0);
    },
  );
}
