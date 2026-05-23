import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/fronting/utils/current_fronters_order.dart';

Member _member(String id, {int displayOrder = 0}) => Member(
  id: id,
  name: id,
  createdAt: DateTime(2026),
  displayOrder: displayOrder,
);

FrontingSession _session(String memberId, DateTime startTime) => FrontingSession(
  id: 'session-$memberId',
  startTime: startTime,
  memberId: memberId,
);

void main() {
  group('orderCurrentFronters', () {
    test('returns empty when there are no active sessions', () {
      final result = orderCurrentFronters(const [], [_member('a')]);
      expect(result, isEmpty);
    });

    test('orders by startTime descending (most recent first)', () {
      final members = [_member('a'), _member('b'), _member('c')];
      final t0 = DateTime(2026, 1, 1, 10);
      final sessions = [
        _session('a', t0),
        _session('b', t0.add(const Duration(minutes: 5))),
        _session('c', t0.add(const Duration(minutes: 2))),
      ];

      final result = orderCurrentFronters(sessions, members);

      expect(result.map((m) => m.id).toList(), ['b', 'c', 'a']);
    });

    test('breaks startTime ties by displayOrder ascending', () {
      final members = [
        _member('a', displayOrder: 30),
        _member('b', displayOrder: 10),
        _member('c', displayOrder: 20),
      ];
      final t = DateTime(2026, 1, 1, 12);
      final sessions = [
        _session('a', t),
        _session('b', t),
        _session('c', t),
      ];

      final result = orderCurrentFronters(sessions, members);

      expect(result.map((m) => m.id).toList(), ['b', 'c', 'a']);
    });

    test('breaks displayOrder ties by id ascending for full determinism', () {
      final members = [
        _member('charlie'),
        _member('alice'),
        _member('bob'),
      ];
      final t = DateTime(2026, 1, 1, 12);
      final sessions = [
        _session('charlie', t),
        _session('alice', t),
        _session('bob', t),
      ];

      final result = orderCurrentFronters(sessions, members);

      expect(result.map((m) => m.id).toList(), ['alice', 'bob', 'charlie']);
    });

    test('skips sessions whose memberId does not resolve to a member', () {
      final members = [_member('a'), _member('b')];
      final t = DateTime(2026, 1, 1, 12);
      final sessions = [
        _session('a', t),
        _session('ghost', t.add(const Duration(minutes: 1))),
        _session('b', t.add(const Duration(minutes: 2))),
      ];

      final result = orderCurrentFronters(sessions, members);

      expect(result.map((m) => m.id).toList(), ['b', 'a']);
    });

    test('skips sessions with null memberId (sleep sessions)', () {
      final members = [_member('a')];
      final t = DateTime(2026, 1, 1, 12);
      final sleep = FrontingSession(
        id: 'sleep',
        startTime: t.add(const Duration(minutes: 5)),
        memberId: null,
      );
      final sessions = [sleep, _session('a', t)];

      final result = orderCurrentFronters(sessions, members);

      expect(result.map((m) => m.id).toList(), ['a']);
    });
  });
}
