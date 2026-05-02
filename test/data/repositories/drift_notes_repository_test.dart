// test/data/repositories/drift_notes_repository_test.dart
//
// DateTime UTC normalization (Fix X — UTC tail).
//
// Pins the contract that every DateTime emitted by `_noteFields` to the
// sync engine is Z-suffixed UTC. Mirrors the pattern from
// drift_conversation_repository_test.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/notes_dao.dart';
import 'package:prism_plurality/data/repositories/drift_notes_repository.dart';
import 'package:prism_plurality/domain/models/note.dart' as domain;

void main() {
  late AppDatabase db;
  late NotesDao dao;
  late DriftNotesRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = NotesDao(db);
    // Null sync handle — debugNoteFields is pure and doesn't call into FFI.
    repo = DriftNotesRepository(dao, null);
  });

  tearDown(() => db.close());

  group('debugNoteFields UTC normalization', () {
    test(
      'date, created_at, and modified_at emit Z-suffixed UTC even when '
      'input is a local DateTime',
      () {
        final localDate = DateTime(2026, 4, 27, 9, 0);
        final localCreated = DateTime(2026, 4, 27, 10, 0);
        final localModified = DateTime(2026, 4, 27, 11, 30);

        final note = domain.Note(
          id: 'n1',
          title: 't',
          body: 'b',
          date: localDate,
          createdAt: localCreated,
          modifiedAt: localModified,
        );

        final fields = repo.debugNoteFields(note);
        final dateStr = fields['date'] as String;
        final createdStr = fields['created_at'] as String;
        final modifiedStr = fields['modified_at'] as String;

        expect(dateStr.endsWith('Z'), isTrue, reason: dateStr);
        expect(createdStr.endsWith('Z'), isTrue, reason: createdStr);
        expect(modifiedStr.endsWith('Z'), isTrue, reason: modifiedStr);
        expect(
          DateTime.parse(dateStr).isAtSameMomentAs(localDate.toUtc()),
          isTrue,
        );
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
