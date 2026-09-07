import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

const _fixturePath = 'test/core/database/fixtures/v0_13_1_schema.sql';

/// Seeds released v0.13.1 DDL with synthetic data.
Future<File> _seedReleasedV0131Database(String name) async {
  final temporaryDirectory = Directory.systemTemp.createTempSync(name);
  addTearDown(() {
    if (temporaryDirectory.existsSync()) {
      temporaryDirectory.deleteSync(recursive: true);
    }
  });

  final databaseFile = File('${temporaryDirectory.path}/database.sqlite');
  final fixture = File(_fixturePath);
  expect(
    fixture.existsSync(),
    isTrue,
    reason: 'released-schema fixture missing',
  );

  final database = raw.sqlite3.open(databaseFile.path);
  try {
    database.execute(fixture.readAsStringSync());

    database.execute('''
      INSERT INTO system_settings (id, system_name)
      VALUES ('singleton', 'Released v0.13.1 fixture')
    ''');
    database.execute('''
      INSERT INTO members
        (id, name, emoji, created_at, pluralkit_uuid, pluralkit_id, is_deleted)
      VALUES
        ('released-tombstone', 'Released Tombstone', '🧱', 1718476800,
         'released-uuid', 'reuse-me', 1)
    ''');
    database.execute('''
      INSERT INTO conversations
        (id, created_at, last_activity_at, participant_ids, last_read_timestamps,
         archived_by_member_ids, muted_by_member_ids)
      VALUES
        ('released-conversation', 1718476800, 1718476800, '[]', '{}', '[]', '[]')
    ''');
    database.execute('''
      INSERT INTO chat_messages
        (id, content, timestamp, conversation_id, reactions)
      VALUES
        ('released-message', 'historical upgrade needle', 1718476800,
         'released-conversation', '[]')
    ''');
  } finally {
    database.close();
  }

  return databaseFile;
}

Future<int> _schemaVersion(AppDatabase database) async {
  final row = await database.customSelect('PRAGMA user_version').getSingle();
  return row.read<int>('user_version');
}

Future<String?> _sqliteObjectSql(AppDatabase database, String name) async {
  final row = await database
      .customSelect(
        'SELECT sql FROM sqlite_master WHERE name = ?',
        variables: [Variable<String>(name)],
      )
      .getSingleOrNull();
  return row?.read<String?>('sql');
}

Future<Set<String>> _columns(AppDatabase database, String table) async {
  final rows = await database.customSelect('PRAGMA table_info($table)').get();
  return rows.map((row) => row.read<String>('name')).toSet();
}

Future<void> _expectReleasedDataAndV40Postconditions(
  AppDatabase database,
) async {
  expect(await _schemaVersion(database), AppDatabase.currentSchemaVersion);

  final settings = await database
      .customSelect(
        'SELECT system_name, member_name_display FROM system_settings '
        "WHERE id = 'singleton'",
      )
      .getSingle();
  expect(settings.read<String?>('system_name'), 'Released v0.13.1 fixture');
  expect(
    settings.read<int>('member_name_display'),
    0,
    reason: 'v38 -> v39 supplies the released-row default',
  );

  expect(
    await _columns(database, 'members'),
    contains('create_push_started_at'),
  );
  final shortIdIndex = await _sqliteObjectSql(
    database,
    'idx_members_pluralkit_id',
  );
  expect(shortIdIndex, isNotNull);
  expect(shortIdIndex, contains('is_deleted = 0'));

  final tombstone = await database
      .customSelect(
        'SELECT name, pluralkit_uuid, pluralkit_id, is_deleted '
        'FROM members WHERE id = ?',
        variables: [const Variable<String>('released-tombstone')],
      )
      .getSingle();
  expect(tombstone.read<String>('name'), 'Released Tombstone');
  expect(tombstone.read<String?>('pluralkit_uuid'), 'released-uuid');
  expect(tombstone.read<String?>('pluralkit_id'), 'reuse-me');
  expect(tombstone.read<bool>('is_deleted'), isTrue);

  // The v40 partial index releases tombstoned short IDs while preserving the
  // tombstone row itself.
  await database.customStatement('''
    INSERT INTO members
      (id, name, emoji, created_at, pluralkit_uuid, pluralkit_id, is_deleted)
    VALUES
      ('live-reuse', 'Live Reuse', '✨', 1718563200, 'live-uuid', 'reuse-me', 0)
  ''');
  final liveReuse = await database
      .customSelect(
        'SELECT pluralkit_id FROM members WHERE id = ?',
        variables: [const Variable<String>('live-reuse')],
      )
      .getSingle();
  expect(liveReuse.read<String?>('pluralkit_id'), 'reuse-me');

  final ftsRows = await database
      .customSelect(
        "SELECT rowid FROM chat_messages_fts WHERE chat_messages_fts MATCH 'needle'",
      )
      .get();
  expect(
    ftsRows,
    hasLength(1),
    reason: 'released FTS data survives the upgrade',
  );
}

void main() {
  group('released v0.13.1 (schema v38) migration fixture', () {
    test(
      'opens through the normal v38 -> v40 path and preserves data',
      () async {
        final databaseFile = await _seedReleasedV0131Database(
          'prism_released_v0131_normal_',
        );

        final database = AppDatabase(NativeDatabase(databaseFile));
        addTearDown(database.close);
        await database.customSelect('SELECT 1').get();

        await _expectReleasedDataAndV40Postconditions(database);
      },
    );

    test(
      'resumes a v39-stamped interruption without losing released data',
      () async {
        final databaseFile = await _seedReleasedV0131Database(
          'prism_released_v0131_resume_',
        );

        final interrupted = AppDatabase(NativeDatabase(databaseFile))
          ..debugFailMigrationStepTo = 40;
        await expectLater(
          interrupted.customSelect('SELECT 1').get(),
          throwsA(isA<StateError>()),
        );
        await interrupted.close();

        final afterFailure = raw.sqlite3.open(databaseFile.path);
        try {
          expect(
            afterFailure.select('PRAGMA user_version').single['user_version'],
            39,
            reason: 'v38 -> v39 committed before the injected v40 interruption',
          );
          final columns = afterFailure
              .select('PRAGMA table_info(members)')
              .map((row) => row['name'] as String)
              .toSet();
          expect(columns, isNot(contains('create_push_started_at')));
        } finally {
          afterFailure.close();
        }

        final resumed = AppDatabase(NativeDatabase(databaseFile));
        addTearDown(resumed.close);
        await resumed.customSelect('SELECT 1').get();

        await _expectReleasedDataAndV40Postconditions(resumed);
      },
    );
  });
}
