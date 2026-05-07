import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    hide FrontingSession, Member;
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/data/mappers/fronting_session_mapper.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/fronting/providers/member_fronting_history_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';

Member _member(String id, String name) =>
    Member(id: id, name: name, createdAt: DateTime(2026, 1, 1));

FrontingSession _session({
  required String id,
  required String memberId,
  required DateTime start,
  required DateTime end,
}) =>
    FrontingSession(id: id, memberId: memberId, startTime: start, endTime: end);

Future<void> _insert(AppDatabase db, FrontingSession session) {
  return db.frontingSessionsDao.insertSession(
    FrontingSessionMapper.toCompanion(session),
  );
}

Future<MemberFrontingHistoryData> _readHistory(
  ProviderContainer container,
  String memberId,
) async {
  for (var i = 0; i < 20; i++) {
    final value = container.read(memberFrontingHistoryProvider(memberId));
    final data = value.whenOrNull(data: (data) => data);
    if (data != null) return data;

    final error = value.whenOrNull(error: (error, _) => error);
    if (error != null) throw error;

    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for member fronting history');
}

void main() {
  group('memberFrontingHistoryProvider', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    ProviderContainer containerWithMembers(List<Member> members) {
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          allMembersProvider.overrideWith((ref) => Stream.value(members)),
        ],
      );
      addTearDown(container.dispose);
      container.listen<AsyncValue<MemberFrontingHistoryData>>(
        memberFrontingHistoryProvider('a'),
        (_, _) {},
        fireImmediately: true,
      );
      return container;
    }

    test(
      'filters derived periods to the selected member with co-front context',
      () async {
        final a = _member('a', 'Alex');
        final b = _member('b', 'Blair');
        final c = _member('c', 'Casey');
        await _insert(
          db,
          _session(
            id: 'a1',
            memberId: 'a',
            start: DateTime(2026, 4, 1, 10),
            end: DateTime(2026, 4, 1, 12),
          ),
        );
        await _insert(
          db,
          _session(
            id: 'b1',
            memberId: 'b',
            start: DateTime(2026, 4, 1, 11),
            end: DateTime(2026, 4, 1, 13),
          ),
        );
        await _insert(
          db,
          _session(
            id: 'c1',
            memberId: 'c',
            start: DateTime(2026, 4, 2, 10),
            end: DateTime(2026, 4, 2, 11),
          ),
        );

        final container = containerWithMembers([a, b, c]);

        final history = await _readHistory(container, 'a');

        expect(history.periods, hasLength(2));
        expect(history.periods[0].activeMembers, ['a']);
        expect(history.periods[1].activeMembers, ['a', 'b']);
        expect(
          history.periods.any((period) => period.activeMembers.contains('c')),
          isFalse,
        );
      },
    );

    test('loads target member history one page at a time', () async {
      final member = _member('a', 'Alex');
      final base = DateTime(2026, 4, 30, 12);
      for (var i = 0; i < memberFrontingHistoryPageSize + 1; i++) {
        final start = base.subtract(Duration(days: i));
        await _insert(
          db,
          _session(
            id: 'a$i',
            memberId: 'a',
            start: start,
            end: start.add(const Duration(hours: 1)),
          ),
        );
      }

      final container = containerWithMembers([member]);

      final firstPage = await _readHistory(container, 'a');
      expect(
        firstPage.targetSessions,
        hasLength(memberFrontingHistoryPageSize),
      );
      expect(firstPage.hasMore, isTrue);

      container
          .read(memberFrontingHistoryLimitProvider('a').notifier)
          .loadMore();
      final secondPage = await _readHistory(container, 'a');
      expect(
        secondPage.targetSessions,
        hasLength(memberFrontingHistoryPageSize + 1),
      );
      expect(secondPage.hasMore, isFalse);
    });
  });
}
