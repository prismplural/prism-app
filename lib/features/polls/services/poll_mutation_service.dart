import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/mutations/app_failure.dart';
import 'package:prism_plurality/core/mutations/mutation_result.dart';
import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/domain/models/poll.dart' as domain;
import 'package:prism_plurality/domain/models/poll_option.dart' as domain;
import 'package:prism_plurality/domain/models/poll_vote.dart' as domain;
import 'package:prism_plurality/domain/repositories/poll_repository.dart';
import 'package:prism_plurality/features/polls/models/cast_poll_vote_command.dart';
import 'package:prism_plurality/features/polls/models/poll_summary.dart';

class PollMutationService {
  PollMutationService({
    required AppDatabase database,
    required PollRepository repository,
    MutationRunner? runner,
  }) : _database = database,
       _repository = repository,
       _runner = runner ?? MutationRunner.forDatabase(database);

  final AppDatabase _database;
  final PollRepository _repository;
  final MutationRunner _runner;

  Stream<List<PollSummary>> watchPollSummaries() {
    return _database
        .customSelect(
          '''
          SELECT
            p.id,
            p.question,
            p.is_anonymous,
            p.allows_multiple_votes,
            p.is_closed,
            p.expires_at,
            p.created_at,
            COUNT(DISTINCT o.id) AS option_count,
            COUNT(v.id) AS vote_count
          FROM polls p
          LEFT JOIN poll_options o
            ON o.poll_id = p.id
           AND o.is_deleted = 0
          LEFT JOIN poll_votes v
            ON v.poll_option_id = o.id
           AND v.is_deleted = 0
          WHERE p.is_deleted = 0
          GROUP BY
            p.id,
            p.question,
            p.is_anonymous,
            p.allows_multiple_votes,
            p.is_closed,
            p.expires_at,
            p.created_at
          ORDER BY p.created_at DESC
          ''',
          readsFrom: {
            _database.polls,
            _database.pollOptions,
            _database.pollVotes,
          },
        )
        .watch()
        .map((rows) => rows.map(_mapSummary).toList());
  }

  Stream<List<domain.PollOption>> watchOptionsWithVotesForPoll(String pollId) {
    return _database
        .customSelect(
          '''
          SELECT
            o.id AS option_id,
            o.option_text,
            o.sort_order,
            o.is_other_option,
            v.id AS vote_id,
            v.member_id,
            v.voted_at,
            v.response_text
          FROM poll_options o
          LEFT JOIN poll_votes v
            ON v.poll_option_id = o.id
           AND v.is_deleted = 0
          WHERE o.poll_id = ?
            AND o.is_deleted = 0
          ORDER BY o.sort_order ASC, v.voted_at DESC
          ''',
          variables: [Variable.withString(pollId)],
          readsFrom: {_database.pollOptions, _database.pollVotes},
        )
        .watch()
        .map(_mapOptionsWithVotes);
  }

  Future<MutationResult<domain.Poll>> createPoll({
    required String question,
    String? description,
    required List<String> optionTexts,
    List<String?>? optionColorHexes,
    required bool isAnonymous,
    required bool allowsMultipleVotes,
    required DateTime? expiresAt,
    required bool addOtherOption,
    required String pollId,
    required DateTime createdAt,
    required List<String> optionIds,
    required String otherOptionId,
  }) {
    return _runner.run<domain.Poll>(
      actionLabel: 'Create poll',
      action: () async {
        final poll = domain.Poll(
          id: pollId,
          question: question,
          description: description,
          isAnonymous: isAnonymous,
          allowsMultipleVotes: allowsMultipleVotes,
          expiresAt: expiresAt,
          createdAt: createdAt,
          options: [
            for (var i = 0; i < optionTexts.length; i++)
              domain.PollOption(
                id: optionIds[i],
                text: optionTexts[i],
                sortOrder: i,
                colorHex: optionColorHexes != null && i < optionColorHexes.length
                    ? optionColorHexes[i]
                    : null,
              ),
            if (addOtherOption)
              domain.PollOption(
                id: otherOptionId,
                text: 'Other',
                sortOrder: optionTexts.length,
                isOtherOption: true,
              ),
          ],
        );
        await _repository.createPoll(poll);

        return poll;
      },
    );
  }

  Future<MutationResult<void>> castVote(CastPollVoteCommand command) {
    return _runner.runVoid(
      actionLabel: 'Cast poll vote',
      action: () async {
        final poll = await _database.pollsDao.getPollById(command.pollId);
        if (poll == null || poll.isDeleted) {
          throw AppFailure.notFound('Poll not found');
        }

        final now = DateTime.now();
        if (poll.isClosed ||
            (poll.expiresAt != null && poll.expiresAt!.isBefore(now))) {
          throw AppFailure.validation('Poll is closed');
        }

        final optionBelongsToPoll = await _optionBelongsToPoll(
          command.optionId,
          command.pollId,
        );
        if (!optionBelongsToPoll) {
          throw AppFailure.validation(
            'Selected option does not belong to poll',
          );
        }

        if (poll.allowsMultipleVotes) {
          final duplicateVotes = await _database.pollVotesDao
              .getVotesForMemberOnOption(command.optionId, command.memberId);
          for (final vote in duplicateVotes) {
            await _repository.removeVote(vote.id);
          }
        } else {
          final existingVotes = await _database.pollVotesDao
              .getVotesForMemberInPoll(command.pollId, command.memberId);
          for (final vote in existingVotes) {
            await _repository.removeVote(vote.id);
          }
        }

        await _repository.castVote(
          domain.PollVote(
            id: '${command.memberId}-${command.optionId}-${now.microsecondsSinceEpoch}',
            memberId: command.memberId,
            votedAt: now,
            responseText: command.responseText,
          ),
          command.optionId,
        );
      },
    );
  }

  Future<MutationResult<void>> removeVote(String voteId) {
    return _runner.runVoid(
      actionLabel: 'Remove poll vote',
      action: () => _repository.removeVote(voteId),
    );
  }

  Future<MutationResult<void>> closePoll(String pollId) {
    return _runner.runVoid(
      actionLabel: 'Close poll',
      action: () => _repository.closePoll(pollId),
    );
  }

  Future<MutationResult<void>> deletePoll(String pollId) {
    return _runner.runVoid(
      actionLabel: 'Delete poll',
      action: () => _repository.deletePoll(pollId),
    );
  }

  PollSummary _mapSummary(QueryRow row) {
    return PollSummary(
      id: _readValue<String>(row, 'id', DriftSqlType.string),
      question: _readValue<String>(row, 'question', DriftSqlType.string),
      isAnonymous: _readValue<bool>(row, 'is_anonymous', DriftSqlType.bool),
      allowsMultipleVotes: _readValue<bool>(
        row,
        'allows_multiple_votes',
        DriftSqlType.bool,
      ),
      isClosed: _readValue<bool>(row, 'is_closed', DriftSqlType.bool),
      expiresAt: _readNullableValue<DateTime>(
        row,
        'expires_at',
        DriftSqlType.dateTime,
      ),
      createdAt: _readValue<DateTime>(row, 'created_at', DriftSqlType.dateTime),
      optionCount: _readValue<int>(row, 'option_count', DriftSqlType.int),
      voteCount: _readValue<int>(row, 'vote_count', DriftSqlType.int),
    );
  }

  List<domain.PollOption> _mapOptionsWithVotes(List<QueryRow> rows) {
    final options = <String, _PollOptionAccumulator>{};
    final order = <String>[];

    for (final row in rows) {
      final optionId = _readValue<String>(
        row,
        'option_id',
        DriftSqlType.string,
      );

      final accumulator = options.putIfAbsent(optionId, () {
        order.add(optionId);
        return _PollOptionAccumulator(
          id: optionId,
          text: _readValue<String>(row, 'option_text', DriftSqlType.string),
          sortOrder: _readValue<int>(row, 'sort_order', DriftSqlType.int),
          isOtherOption: _readValue<bool>(
            row,
            'is_other_option',
            DriftSqlType.bool,
          ),
        );
      });

      final voteId = _readNullableValue<String>(
        row,
        'vote_id',
        DriftSqlType.string,
      );
      if (voteId == null) continue;

      accumulator.votes.add(
        domain.PollVote(
          id: voteId,
          memberId: _readValue<String>(row, 'member_id', DriftSqlType.string),
          votedAt: _readValue<DateTime>(row, 'voted_at', DriftSqlType.dateTime),
          responseText: _readNullableValue<String>(
            row,
            'response_text',
            DriftSqlType.string,
          ),
        ),
      );
    }

    return order.map((id) => options[id]!.build()).toList();
  }

  T _readValue<T>(QueryRow row, String column, DriftSqlType type) {
    final value = _database.typeMapping.read(type, row.data[column]);
    return value as T;
  }

  T? _readNullableValue<T>(QueryRow row, String column, DriftSqlType type) {
    final value = _database.typeMapping.read(type, row.data[column]);
    return value as T?;
  }

  Future<bool> _optionBelongsToPoll(String optionId, String pollId) async {
    final rows = await _database
        .customSelect(
          '''
      SELECT id
      FROM poll_options
      WHERE id = ?
        AND poll_id = ?
        AND is_deleted = 0
      LIMIT 1
      ''',
          variables: [
            Variable.withString(optionId),
            Variable.withString(pollId),
          ],
          readsFrom: {_database.pollOptions},
        )
        .get();

    return rows.isNotEmpty;
  }
}

class _PollOptionAccumulator {
  _PollOptionAccumulator({
    required this.id,
    required this.text,
    required this.sortOrder,
    required this.isOtherOption,
  });

  final String id;
  final String text;
  final int sortOrder;
  final bool isOtherOption;
  final List<domain.PollVote> votes = [];

  domain.PollOption build() {
    return domain.PollOption(
      id: id,
      text: text,
      sortOrder: sortOrder,
      isOtherOption: isOtherOption,
      votes: List<domain.PollVote>.unmodifiable(votes),
    );
  }
}
