import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    hide FrontingSession, Member;
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/services/collapse_open_duplicate_sessions.dart';

void main() {
  // Real in-memory Drift DB (same harness the repair test uses) so the
  // end_time write and the getSessionsForMember query run for real. The
  // repository takes a null sync handle, so emission is a no-op here — the
  // importer that calls this helper handles emission via its post-commit sweep.
  group('collapseOpenDuplicateSessions', () {
    late AppDatabase db;
    late DriftFrontingSessionRepository repository;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repository = DriftFrontingSessionRepository(db.frontingSessionsDao, null);
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> open(
      String id,
      String memberId,
      DateTime start, {
      String? pluralkitUuid,
    }) {
      return repository.createSession(
        FrontingSession(
          id: id,
          startTime: start,
          memberId: memberId,
          pluralkitUuid: pluralkitUuid,
        ),
      );
    }

    Future<List<FrontingSession>> openRowsFor(String memberId) async {
      final rows = await repository.getSessionsForMember(memberId);
      return rows.where((s) => s.endTime == null).toList();
    }

    test('keeps the most-recent open and closes earlier ones at next start',
        () async {
      final t1 = DateTime(2025, 1, 1, 9);
      final t2 = DateTime(2025, 6, 1, 9);
      final t3 = DateTime(2026, 1, 1, 9);
      await open('s1', 'm-1', t1);
      await open('s2', 'm-1', t2);
      await open('s3', 'm-1', t3);

      final closed = await collapseOpenDuplicateSessions(
        repository,
        memberIds: const ['m-1'],
      );

      expect(closed, {'s1', 's2'});
      final opens = await openRowsFor('m-1');
      expect(opens.single.id, 's3');
      expect((await repository.getSessionById('s1'))!.endTime, t2);
      expect((await repository.getSessionById('s2'))!.endTime, t3);
    });

    test('a single open is left untouched (returns nothing closed)', () async {
      await open('s1', 'm-1', DateTime(2026, 1, 1, 9));
      final closed = await collapseOpenDuplicateSessions(
        repository,
        memberIds: const ['m-1'],
      );
      expect(closed, isEmpty);
      expect((await openRowsFor('m-1')).single.id, 's1');
    });

    test('collapses PluralKit-linked opens too, preserving their ids', () async {
      // Unlike the adjacent-merge pass, closing an open only sets end_time and
      // keeps the deterministic (switch, member) id the PK diff sweep needs.
      // Two open switches for one member (the partial unique index on
      // (pluralkit_uuid, member_id) allows distinct switches) is the PK zombie
      // shape — collapse must bound the earlier one without dropping its id.
      await open('pk1', 'm-1', DateTime(2025, 1, 1, 9), pluralkitUuid: 'sw-1');
      await open('pk2', 'm-1', DateTime(2026, 1, 1, 9), pluralkitUuid: 'sw-2');

      final closed = await collapseOpenDuplicateSessions(
        repository,
        memberIds: const ['m-1'],
      );

      expect(closed, {'pk1'});
      expect((await repository.getSessionById('pk1')), isNotNull);
      expect((await openRowsFor('m-1')).single.id, 'pk2');
    });

    test('excluded members are skipped entirely', () async {
      await open('s1', 'm-1', DateTime(2025, 1, 1, 9));
      await open('s2', 'm-1', DateTime(2026, 1, 1, 9));

      final closed = await collapseOpenDuplicateSessions(
        repository,
        memberIds: const ['m-1'],
        excludeMemberIds: const {'m-1'},
      );

      expect(closed, isEmpty);
      expect((await openRowsFor('m-1')).length, 2);
    });
  });
}
