import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

void main() {
  group('squashed database baseline', () {
    test('fresh database creates expected indexes and FTS artifacts', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final rows = await db.customSelect('''
        SELECT name
        FROM sqlite_master
        WHERE name IN (
          'idx_members_active',
          'idx_sessions_end',
          'idx_sessions_start',
          'idx_messages_conv_deleted_ts',
          'idx_sessions_deleted_start',
          'idx_sessions_member_deleted_start',
          'idx_sessions_type',
          'idx_habit_completions_habit_deleted_at',
          'idx_poll_votes_option_deleted',
          'idx_poll_options_poll_deleted_order',
          'idx_conversations_deleted_activity',
          'idx_polls_closed_deleted_created',
          'idx_quarantine_entity',
          'idx_member_group_entries_group_deleted',
          'idx_member_group_entries_member_deleted',
          'idx_custom_fields_deleted_order',
          'idx_custom_field_values_field_member',
          'idx_notes_member',
          'idx_notes_all',
          'idx_comments_session',
          'idx_conv_categories_deleted_order',
          'idx_reminders_active_deleted',
          'idx_conversations_category',
          'idx_friends_deleted',
          'chat_messages_fts',
          'chat_messages_fts_insert',
          'chat_messages_fts_update',
          'chat_messages_fts_delete'
        )
      ''').get();

      final names = rows.map((row) => row.read<String>('name')).toSet();

      expect(
        names,
        equals({
          'idx_members_active',
          'idx_sessions_end',
          'idx_sessions_start',
          'idx_messages_conv_deleted_ts',
          'idx_sessions_deleted_start',
          'idx_sessions_member_deleted_start',
          'idx_sessions_type',
          'idx_habit_completions_habit_deleted_at',
          'idx_poll_votes_option_deleted',
          'idx_poll_options_poll_deleted_order',
          'idx_conversations_deleted_activity',
          'idx_polls_closed_deleted_created',
          'idx_quarantine_entity',
          'idx_member_group_entries_group_deleted',
          'idx_member_group_entries_member_deleted',
          'idx_custom_fields_deleted_order',
          'idx_custom_field_values_field_member',
          'idx_notes_member',
          'idx_notes_all',
          'idx_comments_session',
          'idx_conv_categories_deleted_order',
          'idx_reminders_active_deleted',
          'idx_conversations_category',
          'idx_friends_deleted',
          'chat_messages_fts',
          'chat_messages_fts_insert',
          'chat_messages_fts_update',
          'chat_messages_fts_delete',
        }),
      );

      final legacySleepIndex = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE name = 'idx_sleep_end'",
          )
          .get();
      expect(legacySleepIndex, isEmpty);
    });

    test(
      'non-fresh databases are rejected with the v1-baseline error',
      () async {
        final tempDir = Directory.systemTemp.createTempSync('prism_migration_');
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });

        final dbFile = File('${tempDir.path}/legacy.db');
        final rawDb = raw.sqlite3.open(dbFile.path);
        try {
          // Any pre-beta schema version (v30..v58) hits the same rejection.
          rawDb.execute('PRAGMA user_version = 58;');
        } finally {
          rawDb.close();
        }

        final db = AppDatabase(NativeDatabase(dbFile));
        addTearDown(db.close);

        await expectLater(
          db.customSelect('SELECT 1').get(),
          throwsA(
            isA<UnsupportedError>().having(
              (error) => error.message,
              'message',
              contains('Schema baseline was reset to v1'),
            ),
          ),
        );
      },
    );
  });
}
