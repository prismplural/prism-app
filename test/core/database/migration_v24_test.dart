import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';

/// Helper to check if a column exists on a table using pragma_table_info.
Future<bool> _columnExists(
  AppDatabase db,
  String tableName,
  String columnName,
) async {
  final cols = await db.customSelect(
    "SELECT name FROM pragma_table_info('$tableName') WHERE name = '$columnName'",
  ).get();
  return cols.isNotEmpty;
}

/// Helper to check if an index exists.
Future<bool> _indexExists(AppDatabase db, String indexName) async {
  final indexes = await db.customSelect(
    "SELECT name FROM sqlite_master WHERE type='index' AND name='$indexName'",
  ).get();
  return indexes.isNotEmpty;
}

/// Migration v24 tests.
///
/// These tests verify that the v24 schema creates the expected tables and
/// columns by opening a fresh in-memory database (which runs onCreate and
/// creates all tables at the latest schema) and then querying them.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  group('v24 schema — conversation_categories table', () {
    test('table exists and accepts inserts', () async {
      await db.customInsert(
        'INSERT INTO conversation_categories (id, name, display_order, created_at, modified_at, is_deleted) '
        "VALUES ('cc1', 'Work', 0, ${DateTime(2026, 1, 1).millisecondsSinceEpoch}, "
        '${DateTime(2026, 1, 1).millisecondsSinceEpoch}, 0)',
      );

      final rows = await db.customSelect(
        'SELECT * FROM conversation_categories WHERE id = ?',
        variables: [const Variable('cc1')],
      ).get();

      expect(rows, hasLength(1));
      expect(rows.first.read<String>('name'), 'Work');
      expect(rows.first.read<int>('display_order'), 0);
      expect(rows.first.read<bool>('is_deleted'), false);
    });

    test('has expected columns', () async {
      expect(await _columnExists(db, 'conversation_categories', 'id'), isTrue);
      expect(await _columnExists(db, 'conversation_categories', 'name'), isTrue);
      expect(await _columnExists(db, 'conversation_categories', 'display_order'), isTrue);
      expect(await _columnExists(db, 'conversation_categories', 'created_at'), isTrue);
      expect(await _columnExists(db, 'conversation_categories', 'modified_at'), isTrue);
      expect(await _columnExists(db, 'conversation_categories', 'is_deleted'), isTrue);
    });

    // Note: idx_conv_categories_deleted_order is created only during
    // onUpgrade (from < 24), not in onCreate. We verify the table itself
    // is functional via the insert test above.
  });

  group('v24 schema — reminders table', () {
    test('table exists and accepts inserts', () async {
      await db.customInsert(
        'INSERT INTO reminders (id, name, message, "trigger", interval_days, time_of_day, delay_hours, is_active, created_at, modified_at, is_deleted) '
        "VALUES ('r1', 'Daily Check', 'Time to check', 0, 1, '09:00', NULL, 1, "
        '${DateTime(2026, 1, 1).millisecondsSinceEpoch}, '
        '${DateTime(2026, 1, 1).millisecondsSinceEpoch}, 0)',
      );

      final rows = await db.customSelect(
        'SELECT * FROM reminders WHERE id = ?',
        variables: [const Variable('r1')],
      ).get();

      expect(rows, hasLength(1));
      expect(rows.first.read<String>('name'), 'Daily Check');
      expect(rows.first.read<String>('message'), 'Time to check');
      expect(rows.first.read<int>('trigger'), 0);
      expect(rows.first.read<int>('interval_days'), 1);
      expect(rows.first.read<String>('time_of_day'), '09:00');
      expect(rows.first.read<bool>('is_active'), true);
    });

    test('nullable columns accept null values', () async {
      await db.customInsert(
        'INSERT INTO reminders (id, name, message, "trigger", interval_days, time_of_day, delay_hours, is_active, created_at, modified_at, is_deleted) '
        "VALUES ('r2', 'Simple', 'msg', 1, NULL, NULL, NULL, 1, "
        '${DateTime(2026, 1, 1).millisecondsSinceEpoch}, '
        '${DateTime(2026, 1, 1).millisecondsSinceEpoch}, 0)',
      );

      final rows = await db.customSelect(
        'SELECT * FROM reminders WHERE id = ?',
        variables: [const Variable('r2')],
      ).get();

      expect(rows, hasLength(1));
      expect(rows.first.readNullable<int>('interval_days'), isNull);
      expect(rows.first.readNullable<String>('time_of_day'), isNull);
      expect(rows.first.readNullable<int>('delay_hours'), isNull);
    });

    test('has expected columns', () async {
      expect(await _columnExists(db, 'reminders', 'id'), isTrue);
      expect(await _columnExists(db, 'reminders', 'name'), isTrue);
      expect(await _columnExists(db, 'reminders', 'message'), isTrue);
      expect(await _columnExists(db, 'reminders', 'trigger'), isTrue);
      expect(await _columnExists(db, 'reminders', 'interval_days'), isTrue);
      expect(await _columnExists(db, 'reminders', 'time_of_day'), isTrue);
      expect(await _columnExists(db, 'reminders', 'delay_hours'), isTrue);
      expect(await _columnExists(db, 'reminders', 'is_active'), isTrue);
      expect(await _columnExists(db, 'reminders', 'created_at'), isTrue);
      expect(await _columnExists(db, 'reminders', 'modified_at'), isTrue);
      expect(await _columnExists(db, 'reminders', 'is_deleted'), isTrue);
    });

    // Note: idx_reminders_active_deleted is created only during onUpgrade
    // (from < 24), not in onCreate. A fresh database uses Drift's implicit
    // indexes from the table definition. This is expected behavior.
  });

  group('v24 schema — new columns on existing tables', () {
    test('polls.description column exists', () async {
      expect(await _columnExists(db, 'polls', 'description'), isTrue);
    });

    test('poll_options.color_hex column exists', () async {
      expect(await _columnExists(db, 'poll_options', 'color_hex'), isTrue);
    });

    test('members.markdown_enabled column exists', () async {
      expect(await _columnExists(db, 'members', 'markdown_enabled'), isTrue);
    });

    test('conversations.description column exists', () async {
      expect(await _columnExists(db, 'conversations', 'description'), isTrue);
    });

    test('conversations.category_id column exists', () async {
      expect(await _columnExists(db, 'conversations', 'category_id'), isTrue);
    });

    test('conversations.display_order column exists', () async {
      expect(await _columnExists(db, 'conversations', 'display_order'), isTrue);
    });

    test('system_settings.reminders_enabled column exists', () async {
      expect(await _columnExists(db, 'system_settings', 'reminders_enabled'), isTrue);
    });

    test('system_settings.font_scale column exists', () async {
      expect(await _columnExists(db, 'system_settings', 'font_scale'), isTrue);
    });

    test('system_settings.font_family column exists', () async {
      expect(await _columnExists(db, 'system_settings', 'font_family'), isTrue);
    });

    test('system_settings.pin_lock_enabled column exists', () async {
      expect(await _columnExists(db, 'system_settings', 'pin_lock_enabled'), isTrue);
    });

    test('system_settings.biometric_lock_enabled column exists', () async {
      expect(await _columnExists(db, 'system_settings', 'biometric_lock_enabled'), isTrue);
    });

    test('system_settings.auto_lock_delay_seconds column exists', () async {
      expect(await _columnExists(db, 'system_settings', 'auto_lock_delay_seconds'), isTrue);
    });

    test('system_settings.system_description column exists', () async {
      expect(await _columnExists(db, 'system_settings', 'system_description'), isTrue);
    });

    test('system_settings.system_avatar_data column exists', () async {
      expect(await _columnExists(db, 'system_settings', 'system_avatar_data'), isTrue);
    });

    // Note: idx_conversations_category is created only during onUpgrade
    // (from < 24), not in onCreate. A fresh database won't have it.
  });
}
