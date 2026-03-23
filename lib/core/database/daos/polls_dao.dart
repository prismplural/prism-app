import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/polls_table.dart';

part 'polls_dao.g.dart';

@DriftAccessor(tables: [Polls])
class PollsDao extends DatabaseAccessor<AppDatabase> with _$PollsDaoMixin {
  PollsDao(super.db);

  Future<List<Poll>> getAllPolls() => (select(polls)
        ..where((p) => p.isDeleted.equals(false))
        ..orderBy([(p) => OrderingTerm.desc(p.createdAt)]))
      .get();

  Stream<List<Poll>> watchAllPolls() => (select(polls)
        ..where((p) => p.isDeleted.equals(false))
        ..orderBy([(p) => OrderingTerm.desc(p.createdAt)]))
      .watch();

  Future<List<Poll>> getActivePolls() {
    final now = DateTime.now();
    return (select(polls)
          ..where((p) =>
              p.isClosed.equals(false) &
              p.isDeleted.equals(false) &
              (p.expiresAt.isNull() |
                  p.expiresAt.isBiggerOrEqualValue(now)))
          ..orderBy([(p) => OrderingTerm.desc(p.createdAt)]))
        .get();
  }

  Stream<List<Poll>> watchActivePolls() {
    final now = DateTime.now();
    return (select(polls)
          ..where((p) =>
              p.isClosed.equals(false) &
              p.isDeleted.equals(false) &
              (p.expiresAt.isNull() |
                  p.expiresAt.isBiggerOrEqualValue(now)))
          ..orderBy([(p) => OrderingTerm.desc(p.createdAt)]))
        .watch();
  }

  Future<List<Poll>> getClosedPolls() => (select(polls)
        ..where((p) =>
            p.isClosed.equals(true) & p.isDeleted.equals(false))
        ..orderBy([(p) => OrderingTerm.desc(p.createdAt)]))
      .get();

  Future<Poll?> getPollById(String id) =>
      (select(polls)..where((p) => p.id.equals(id))).getSingleOrNull();

  Stream<Poll?> watchPollById(String id) =>
      (select(polls)..where((p) => p.id.equals(id))).watchSingleOrNull();

  Future<int> insertPoll(PollsCompanion poll) => into(polls).insert(poll);

  Future<void> updatePoll(PollsCompanion poll) {
    assert(poll.id.present, 'Poll id is required for update');
    return (update(polls)..where((p) => p.id.equals(poll.id.value)))
        .write(poll);
  }

  Future<void> softDeletePoll(String id) =>
      (update(polls)..where((p) => p.id.equals(id))).write(
          const PollsCompanion(isDeleted: Value(true)));

  Future<void> closePoll(String id) =>
      (update(polls)..where((p) => p.id.equals(id))).write(
          const PollsCompanion(isClosed: Value(true)));

  Future<int> getCount() async {
    final count = countAll();
    final query = selectOnly(polls)
      ..where(polls.isDeleted.equals(false))
      ..addColumns([count]);
    final row = await query.getSingle();
    return row.read(count)!;
  }
}
