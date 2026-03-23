import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/domain/models/poll_vote.dart' as domain;

class PollVoteMapper {
  PollVoteMapper._();

  static domain.PollVote toDomain(PollVote row) {
    return domain.PollVote(
      id: row.id,
      memberId: row.memberId,
      votedAt: row.votedAt,
      responseText: row.responseText,
    );
  }

  static PollVotesCompanion toCompanion(
      domain.PollVote model, String optionId) {
    return PollVotesCompanion(
      id: Value(model.id),
      pollOptionId: Value(optionId),
      memberId: Value(model.memberId),
      votedAt: Value(model.votedAt),
      responseText: Value(model.responseText),
    );
  }
}
