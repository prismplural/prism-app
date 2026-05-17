import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/poll_votes_table.dart';

part 'poll_votes_dao.g.dart';

@DriftAccessor(tables: [PollVotes])
class PollVotesDao extends DatabaseAccessor<AppDatabase>
    with _$PollVotesDaoMixin {
  PollVotesDao(super.db);

  Future<List<PollVote>> getAllVotes() =>
      (select(pollVotes)..where((v) => v.isDeleted.equals(false))).get();

  Future<List<PollVote>> getVotesForOption(String optionId) =>
      (select(pollVotes)
            ..where(
              (v) =>
                  v.pollOptionId.equals(optionId) & v.isDeleted.equals(false),
            )
            ..orderBy([(v) => OrderingTerm.desc(v.votedAt)]))
          .get();

  Stream<List<PollVote>> watchVotesForOption(String optionId) =>
      (select(pollVotes)
            ..where(
              (v) =>
                  v.pollOptionId.equals(optionId) & v.isDeleted.equals(false),
            )
            ..orderBy([(v) => OrderingTerm.desc(v.votedAt)]))
          .watch();

  Future<PollVote?> getVoteById(String id) =>
      (select(pollVotes)..where((v) => v.id.equals(id))).getSingleOrNull();

  Future<List<PollVote>> getVotesForMember(String memberId) =>
      (select(pollVotes)..where(
            (v) => v.memberId.equals(memberId) & v.isDeleted.equals(false),
          ))
          .get();

  Future<List<PollVote>> getVotesForMemberOnOption(
    String optionId,
    String memberId,
  ) =>
      (select(pollVotes)..where(
            (v) =>
                v.pollOptionId.equals(optionId) &
                v.memberId.equals(memberId) &
                v.isDeleted.equals(false),
          ))
          .get();

  Future<List<PollVote>> getVotesForMemberInPoll(
    String pollId,
    String memberId,
  ) {
    return customSelect(
      '''
      SELECT v.*
      FROM poll_votes v
      INNER JOIN poll_options o
        ON o.id = v.poll_option_id
      WHERE o.poll_id = ?
        AND o.is_deleted = 0
        AND v.member_id = ?
        AND v.is_deleted = 0
      ORDER BY v.voted_at DESC
      ''',
      variables: [Variable.withString(pollId), Variable.withString(memberId)],
      readsFrom: {db.pollVotes, db.pollOptions},
    ).map((row) => pollVotes.map(row.data)).get();
  }

  Future<int> insertVote(PollVotesCompanion vote) =>
      into(pollVotes).insert(vote);

  /// Batch-insert poll votes in a single Drift `batch()` round-trip.
  ///
  /// Used by the SP importer's Phase 5 capture-replay path
  /// (`docs/plans/sp-import-perf-quick-wins.md`) to collapse N per-vote
  /// inserts into one DAO call. Bypasses [DriftPollRepository.castVote], so
  /// the caller is responsible for pushing a captured op tuple per row
  /// using [DriftPollRepository.pollVoteFields] to keep the emission
  /// payload byte-equal to the live-edit path.
  Future<void> batchInsertVotes(List<PollVotesCompanion> rows) async {
    if (rows.isEmpty) return;
    await batch((b) => b.insertAll(pollVotes, rows));
  }

  Future<void> updateVote(PollVotesCompanion vote) {
    assert(vote.id.present, 'Vote id is required for update');
    return (update(
      pollVotes,
    )..where((v) => v.id.equals(vote.id.value))).write(vote);
  }

  Future<void> softDeleteVote(String id) =>
      (update(pollVotes)..where((v) => v.id.equals(id))).write(
        const PollVotesCompanion(isDeleted: Value(true)),
      );
}
