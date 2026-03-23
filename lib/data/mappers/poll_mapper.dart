import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/domain/models/poll.dart' as domain;

class PollMapper {
  PollMapper._();

  /// Maps a Drift [Poll] row to a domain [domain.Poll].
  ///
  /// Note: The [options] field is set to an empty list by default.
  /// Callers should populate options separately via [PollOptionMapper].
  static domain.Poll toDomain(Poll row) {
    return domain.Poll(
      id: row.id,
      question: row.question,
      description: row.description,
      isAnonymous: row.isAnonymous,
      allowsMultipleVotes: row.allowsMultipleVotes,
      isClosed: row.isClosed,
      expiresAt: row.expiresAt,
      createdAt: row.createdAt,
      options: const [],
    );
  }

  static PollsCompanion toCompanion(domain.Poll model) {
    return PollsCompanion(
      id: Value(model.id),
      question: Value(model.question),
      description: Value(model.description),
      isAnonymous: Value(model.isAnonymous),
      allowsMultipleVotes: Value(model.allowsMultipleVotes),
      isClosed: Value(model.isClosed),
      expiresAt: Value(model.expiresAt),
      createdAt: Value(model.createdAt),
    );
  }
}
