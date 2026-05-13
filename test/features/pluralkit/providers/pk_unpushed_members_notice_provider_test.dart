import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_unpushed_members_notice_provider.dart';

Member _member({
  required String id,
  String name = 'Member',
  String? displayName,
  String? pluralkitId,
  String? pluralkitUuid,
  bool pluralkitSyncIgnored = false,
  bool isDeleted = false,
}) {
  return Member(
    id: id,
    name: name,
    displayName: displayName,
    emoji: '❔',
    isActive: true,
    createdAt: DateTime.utc(2026, 1, 1),
    pluralkitId: pluralkitId,
    pluralkitUuid: pluralkitUuid,
    pluralkitSyncIgnored: pluralkitSyncIgnored,
    isDeleted: isDeleted,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('applyMembersSnapshot clears when pkReady is false', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(pkUnpushedMembersNoticeProvider.future);
    final controller = container.read(
      pkUnpushedMembersNoticeProvider.notifier,
    );

    // Seed a notice via a normal apply first.
    await controller.applyMembersSnapshot(
      [_member(id: 'm-1', name: 'Alice')],
      pkReady: true,
      pushDisabled: true,
    );
    expect(
      container.read(pkUnpushedMembersNoticeProvider).value?.currentNotice,
      isNotNull,
    );

    await controller.applyMembersSnapshot(
      [_member(id: 'm-1', name: 'Alice')],
      pkReady: false,
      pushDisabled: true,
    );

    expect(
      container.read(pkUnpushedMembersNoticeProvider).value?.currentNotice,
      isNull,
    );
  });

  test('applyMembersSnapshot clears when pushDisabled is false', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(pkUnpushedMembersNoticeProvider.future);
    final controller = container.read(
      pkUnpushedMembersNoticeProvider.notifier,
    );

    await controller.applyMembersSnapshot(
      [_member(id: 'm-1', name: 'Alice')],
      pkReady: true,
      pushDisabled: true,
    );
    expect(
      container.read(pkUnpushedMembersNoticeProvider).value?.currentNotice,
      isNotNull,
    );

    await controller.applyMembersSnapshot(
      [_member(id: 'm-1', name: 'Alice')],
      pkReady: true,
      pushDisabled: false,
    );

    expect(
      container.read(pkUnpushedMembersNoticeProvider).value?.currentNotice,
      isNull,
    );
  });

  test(
    'applyMembersSnapshot publishes notice for one unlinked unmarked member',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(pkUnpushedMembersNoticeProvider.future);
      await container
          .read(pkUnpushedMembersNoticeProvider.notifier)
          .applyMembersSnapshot(
            [_member(id: 'm-1', name: 'Alice', displayName: 'Ali')],
            pkReady: true,
            pushDisabled: true,
          );

      final notice = container
          .read(pkUnpushedMembersNoticeProvider)
          .value
          ?.currentNotice;
      expect(notice, isNotNull);
      expect(notice!.refs, hasLength(1));
      expect(notice.refs.single.memberId, 'm-1');
      expect(notice.refs.single.memberName, 'Alice');
      expect(notice.refs.single.displayName, 'Ali');
    },
  );

  test(
    'members with pluralkitSyncIgnored are filtered out and produce an empty '
    'notice (cleared)',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(pkUnpushedMembersNoticeProvider.future);
      await container
          .read(pkUnpushedMembersNoticeProvider.notifier)
          .applyMembersSnapshot(
            [
              _member(
                id: 'm-1',
                name: 'Alice',
                pluralkitSyncIgnored: true,
              ),
            ],
            pkReady: true,
            pushDisabled: true,
          );

      expect(
        container.read(pkUnpushedMembersNoticeProvider).value?.currentNotice,
        isNull,
      );
    },
  );

  test('members linked to PK are filtered out', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(pkUnpushedMembersNoticeProvider.future);
    await container
        .read(pkUnpushedMembersNoticeProvider.notifier)
        .applyMembersSnapshot(
          [
            _member(
              id: 'm-1',
              name: 'Linked',
              pluralkitUuid: 'uuid-1',
            ),
            _member(id: 'm-2', name: 'LinkedShort', pluralkitId: 'abcde'),
          ],
          pkReady: true,
          pushDisabled: true,
        );

    expect(
      container.read(pkUnpushedMembersNoticeProvider).value?.currentNotice,
      isNull,
    );
  });

  test('soft-deleted members are filtered out', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(pkUnpushedMembersNoticeProvider.future);
    await container
        .read(pkUnpushedMembersNoticeProvider.notifier)
        .applyMembersSnapshot(
          [_member(id: 'm-1', name: 'Tombstone', isDeleted: true)],
          pkReady: true,
          pushDisabled: true,
        );

    expect(
      container.read(pkUnpushedMembersNoticeProvider).value?.currentNotice,
      isNull,
    );
  });

  test('unknown sentinel member is filtered out', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(pkUnpushedMembersNoticeProvider.future);
    await container
        .read(pkUnpushedMembersNoticeProvider.notifier)
        .applyMembersSnapshot(
          [_member(id: unknownSentinelMemberId, name: 'Unknown')],
          pkReady: true,
          pushDisabled: true,
        );

    expect(
      container.read(pkUnpushedMembersNoticeProvider).value?.currentNotice,
      isNull,
    );
  });

  test(
    'dismiss persists the hash and identical snapshot does not republish',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(pkUnpushedMembersNoticeProvider.future);
      final controller = container.read(
        pkUnpushedMembersNoticeProvider.notifier,
      );

      final members = [_member(id: 'm-1', name: 'Alice')];

      await controller.applyMembersSnapshot(
        members,
        pkReady: true,
        pushDisabled: true,
      );
      final notice = container
          .read(pkUnpushedMembersNoticeProvider)
          .value!
          .currentNotice!;

      await controller.dismiss(notice);

      final afterDismiss = container
          .read(pkUnpushedMembersNoticeProvider)
          .value!;
      expect(afterDismiss.currentNotice, isNull);
      expect(
        afterDismiss.dismissedFingerprintHashes,
        contains(notice.dismissalKey),
      );

      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(
        pkUnpushedMembersDismissedHashesPrefsKey,
      );
      expect(stored, [notice.dismissalKey]);
      // The hash must not leak raw member IDs.
      expect(stored!.single, isNot(contains('m-1')));

      // Identical snapshot — must remain suppressed.
      await controller.applyMembersSnapshot(
        members,
        pkReady: true,
        pushDisabled: true,
      );
      expect(
        container.read(pkUnpushedMembersNoticeProvider).value?.currentNotice,
        isNull,
      );
    },
  );

  test(
    'a different cohort produces a different hash and resurfaces the notice',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(pkUnpushedMembersNoticeProvider.future);
      final controller = container.read(
        pkUnpushedMembersNoticeProvider.notifier,
      );

      final original = [_member(id: 'm-1', name: 'Alice')];

      await controller.applyMembersSnapshot(
        original,
        pkReady: true,
        pushDisabled: true,
      );
      final firstNotice = container
          .read(pkUnpushedMembersNoticeProvider)
          .value!
          .currentNotice!;
      await controller.dismiss(firstNotice);

      // New member added — cohort hash should change and banner returns.
      final widened = [
        _member(id: 'm-1', name: 'Alice'),
        _member(id: 'm-2', name: 'Bob'),
      ];
      await controller.applyMembersSnapshot(
        widened,
        pkReady: true,
        pushDisabled: true,
      );

      final next = container
          .read(pkUnpushedMembersNoticeProvider)
          .value
          ?.currentNotice;
      expect(next, isNotNull);
      expect(
        next!.memberIds,
        equals({'m-1', 'm-2'}),
      );
      expect(next.dismissalKey, isNot(firstNotice.dismissalKey));
    },
  );

  test('clearDismissals allows previously-dismissed cohort to republish',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(pkUnpushedMembersNoticeProvider.future);
    final controller = container.read(
      pkUnpushedMembersNoticeProvider.notifier,
    );

    final members = [_member(id: 'm-1', name: 'Alice')];

    await controller.applyMembersSnapshot(
      members,
      pkReady: true,
      pushDisabled: true,
    );
    final notice = container
        .read(pkUnpushedMembersNoticeProvider)
        .value!
        .currentNotice!;
    await controller.dismiss(notice);

    await controller.applyMembersSnapshot(
      members,
      pkReady: true,
      pushDisabled: true,
    );
    expect(
      container.read(pkUnpushedMembersNoticeProvider).value?.currentNotice,
      isNull,
    );

    await controller.clearDismissals();

    await controller.applyMembersSnapshot(
      members,
      pkReady: true,
      pushDisabled: true,
    );

    final after = container
        .read(pkUnpushedMembersNoticeProvider)
        .value
        ?.currentNotice;
    expect(after, isNotNull);
    expect(after!.memberIds, equals({'m-1'}));
  });
}
