// Regression tests for the data-write + sync-outbox atomicity invariant.

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
}
