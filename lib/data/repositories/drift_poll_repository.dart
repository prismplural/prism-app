import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/app_database.dart' as db;
import 'package:prism_plurality/core/database/daos/poll_options_dao.dart';
import 'package:prism_plurality/core/database/daos/poll_votes_dao.dart';
import 'package:prism_plurality/core/database/daos/polls_dao.dart';
import 'package:prism_plurality/data/mappers/poll_mapper.dart';
import 'package:prism_plurality/data/mappers/poll_option_mapper.dart';
import 'package:prism_plurality/data/mappers/poll_vote_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/data/sync/field_diff.dart';
import 'package:prism_plurality/data/utils/sync_datetime.dart';
import 'package:prism_plurality/domain/models/poll.dart' as domain;
import 'package:prism_plurality/domain/models/poll_option.dart' as domain;
import 'package:prism_plurality/domain/models/poll_vote.dart' as domain;
import 'package:prism_plurality/domain/repositories/poll_repository.dart';

class DriftPollRepository with SyncRecordMixin implements PollRepository {
  final PollsDao _pollsDao;
  final PollOptionsDao _optionsDao;
  final PollVotesDao _votesDao;
  final ffi.PrismSyncHandle? _syncHandle;

  @override
  ffi.PrismSyncHandle? get syncHandle => _syncHandle;

  @override
  db.AppDatabase get syncOutboxDatabase => _pollsDao.attachedDatabase;

  static const _pollTable = 'polls';
  static const _pollOptionTable = 'poll_options';
  static const _pollVoteTable = 'poll_votes';

  DriftPollRepository(
    this._pollsDao,
    this._optionsDao,
    this._votesDao,
    this._syncHandle,
  );

  @override
  Future<List<domain.Poll>> getAllPolls() async {
    final rows = await _pollsDao.getAllPolls();
    return rows.map(PollMapper.toDomain).toList();
  }

  @override
  Stream<List<domain.Poll>> watchAllPolls() {
    return _pollsDao.watchAllPolls().map(
      (rows) => rows.map(PollMapper.toDomain).toList(),
    );
  }

  @override
  Future<List<domain.Poll>> getActivePolls() async {
    final rows = await _pollsDao.getActivePolls();
    return rows.map(PollMapper.toDomain).toList();
  }

  @override
  Stream<List<domain.Poll>> watchActivePolls() {
    return _pollsDao.watchActivePolls().map(
      (rows) => rows.map(PollMapper.toDomain).toList(),
    );
  }

  @override
  Future<List<domain.Poll>> getClosedPolls() async {
    final rows = await _pollsDao.getClosedPolls();
    return rows.map(PollMapper.toDomain).toList();
  }

  @override
  Future<domain.Poll?> getPollById(String id) async {
    final row = await _pollsDao.getPollById(id);
    return row != null ? PollMapper.toDomain(row) : null;
  }

  @override
  Stream<domain.Poll?> watchPollById(String id) {
    return _pollsDao
        .watchPollById(id)
        .map((row) => row != null ? PollMapper.toDomain(row) : null);
  }

  @override
  Future<void> createPoll(domain.Poll poll) async {
    await runSyncedWrite(() async {
      final companion = PollMapper.toCompanion(poll);
      await _pollsDao.insertPoll(companion);
      await syncRecordCreate(_pollTable, poll.id, _pollFields(poll));
      for (final option in poll.options) {
        await _optionsDao.insertOption(
          PollOptionMapper.toCompanion(option, poll.id),
        );
        await syncRecordCreate(
          _pollOptionTable,
          option.id,
          _pollOptionFields(option, poll.id),
        );
      }
    });
  }

  @override
  Future<void> updatePoll(domain.Poll poll) async {
    await runSyncedWrite(() async {
      final existingRow = await _pollsDao.getPollById(poll.id);
      if (existingRow == null || existingRow.isDeleted) return;

      final changedFields = diffSyncFields(
        _pollFieldsFromRow(existingRow),
        _pollFields(poll),
      );
      if (changedFields.isEmpty) return;

      final companion = _partialPollCompanion(changedFields);
      await _pollsDao.updatePoll(companion.copyWith(id: Value(poll.id)));
      await syncRecordUpdate(_pollTable, poll.id, changedFields);
    });
  }

  @override
  Future<void> deletePoll(String id) async {
    await runSyncedWrite(() async {
      await _pollsDao.softDeletePoll(id);
      await syncRecordDelete(_pollTable, id);
    });
  }

  @override
  Future<int> getCount() => _pollsDao.getCount();

  @override
  Future<void> closePoll(String id) async {
    // Read BEFORE the DAO write to avoid the read-after-write trap: a
    // post-write fetch would diff a closed row against a closed-state field
    // map and produce an empty patch. Compute the diff on the pre-write row
    // against a domain object representing the closed state, then write the
    // partial companion and emit the patch.
    await runSyncedWrite(() async {
      final existingRow = await _pollsDao.getPollById(id);
      if (existingRow == null || existingRow.isDeleted) return;
      if (existingRow.isClosed) return;

      final previousFields = _pollFieldsFromRow(existingRow);
      final closedRow = existingRow.copyWith(isClosed: true);
      final closedFields = _pollFieldsFromRow(closedRow);

      final changedFields = diffSyncFields(previousFields, closedFields);
      if (changedFields.isEmpty) return;

      final companion = _partialPollCompanion(changedFields);
      await _pollsDao.updatePoll(companion.copyWith(id: Value(id)));
      await syncRecordUpdate(_pollTable, id, changedFields);
    });
  }

  // Options

  @override
  Future<List<domain.PollOption>> getAllOptions() async {
    final rows = await _optionsDao.getAllOptions();
    return rows.map(PollOptionMapper.toDomain).toList();
  }

  @override
  Future<Map<String, List<domain.PollOption>>>
  getAllOptionsGroupedByPoll() async {
    final rows = await _optionsDao.getAllOptions();
    final grouped = <String, List<domain.PollOption>>{};
    for (final row in rows) {
      (grouped[row.pollId] ??= []).add(PollOptionMapper.toDomain(row));
    }
    return grouped;
  }

  @override
  Future<List<domain.PollOption>> getOptionsForPoll(String pollId) async {
    final rows = await _optionsDao.getOptionsForPoll(pollId);
    return rows.map(PollOptionMapper.toDomain).toList();
  }

  @override
  Stream<List<domain.PollOption>> watchOptionsForPoll(String pollId) {
    return _optionsDao
        .watchOptionsForPoll(pollId)
        .map((rows) => rows.map(PollOptionMapper.toDomain).toList());
  }

  @override
  Future<void> createOption(domain.PollOption option, String pollId) async {
    await runSyncedWrite(() async {
      final companion = PollOptionMapper.toCompanion(option, pollId);
      await _optionsDao.insertOption(companion);
      await syncRecordCreate(
        _pollOptionTable,
        option.id,
        _pollOptionFields(option, pollId),
      );
    });
  }

  @override
  Future<void> deleteOption(String id) async {
    await runSyncedWrite(() async {
      await _optionsDao.softDeleteOption(id);
      await syncRecordDelete(_pollOptionTable, id);
    });
  }

  // Votes

  @override
  Future<List<domain.PollVote>> getAllVotes() async {
    final rows = await _votesDao.getAllVotes();
    return rows.map(PollVoteMapper.toDomain).toList();
  }

  @override
  Future<Map<String, List<domain.PollVote>>>
  getAllVotesGroupedByOption() async {
    final rows = await _votesDao.getAllVotes();
    final grouped = <String, List<domain.PollVote>>{};
    for (final row in rows) {
      (grouped[row.pollOptionId] ??= []).add(PollVoteMapper.toDomain(row));
    }
    return grouped;
  }

  @override
  Future<List<domain.PollVote>> getVotesForOption(String optionId) async {
    final rows = await _votesDao.getVotesForOption(optionId);
    return rows.map(PollVoteMapper.toDomain).toList();
  }

  @override
  Stream<List<domain.PollVote>> watchVotesForOption(String optionId) {
    return _votesDao
        .watchVotesForOption(optionId)
        .map((rows) => rows.map(PollVoteMapper.toDomain).toList());
  }

  @override
  Future<void> castVote(domain.PollVote vote, String optionId) async {
    await runSyncedWrite(() async {
      final companion = PollVoteMapper.toCompanion(vote, optionId);
      await _votesDao.insertVote(companion);
      await syncRecordCreate(
        _pollVoteTable,
        vote.id,
        _pollVoteFields(vote, optionId),
      );
    });
  }

  @override
  Future<void> removeVote(String id) async {
    await runSyncedWrite(() async {
      await _votesDao.softDeleteVote(id);
      await syncRecordDelete(_pollVoteTable, id);
    });
  }

  /// Visible-for-testing: builds the field map this repository hands to the
  /// Rust sync engine for create/update.
  @visibleForTesting
  Map<String, dynamic> debugPollFields(domain.Poll p) => _pollFields(p);

  db.PollsCompanion _partialPollCompanion(Map<String, dynamic> fields) {
    return db.PollsCompanion(
      question: fields.containsKey('question')
          ? Value(fields['question'] as String)
          : const Value.absent(),
      description: fields.containsKey('description')
          ? Value(fields['description'] as String?)
          : const Value.absent(),
      isAnonymous: fields.containsKey('is_anonymous')
          ? Value(fields['is_anonymous'] as bool)
          : const Value.absent(),
      allowsMultipleVotes: fields.containsKey('allows_multiple_votes')
          ? Value(fields['allows_multiple_votes'] as bool)
          : const Value.absent(),
      isClosed: fields.containsKey('is_closed')
          ? Value(fields['is_closed'] as bool)
          : const Value.absent(),
      expiresAt: fields.containsKey('expires_at')
          ? Value(
              fields['expires_at'] == null
                  ? null
                  : parseSyncDateTime(fields['expires_at']),
            )
          : const Value.absent(),
      createdAt: fields.containsKey('created_at')
          ? Value(parseSyncDateTime(fields['created_at']))
          : const Value.absent(),
    );
  }

  Map<String, dynamic> _pollFieldsFromRow(db.Poll p) {
    return {
      'question': p.question,
      'description': p.description,
      'is_anonymous': p.isAnonymous,
      'allows_multiple_votes': p.allowsMultipleVotes,
      'is_closed': p.isClosed,
      'expires_at': toSyncUtcOrNull(p.expiresAt),
      'created_at': toSyncUtc(p.createdAt),
      'is_deleted': p.isDeleted,
    };
  }

  Map<String, dynamic> _pollFields(domain.Poll p) => pollFields(p);

  /// Field-map builder for poll sync emissions.
  ///
  /// Public so the Phase 6 batch capture path in `sp_importer.dart` can
  /// construct byte-identical `fields` payloads when it bypasses
  /// `createPoll()` for the bulk insert. See
  /// `docs/plans/sp-import-perf-quick-wins.md` (Phase 5 "Field-map reuse").
  static Map<String, dynamic> pollFields(domain.Poll p) {
    return {
      'question': p.question,
      'description': p.description,
      'is_anonymous': p.isAnonymous,
      'allows_multiple_votes': p.allowsMultipleVotes,
      'is_closed': p.isClosed,
      'expires_at': toSyncUtcOrNull(p.expiresAt),
      'created_at': toSyncUtc(p.createdAt),
      'is_deleted': false,
    };
  }

  Map<String, dynamic> _pollOptionFields(domain.PollOption o, String pollId) =>
      pollOptionFields(o, pollId);

  /// Field-map builder for poll-option sync emissions.
  ///
  /// Public so the Phase 6 batch capture path in `sp_importer.dart` can
  /// construct byte-identical `fields` payloads when it bypasses
  /// the per-option emission inside `createPoll()` for the bulk insert.
  static Map<String, dynamic> pollOptionFields(
    domain.PollOption o,
    String pollId,
  ) {
    return {
      'poll_id': pollId,
      'option_text': o.text,
      'sort_order': o.sortOrder,
      'is_other_option': o.isOtherOption,
      'color_hex': o.colorHex,
      'is_deleted': false,
    };
  }

  Map<String, dynamic> _pollVoteFields(domain.PollVote v, String optionId) =>
      pollVoteFields(v, optionId);

  /// Field-map builder for poll-vote sync emissions.
  ///
  /// Public so the Phase 5 capture-replay path in `sp_importer.dart` can
  /// construct byte-identical `fields` payloads when it bypasses
  /// `castVote()` for the bulk batch insert. Keeping a single implementation
  /// in this file prevents the v1 op-type drift bug from re-entering via a
  /// divergent inline copy. See `docs/plans/sp-import-perf-quick-wins.md`
  /// (Phase 5 "Field-map reuse").
  static Map<String, dynamic> pollVoteFields(
    domain.PollVote v,
    String optionId,
  ) {
    return {
      'poll_option_id': optionId,
      'member_id': v.memberId,
      'voted_at': v.votedAt.toUtc().toIso8601String(),
      'response_text': v.responseText,
      'is_deleted': false,
    };
  }
}
