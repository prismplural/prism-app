import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/notes/utils/notes_filter.dart';
import 'package:prism_plurality/domain/models/note.dart';

void main() {
  final sampleNotes = [
    Note(
      id: '1',
      title: 'Shopping List',
      body: 'Milk, eggs, bread',
      memberId: 'mem-a',
      date: DateTime(2024, 1, 1),
      createdAt: DateTime(2024, 1, 1),
      modifiedAt: DateTime(2024, 1, 1),
    ),
    Note(
      id: '2',
      title: 'Gratitude',
      body: 'Grateful for sunshine',
      memberId: 'mem-b',
      date: DateTime(2024, 1, 2),
      createdAt: DateTime(2024, 1, 2),
      modifiedAt: DateTime(2024, 1, 2),
    ),
    Note(
      id: '3',
      title: 'Random thoughts',
      body: 'Nothing important',
      memberId: null,
      date: DateTime(2024, 1, 3),
      createdAt: DateTime(2024, 1, 3),
      modifiedAt: DateTime(2024, 1, 3),
    ),
    Note(
      id: '4',
      title: 'Project ideas',
      body: 'Build an app',
      memberId: 'mem-a',
      date: DateTime(2024, 1, 4),
      createdAt: DateTime(2024, 1, 4),
      modifiedAt: DateTime(2024, 1, 4),
    ),
  ];

  group('filterNotes', () {
    group('no filter active', () {
      test('returns all notes when both filters are null', () {
        expect(filterNotes(sampleNotes).length, 4);
      });

      test('returns all notes when query is empty', () {
        expect(filterNotes(sampleNotes, query: '').length, 4);
      });

      test('returns all notes when filterMemberId is null', () {
        expect(filterNotes(sampleNotes, filterMemberId: null).length, 4);
      });
    });

    group('search query', () {
      test('matches title case-insensitively', () {
        final result = filterNotes(sampleNotes, query: 'shopping');
        expect(result.length, 1);
        expect(result.first.id, '1');
      });

      test('matches body text', () {
        final result = filterNotes(sampleNotes, query: 'sunshine');
        expect(result.length, 1);
        expect(result.first.id, '2');
      });

      test('matches multiple notes', () {
        // "in" appears in "Shopping" (title #1), "sunshine" (body #2),
        // and "Nothing" (body #3)
        final result = filterNotes(sampleNotes, query: 'in');
        expect(result.length, 3);
        expect(result.map((n) => n.id), containsAll(['1', '2', '3']));
      });

      test('skips query under 2 characters', () {
        final result = filterNotes(sampleNotes, query: 'x');
        expect(result.length, 4);
      });

      test('skips whitespace-only query', () {
        final result = filterNotes(sampleNotes, query: '   ');
        expect(result.length, 4);
      });

      test('trims whitespace around query', () {
        final result = filterNotes(sampleNotes, query: '  shopping  ');
        expect(result.length, 1);
        expect(result.first.id, '1');
      });

      test('returns empty when nothing matches', () {
        final result = filterNotes(sampleNotes, query: 'xyzzynotfound');
        expect(result, isEmpty);
      });
    });

    group('member filter', () {
      test('filters by specific memberId', () {
        final result = filterNotes(sampleNotes, filterMemberId: 'mem-a');
        expect(result.length, 2);
        expect(result.map((n) => n.id), containsAll(['1', '4']));
      });

      test('filters unassociated notes with filterNoMemberId', () {
        final result =
            filterNotes(sampleNotes, filterMemberId: filterNoMemberId);
        expect(result.length, 1);
        expect(result.first.id, '3');
        expect(result.first.memberId, isNull);
      });

      test('returns empty when memberId has no notes', () {
        final result = filterNotes(sampleNotes, filterMemberId: 'mem-z');
        expect(result, isEmpty);
      });
    });

    group('AND logic', () {
      test('narrows results when both query and memberId active', () {
        // mem-a has "Shopping List" and "Project ideas"
        final result = filterNotes(
          sampleNotes,
          query: 'shopping',
          filterMemberId: 'mem-a',
        );
        expect(result.length, 1);
        expect(result.first.id, '1');
      });

      test('returns empty when query matches but memberId does not', () {
        final result = filterNotes(
          sampleNotes,
          query: 'shopping',
          filterMemberId: 'mem-b',
        );
        expect(result, isEmpty);
      });

      test('returns empty when memberId matches but query does not', () {
        final result = filterNotes(
          sampleNotes,
          query: 'xyzzynotfound',
          filterMemberId: 'mem-a',
        );
        expect(result, isEmpty);
      });

      test('combined with filterNoMemberId and query', () {
        final result = filterNotes(
          sampleNotes,
          query: 'random',
          filterMemberId: filterNoMemberId,
        );
        expect(result.length, 1);
        expect(result.first.id, '3');
      });
    });
  });
}
