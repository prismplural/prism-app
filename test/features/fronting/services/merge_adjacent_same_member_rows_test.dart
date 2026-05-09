import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/services/merge_adjacent_same_member_rows.dart';

import '../../../helpers/fake_repositories.dart';

void main() {
  group('mergeAdjacentSameMemberRows', () {
    test(
      'merges same-member rows separated by a tolerated rapid-action gap',
      () async {
        final repo = FakeFrontingSessionRepository();
        await repo.createSession(
          FrontingSession(
            id: 'before',
            memberId: 'host',
            startTime: DateTime.utc(2026, 5, 8, 10),
            endTime: DateTime.utc(2026, 5, 8, 11),
          ),
        );
        await repo.createSession(
          FrontingSession(
            id: 'after',
            memberId: 'host',
            startTime: DateTime.utc(2026, 5, 8, 11, 0, 12),
            endTime: DateTime.utc(2026, 5, 8, 12),
          ),
        );

        final merges = await mergeAdjacentSameMemberRows(
          repo,
          memberIds: const ['host'],
          snapTolerance: kAdjacentSameMemberSnapTolerance,
        );

        expect(merges, 1);
        expect(repo.sessions, hasLength(1));
        expect(repo.sessions.single.id, 'before');
        expect(repo.sessions.single.startTime, DateTime.utc(2026, 5, 8, 10));
        expect(repo.sessions.single.endTime, DateTime.utc(2026, 5, 8, 12));
        expect(repo.deletedIds, ['after']);
      },
    );

    test('merges same-member rows with a tolerated boundary overlap', () async {
      final repo = FakeFrontingSessionRepository();
      await repo.createSession(
        FrontingSession(
          id: 'before',
          memberId: 'host',
          startTime: DateTime.utc(2026, 5, 8, 10),
          endTime: DateTime.utc(2026, 5, 8, 11, 0, 12),
        ),
      );
      await repo.createSession(
        FrontingSession(
          id: 'after',
          memberId: 'host',
          startTime: DateTime.utc(2026, 5, 8, 11),
          endTime: DateTime.utc(2026, 5, 8, 12),
        ),
      );

      final merges = await mergeAdjacentSameMemberRows(
        repo,
        memberIds: const ['host'],
        snapTolerance: kAdjacentSameMemberSnapTolerance,
      );

      expect(merges, 1);
      expect(repo.sessions, hasLength(1));
      expect(repo.sessions.single.id, 'before');
      expect(repo.sessions.single.startTime, DateTime.utc(2026, 5, 8, 10));
      expect(repo.sessions.single.endTime, DateTime.utc(2026, 5, 8, 12));
      expect(repo.deletedIds, ['after']);
    });

    test('does not merge larger intentional gaps', () async {
      final repo = FakeFrontingSessionRepository();
      await repo.createSession(
        FrontingSession(
          id: 'before',
          memberId: 'host',
          startTime: DateTime.utc(2026, 5, 8, 10),
          endTime: DateTime.utc(2026, 5, 8, 11),
        ),
      );
      await repo.createSession(
        FrontingSession(
          id: 'after',
          memberId: 'host',
          startTime: DateTime.utc(2026, 5, 8, 11, 5),
          endTime: DateTime.utc(2026, 5, 8, 12),
        ),
      );

      final merges = await mergeAdjacentSameMemberRows(
        repo,
        memberIds: const ['host'],
        snapTolerance: kAdjacentSameMemberSnapTolerance,
      );

      expect(merges, 0);
      expect(repo.sessions, hasLength(2));
      expect(repo.deletedIds, isEmpty);
    });
  });
}
