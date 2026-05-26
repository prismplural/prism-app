// test/data/repositories/drift_notes_repository_test.dart
//
// Two test groups:
//
// 1. DateTime UTC normalization — pins that every DateTime emitted by
//    `_noteFields` to the sync engine is Z-suffixed UTC. Mirrors
//    drift_conversation_repository_test.
// 2. Patch-style `updateNote` (item #1 of the drift-repo migration plan) —
//    asserts that update emits only changed fields, no-ops on unchanged
//    input, refuses tombstoned/missing rows, and never emits `is_deleted`
//    through the diff path.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/notes_dao.dart';
import 'package:prism_plurality/data/repositories/drift_notes_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
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

  group('updateNote (patch-style emission)', () {
    final baseTime = DateTime.utc(2026, 5, 1, 12);

    domain.Note makeNote({
      String id = 'n1',
      String title = 'Original title',
      String body = 'Original body',
      String? colorHex,
      String? memberId,
      DateTime? date,
      DateTime? createdAt,
      DateTime? modifiedAt,
    }) {
      return domain.Note(
        id: id,
        title: title,
        body: body,
        colorHex: colorHex,
        memberId: memberId,
        date: date ?? baseTime,
        createdAt: createdAt ?? baseTime,
        modifiedAt: modifiedAt ?? baseTime,
      );
    }

    test('emits only the changed fields', () async {
      await repo.createNote(makeNote());
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      final later = baseTime.add(const Duration(hours: 1));
      await repo.updateNote(
        makeNote(body: 'Updated body', modifiedAt: later),
      );

      expect(captured, hasLength(1));
      expect(captured.single.opType, SyncRecordOpType.update);
      expect(captured.single.table, 'notes');
      expect(captured.single.entityId, 'n1');
      expect(captured.single.fields.keys.toSet(), {'body', 'modified_at'});
      expect(captured.single.fields['body'], 'Updated body');
      expect(captured.single.fields['is_deleted'], isNull);
    });

    test('emits nothing when the domain object matches the stored row',
        () async {
      await repo.createNote(makeNote());
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateNote(makeNote());

      expect(captured, isEmpty);
    });

    test('preserves untouched columns in the database', () async {
      await repo.createNote(
        makeNote(colorHex: '#ff0000', memberId: 'm1'),
      );

      await repo.updateNote(
        makeNote(
          body: 'Updated body',
          colorHex: '#ff0000',
          memberId: 'm1',
          modifiedAt: baseTime.add(const Duration(hours: 1)),
        ),
      );

      final row = await dao.getNoteById('n1');
      expect(row, isNotNull);
      expect(row!.body, 'Updated body');
      expect(row.title, 'Original title');
      expect(row.colorHex, '#ff0000');
      expect(row.memberId, 'm1');
    });

    test('null-clearing emits the null and writes it to the database',
        () async {
      await repo.createNote(makeNote(colorHex: '#ff0000'));
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateNote(
        makeNote(
          colorHex: null,
          modifiedAt: baseTime.add(const Duration(hours: 1)),
        ),
      );

      expect(captured, hasLength(1));
      final patch = captured.single.fields;
      expect(patch.containsKey('color_hex'), isTrue);
      expect(patch['color_hex'], isNull);

      final row = await dao.getNoteById('n1');
      expect(row!.colorHex, isNull);
    });

    test('silently no-ops on a tombstoned row (does not emit, '
        'does not resurrect)', () async {
      await repo.createNote(makeNote());
      await repo.deleteNote('n1');
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateNote(makeNote(body: 'Attempted edit'));

      expect(captured, isEmpty);
      final row = await dao.getNoteById('n1');
      expect(row, isNotNull);
      expect(row!.isDeleted, isTrue);
      expect(row.body, 'Original body');
    });

    test('silently no-ops when the row does not exist', () async {
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateNote(makeNote(id: 'missing'));

      expect(captured, isEmpty);
      final row = await dao.getNoteById('missing');
      expect(row, isNull);
    });
  });
}
