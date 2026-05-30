import 'package:prism_plurality/domain/models/note.dart' as domain;

abstract class NotesRepository {
  Stream<List<domain.Note>> watchNotesForMember(String memberId);
  Stream<List<domain.Note>> watchRecentNotesForMember(String memberId,
      {int limit = 5});
  Stream<List<domain.Note>> watchAllNotes();

  /// One-shot list of all active notes (mirrors [watchAllNotes]'s filter +
  /// ordering). Prefer this over awaiting a stream provider's `.future` in
  /// non-watching contexts, which can stall.
  Future<List<domain.Note>> getAllNotes();
  Future<domain.Note?> getNoteById(String id);
  Stream<domain.Note?> watchNoteById(String id);
  Future<void> createNote(domain.Note note);
  Future<void> updateNote(domain.Note note);
  Future<void> deleteNote(String id);
}
