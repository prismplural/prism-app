import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

Future<void> _seedV35Db(File dbFile, {required bool dropColumns}) async {
  final seeded = AppDatabase(NativeDatabase(dbFile));
  await seeded.customSelect('SELECT 1').get();
  await seeded.close();

  final rawDb = raw.sqlite3.open(dbFile.path);
  try {
    if (dropColumns) {
      rawDb.execute(
        'ALTER TABLE system_settings DROP COLUMN nav_bar_label_display_mode',
      );
      rawDb.execute(
        'ALTER TABLE system_settings '
        'DROP COLUMN nav_bar_reveal_labels_when_expanded',
      );
    }
    rawDb.execute('PRAGMA user_version = 35;');
  } finally {
    rawDb.close();
  }
}

Set<String> _systemSettingsColumns(String path) {
  final db = raw.sqlite3.open(path);
  try {
    return db
        .select('PRAGMA table_info(system_settings)')
        .map((row) => row['name'] as String)
        .toSet();
  } finally {
    db.close();
  }
}

Map<String, Object?> _settingsDefaults(String path) {
  final db = raw.sqlite3.open(path);
  try {
    db.execute(
      "INSERT OR IGNORE INTO system_settings (id) VALUES ('singleton')",
    );
    final row = db.select(
      'SELECT nav_bar_label_display_mode, '
      'nav_bar_reveal_labels_when_expanded '
      'FROM system_settings WHERE id = ?',
      ['singleton'],
    ).single;
    return {
      'nav_bar_label_display_mode': row['nav_bar_label_display_mode'],
      'nav_bar_reveal_labels_when_expanded':
          row['nav_bar_reveal_labels_when_expanded'],
    };
  } finally {
    db.close();
  }
}

void main() {
  test('v35→v36 migration adds nav display columns with defaults', () async {
    final dir = await Directory.systemTemp.createTemp('nav_display_migration');
    addTearDown(() => dir.delete(recursive: true));
    final dbFile = File('${dir.path}/app.db');

    await _seedV35Db(dbFile, dropColumns: true);

    final before = _systemSettingsColumns(dbFile.path);
    expect(before.contains('nav_bar_label_display_mode'), isFalse);
    expect(before.contains('nav_bar_reveal_labels_when_expanded'), isFalse);

    final upgraded = AppDatabase(NativeDatabase(dbFile));
    addTearDown(upgraded.close);
    await upgraded.customSelect('SELECT 1').get();

    final after = _systemSettingsColumns(dbFile.path);
    expect(after.contains('nav_bar_label_display_mode'), isTrue);
    expect(after.contains('nav_bar_reveal_labels_when_expanded'), isTrue);
    expect(_settingsDefaults(dbFile.path), {
      'nav_bar_label_display_mode': 0,
      'nav_bar_reveal_labels_when_expanded': 1,
    });
  });

  test('v35→v36 migration skips columns that already exist', () async {
    final dir = await Directory.systemTemp.createTemp('nav_display_current');
    addTearDown(() => dir.delete(recursive: true));
    final dbFile = File('${dir.path}/app.db');

    await _seedV35Db(dbFile, dropColumns: false);

    final upgraded = AppDatabase(NativeDatabase(dbFile));
    addTearDown(upgraded.close);
    await upgraded.customSelect('SELECT 1').get();

    final after = _systemSettingsColumns(dbFile.path);
    expect(after.contains('nav_bar_label_display_mode'), isTrue);
    expect(after.contains('nav_bar_reveal_labels_when_expanded'), isTrue);
  });
}
