import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/reminders_table.dart';

part 'reminders_dao.g.dart';

@DriftAccessor(tables: [Reminders])
class RemindersDao extends DatabaseAccessor<AppDatabase>
    with _$RemindersDaoMixin {
  RemindersDao(super.db);

  Stream<List<ReminderRow>> watchAll() =>
      (select(reminders)
            ..where((r) => r.isDeleted.equals(false))
            ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]))
          .watch();

  Stream<List<ReminderRow>> watchActive() => (select(
    reminders,
  )..where((r) => r.isActive.equals(true) & r.isDeleted.equals(false))).watch();

  Future<List<ReminderRow>> getAll() =>
      (select(reminders)
            ..where((r) => r.isDeleted.equals(false))
            ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]))
          .get();

  Future<ReminderRow?> getById(String id) =>
      (select(reminders)
            ..where((r) => r.id.equals(id) & r.isDeleted.equals(false)))
          .getSingleOrNull();

  Future<int> create(RemindersCompanion companion) =>
      into(reminders).insert(companion);

  /// Batch-insert reminders in a single Drift `batch()` round-trip.
  /// Phase 6 SP importer; see `docs/plans/sp-import-perf-quick-wins.md`.
  Future<void> batchInsertReminders(List<RemindersCompanion> rows) async {
    if (rows.isEmpty) return;
    await batch((b) => b.insertAll(reminders, rows));
  }

  Future<void> updateReminder(String id, RemindersCompanion companion) =>
      (update(reminders)..where((r) => r.id.equals(id))).write(companion);

  Future<void> softDelete(String id) =>
      (update(reminders)..where((r) => r.id.equals(id))).write(
        const RemindersCompanion(isDeleted: Value(true)),
      );
}
