import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/friends_table.dart';

part 'friends_dao.g.dart';

@DriftAccessor(tables: [Friends])
class FriendsDao extends DatabaseAccessor<AppDatabase> with _$FriendsDaoMixin {
  FriendsDao(super.db);

  Stream<List<FriendRow>> watchAll() =>
      (select(friends)
            ..where((f) => f.isDeleted.equals(false))
            ..orderBy([(f) => OrderingTerm.desc(f.createdAt)]))
          .watch();

  Future<FriendRow?> getById(String id) =>
      (select(friends)..where((f) => f.id.equals(id))).getSingleOrNull();

  Future<int> createFriend(FriendsCompanion companion) =>
      into(friends).insert(companion);

  Future<void> updateFriend(String id, FriendsCompanion companion) =>
      (update(friends)..where((f) => f.id.equals(id))).write(companion);

  Future<void> softDelete(String id) =>
      (update(friends)..where((f) => f.id.equals(id)))
          .write(const FriendsCompanion(isDeleted: Value(true)));
}
