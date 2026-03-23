import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/fronting/editing/fronting_session_change.dart';

void main() {
  group('FrontingSessionPatch', () {
    test('isEmpty is true when no fields are set', () {
      const patch = FrontingSessionPatch();
      expect(patch.isEmpty, isTrue);
    });

    test('isEmpty is false when start is set', () {
      final patch = FrontingSessionPatch(start: DateTime(2025, 1, 1));
      expect(patch.isEmpty, isFalse);
    });

    test('isEmpty is false when end is set', () {
      final patch = FrontingSessionPatch(end: DateTime(2025, 1, 1, 2));
      expect(patch.isEmpty, isFalse);
    });

    test('isEmpty is false when clearEnd is true', () {
      const patch = FrontingSessionPatch(clearEnd: true);
      expect(patch.isEmpty, isFalse);
    });

    test('isEmpty is false when memberId is set', () {
      const patch = FrontingSessionPatch(memberId: 'member-123');
      expect(patch.isEmpty, isFalse);
    });

    test('isEmpty is false when clearMemberId is true', () {
      const patch = FrontingSessionPatch(clearMemberId: true);
      expect(patch.isEmpty, isFalse);
    });

    test('isEmpty is false when coFronterIds is set', () {
      const patch = FrontingSessionPatch(coFronterIds: ['a', 'b']);
      expect(patch.isEmpty, isFalse);
    });

    test('isEmpty is false when notes is set', () {
      const patch = FrontingSessionPatch(notes: 'some notes');
      expect(patch.isEmpty, isFalse);
    });

    test('isEmpty is false when confidenceIndex is set', () {
      const patch = FrontingSessionPatch(confidenceIndex: 3);
      expect(patch.isEmpty, isFalse);
    });
  });

  group('FrontingSessionDraft', () {
    test('construction with required fields only', () {
      final start = DateTime(2025, 6, 1, 10);
      final draft = FrontingSessionDraft(
        memberId: null,
        start: DateTime(2025, 6, 1, 10),
      );

      expect(draft.memberId, isNull);
      expect(draft.start, equals(start));
      expect(draft.end, isNull);
      expect(draft.coFronterIds, isEmpty);
      expect(draft.notes, isNull);
      expect(draft.confidenceIndex, isNull);
    });

    test('construction with all optional fields', () {
      final start = DateTime(2025, 6, 1, 10);
      final end = DateTime(2025, 6, 1, 12);
      final draft = FrontingSessionDraft(
        memberId: 'member-abc',
        start: start,
        end: end,
        coFronterIds: const ['member-x', 'member-y'],
        notes: 'A note',
        confidenceIndex: 4,
      );

      expect(draft.memberId, equals('member-abc'));
      expect(draft.start, equals(start));
      expect(draft.end, equals(end));
      expect(draft.coFronterIds, equals(['member-x', 'member-y']));
      expect(draft.notes, equals('A note'));
      expect(draft.confidenceIndex, equals(4));
    });
  });

  group('FrontingSessionChange sealed subclasses', () {
    test('CreateSessionChange holds draft', () {
      final draft = FrontingSessionDraft(
        memberId: 'member-1',
        start: DateTime(2025, 1, 1),
      );
      final change = CreateSessionChange(draft);

      expect(change.session, same(draft));
    });

    test('UpdateSessionChange holds sessionId and patch', () {
      const patch = FrontingSessionPatch(notes: 'updated');
      const change = UpdateSessionChange(sessionId: 'session-42', patch: patch);

      expect(change.sessionId, equals('session-42'));
      expect(change.patch, same(patch));
    });

    test('DeleteSessionChange holds sessionId', () {
      const change = DeleteSessionChange('session-99');

      expect(change.sessionId, equals('session-99'));
    });

    test('sealed class exhaustive switch works for all 3 types', () {
      final List<FrontingSessionChange> changes = [
        CreateSessionChange(
          FrontingSessionDraft(memberId: null, start: DateTime(2025, 1, 1)),
        ),
        const UpdateSessionChange(
          sessionId: 's1',
          patch: FrontingSessionPatch(confidenceIndex: 2),
        ),
        const DeleteSessionChange('s2'),
      ];

      final results = changes.map(_describeChange).toList();

      expect(results, equals(['create', 'update', 'delete']));
    });
  });
}

String _describeChange(FrontingSessionChange change) => switch (change) {
      CreateSessionChange() => 'create',
      UpdateSessionChange() => 'update',
      DeleteSessionChange() => 'delete',
    };
