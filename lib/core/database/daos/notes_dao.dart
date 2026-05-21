import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/sql_like.dart';
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

  Future<NoteRow?> getNoteById(String id) =>
      (select(notes)..where((n) => n.id.equals(id))).getSingleOrNull();

  Stream<NoteRow?> watchNoteById(String id) =>
      (select(notes)..where((n) => n.id.equals(id))).watchSingleOrNull();

  Future<NoteRow?> getMentionNoteById(String id) =>
      (select(notes)..where((n) => n.id.equals(id) & n.isDeleted.equals(false)))
          .getSingleOrNull();

  Stream<List<NoteRow>> watchMentionNotesByIds(List<String> ids) {
    if (ids.isEmpty) return Stream.value(const <NoteRow>[]);
    return (select(
      notes,
    )..where((n) => n.id.isIn(ids) & n.isDeleted.equals(false))).watch();
  }

  Future<List<NoteRow>> searchMentionCandidates(
    String filter, {
    int limit = 8,
  }) {
    final trimmed = filter.trim();
    final query = select(notes)
      ..where((n) {
        final visible = n.isDeleted.equals(false);
        if (trimmed.isEmpty) return visible;
        final pattern = escapedSqlLikeContainsPattern(trimmed);
        return visible &
            (n.title.like(pattern, escapeChar: sqlLikeEscapeChar) |
                n.body.like(pattern, escapeChar: sqlLikeEscapeChar));
      })
      ..orderBy([(n) => OrderingTerm.desc(n.date)])
      ..limit(limit);
    return query.get();
  }

  Future<int> createNote(NotesCompanion companion) =>
      into(notes).insert(companion);

  /// Batch-insert notes in a single Drift `batch()` round-trip.
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
