import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/conversation_categories_dao.dart';
import 'package:prism_plurality/data/repositories/drift_conversation_categories_repository.dart';
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

  ConversationCategory _makeCategory({
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
      final category = _makeCategory(id: 'c1', name: 'Work');

      await repo.create(category);

      final all = await repo.watchAll().first;
      expect(all, hasLength(1));
      expect(all.first.id, 'c1');
      expect(all.first.name, 'Work');
      expect(all.first.displayOrder, 0);
    });

    test('multiple categories appear in watchAll', () async {
      await repo.create(_makeCategory(id: 'c1', name: 'Work'));
      await repo.create(_makeCategory(id: 'c2', name: 'Personal'));

      final all = await repo.watchAll().first;
      expect(all, hasLength(2));
    });
  });

  group('update', () {
    test('update changes name', () async {
      await repo.create(_makeCategory(id: 'c1', name: 'Old Name'));

      final updated = _makeCategory(id: 'c1', name: 'New Name');
      await repo.update(updated);

      final all = await repo.watchAll().first;
      expect(all, hasLength(1));
      expect(all.first.name, 'New Name');
    });

    test('update changes displayOrder', () async {
      await repo.create(_makeCategory(id: 'c1', displayOrder: 0));

      final updated = _makeCategory(id: 'c1', displayOrder: 5);
      await repo.update(updated);

      final all = await repo.watchAll().first;
      expect(all.first.displayOrder, 5);
    });
  });

  group('delete', () {
    test('soft-delete removes from watchAll', () async {
      await repo.create(_makeCategory(id: 'c1', name: 'Keep'));
      await repo.create(_makeCategory(id: 'c2', name: 'Remove'));

      await repo.delete('c2');

      final all = await repo.watchAll().first;
      expect(all, hasLength(1));
      expect(all.first.id, 'c1');
    });

    test('soft-deleted category not returned by getById', () async {
      await repo.create(_makeCategory(id: 'c1'));
      await repo.delete('c1');

      final result = await repo.getById('c1');
      expect(result, isNull);
    });
  });

  group('ordering by displayOrder', () {
    test('watchAll returns categories ordered by displayOrder ascending', () async {
      await repo.create(_makeCategory(id: 'c3', name: 'Third', displayOrder: 3));
      await repo.create(_makeCategory(id: 'c1', name: 'First', displayOrder: 1));
      await repo.create(_makeCategory(id: 'c2', name: 'Second', displayOrder: 2));

      final all = await repo.watchAll().first;
      expect(all, hasLength(3));
      expect(all[0].name, 'First');
      expect(all[1].name, 'Second');
      expect(all[2].name, 'Third');
    });

    test('categories with same displayOrder are stable', () async {
      await repo.create(_makeCategory(id: 'c1', name: 'A', displayOrder: 0));
      await repo.create(_makeCategory(id: 'c2', name: 'B', displayOrder: 0));

      final all = await repo.watchAll().first;
      expect(all, hasLength(2));
      // Both should be returned regardless of internal order.
      final names = all.map((c) => c.name).toSet();
      expect(names, containsAll(['A', 'B']));
    });
  });

  group('getById', () {
    test('returns category when it exists', () async {
      await repo.create(_makeCategory(id: 'c1', name: 'Found'));

      final found = await repo.getById('c1');
      expect(found, isNotNull);
      expect(found!.name, 'Found');
    });

    test('returns null for non-existent id', () async {
      final found = await repo.getById('nonexistent');
      expect(found, isNull);
    });
  });
}
