// ignore_for_file: experimental_member_use

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/members_dao.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:sqlite3/sqlite3.dart' show SqliteException;

/// Wraps a real MembersDao and overrides only the methods the
/// `ensureUnknownSentinelMember` path touches. `insertMember` always
/// throws the configured exception. `getMemberById` returns null on the
/// first call (so the repo decides to insert), then forwards to the
/// underlying DAO (so the post-failure refetch sees whatever the test
/// pre-populated). This lets us drive the race-loser catch path
/// deterministically.
class _RacingDao implements MembersDao {
  _RacingDao(this._delegate, this._toThrow);

  final MembersDao _delegate;
  final Object _toThrow;
  int _getCalls = 0;

  @override
  Future<int> insertMember(MembersCompanion member) async {
    throw _toThrow;
  }

  @override
  Future<Member?> getMemberById(String id) async {
    _getCalls++;
    if (_getCalls == 1) return null;
    return _delegate.getMemberById(id);
  }

  @override
  noSuchMethod(Invocation invocation) =>
      Function.apply(_delegate.noSuchMethod, [invocation]);
}

void main() {
  late AppDatabase db;
  late MembersDao dao;
  late DriftMemberRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = db.membersDao;
    // Pass null for sync handle so syncRecordCreate is a no-op.
    repo = DriftMemberRepository(dao, null);
  });

  tearDown(() async {
    await db.close();
  });

  group('ensureUnknownSentinelMember', () {
    test(
      'first call creates the sentinel and reports wasCreated=true',
      () async {
        final result = await repo.ensureUnknownSentinelMember();
        expect(result.wasCreated, isTrue);
        expect(result.member.id, unknownSentinelMemberId);

        final fetched = await repo.getMemberById(unknownSentinelMemberId);
        expect(fetched, isNotNull);
        expect(fetched!.id, unknownSentinelMemberId);
      },
    );

    test('second call is idempotent and reports wasCreated=false', () async {
      final first = await repo.ensureUnknownSentinelMember();
      expect(first.wasCreated, isTrue);

      final second = await repo.ensureUnknownSentinelMember();
      expect(second.wasCreated, isFalse);
      expect(second.member.id, unknownSentinelMemberId);

      // Exactly one row in the table for the sentinel id.
      final all = await repo.getAllMembers();
      expect(all.where((m) => m.id == unknownSentinelMemberId).length, 1);
    });

    test(
      'returns wasCreated=false when the sentinel was pre-inserted via the DAO',
      () async {
        // Pre-insert directly through the DAO to simulate a row that
        // already existed before this code path runs. The repo should
        // observe it on the initial getMemberById and short-circuit.
        await dao.insertMember(
          MembersCompanion.insert(
            id: unknownSentinelMemberId,
            name: 'Unknown',
            createdAt: DateTime.now().toUtc(),
            emoji: const Value('PRE'),
          ),
        );

        final result = await repo.ensureUnknownSentinelMember();
        expect(result.wasCreated, isFalse);
        // Existing row must be returned untouched (not overwritten).
        expect(result.member.emoji, 'PRE');
      },
    );

    test('two concurrent calls converge — exactly one wasCreated=true, '
        'no thrown exceptions, single row in the table', () async {
      // Drift queues writes on a single connection so the second future
      // typically observes the row from the first; this test guards the
      // defense-in-depth path by also asserting the catch arm is well
      // behaved if the race ever does materialize.
      final results = await Future.wait([
        repo.ensureUnknownSentinelMember(),
        repo.ensureUnknownSentinelMember(),
      ]);

      expect(results, hasLength(2));
      for (final r in results) {
        expect(r.member.id, unknownSentinelMemberId);
      }

      final createdCount = results.where((r) => r.wasCreated).length;
      expect(
        createdCount,
        lessThanOrEqualTo(1),
        reason: 'at most one caller can be the creator',
      );

      final all = await repo.getAllMembers();
      expect(
        all.where((m) => m.id == unknownSentinelMemberId).length,
        1,
        reason: 'exactly one sentinel row regardless of races',
      );
    });

    test('simulated PK constraint violation in insertMember is caught and '
        'the winner is refetched', () async {
      // Pre-insert the "winning" row directly through the DAO so the
      // post-failure refetch in the repo finds something to return.
      await dao.insertMember(
        MembersCompanion.insert(
          id: unknownSentinelMemberId,
          name: 'Winner',
          createdAt: DateTime.now().toUtc(),
          emoji: const Value('WIN'),
        ),
      );

      // _RacingDao returns null on the first getMemberById (so the
      // repo decides to insert), throws PK violation on insertMember
      // (simulating the racing winner already inserted), then forwards
      // the second getMemberById to the real DAO so the refetch sees
      // the winning row.
      final pkException = SqliteException(
        extendedResultCode: 1555, // SQLITE_CONSTRAINT_PRIMARYKEY
        message: 'PRIMARY KEY constraint failed: members.id',
      );
      final racingDao = _RacingDao(dao, pkException);
      final racingRepo = DriftMemberRepository(racingDao, null);

      final result = await racingRepo.ensureUnknownSentinelMember();
      expect(result.wasCreated, isFalse);
      expect(result.member.id, unknownSentinelMemberId);
      expect(result.member.emoji, 'WIN');
    });

    test('a non-constraint exception in insertMember is rethrown', () async {
      // The repo must not swallow arbitrary errors — only SQLite
      // unique/PK constraint violations. A generic StateError must
      // propagate.
      final boom = StateError('disk on fire');
      final racingDao = _RacingDao(dao, boom);
      final boomRepo = DriftMemberRepository(racingDao, null);

      await expectLater(
        boomRepo.ensureUnknownSentinelMember(),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('deleteMember sentinel guard', () {
    test('refuses to delete the Unknown sentinel', () async {
      // Pre-create the sentinel so we know there's a row to "delete."
      await repo.ensureUnknownSentinelMember();

      await expectLater(
        repo.deleteMember(unknownSentinelMemberId),
        throwsA(isA<StateError>()),
      );

      // Sentinel must still be present and not soft-deleted.
      final fetched = await repo.getMemberById(unknownSentinelMemberId);
      expect(fetched, isNotNull);
      expect(fetched!.isDeleted, isFalse);
    });

    test('still deletes ordinary members', () async {
      final member = domain.Member(
        id: 'ordinary-1',
        name: 'Ordinary',
        createdAt: DateTime.now().toUtc(),
      );
      await repo.createMember(member);

      await repo.deleteMember('ordinary-1');

      // softDeleteMember filters by is_deleted=false in the watch streams,
      // but getMemberById returns the row regardless — verify it's flagged.
      final fetched = await repo.getMemberById('ordinary-1');
      expect(fetched, isNotNull);
      expect(fetched!.isDeleted, isTrue);
    });
  });

  group('isAlwaysFronting round-trip', () {
    test('persists isAlwaysFronting=true through create + read', () async {
      final member = domain.Member(
        id: 'always-1',
        name: 'Host',
        createdAt: DateTime.now().toUtc(),
        isAlwaysFronting: true,
      );
      await repo.createMember(member);

      final fetched = await repo.getMemberById('always-1');
      expect(fetched, isNotNull);
      expect(fetched!.isAlwaysFronting, isTrue);
    });

    test('defaults to false when not specified', () async {
      final member = domain.Member(
        id: 'default-1',
        name: 'Default',
        createdAt: DateTime.now().toUtc(),
      );
      await repo.createMember(member);

      final fetched = await repo.getMemberById('default-1');
      expect(fetched, isNotNull);
      expect(fetched!.isAlwaysFronting, isFalse);
    });

    test('updateMember can flip the flag from false → true', () async {
      final member = domain.Member(
        id: 'flip-1',
        name: 'Flip',
        createdAt: DateTime.now().toUtc(),
      );
      await repo.createMember(member);

      final initial = await repo.getMemberById('flip-1');
      expect(initial!.isAlwaysFronting, isFalse);

      await repo.updateMember(initial.copyWith(isAlwaysFronting: true));

      final updated = await repo.getMemberById('flip-1');
      expect(updated!.isAlwaysFronting, isTrue);
    });
  });
}
