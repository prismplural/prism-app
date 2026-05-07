import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

Future<void> _seedV17Db(File dbFile) async {
  final seeded = AppDatabase(NativeDatabase(dbFile));
  await seeded.customSelect('SELECT 1').get();
  await seeded.systemSettingsDao.updateSystemName('V17 System');
  await seeded.systemSettingsDao.updateAccentColorHex('#112233');
  await seeded.close();

  final rawDb = raw.sqlite3.open(dbFile.path);
  try {
    rawDb.execute(
      'ALTER TABLE system_settings DROP COLUMN members_show_pronouns',
    );
    rawDb.execute(
      'ALTER TABLE system_settings DROP COLUMN members_show_front_buttons',
    );
    rawDb.execute(
      'ALTER TABLE system_settings DROP COLUMN members_front_button_behavior',
    );
    rawDb.execute(
      'ALTER TABLE system_settings DROP COLUMN members_list_view_mode',
    );
    rawDb.execute(
      'ALTER TABLE system_settings DROP COLUMN members_grouped_default_state',
    );
    rawDb.execute(
      'ALTER TABLE system_settings DROP COLUMN members_folder_member_visibility',
    );
    rawDb.execute('PRAGMA user_version = 17;');
  } finally {
    rawDb.close();
  }
}

void main() {
  group('schema v17 -> v18 members tab preferences migration', () {
    test(
      'adds collapsed preference columns with defaults and preserves row',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'prism_migration_v17_to_v18_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });

        final dbFile = File('${tempDir.path}/v17_to_v18.db');
        await _seedV17Db(dbFile);

        final upgraded = AppDatabase(NativeDatabase(dbFile));
        addTearDown(upgraded.close);
        await upgraded.customSelect('SELECT 1').get();

        final version = await upgraded
            .customSelect('PRAGMA user_version')
            .getSingle();
        expect(version.read<int>('user_version'), 18);

        final cols = await upgraded
            .customSelect('PRAGMA table_info(system_settings)')
            .get();
        final colNames = cols.map((row) => row.read<String>('name')).toSet();
        expect(colNames, contains('members_list_view_mode'));
        expect(colNames, contains('members_grouped_default_state'));
        expect(colNames, contains('members_folder_member_visibility'));
        expect(colNames, contains('members_show_pronouns'));
        expect(colNames, contains('members_show_front_buttons'));
        expect(colNames, contains('members_front_button_behavior'));

        final settings = await upgraded.systemSettingsDao.getSettings();
        expect(settings.systemName, 'V17 System');
        expect(settings.accentColorHex, '#112233');
        expect(settings.membersListViewMode, 0);
        expect(settings.membersGroupedDefaultState, 0);
        expect(settings.membersFolderMemberVisibility, 0);
        expect(settings.membersShowPronouns, isTrue);
        expect(settings.membersShowFrontButtons, isFalse);
        expect(settings.membersFrontButtonBehavior, 0);
      },
    );
  });
}
