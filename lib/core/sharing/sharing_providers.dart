import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/sharing/friend.dart';
import 'package:prism_plurality/core/sharing/share_scope.dart';
import 'package:prism_plurality/core/sharing/sharing_service.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/domain/models/friend_record.dart';

/// Provides the [SharingService], wired to the Rust FFI handle.
///
/// Returns `null` when sync is not configured (no handle available).
final sharingServiceProvider = Provider<SharingService?>((ref) {
  final handleAsync = ref.watch(prismSyncHandleProvider);
  final handle = handleAsync.value;
  if (handle == null) return null;
  return SharingService(handle: handle);
});

/// Database-backed friends list.
///
/// Converts between the domain [FriendRecord] (persisted) and the in-memory
/// [Friend] model used by the sharing UI.
final friendsProvider =
    NotifierProvider<FriendsNotifier, List<Friend>>(FriendsNotifier.new);

class FriendsNotifier extends Notifier<List<Friend>> {
  @override
  List<Friend> build() {
    final repo = ref.watch(friendsRepositoryProvider);
    final sub = repo.watchAll().listen((records) {
      state = records.map(_recordToFriend).toList();
    });
    ref.onDispose(sub.cancel);
    return [];
  }

  Future<void> addFriend(Friend friend) async {
    final repo = ref.read(friendsRepositoryProvider);
    await repo.createFriend(_friendToRecord(friend));
    ref.invalidateSelf();
  }

  Future<void> removeFriend(String id) async {
    final repo = ref.read(friendsRepositoryProvider);
    await repo.deleteFriend(id);
    ref.invalidateSelf();
  }

  Future<void> updateFriend(Friend friend) async {
    final repo = ref.read(friendsRepositoryProvider);
    await repo.updateFriend(_friendToRecord(friend));
    ref.invalidateSelf();
  }
}

// ---------------------------------------------------------------------------
// Conversion helpers
// ---------------------------------------------------------------------------

Friend _recordToFriend(FriendRecord record) {
  return Friend(
    id: record.id,
    displayName: record.displayName,
    publicKeyHex: record.publicKeyHex,
    grantedScopes: record.grantedScopes
        .map(_parseScopeString)
        .whereType<ShareScope>()
        .toList(),
    addedAt: record.createdAt,
    lastSyncAt: record.lastSyncAt,
    sharedSecretHex: record.sharedSecretHex,
    isVerified: record.isVerified,
  );
}

FriendRecord _friendToRecord(Friend friend) {
  return FriendRecord(
    id: friend.id,
    displayName: friend.displayName,
    publicKeyHex: friend.publicKeyHex,
    sharedSecretHex: friend.sharedSecretHex,
    grantedScopes: friend.grantedScopes.map((s) => s.name).toList(),
    isVerified: friend.isVerified,
    createdAt: friend.addedAt,
    lastSyncAt: friend.lastSyncAt,
  );
}

ShareScope? _parseScopeString(String name) {
  for (final scope in ShareScope.values) {
    if (scope.name == name) return scope;
  }
  return null;
}
