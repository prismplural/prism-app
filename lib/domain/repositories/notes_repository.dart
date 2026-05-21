import 'package:prism_plurality/domain/models/note.dart' as domain;

abstract class NotesRepository {
  Stream<List<domain.Note>> watchNotesForMember(String memberId);
  Stream<List<domain.Note>> watchRecentNotesForMember(
    String memberId, {
    int limit = 5,
  });
  Stream<List<domain.Note>> watchAllNotes();
  Future<domain.Note?> getNoteById(String id);
  Stream<domain.Note?> watchNoteById(String id);
  Future<domain.Note?> getMentionNoteById(String id);
  Stream<List<domain.Note>> watchMentionNotesByIds(List<String> ids);
  Future<List<domain.Note>> searchMentionCandidates(
    String filter, {
    int limit = 8,
  });
  Future<void> createNote(domain.Note note);
  Future<void> updateNote(domain.Note note);
  Future<void> deleteNote(String id);
}
