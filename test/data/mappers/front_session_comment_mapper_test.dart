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
    final targetTime = DateTime(2026, 3, 20, 10, 30);

    test('toDomain maps all fields correctly (with targetTime + authorMemberId)',
        () {
      final row = db.FrontSessionCommentRow(
        id: 'comment-full',
        sessionId: 'legacy-session-42',
        body: 'Feeling good today',
        timestamp: commentTime,
        createdAt: now,
        isDeleted: false,
        targetTime: targetTime,
        authorMemberId: 'member-alice',
      );

      final model = FrontSessionCommentMapper.toDomain(row);
      expect(model.id, 'comment-full');
      expect(model.body, 'Feeling good today');
      expect(model.timestamp, commentTime);
      expect(model.createdAt, now);
      expect(model.targetTime, targetTime);
      expect(model.authorMemberId, 'member-alice');
    });

    test('toDomain returns null targetTime for un-migrated rows', () {
      final row = makeDbFrontSessionComment(
        id: 'old-comment',
        body: 'Legacy comment',
        timestamp: commentTime,
        createdAt: now,
        // targetTime and authorMemberId default to null in the helper
      );

      final model = FrontSessionCommentMapper.toDomain(row);
      expect(model.id, 'old-comment');
      expect(model.body, 'Legacy comment');
      expect(model.targetTime, isNull);
      expect(model.authorMemberId, isNull);
    });

    test('toCompanion preserves all fields', () {
      final model = domain.FrontSessionComment(
        id: 'comment-comp',
        body: 'Companion test body',
        timestamp: commentTime,
        createdAt: now,
        targetTime: targetTime,
        authorMemberId: 'member-bob',
      );

      final companion = FrontSessionCommentMapper.toCompanion(model);
      expect(companion.id.value, 'comment-comp');
      expect(companion.body.value, 'Companion test body');
      expect(companion.timestamp.value, commentTime);
      expect(companion.createdAt.value, now);
      expect(companion.targetTime.value, targetTime);
      expect(companion.authorMemberId.value, 'member-bob');
    });

    test('toCompanion handles null targetTime and authorMemberId', () {
      final model = domain.FrontSessionComment(
        id: 'comment-minimal',
        body: 'No target',
        timestamp: commentTime,
        createdAt: now,
      );

      final companion = FrontSessionCommentMapper.toCompanion(model);
      expect(companion.targetTime.value, isNull);
      expect(companion.authorMemberId.value, isNull);
    });

    test('round-trip preserves data', () {
      final original = domain.FrontSessionComment(
        id: 'rt-comment',
        body: 'Round trip comment',
        timestamp: commentTime,
        createdAt: now,
        targetTime: targetTime,
        authorMemberId: 'member-sky',
      );

      final companion = FrontSessionCommentMapper.toCompanion(original);
      final row = db.FrontSessionCommentRow(
        id: companion.id.value,
        sessionId: '',
        body: companion.body.value,
        timestamp: companion.timestamp.value,
        createdAt: companion.createdAt.value,
        isDeleted: false,
        targetTime: companion.targetTime.value,
        authorMemberId: companion.authorMemberId.value,
      );

      final restored = FrontSessionCommentMapper.toDomain(row);
      expect(restored.id, original.id);
      expect(restored.body, original.body);
      expect(restored.timestamp, original.timestamp);
      expect(restored.createdAt, original.createdAt);
      expect(restored.targetTime, original.targetTime);
      expect(restored.authorMemberId, original.authorMemberId);
    });

    test('handles empty body', () {
      final row = makeDbFrontSessionComment(body: '');
      final model = FrontSessionCommentMapper.toDomain(row);
      expect(model.body, '');
    });
  });
}
