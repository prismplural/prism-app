// Per-device, per-group cosmetic flag.
// Does NOT sync across devices.
//
// Storage key: 'group.show_emoji_on_avatar.<groupId>'
// Default: true (show the emoji badge on top of the avatar when both are set).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _prefKey(String groupId) => 'group.show_emoji_on_avatar.$groupId';

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class GroupShowEmojiOnAvatarNotifier extends AsyncNotifier<bool> {
  GroupShowEmojiOnAvatarNotifier(this.groupId);
  final String groupId;

  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey(groupId)) ?? true;
  }

  /// Persists [value] to SharedPreferences and updates the in-memory state.
  Future<void> set(bool value) async {
    state = AsyncValue.data(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey(groupId), value);
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Family provider keyed by [groupId].
///
/// Usage:
/// ```dart
/// // Read the current value (async):
/// final show = ref.watch(groupShowEmojiOnAvatarProvider(groupId));
///
/// // Persist a change:
/// await ref.read(groupShowEmojiOnAvatarProvider(groupId).notifier).set(false);
/// ```
final groupShowEmojiOnAvatarProvider = AsyncNotifierProvider.family<
    GroupShowEmojiOnAvatarNotifier, bool, String>(
  GroupShowEmojiOnAvatarNotifier.new,
);
