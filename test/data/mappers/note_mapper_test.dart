import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart' as db;
import 'package:prism_plurality/data/mappers/note_mapper.dart';
import 'package:prism_plurality/domain/models/note.dart' as domain;

import '../../helpers/mapper_test_helpers.dart';

void main() {
  group('NoteMapper', () {
    final now = DateTime(2026, 3, 20, 12, 0);
    final later = DateTime(2026, 3, 20, 14, 30);
    final noteDate = DateTime(2026, 3, 19);

    test('toDomain maps all fields correctly', () {
      final row = makeDbNote(
        id: 'note-full',
        title: 'My Note',
        body: 'Detailed body text',
        colorHex: '#FF5733',
        memberId: 'member-42',
        date: noteDate,
        createdAt: now,
        modifiedAt: later,
      );

      final model = NoteMapper.toDomain(row);
      expect(model.id, 'note-full');
      expect(model.title, 'My Note');
      expect(model.body, 'Detailed body text');
      expect(model.colorHex, '#FF5733');
      expect(model.memberId, 'member-42');
      expect(model.date, noteDate);
      expect(model.createdAt, now);
      expect(model.modifiedAt, later);
    });

    test('toDomain handles null optional fields', () {
      final row = makeDbNote(
        colorHex: null,
        memberId: null,
      );

      final model = NoteMapper.toDomain(row);
      expect(model.colorHex, isNull);
      expect(model.memberId, isNull);
    });

    test('toCompanion preserves all fields in Value wrappers', () {
      final model = domain.Note(
        id: 'note-comp',
        title: 'Companion Test',
        body: 'Body here',
        colorHex: '#00FF00',
        memberId: 'member-7',
        date: noteDate,
        createdAt: now,
        modifiedAt: later,
      );

      final companion = NoteMapper.toCompanion(model);
      expect(companion.id.value, 'note-comp');
      expect(companion.title.value, 'Companion Test');
      expect(companion.body.value, 'Body here');
      expect(companion.colorHex.value, '#00FF00');
      expect(companion.memberId.value, 'member-7');
      expect(companion.date.value, noteDate);
      expect(companion.createdAt.value, now);
      expect(companion.modifiedAt.value, later);
    });

    test('toCompanion preserves null optional fields', () {
      final model = domain.Note(
        id: 'note-null',
        title: 'No Color',
        body: 'Plain note',
        colorHex: null,
        memberId: null,
        date: noteDate,
        createdAt: now,
        modifiedAt: later,
      );

      final companion = NoteMapper.toCompanion(model);
      expect(companion.colorHex.value, isNull);
      expect(companion.memberId.value, isNull);
    });

    test('round-trip preserves data', () {
      final original = domain.Note(
        id: 'rt-note',
        title: 'Round Trip',
        body: 'Testing round trip',
        colorHex: '#AABB11',
        memberId: 'member-rt',
        date: noteDate,
        createdAt: now,
        modifiedAt: later,
      );

      final companion = NoteMapper.toCompanion(original);
      final row = db.NoteRow(
        id: companion.id.value,
        title: companion.title.value,
        body: companion.body.value,
        colorHex: companion.colorHex.value,
        memberId: companion.memberId.value,
        date: companion.date.value,
        createdAt: companion.createdAt.value,
        modifiedAt: companion.modifiedAt.value,
        isDeleted: false,
      );

      final restored = NoteMapper.toDomain(row);
      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.body, original.body);
      expect(restored.colorHex, original.colorHex);
      expect(restored.memberId, original.memberId);
      expect(restored.date, original.date);
      expect(restored.createdAt, original.createdAt);
      expect(restored.modifiedAt, original.modifiedAt);
    });

    test('round-trip preserves data with null optionals', () {
      final original = domain.Note(
        id: 'rt-null',
        title: 'Null Fields',
        body: 'No color or member',
        colorHex: null,
        memberId: null,
        date: noteDate,
        createdAt: now,
        modifiedAt: later,
      );

      final companion = NoteMapper.toCompanion(original);
      final row = db.NoteRow(
        id: companion.id.value,
        title: companion.title.value,
        body: companion.body.value,
        colorHex: companion.colorHex.value,
        memberId: companion.memberId.value,
        date: companion.date.value,
        createdAt: companion.createdAt.value,
        modifiedAt: companion.modifiedAt.value,
        isDeleted: false,
      );

      final restored = NoteMapper.toDomain(row);
      expect(restored.id, original.id);
      expect(restored.colorHex, isNull);
      expect(restored.memberId, isNull);
    });
  });
}
