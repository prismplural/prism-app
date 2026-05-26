// test/data/repositories/drift_poll_repository_test.dart
//
// Patch-style `updatePoll` and `closePoll` (item #8 of the drift-repo
// migration plan). Asserts that:
//
//   * `updatePoll` emits only changed fields, no-ops on unchanged input,
//     refuses tombstoned/missing rows, null-clears, and never emits
//     `is_deleted` through the diff path.
//   * `closePoll` emits a narrow patch (only `is_closed`), reads pre-write
//     state so unrelated columns don't end up in the patch (no
//     read-after-write trap), and silently no-ops on already-closed or
//     tombstoned polls.
//
// Mirrors the test pattern in drift_notes_repository_test.dart.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/poll_options_dao.dart';
import 'package:prism_plurality/core/database/daos/poll_votes_dao.dart';
import 'package:prism_plurality/core/database/daos/polls_dao.dart';
import 'package:prism_plurality/data/repositories/drift_poll_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/poll.dart' as domain;

void main() {
  late AppDatabase db;
  late PollsDao pollsDao;
  late PollOptionsDao optionsDao;
  late PollVotesDao votesDao;
  late DriftPollRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    pollsDao = PollsDao(db);
    optionsDao = PollOptionsDao(db);
    votesDao = PollVotesDao(db);
    repo = DriftPollRepository(pollsDao, optionsDao, votesDao, null);
  });

  tearDown(() => db.close());

  final baseTime = DateTime.utc(2026, 5, 1, 12);

  domain.Poll makePoll({
    String id = 'p1',
    String question = 'Original question',
    String? description = 'Original description',
    bool isAnonymous = false,
    bool allowsMultipleVotes = false,
    bool isClosed = false,
    DateTime? expiresAt,
    DateTime? createdAt,
  }) {
    return domain.Poll(
      id: id,
      question: question,
      description: description,
      isAnonymous: isAnonymous,
      allowsMultipleVotes: allowsMultipleVotes,
      isClosed: isClosed,
      expiresAt: expiresAt,
      createdAt: createdAt ?? baseTime,
    );
  }

  group('updatePoll (patch-style emission)', () {
    test('emits only the changed fields', () async {
      await repo.createPoll(makePoll());
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updatePoll(makePoll(question: 'Updated question'));

      expect(captured, hasLength(1));
      expect(captured.single.opType, SyncRecordOpType.update);
      expect(captured.single.table, 'polls');
      expect(captured.single.entityId, 'p1');
      expect(captured.single.fields.keys.toSet(), {'question'});
      expect(captured.single.fields['question'], 'Updated question');
      expect(captured.single.fields.containsKey('is_deleted'), isFalse);
    });

    test('emits nothing when the domain object matches the stored row',
        () async {
      await repo.createPoll(makePoll());
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updatePoll(makePoll());

      expect(captured, isEmpty);
    });

    test('preserves untouched columns in the database', () async {
      await repo.createPoll(
        makePoll(
          description: 'Original description',
          isAnonymous: true,
          allowsMultipleVotes: true,
          expiresAt: baseTime.add(const Duration(days: 7)),
        ),
      );

      await repo.updatePoll(
        makePoll(
          question: 'Updated question',
          description: 'Original description',
          isAnonymous: true,
          allowsMultipleVotes: true,
          expiresAt: baseTime.add(const Duration(days: 7)),
        ),
      );

      final row = await pollsDao.getPollById('p1');
      expect(row, isNotNull);
      expect(row!.question, 'Updated question');
      expect(row.description, 'Original description');
      expect(row.isAnonymous, isTrue);
      expect(row.allowsMultipleVotes, isTrue);
      // Drift stores DateTimes without the UTC marker, so compare instants.
      expect(
        row.expiresAt!.isAtSameMomentAs(baseTime.add(const Duration(days: 7))),
        isTrue,
      );
    });

    test('null-clearing emits the null and writes it to the database',
        () async {
      await repo.createPoll(
        makePoll(description: 'Original description'),
      );
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updatePoll(makePoll(description: null));

      expect(captured, hasLength(1));
      final patch = captured.single.fields;
      expect(patch.containsKey('description'), isTrue);
      expect(patch['description'], isNull);

      final row = await pollsDao.getPollById('p1');
      expect(row!.description, isNull);
    });

    test('silently no-ops on a tombstoned poll', () async {
      await repo.createPoll(makePoll());
      await repo.deletePoll('p1');
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updatePoll(makePoll(question: 'Attempted edit'));

      expect(captured, isEmpty);
      final row = await pollsDao.getPollById('p1');
      expect(row, isNotNull);
      expect(row!.isDeleted, isTrue);
      expect(row.question, 'Original question');
    });

    test('silently no-ops when the row does not exist', () async {
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updatePoll(makePoll(id: 'missing'));

      expect(captured, isEmpty);
      final row = await pollsDao.getPollById('missing');
      expect(row, isNull);
    });

    test('does not emit is_deleted in the patch', () async {
      // A domain object always has isDeleted-equivalent semantics of "false"
      // (no such field on the domain model), so the only way is_deleted can
      // appear in an update emission is if the diff helper leaks it. Pin
      // that it doesn't.
      await repo.createPoll(makePoll());
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updatePoll(makePoll(question: 'Updated question'));

      expect(captured, hasLength(1));
      expect(captured.single.fields.containsKey('is_deleted'), isFalse);
    });
  });

  group('closePoll (patch-style emission)', () {
    test('emits only is_closed', () async {
      await repo.createPoll(makePoll());
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.closePoll('p1');

      expect(captured, hasLength(1));
      expect(captured.single.opType, SyncRecordOpType.update);
      expect(captured.single.table, 'polls');
      expect(captured.single.entityId, 'p1');
      expect(captured.single.fields.keys.toSet(), {'is_closed'});
      expect(captured.single.fields['is_closed'], isTrue);
      expect(captured.single.fields.containsKey('is_deleted'), isFalse);

      // The DAO row should reflect the close.
      final row = await pollsDao.getPollById('p1');
      expect(row!.isClosed, isTrue);
    });

    test(
      'closePoll reads pre-write state (no read-after-write trap)',
      () async {
        // Set up a poll with non-default values for every column closePoll
        // does NOT touch. If closePoll naively refetched after the DAO
        // write, the diff would either drop is_closed (refetch shows
        // closed) or include every column the refetch returned. Pinning:
        // the patch must contain ONLY is_closed and nothing else.
        await repo.createPoll(
          makePoll(
            question: 'Pre-close question',
            description: 'Pre-close description',
            isAnonymous: true,
            allowsMultipleVotes: true,
            expiresAt: baseTime.add(const Duration(days: 14)),
            createdAt: baseTime,
          ),
        );
        final captured = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(captured.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

        await repo.closePoll('p1');

        expect(captured, hasLength(1));
        final patch = captured.single.fields;
        expect(patch.keys.toSet(), {'is_closed'});
        expect(patch['is_closed'], isTrue);

        // Sanity: the other columns kept their original values; closePoll
        // didn't accidentally write them through the partial companion.
        final row = await pollsDao.getPollById('p1');
        expect(row!.question, 'Pre-close question');
        expect(row.description, 'Pre-close description');
        expect(row.isAnonymous, isTrue);
        expect(row.allowsMultipleVotes, isTrue);
        expect(
          row.expiresAt!
              .isAtSameMomentAs(baseTime.add(const Duration(days: 14))),
          isTrue,
        );
        expect(row.isClosed, isTrue);
      },
    );

    test('silently no-ops on an already-closed poll', () async {
      await repo.createPoll(makePoll(isClosed: true));
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.closePoll('p1');

      expect(captured, isEmpty);
    });

    test('silently no-ops on a tombstoned poll', () async {
      await repo.createPoll(makePoll());
      await repo.deletePoll('p1');
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.closePoll('p1');

      expect(captured, isEmpty);
      final row = await pollsDao.getPollById('p1');
      expect(row, isNotNull);
      expect(row!.isClosed, isFalse);
    });

    test('silently no-ops when the row does not exist', () async {
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.closePoll('missing');

      expect(captured, isEmpty);
    });
  });
}
