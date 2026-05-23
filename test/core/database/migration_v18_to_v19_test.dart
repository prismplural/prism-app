import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

Future<void> _seedV18Db(File dbFile) async {
  final seeded = AppDatabase(NativeDatabase(dbFile));
  await seeded.customSelect('SELECT 1').get();
  await seeded.close();

  final rawDb = raw.sqlite3.open(dbFile.path);
  try {
    final now = DateTime.utc(2026, 5, 9, 12).millisecondsSinceEpoch ~/ 1000;

    rawDb.execute(
      '''
      INSERT INTO conversations (id, created_at, last_activity_at, title)
      VALUES (?, ?, ?, ?)
      ''',
      ['conv-v18', now, now, 'V18 conversation'],
    );
    rawDb.execute(
      '''
      INSERT INTO chat_messages
        (id, content, timestamp, conversation_id)
      VALUES (?, ?, ?, ?)
      ''',
      ['msg-v18', 'alpha searchable message', now, 'conv-v18'],
    );
    rawDb.execute(
      '''
      INSERT INTO members (id, name, created_at, pluralkit_id, display_name)
      VALUES (?, ?, ?, ?, ?)
      ''',
      ['member-v18', 'Member V18', now, 'pk123', 'Legacy Display'],
    );
    rawDb.execute(
      '''
      INSERT INTO member_groups (id, name, created_at)
      VALUES (?, ?, ?)
      ''',
      ['group-v18', 'Group V18', now],
    );
    rawDb.execute(
      '''
      INSERT INTO member_group_entries (id, group_id, member_id)
      VALUES (?, ?, ?)
      ''',
      ['entry-v18', 'group-v18', 'member-v18'],
    );

    rawDb.execute('DROP TRIGGER IF EXISTS chat_messages_fts_insert');
    rawDb.execute('DROP TRIGGER IF EXISTS chat_messages_fts_update');
    rawDb.execute('DROP TRIGGER IF EXISTS chat_messages_fts_delete');
    rawDb.execute('DROP TABLE IF EXISTS chat_messages_fts');
    rawDb.execute('''
      CREATE VIRTUAL TABLE chat_messages_fts USING fts5(
        content,
        message_id UNINDEXED,
        conversation_id UNINDEXED,
        tokenize='unicode61 remove_diacritics 2'
      )
    ''');
    rawDb.execute('''
      INSERT INTO chat_messages_fts (content, message_id, conversation_id)
      SELECT content, id, conversation_id FROM chat_messages
      WHERE is_deleted = 0 AND is_system_message = 0 AND content != ''
      ''');

    rawDb.execute('ALTER TABLE member_group_entries DROP COLUMN pending_pk_op');
    rawDb.execute('ALTER TABLE members DROP COLUMN pluralkit_display_name');
    rawDb.execute(
      'ALTER TABLE system_settings DROP COLUMN bio_markdown_enabled',
    );
    // Drop columns added by v21-v25 so their migrations can re-add them when
    // stepping forward through v18 -> current.
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
    rawDb.execute('PRAGMA user_version = 18;');
  } finally {
    rawDb.close();
  }
}

void main() {
  group('schema v18 -> v19 flattened post-0.8.0 migration', () {
    test('rebuilds FTS and adds both flattened columns', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'prism_migration_v18_to_v19_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final dbFile = File('${tempDir.path}/v18_to_v19.db');
      await _seedV18Db(dbFile);

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      final version = await upgraded
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.read<int>('user_version'), 27);

      final entryCols = await upgraded
          .customSelect('PRAGMA table_info(member_group_entries)')
          .get();
      expect(
        entryCols.map((row) => row.read<String>('name')).toSet(),
        contains('pending_pk_op'),
      );

      final memberCols = await upgraded
          .customSelect('PRAGMA table_info(members)')
          .get();
      expect(
        memberCols.map((row) => row.read<String>('name')).toSet(),
        contains('pluralkit_display_name'),
      );

      final entry = await upgraded
          .customSelect(
            'SELECT pending_pk_op FROM member_group_entries WHERE id = ?',
            variables: [Variable.withString('entry-v18')],
          )
          .getSingle();
      expect(entry.read<String>('pending_pk_op'), 'none');

      final member = await upgraded
          .customSelect(
            '''
            SELECT display_name, pluralkit_display_name
            FROM members
            WHERE id = ?
            ''',
            variables: [Variable.withString('member-v18')],
          )
          .getSingle();
      expect(member.read<String>('display_name'), 'Legacy Display');
      expect(member.readNullable<String>('pluralkit_display_name'), isNull);

      final ftsSql = await upgraded.customSelect('''
            SELECT sql FROM sqlite_master
            WHERE type = 'table' AND name = 'chat_messages_fts'
            ''').getSingle();
      expect(ftsSql.read<String>('sql'), contains("prefix='2 3 4'"));

      final hits = await upgraded.chatMessagesDao.searchMessages('alpha');
      expect(hits.map((hit) => hit.messageId), contains('msg-v18'));
    });
  });
}
