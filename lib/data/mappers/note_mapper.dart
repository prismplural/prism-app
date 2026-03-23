import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/domain/models/note.dart' as domain;

class NoteMapper {
  NoteMapper._();

  static domain.Note toDomain(NoteRow row) {
    return domain.Note(
      id: row.id,
      title: row.title,
      body: row.body,
      colorHex: row.colorHex,
      memberId: row.memberId,
      date: row.date,
      createdAt: row.createdAt,
      modifiedAt: row.modifiedAt,
    );
  }

  static NotesCompanion toCompanion(domain.Note model) {
    return NotesCompanion(
      id: Value(model.id),
      title: Value(model.title),
      body: Value(model.body),
      colorHex: Value(model.colorHex),
      memberId: Value(model.memberId),
      date: Value(model.date),
      createdAt: Value(model.createdAt),
      modifiedAt: Value(model.modifiedAt),
    );
  }
}
