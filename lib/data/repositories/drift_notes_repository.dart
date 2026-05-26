import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/notes_dao.dart';
import 'package:prism_plurality/data/mappers/note_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/data/sync/field_diff.dart';
import 'package:prism_plurality/data/utils/sync_datetime.dart';
import 'package:prism_plurality/domain/models/note.dart' as domain;
import 'package:prism_plurality/domain/repositories/notes_repository.dart';

class DriftNotesRepository with SyncRecordMixin implements NotesRepository {
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
  Stream<List<domain.Note>> watchRecentNotesForMember(
    String memberId, {
    int limit = 5,
  }) {
    return _dao
        .watchRecentNotesForMember(memberId, limit: limit)
        .map((rows) => rows.map(NoteMapper.toDomain).toList());
  }

  @override
  Stream<List<domain.Note>> watchAllNotes() {
    return _dao.watchAllNotes().map(
      (rows) => rows.map(NoteMapper.toDomain).toList(),
    );
  }

  @override
  Future<domain.Note?> getNoteById(String id) async {
    final row = await _dao.getNoteById(id);
    return row != null ? NoteMapper.toDomain(row) : null;
  }

  @override
  Stream<domain.Note?> watchNoteById(String id) {
    return _dao
        .watchNoteById(id)
        .map((row) => row != null ? NoteMapper.toDomain(row) : null);
  }

  @override
  Future<void> createNote(domain.Note note) async {
    final companion = NoteMapper.toCompanion(note);
    await _dao.createNote(companion);
    await syncRecordCreate(_table, note.id, _noteFields(note));
  }

  @override
  Future<void> updateNote(domain.Note note) async {
    final existingRow = await _dao.getNoteById(note.id);
    if (existingRow == null || existingRow.isDeleted) return;

    final changedFields = diffSyncFields(
      _noteFieldsFromRow(existingRow),
      _noteFields(note),
    );
    if (changedFields.isEmpty) return;

    final companion = _partialNoteCompanion(changedFields);
    await _dao.updateNote(note.id, companion);
    await syncRecordUpdate(_table, note.id, changedFields);
  }

  @override
  Future<void> deleteNote(String id) async {
    await _dao.deleteNote(id);
    await syncRecordDelete(_table, id);
  }

  /// Visible-for-testing: builds the field map this repository hands to the
  /// Rust sync engine for create/update. Exposed so a regression test can
  /// pin every emitted DateTime as Z-suffixed UTC.
  @visibleForTesting
  Map<String, dynamic> debugNoteFields(domain.Note n) => _noteFields(n);

  NotesCompanion _partialNoteCompanion(Map<String, dynamic> fields) {
    return NotesCompanion(
      title: fields.containsKey('title')
          ? Value(fields['title'] as String)
          : const Value.absent(),
      body: fields.containsKey('body')
          ? Value(fields['body'] as String)
          : const Value.absent(),
      colorHex: fields.containsKey('color_hex')
          ? Value(fields['color_hex'] as String?)
          : const Value.absent(),
      memberId: fields.containsKey('member_id')
          ? Value(fields['member_id'] as String?)
          : const Value.absent(),
      date: fields.containsKey('date')
          ? Value(parseSyncDateTime(fields['date']))
          : const Value.absent(),
      createdAt: fields.containsKey('created_at')
          ? Value(parseSyncDateTime(fields['created_at']))
          : const Value.absent(),
      modifiedAt: fields.containsKey('modified_at')
          ? Value(parseSyncDateTime(fields['modified_at']))
          : const Value.absent(),
    );
  }

  Map<String, dynamic> _noteFieldsFromRow(NoteRow n) {
    return {
      'title': n.title,
      'body': n.body,
      'color_hex': n.colorHex,
      'member_id': n.memberId,
      'date': toSyncUtc(n.date),
      'created_at': toSyncUtc(n.createdAt),
      'modified_at': toSyncUtc(n.modifiedAt),
      'is_deleted': n.isDeleted,
    };
  }

  Map<String, dynamic> _noteFields(domain.Note n) => noteFields(n);

  /// Field-map builder for note sync emissions.
  ///
  /// Public so the Phase 6 batch capture path in `sp_importer.dart` can
  /// construct byte-identical `fields` payloads when it bypasses
  /// `createNote()` for the bulk insert. See
  /// `docs/plans/sp-import-perf-quick-wins.md` (Phase 5 "Field-map reuse").
  static Map<String, dynamic> noteFields(domain.Note n) {
    return {
      'title': n.title,
      'body': n.body,
      'color_hex': n.colorHex,
      'member_id': n.memberId,
      'date': toSyncUtc(n.date),
      'created_at': toSyncUtc(n.createdAt),
      'modified_at': toSyncUtc(n.modifiedAt),
      'is_deleted': false,
    };
  }
}
