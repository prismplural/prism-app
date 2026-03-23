import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/daos/notes_dao.dart';
import 'package:prism_plurality/data/mappers/note_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/note.dart' as domain;
import 'package:prism_plurality/domain/repositories/notes_repository.dart';

class DriftNotesRepository
    with SyncRecordMixin
    implements NotesRepository {
  final NotesDao _dao;
  final ffi.PrismSyncHandle? _syncHandle;

  @override
  ffi.PrismSyncHandle? get syncHandle => _syncHandle;

  static const _table = 'notes';

  DriftNotesRepository(this._dao, this._syncHandle);

  @override
  Stream<List<domain.Note>> watchNotesForMember(String memberId) {
    return _dao
        .watchNotesForMember(memberId)
        .map((rows) => rows.map(NoteMapper.toDomain).toList());
  }

  @override
  Stream<List<domain.Note>> watchRecentNotesForMember(String memberId,
      {int limit = 5}) {
    return _dao
        .watchRecentNotesForMember(memberId, limit: limit)
        .map((rows) => rows.map(NoteMapper.toDomain).toList());
  }

  @override
  Stream<List<domain.Note>> watchAllNotes() {
    return _dao
        .watchAllNotes()
        .map((rows) => rows.map(NoteMapper.toDomain).toList());
  }

  @override
  Future<domain.Note?> getNoteById(String id) async {
    final row = await _dao.getNoteById(id);
    return row != null ? NoteMapper.toDomain(row) : null;
  }

  @override
  Future<void> createNote(domain.Note note) async {
    final companion = NoteMapper.toCompanion(note);
    await _dao.createNote(companion);
    await syncRecordCreate(_table, note.id, _noteFields(note));
  }

  @override
  Future<void> updateNote(domain.Note note) async {
    final companion = NoteMapper.toCompanion(note);
    await _dao.updateNote(note.id, companion);
    await syncRecordUpdate(_table, note.id, _noteFields(note));
  }

  @override
  Future<void> deleteNote(String id) async {
    await _dao.deleteNote(id);
    await syncRecordDelete(_table, id);
  }

  Map<String, dynamic> _noteFields(domain.Note n) {
    return {
      'title': n.title,
      'body': n.body,
      'color_hex': n.colorHex,
      'member_id': n.memberId,
      'date': n.date.toIso8601String(),
      'created_at': n.createdAt.toIso8601String(),
      'modified_at': n.modifiedAt.toIso8601String(),
      'is_deleted': false,
    };
  }
}
