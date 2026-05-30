import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/notes_table.dart';

part 'notes_dao.g.dart';

@DriftAccessor(tables: [Notes])
class NotesDao extends DatabaseAccessor<AppDatabase> with _$NotesDaoMixin {
  NotesDao(super.db);

  Stream<List<NoteRow>> watchNotesForMember(String memberId) =>
      (select(notes)
            ..where(
              (n) => n.memberId.equals(memberId) & n.isDeleted.equals(false),
            )
            ..orderBy([(n) => OrderingTerm.desc(n.date)]))
          .watch();

  Stream<List<NoteRow>> watchRecentNotesForMember(
    String memberId, {
    int limit = 5,
  }) =>
      (select(notes)
            ..where(
              (n) => n.memberId.equals(memberId) & n.isDeleted.equals(false),
            )
            ..orderBy([(n) => OrderingTerm.desc(n.date)])
            ..limit(limit))
          .watch();

  Stream<List<NoteRow>> watchAllNotes() =>
      (select(notes)
            ..where((n) => n.isDeleted.equals(false))
            ..orderBy([(n) => OrderingTerm.desc(n.date)]))
          .watch();

  /// One-shot counterpart to [watchAllNotes] (same active/deleted filter +
  /// ordering). Used by usage scans that must not `await` a stream provider's
  /// `.future` (which can stall when nothing else watches it).
  Future<List<NoteRow>> getAllNotes() =>
      (select(notes)
            ..where((n) => n.isDeleted.equals(false))
            ..orderBy([(n) => OrderingTerm.desc(n.date)]))
          .get();

  Future<NoteRow?> getNoteById(String id) =>
      (select(notes)..where((n) => n.id.equals(id))).getSingleOrNull();

  Stream<NoteRow?> watchNoteById(String id) =>
      (select(notes)..where((n) => n.id.equals(id))).watchSingleOrNull();

  Future<int> createNote(NotesCompanion companion) =>
      into(notes).insert(companion);

  /// Batch-insert notes in a single Drift `batch()` round-trip.
  /// Phase 6 SP importer; see `docs/plans/sp-import-perf-quick-wins.md`.
  Future<void> batchInsertNotes(List<NotesCompanion> rows) async {
    if (rows.isEmpty) return;
    await batch((b) => b.insertAll(notes, rows));
  }

  Future<void> updateNote(String id, NotesCompanion companion) =>
      (update(notes)..where((n) => n.id.equals(id))).write(companion);

  Future<void> deleteNote(String id) =>
      (update(notes)..where((n) => n.id.equals(id))).write(
        const NotesCompanion(isDeleted: Value(true)),
      );
}
