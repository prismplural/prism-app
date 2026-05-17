import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

int _seconds(DateTime value) => value.toUtc().millisecondsSinceEpoch ~/ 1000;

Future<void> _seedV15TimestampCommentShapeDb(File dbFile) async {
  final seeded = AppDatabase(NativeDatabase(dbFile));
  await seeded.customSelect('SELECT 1').get();
  await seeded.close();

  final rawDb = raw.sqlite3.open(dbFile.path);
  try {
    // v18 (members tab preferences) — drop columns added by v17→v18.
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

    // v17 (fronting auto-promotion) — drop column added by v16→v17.
    rawDb.execute(
      'ALTER TABLE system_settings DROP COLUMN auto_promote_long_fronting_sessions',
    );

    rawDb.execute(
      'ALTER TABLE front_session_comments ADD COLUMN target_time INTEGER',
    );
    rawDb.execute(
      'ALTER TABLE front_session_comments ADD COLUMN author_member_id TEXT',
    );
    rawDb.execute(
      'CREATE INDEX idx_comments_target_time '
      'ON front_session_comments (target_time, is_deleted, timestamp ASC)',
    );

    final insert = rawDb.prepare('''
      INSERT INTO front_session_comments (
        id,
        session_id,
        body,
        timestamp,
        created_at,
        is_deleted,
        target_time,
        author_member_id
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ''');
    try {
      final validTimestamp = DateTime.utc(2026, 4, 30, 10, 15);
      final deletedTimestamp = DateTime.utc(2026, 4, 30, 10, 30);
      final blankTimestamp = DateTime.utc(2026, 4, 30, 10, 45);
      insert.execute([
        'valid-session-comment',
        'session-parent',
        'kept',
        _seconds(validTimestamp),
        _seconds(DateTime.utc(2026, 4, 30, 10, 20)),
        0,
        _seconds(validTimestamp),
        'author-a',
      ]);
      insert.execute([
        'deleted-session-comment',
        'session-parent',
        'deleted tombstone kept',
        _seconds(deletedTimestamp),
        _seconds(DateTime.utc(2026, 4, 30, 10, 35)),
        1,
        _seconds(deletedTimestamp),
        'author-a',
      ]);
      insert.execute([
        'blank-timestamp-comment',
        '',
        'dropped timestamp-only row',
        _seconds(blankTimestamp),
        _seconds(DateTime.utc(2026, 4, 30, 10, 50)),
        0,
        _seconds(blankTimestamp),
        'author-b',
      ]);
    } finally {
      insert.close();
    }

    rawDb.execute('ALTER TABLE members DROP COLUMN pluralkit_display_name');

    // Flattened v18→v19: drop pending_pk_op so onUpgrade can re-add it.

    rawDb.execute('ALTER TABLE member_group_entries DROP COLUMN pending_pk_op');

    rawDb.execute('ALTER TABLE system_settings DROP COLUMN bio_markdown_enabled');
    // Drop columns added by v21-v23 so their migrations can re-add them when
    // stepping forward through v15 -> current.
    rawDb.execute('ALTER TABLE member_groups DROP COLUMN sort_state');
    rawDb.execute(
      'ALTER TABLE plural_kit_sync_state DROP COLUMN direction_confirmed',
    );
    rawDb.execute('ALTER TABLE system_settings DROP COLUMN palette_source');
    rawDb.execute(
      'ALTER TABLE system_settings DROP COLUMN palette_seed_color_hex',
    );
    rawDb.execute('ALTER TABLE system_settings DROP COLUMN palette_mood');
    rawDb.execute('ALTER TABLE system_settings DROP COLUMN palette_contrast');
    rawDb.execute('ALTER TABLE conversations DROP COLUMN includes_all_members');
    rawDb.execute('PRAGMA user_version = 15;');
  } finally {
    rawDb.close();
  }
}

void main() {
  group('schema v15 -> v16 front_session_comments cleanup', () {
    test('preserves session-attached rows, drops blank timestamp-shaped rows, '
        'and removes abandoned columns/index', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'prism_migration_v15_to_v16_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final dbFile = File('${tempDir.path}/v15_to_v16.db');
      await _seedV15TimestampCommentShapeDb(dbFile);

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      final version = await upgraded
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.read<int>('user_version'), 24);

      final cols = await upgraded
          .customSelect("PRAGMA table_info('front_session_comments')")
          .get();
      final colNames = cols.map((row) => row.read<String>('name')).toSet();
      expect(colNames, contains('session_id'));
      expect(colNames, contains('timestamp'));
      expect(colNames, contains('created_at'));
      expect(colNames, isNot(contains('target_time')));
      expect(colNames, isNot(contains('author_member_id')));

      final indexes = await upgraded
          .customSelect("PRAGMA index_list('front_session_comments')")
          .get();
      final indexNames = indexes.map((row) => row.read<String>('name')).toSet();
      expect(indexNames, contains('idx_comments_session'));
      expect(indexNames, isNot(contains('idx_comments_target_time')));

      final rows = await upgraded.select(upgraded.frontSessionComments).get();
      final rowsById = {for (final row in rows) row.id: row};
      expect(
        rowsById.keys,
        unorderedEquals(['valid-session-comment', 'deleted-session-comment']),
      );
      expect(
        rowsById,
        isNot(containsPair('blank-timestamp-comment', anything)),
      );

      final valid = rowsById['valid-session-comment']!;
      expect(valid.sessionId, 'session-parent');
      expect(valid.body, 'kept');
      expect(valid.timestamp.toUtc(), DateTime.utc(2026, 4, 30, 10, 15));
      expect(valid.createdAt.toUtc(), DateTime.utc(2026, 4, 30, 10, 20));
      expect(valid.isDeleted, isFalse);

      final deleted = rowsById['deleted-session-comment']!;
      expect(deleted.sessionId, 'session-parent');
      expect(deleted.body, 'deleted tombstone kept');
      expect(deleted.timestamp.toUtc(), DateTime.utc(2026, 4, 30, 10, 30));
      expect(deleted.createdAt.toUtc(), DateTime.utc(2026, 4, 30, 10, 35));
      expect(deleted.isDeleted, isTrue);
    });
  });
}
