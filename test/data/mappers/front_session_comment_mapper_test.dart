import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart' as db;
import 'package:prism_plurality/data/mappers/front_session_comment_mapper.dart';
import 'package:prism_plurality/domain/models/front_session_comment.dart'
    as domain;

import '../../helpers/mapper_test_helpers.dart';

void main() {
  group('FrontSessionCommentMapper', () {
    final now = DateTime(2026, 3, 20, 12, 0);
    final commentTime = DateTime(2026, 3, 20, 10, 45);

    test('toDomain maps all fields correctly', () {
      final row = makeDbFrontSessionComment(
        id: 'comment-full',
        sessionId: 'session-42',
        body: 'Feeling good today',
        timestamp: commentTime,
        createdAt: now,
      );

      final model = FrontSessionCommentMapper.toDomain(row);
      expect(model.id, 'comment-full');
      expect(model.sessionId, 'session-42');
      expect(model.body, 'Feeling good today');
      expect(model.timestamp, commentTime);
      expect(model.createdAt, now);
    });

    test('toCompanion preserves all fields', () {
      final model = domain.FrontSessionComment(
        id: 'comment-comp',
        sessionId: 'session-7',
        body: 'Companion test body',
        timestamp: commentTime,
        createdAt: now,
      );

      final companion = FrontSessionCommentMapper.toCompanion(model);
      expect(companion.id.value, 'comment-comp');
      expect(companion.sessionId.value, 'session-7');
      expect(companion.body.value, 'Companion test body');
      expect(companion.timestamp.value, commentTime);
      expect(companion.createdAt.value, now);
    });

    test('round-trip preserves data', () {
      final original = domain.FrontSessionComment(
        id: 'rt-comment',
        sessionId: 'rt-session',
        body: 'Round trip comment',
        timestamp: commentTime,
        createdAt: now,
      );

      final companion = FrontSessionCommentMapper.toCompanion(original);
      final row = db.FrontSessionCommentRow(
        id: companion.id.value,
        sessionId: companion.sessionId.value,
        body: companion.body.value,
        timestamp: companion.timestamp.value,
        createdAt: companion.createdAt.value,
        isDeleted: false,
        targetTime: null,
        authorMemberId: null,
      );

      final restored = FrontSessionCommentMapper.toDomain(row);
      expect(restored.id, original.id);
      expect(restored.sessionId, original.sessionId);
      expect(restored.body, original.body);
      expect(restored.timestamp, original.timestamp);
      expect(restored.createdAt, original.createdAt);
    });

    test('handles empty body', () {
      final row = makeDbFrontSessionComment(body: '');
      final model = FrontSessionCommentMapper.toDomain(row);
      expect(model.body, '');
    });
  });
}
