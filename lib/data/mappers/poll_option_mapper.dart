import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/domain/models/poll_option.dart' as domain;

class PollOptionMapper {
  PollOptionMapper._();

  /// Maps a Drift [PollOption] row to a domain [domain.PollOption].
  ///
  /// Note: The [votes] field is set to an empty list by default.
  /// Callers should populate votes separately via [PollVoteMapper].
  static domain.PollOption toDomain(PollOption row) {
    return domain.PollOption(
      id: row.id,
      text: row.optionText,
      sortOrder: row.sortOrder,
      isOtherOption: row.isOtherOption,
      colorHex: row.colorHex,
      votes: const [],
    );
  }

  static PollOptionsCompanion toCompanion(
      domain.PollOption model, String pollId) {
    return PollOptionsCompanion(
      id: Value(model.id),
      pollId: Value(pollId),
      optionText: Value(model.text),
      sortOrder: Value(model.sortOrder),
      isOtherOption: Value(model.isOtherOption),
      colorHex: Value(model.colorHex),
    );
  }
}
