import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/conversation_categories_dao.dart';
import 'package:prism_plurality/data/repositories/drift_conversation_categories_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/conversation_category.dart';

void main() {
  late AppDatabase db;
  late ConversationCategoriesDao dao;
  late DriftConversationCategoriesRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = ConversationCategoriesDao(db);
    // Pass null for sync handle — tests run without sync.
    repo = DriftConversationCategoriesRepository(dao, null);
  });

  tearDown(() => db.close());

  ConversationCategory makeCategory({
    required String id,
    String name = 'General',
    int displayOrder = 0,
  }) {
    final now = DateTime(2026, 1, 15);
    return ConversationCategory(
      id: id,
      name: name,
      displayOrder: displayOrder,
      createdAt: now,
      modifiedAt: now,
    );
  }

  group('create + watchAll round-trip', () {
    test('created category appears in watchAll stream', () async {
      final category = makeCategory(id: 'c1', name: 'Work');

      await repo.create(category);

      final all = await repo.watchAll().first;
      expect(all, hasLength(1));
      expect(all.first.id, 'c1');
      expect(all.first.name, 'Work');
      expect(all.first.displayOrder, 0);
    });

    test('multiple categories appear in watchAll', () async {
      await repo.create(makeCategory(id: 'c1', name: 'Work'));
      await repo.create(makeCategory(id: 'c2', name: 'Personal'));

      final all = await repo.watchAll().first;
      expect(all, hasLength(2));
    });
  });

  group('update', () {
    test('update changes name', () async {
      await repo.create(makeCategory(id: 'c1', name: 'Old Name'));

      final updated = makeCategory(id: 'c1', name: 'New Name');
      await repo.update(updated);

      final all = await repo.watchAll().first;
      expect(all, hasLength(1));
      expect(all.first.name, 'New Name');
    });

    test('update changes displayOrder', () async {
      await repo.create(makeCategory(id: 'c1', displayOrder: 0));

      final updated = makeCategory(id: 'c1', displayOrder: 5);
      await repo.update(updated);

      final all = await repo.watchAll().first;
      expect(all.first.displayOrder, 5);
    });
  });

  group('delete', () {
    test('soft-delete removes from watchAll', () async {
      await repo.create(makeCategory(id: 'c1', name: 'Keep'));
      await repo.create(makeCategory(id: 'c2', name: 'Remove'));

      await repo.delete('c2');

      final all = await repo.watchAll().first;
      expect(all, hasLength(1));
      expect(all.first.id, 'c1');
    });

    test('soft-deleted category not returned by getById', () async {
      await repo.create(makeCategory(id: 'c1'));
      await repo.delete('c1');

      final result = await repo.getById('c1');
      expect(result, isNull);
    });
  });

  group('ordering by displayOrder', () {
    test('watchAll returns categories ordered by displayOrder ascending', () async {
      await repo.create(makeCategory(id: 'c3', name: 'Third', displayOrder: 3));
      await repo.create(makeCategory(id: 'c1', name: 'First', displayOrder: 1));
      await repo.create(makeCategory(id: 'c2', name: 'Second', displayOrder: 2));

      final all = await repo.watchAll().first;
      expect(all, hasLength(3));
      expect(all[0].name, 'First');
      expect(all[1].name, 'Second');
      expect(all[2].name, 'Third');
    });

    test('categories with same displayOrder are stable', () async {
      await repo.create(makeCategory(id: 'c1', name: 'A', displayOrder: 0));
      await repo.create(makeCategory(id: 'c2', name: 'B', displayOrder: 0));

      final all = await repo.watchAll().first;
      expect(all, hasLength(2));
      // Both should be returned regardless of internal order.
      final names = all.map((c) => c.name).toSet();
      expect(names, containsAll(['A', 'B']));
    });
  });

  group('getById', () {
    test('returns category when it exists', () async {
      await repo.create(makeCategory(id: 'c1', name: 'Found'));

      final found = await repo.getById('c1');
      expect(found, isNotNull);
      expect(found!.name, 'Found');
    });

    test('returns null for non-existent id', () async {
      final found = await repo.getById('nonexistent');
      expect(found, isNull);
    });
  });

  group('update (patch-style emission)', () {
    final baseTime = DateTime.utc(2026, 5, 1, 12);

    ConversationCategory makeFullCategory({
      String id = 'c1',
      String name = 'Original name',
      int displayOrder = 0,
      DateTime? createdAt,
      DateTime? modifiedAt,
    }) {
      return ConversationCategory(
        id: id,
        name: name,
        displayOrder: displayOrder,
        createdAt: createdAt ?? baseTime,
        modifiedAt: modifiedAt ?? baseTime,
      );
    }

    test('emits only the changed fields', () async {
      await repo.create(makeFullCategory());
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      final later = baseTime.add(const Duration(hours: 1));
      await repo.update(
        makeFullCategory(name: 'Renamed', modifiedAt: later),
      );

      expect(captured, hasLength(1));
      expect(captured.single.opType, SyncRecordOpType.update);
      expect(captured.single.table, 'conversation_categories');
      expect(captured.single.entityId, 'c1');
      expect(captured.single.fields.keys.toSet(), {'name', 'modified_at'});
      expect(captured.single.fields['name'], 'Renamed');
    });

    test('emits nothing when the domain object matches the stored row',
        () async {
      await repo.create(makeFullCategory());
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.update(makeFullCategory());

      expect(captured, isEmpty);
    });

    test('preserves untouched columns in the database', () async {
      await repo.create(
        makeFullCategory(name: 'Original name', displayOrder: 7),
      );

      await repo.update(
        makeFullCategory(
          name: 'Renamed',
          displayOrder: 7,
          modifiedAt: baseTime.add(const Duration(hours: 1)),
        ),
      );

      final row = await dao.getById('c1');
      expect(row, isNotNull);
      expect(row!.name, 'Renamed');
      expect(row.displayOrder, 7);
      expect(row.createdAt.toUtc(), baseTime);
    });

    test('silently no-ops on a tombstoned row (does not emit, '
        'does not resurrect)', () async {
      await repo.create(makeFullCategory(name: 'Original name'));
      await repo.delete('c1');
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.update(makeFullCategory(name: 'Attempted edit'));

      expect(captured, isEmpty);
      final row = await dao.getByIdRow('c1');
      expect(row, isNotNull);
      expect(row!.isDeleted, isTrue);
      expect(row.name, 'Original name');
    });

    test('silently no-ops when the row does not exist', () async {
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.update(makeFullCategory(id: 'missing'));

      expect(captured, isEmpty);
      final row = await dao.getByIdRow('missing');
      expect(row, isNull);
    });

    test('does not emit is_deleted in the patch', () async {
      await repo.create(makeFullCategory());
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.update(
        makeFullCategory(
          name: 'Renamed',
          modifiedAt: baseTime.add(const Duration(hours: 1)),
        ),
      );

      expect(captured, hasLength(1));
      expect(captured.single.fields.containsKey('is_deleted'), isFalse);
    });
  });

  // UTC tail (Fix X follow-up). Mirrors the pattern from
  // drift_conversation_repository_test: a local DateTime fed into
  // _fields() must be emitted as Z-suffixed UTC, otherwise peers in other
  // timezones reparse it as local time and shift the absolute moment.
  group('debugCategoryFields UTC normalization', () {
    test(
      'created_at and modified_at emit Z-suffixed UTC even when input is local',
      () {
        final localCreated = DateTime(2026, 4, 27, 10, 0);
        final localModified = DateTime(2026, 4, 27, 11, 30);

        final category = ConversationCategory(
          id: 'c1',
          name: 'cat',
          displayOrder: 0,
          createdAt: localCreated,
          modifiedAt: localModified,
        );

        final fields = repo.debugCategoryFields(category);
        final createdStr = fields['created_at'] as String;
        final modifiedStr = fields['modified_at'] as String;

        expect(createdStr.endsWith('Z'), isTrue, reason: createdStr);
        expect(modifiedStr.endsWith('Z'), isTrue, reason: modifiedStr);
        expect(
          DateTime.parse(createdStr).isAtSameMomentAs(localCreated.toUtc()),
          isTrue,
        );
        expect(
          DateTime.parse(modifiedStr).isAtSameMomentAs(localModified.toUtc()),
          isTrue,
        );
      },
    );
  });
}
