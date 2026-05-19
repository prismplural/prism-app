// Per-device, per-group cosmetic flag. Does NOT sync across devices.
// Storage key: `group.show_emoji_on_avatar.<groupId>`. Default: true.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _prefKey(String groupId) => 'group.show_emoji_on_avatar.$groupId';

class GroupShowEmojiOnAvatarNotifier extends AsyncNotifier<bool> {
  GroupShowEmojiOnAvatarNotifier(this.groupId);
  final String groupId;

  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey(groupId)) ?? true;
  }

  /// Persist [value] and update in-memory state.
  Future<void> set(bool value) async {
    state = AsyncValue.data(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey(groupId), value);
  }
}

/// Family provider keyed by [groupId]. Default `true` until SharedPreferences resolves.
final groupShowEmojiOnAvatarProvider = AsyncNotifierProvider.family<
    GroupShowEmojiOnAvatarNotifier, bool, String>(
  GroupShowEmojiOnAvatarNotifier.new,
);
