// Regression tests for the data-write + sync-outbox atomicity invariant.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart' as db;
import 'package:prism_plurality/core/database/daos/custom_fields_dao.dart';
import 'package:prism_plurality/core/database/daos/member_board_posts_dao.dart';
import 'package:prism_plurality/core/database/daos/members_dao.dart';
import 'package:prism_plurality/core/database/daos/system_settings_dao.dart';
import 'package:prism_plurality/core/sync/sync_runtime_state.dart';
import 'package:prism_plurality/data/repositories/drift_custom_fields_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_board_posts_repository.dart';
import 'package:prism_plurality/data/repositories/drift_system_settings_repository.dart';
import 'package:prism_plurality/domain/models/custom_field.dart' as domain;
import 'package:prism_plurality/core/database/daos/habits_dao.dart';
import 'package:prism_plurality/core/database/daos/member_groups_dao.dart';
import 'package:prism_plurality/data/mappers/member_group_mapper.dart';
import 'package:prism_plurality/data/repositories/drift_habit_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_groups_repository.dart';
import 'package:prism_plurality/domain/models/group_sort_state.dart';

class _BoomCustomFields extends DriftCustomFieldsRepository {
  _BoomCustomFields(CustomFieldsDao dao) : super(dao, null);

  @override
  Future<void> syncRecordCreate(
    String table,
    String entityId,
    Map<String, dynamic> fields,
  ) async {
    throw StateError('boom-create');
  }
}

class _BoomSettings extends DriftSystemSettingsRepository {
  _BoomSettings(SystemSettingsDao dao) : super(dao, null);

  @override
  Future<void> syncRecordUpdate(
    String table,
    String entityId,
    Map<String, dynamic> fields,
  ) async {
    throw StateError('boom-update');
  }
}

class _BoomBoardPosts extends DriftMemberBoardPostsRepository {
  _BoomBoardPosts(MemberBoardPostsDao dao, MembersDao membersDao)
    : super(dao, membersDao, null);

  @override
  Future<void> syncRecordUpdate(
    String table,
    String entityId,
    Map<String, dynamic> fields,
  ) async {
    throw StateError('boom-update');
  }
}

class _BoomMemberGroups extends DriftMemberGroupsRepository {
  _BoomMemberGroups(MemberGroupsDao dao) : super(dao, null);

  // deleteGroup emits syncRecordDeleteMulti(entries) then syncRecordDelete(group).
  // Throw on the group tombstone — the second emission — after the coalesced
  // entry tombstones have already been captured.
  @override
  Future<void> syncRecordDelete(String table, String entityId) async {
    throw StateError('boom-delete');
  }
}

class _BoomHabit extends DriftHabitRepository {
  _BoomHabit(HabitsDao dao) : super(dao, null);

  // deleteHabit emits a syncRecordDelete per completion, then one for the habit.
  // Let the completion tombstones capture, then throw on the habit tombstone.
  @override
  Future<void> syncRecordDelete(String table, String entityId) async {
    if (table == 'habits') throw StateError('boom-delete');
    return super.syncRecordDelete(table, entityId);
  }
}

domain.CustomField _field(String id) => domain.CustomField(
  id: id,
  name: 'Field $id',
  fieldType: domain.CustomFieldType.text,
  displayOrder: 0,
  createdAt: DateTime(2024),
  fieldTypeId: 'text',
);

void main() {
  late db.AppDatabase database;

  setUp(() {
    database = db.AppDatabase(NativeDatabase.memory());
    // Arm the durable-outbox path so an outbox row WOULD be written on success.
    syncCredentialsPersisted.value = true;
  });

  tearDown(() async {
    syncCredentialsPersisted.value = false;
    await database.close();
  });

  Future<List<db.SyncOpOutboxRow>> outbox() =>
      database.syncOutboxDao.allInIdOrder();

  test('custom_fields createField: emit throw rolls back the field row and '
      'persists no outbox row', () async {
    final repo = _BoomCustomFields(database.customFieldsDao);

    await expectLater(repo.createField(_field('f1')), throwsStateError);

    // Data write rolled back with the failed emission.
    expect(await database.customFieldsDao.getFieldById('f1'), isNull);
    // No durable outbox row leaked for an uncommitted write.
    expect(await outbox(), isEmpty);
  });

  test('system_settings updateFrontingReminders: emit throw rolls back the DAO '
      'write and persists no outbox row', () async {
    final dao = database.systemSettingsDao;
    final repo = _BoomSettings(dao);

    // Seed the singleton row and capture the pre-write reminder state.
    final before = await dao.getSettings();

    await expectLater(
      repo.updateFrontingReminders(enabled: true, intervalMinutes: 45),
      throwsStateError,
    );

    final after = await dao.getSettings();
    expect(after.frontingRemindersEnabled, before.frontingRemindersEnabled);
    expect(
      after.frontingReminderIntervalMinutes,
      before.frontingReminderIntervalMinutes,
    );
    expect(await outbox(), isEmpty);
  });

  test(
    'member board markInboxOpenedFor: emit throw rolls back board_last_read_at '
    'and persists no outbox row',
    () async {
      await database
          .into(database.members)
          .insert(
            db.MembersCompanion.insert(
              id: 'm1',
              name: 'm1',
              createdAt: DateTime.utc(2026, 1, 1),
            ),
          );
      final repo = _BoomBoardPosts(
        database.memberBoardPostsDao,
        database.membersDao,
      );

      await expectLater(repo.markInboxOpenedFor(['m1']), throwsStateError);

      final row = await database.membersDao.getMemberById('m1');
      expect(
        row?.boardLastReadAt,
        isNull,
        reason:
            'the conditional board_last_read_at write must roll back '
            'with the failed emission',
      );
      expect(await outbox(), isEmpty);
    },
  );

  test(
    'member_groups deleteGroup: a throw on the group tombstone (after the '
    'coalesced entry tombstones) rolls back both tables and persists no '
    'outbox row',
    () async {
      // Seed a plain (non-PK) group with one entry via direct inserts so the
      // setup itself emits nothing.
      await database.into(database.memberGroups).insert(
            db.MemberGroupsCompanion.insert(
              id: 'g1',
              name: 'g1',
              createdAt: DateTime.utc(2026, 1, 1),
              sortState: Value(
                MemberGroupMapper.encodeSortStateForColumn(
                  GroupSortState.manualEmpty,
                ),
              ),
            ),
          );
      await database.into(database.memberGroupEntries).insert(
            db.MemberGroupEntriesCompanion.insert(
              id: 'e1',
              groupId: 'g1',
              memberId: 'm1',
            ),
          );

      final repo = _BoomMemberGroups(database.memberGroupsDao);

      // Match the boom specifically so an incidental StateError (e.g. entity-id
      // computation) can't make this pass without reaching the second emission.
      await expectLater(
        repo.deleteGroup('g1'),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', 'boom-delete'),
        ),
      );

      // The group and its entry survive the rolled-back transaction...
      expect(await database.memberGroupsDao.getGroupById('g1'), isNotNull);
      expect(
        await database.memberGroupsDao.entriesForGroup('g1'),
        isNotEmpty,
        reason: 'entry deletes must roll back with the failed group emission',
      );
      // ...and the entry tombstone captured before the throw left no phantom row.
      expect(await outbox(), isEmpty);
    },
  );

  test(
    'habit deleteHabit: a throw on the habit tombstone (after the completion '
    'tombstones) rolls back both tables and persists no outbox row',
    () async {
      await database.into(database.habits).insert(
            db.HabitsCompanion.insert(
              id: 'h1',
              name: 'Habit',
              createdAt: DateTime.utc(2026, 1, 1),
              modifiedAt: DateTime.utc(2026, 1, 1),
            ),
          );
      await database.into(database.habitCompletions).insert(
            db.HabitCompletionsCompanion.insert(
              id: 'c1',
              habitId: 'h1',
              completedAt: DateTime.utc(2026, 1, 2),
              createdAt: DateTime.utc(2026, 1, 2),
              modifiedAt: DateTime.utc(2026, 1, 2),
            ),
          );

      final repo = _BoomHabit(database.habitsDao);

      await expectLater(
        repo.deleteHabit('h1'),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', 'boom-delete'),
        ),
      );

      final habit = await (database.select(database.habits)
            ..where((h) => h.id.equals('h1')))
          .getSingleOrNull();
      expect(habit, isNotNull);
      expect(
        await database.select(database.habitCompletions).get(),
        isNotEmpty,
        reason: 'completion deletes must roll back with the failed habit emit',
      );
      expect(await outbox(), isEmpty);
    },
  );
}
