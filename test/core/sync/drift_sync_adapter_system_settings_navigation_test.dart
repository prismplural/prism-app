import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart' as database;
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';

void main() {
  test(
    'system_settings apply ignores nav layout while nav sync is disabled',
    () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final dao = db.systemSettingsDao;
      await dao.getSettings();
      await dao.updateSyncNavigationEnabled(false);
      await dao.updateNavBarItems('["home","settings"]');
      await dao.updateNavBarOverflowItems('["members"]');
      await dao.updateNavBarLabelDisplayMode(0);
      await dao.updateNavBarRevealLabelsWhenExpanded(true);

      final settingsEntity = buildSyncAdapterWithCompletion(
        db,
      ).adapter.entities.singleWhere((e) => e.tableName == 'system_settings');

      final exported = settingsEntity.toSyncFields(await dao.getSettings());
      expect(exported['sync_navigation_enabled'], isFalse);
      expect(exported, isNot(contains('nav_bar_items')));
      expect(exported, isNot(contains('nav_bar_overflow_items')));
      expect(exported, isNot(contains('nav_bar_label_display_mode')));
      expect(exported, isNot(contains('nav_bar_reveal_labels_when_expanded')));

      final readBack = await settingsEntity.readRow('singleton');
      expect(readBack, isNotNull);
      expect(readBack!['sync_navigation_enabled'], isFalse);
      expect(readBack, isNot(contains('nav_bar_items')));
      expect(readBack, isNot(contains('nav_bar_overflow_items')));
      expect(readBack, isNot(contains('nav_bar_label_display_mode')));
      expect(readBack, isNot(contains('nav_bar_reveal_labels_when_expanded')));

      await settingsEntity.applyFields('singleton', {
        'system_name': 'Remote rename',
        'sync_navigation_enabled': false,
        'nav_bar_items': '["settings","members"]',
        'nav_bar_overflow_items': '["home"]',
        'nav_bar_label_display_mode': 1,
        'nav_bar_reveal_labels_when_expanded': false,
        'is_deleted': false,
      });

      final row = await dao.getSettings();
      expect(row.systemName, 'Remote rename');
      expect(row.syncNavigationEnabled, isFalse);
      expect(row.navBarItems, '["home","settings"]');
      expect(row.navBarOverflowItems, '["members"]');
      expect(row.navBarLabelDisplayMode, 0);
      expect(row.navBarRevealLabelsWhenExpanded, isTrue);
    },
  );

  test(
    'system_settings apply ignores sparse nav layout when local nav sync is disabled',
    () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final dao = db.systemSettingsDao;
      await dao.getSettings();
      await dao.updateSyncNavigationEnabled(false);
      await dao.updateNavBarItems('["home","settings"]');
      await dao.updateNavBarOverflowItems('["members"]');
      await dao.updateNavBarLabelDisplayMode(0);
      await dao.updateNavBarRevealLabelsWhenExpanded(true);

      final settingsEntity = buildSyncAdapterWithCompletion(
        db,
      ).adapter.entities.singleWhere((e) => e.tableName == 'system_settings');

      await settingsEntity.applyFields('singleton', {
        'nav_bar_items': '["settings","members"]',
        'nav_bar_overflow_items': '["home"]',
        'nav_bar_label_display_mode': 1,
        'nav_bar_reveal_labels_when_expanded': false,
        'is_deleted': false,
      });

      final row = await dao.getSettings();
      expect(row.syncNavigationEnabled, isFalse);
      expect(row.navBarItems, '["home","settings"]');
      expect(row.navBarOverflowItems, '["members"]');
      expect(row.navBarLabelDisplayMode, 0);
      expect(row.navBarRevealLabelsWhenExpanded, isTrue);
    },
  );

  test(
    'system_settings apply accepts nav layout when remote re-enables nav sync',
    () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final dao = db.systemSettingsDao;
      await dao.getSettings();
      await dao.updateSyncNavigationEnabled(false);
      await dao.updateNavBarItems('["home","settings"]');
      await dao.updateNavBarOverflowItems('["members"]');

      final settingsEntity = buildSyncAdapterWithCompletion(
        db,
      ).adapter.entities.singleWhere((e) => e.tableName == 'system_settings');

      await settingsEntity.applyFields('singleton', {
        'sync_navigation_enabled': true,
        'nav_bar_items': '["settings","members"]',
        'nav_bar_overflow_items': '["home"]',
        'nav_bar_label_display_mode': 1,
        'nav_bar_reveal_labels_when_expanded': false,
        'is_deleted': false,
      });

      final row = await dao.getSettings();
      expect(row.syncNavigationEnabled, isTrue);
      expect(row.navBarItems, '["settings","members"]');
      expect(row.navBarOverflowItems, '["home"]');
      expect(row.navBarLabelDisplayMode, 1);
      expect(row.navBarRevealLabelsWhenExpanded, isFalse);

      final readBack = await settingsEntity.readRow('singleton');
      expect(readBack, isNotNull);
      expect(readBack!['sync_navigation_enabled'], isTrue);
      expect(readBack['nav_bar_items'], '["settings","members"]');
      expect(readBack['nav_bar_overflow_items'], '["home"]');
      expect(readBack['nav_bar_label_display_mode'], 1);
      expect(readBack['nav_bar_reveal_labels_when_expanded'], isFalse);
    },
  );
}
