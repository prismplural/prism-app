import 'package:prism_plurality/domain/models/friend_record.dart' as domain;

abstract class FriendsRepository {
  Stream<List<domain.FriendRecord>> watchAll();
  Future<domain.FriendRecord?> getById(String id);
  Future<void> createFriend(domain.FriendRecord friend);
  Future<void> updateFriend(domain.FriendRecord friend);
  Future<void> deleteFriend(String id);
}
