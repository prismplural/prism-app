import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/domain/models/front_session_comment.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/services/fronting_mutation_service.dart';

import '../../../helpers/fake_repositories.dart';

Future<T> _passthrough<T>(Future<T> Function() action) => action();

void main() {
  group('logHistoricalFronting', () {
    late FakeFrontingSessionRepository repo;
    late FakeFrontSessionCommentsRepository comments;
    late FrontingMutationService service;

    setUp(() {
      repo = FakeFrontingSessionRepository();
      comments = FakeFrontSessionCommentsRepository();
      service = FrontingMutationService(
        repository: repo,
        mutationRunner: MutationRunner(transactionRunner: _passthrough),
        frontSessionCommentsRepository: comments,
      );
    });

    test('same-member overlap merges into one canonical row', () async {
      await repo.createSession(
        FrontingSession(
          id: 'alice-old',
          startTime: DateTime(2026, 4, 28, 9),
          endTime: DateTime(2026, 4, 28, 10),
          memberId: 'alice',
          notes: 'old',
          confidence: FrontConfidence.unsure,
        ),
      );

      final result = await service.logHistoricalFronting(
        ['alice'],
        startTime: DateTime(2026, 4, 28, 9, 30),
        endTime: DateTime(2026, 4, 28, 11),
        notes: 'new',
        confidence: FrontConfidence.certain,
      );

      expect(result.isSuccess, isTrue);
      expect(repo.sessions, hasLength(1));
      final merged = repo.sessions.single;
      expect(merged.id, 'alice-old');
      expect(merged.startTime, DateTime(2026, 4, 28, 9));
      expect(merged.endTime, DateTime(2026, 4, 28, 11));
      expect(merged.notes, 'old\n\nnew');
      expect(merged.confidence, FrontConfidence.certain);
    });

    test(
      'same-member touching rows bridge and collapse across the full chain',
      () async {
        await repo.createSession(
          FrontingSession(
            id: 'alice-earliest',
            startTime: DateTime(2026, 4, 28, 7),
            endTime: DateTime(2026, 4, 28, 8),
            memberId: 'alice',
          ),
        );
        await repo.createSession(
          FrontingSession(
            id: 'alice-early',
            startTime: DateTime(2026, 4, 28, 8),
            endTime: DateTime(2026, 4, 28, 9),
            memberId: 'alice',
          ),
        );
        await repo.createSession(
          FrontingSession(
            id: 'alice-late',
            startTime: DateTime(2026, 4, 28, 10),
            endTime: DateTime(2026, 4, 28, 11),
            memberId: 'alice',
          ),
        );
        await comments.createComment(
          FrontSessionComment(
            id: 'comment-1',
            sessionId: 'alice-late',
            body: 'keep me',
            timestamp: DateTime(2026, 4, 28, 10, 30),
            createdAt: DateTime(2026, 4, 28, 10, 30),
          ),
        );

        final result = await service.logHistoricalFronting(
          ['alice'],
          startTime: DateTime(2026, 4, 28, 9),
          endTime: DateTime(2026, 4, 28, 10),
        );

        expect(result.isSuccess, isTrue);
        expect(repo.sessions, hasLength(1));
        final merged = repo.sessions.single;
        expect(merged.id, 'alice-earliest');
        expect(merged.startTime, DateTime(2026, 4, 28, 7));
        expect(merged.endTime, DateTime(2026, 4, 28, 11));
        expect(comments.reparentCalls, [
          (fromSessionId: 'alice-early', toSessionId: 'alice-earliest'),
          (fromSessionId: 'alice-late', toSessionId: 'alice-earliest'),
        ]);
        expect(comments.comments.single.sessionId, 'alice-earliest');
      },
    );

    test('different-member overlap stays separate', () async {
      await repo.createSession(
        FrontingSession(
          id: 'bob-existing',
          startTime: DateTime(2026, 4, 28, 10),
          endTime: DateTime(2026, 4, 28, 11),
          memberId: 'bob',
        ),
      );

      final result = await service.logHistoricalFronting(
        ['alice'],
        startTime: DateTime(2026, 4, 28, 10, 15),
        endTime: DateTime(2026, 4, 28, 10, 45),
      );

      expect(result.isSuccess, isTrue);
      expect(repo.sessions, hasLength(2));
      expect(repo.sessions.map((session) => session.memberId).toSet(), {
        'alice',
        'bob',
      });
    });
  });
}
