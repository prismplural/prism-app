import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/features/members/providers/group_display_prefs_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('groupShowEmojiOnAvatarProvider', () {
    test('default returns true when nothing is persisted for the groupId',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final value = await container.read(
        groupShowEmojiOnAvatarProvider('group-a').future,
      );
      expect(value, isTrue);
    });

    test(
        'set(false) updates state synchronously, persists to SharedPreferences, '
        'and next read returns false', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Await initial build.
      await container.read(groupShowEmojiOnAvatarProvider('group-b').future);
      expect(
        container.read(groupShowEmojiOnAvatarProvider('group-b')).value,
        isTrue,
      );

      // Set to false.
      await container
          .read(groupShowEmojiOnAvatarProvider('group-b').notifier)
          .set(false);

      // In-memory state updated synchronously.
      expect(
        container.read(groupShowEmojiOnAvatarProvider('group-b')).value,
        isFalse,
      );

      // Persisted to SharedPreferences — verify via a fresh container.
      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      final persisted = await container2.read(
        groupShowEmojiOnAvatarProvider('group-b').future,
      );
      expect(persisted, isFalse);
    });

    test('two different groupIds maintain independent persisted state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Await initial builds for both groups.
      await container.read(groupShowEmojiOnAvatarProvider('group-x').future);
      await container.read(groupShowEmojiOnAvatarProvider('group-y').future);

      // Set group-x to false, leave group-y at default.
      await container
          .read(groupShowEmojiOnAvatarProvider('group-x').notifier)
          .set(false);

      expect(
        container.read(groupShowEmojiOnAvatarProvider('group-x')).value,
        isFalse,
      );
      // group-y must remain true — no key collision.
      expect(
        container.read(groupShowEmojiOnAvatarProvider('group-y')).value,
        isTrue,
      );

      // Confirm via fresh container.
      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      final xVal = await container2.read(
        groupShowEmojiOnAvatarProvider('group-x').future,
      );
      final yVal = await container2.read(
        groupShowEmojiOnAvatarProvider('group-y').future,
      );
      expect(xVal, isFalse);
      expect(yVal, isTrue);
    });
  });
}
