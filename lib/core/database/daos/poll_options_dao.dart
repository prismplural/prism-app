import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/poll_options_table.dart';

part 'poll_options_dao.g.dart';

@DriftAccessor(tables: [PollOptions])
class PollOptionsDao extends DatabaseAccessor<AppDatabase>
    with _$PollOptionsDaoMixin {
  PollOptionsDao(super.db);

  Future<List<PollOption>> getOptionsForPoll(String pollId) =>
      (select(pollOptions)
            ..where((o) =>
                o.pollId.equals(pollId) & o.isDeleted.equals(false))
            ..orderBy([(o) => OrderingTerm.asc(o.sortOrder)]))
          .get();

  Stream<List<PollOption>> watchOptionsForPoll(String pollId) =>
      (select(pollOptions)
            ..where((o) =>
                o.pollId.equals(pollId) & o.isDeleted.equals(false))
            ..orderBy([(o) => OrderingTerm.asc(o.sortOrder)]))
          .watch();

  Future<PollOption?> getOptionById(String id) =>
      (select(pollOptions)..where((o) => o.id.equals(id)))
          .getSingleOrNull();

  Future<int> insertOption(PollOptionsCompanion option) =>
      into(pollOptions).insert(option);

  Future<void> updateOption(PollOptionsCompanion option) {
    assert(option.id.present, 'Option id is required for update');
    return (update(pollOptions)
          ..where((o) => o.id.equals(option.id.value)))
        .write(option);
  }

  Future<void> softDeleteOption(String id) =>
      (update(pollOptions)..where((o) => o.id.equals(id))).write(
          const PollOptionsCompanion(isDeleted: Value(true)));
}
