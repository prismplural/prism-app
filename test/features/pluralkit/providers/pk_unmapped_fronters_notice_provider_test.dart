import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/features/pluralkit/models/pk_live_fronters_notice.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_unmapped_fronters_notice_provider.dart';

PkUnmappedFrontersNotice _notice({
  String switchId = 'switch-1',
  List<String> sortedPkIds = const ['bbbbb', 'aaaaa'],
}) {
  return PkUnmappedFrontersNotice(
    systemId: 'system-1',
    switchId: switchId,
    switchTimestamp: DateTime.utc(2026, 5, 1, 12),
    sortedPkIds: sortedPkIds,
    refs: [
      for (final id in sortedPkIds)
        PkUnmappedFronterRef(
          pkId: id,
          pkUuid: 'uuid-$id',
          name: 'Name $id',
          displayName: 'Display $id',
          avatarUrl: 'https://cdn.example/$id.png',
        ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('dismiss persists only the hashed dismissal fingerprint', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notice = _notice();

    await container.read(pkUnmappedFrontersNoticeProvider.future);
    await container
        .read(pkUnmappedFrontersNoticeProvider.notifier)
        .publish(notice);
    expect(
      container.read(pkUnmappedFrontersNoticeProvider).value?.currentNotice,
      notice,
    );

    await container
        .read(pkUnmappedFrontersNoticeProvider.notifier)
        .dismissCurrent();

    final state = container.read(pkUnmappedFrontersNoticeProvider).value!;
    expect(state.currentNotice, isNull);
    expect(state.dismissedFingerprintHashes, contains(notice.dismissalKey));

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(
      pkUnmappedFrontersDismissedHashesPrefsKey,
    );
    expect(stored, [notice.dismissalKey]);
    expect(stored!.single, isNot(contains('switch-1')));
    expect(stored.single, isNot(contains('aaaaa')));
    expect(stored.single, isNot(contains('bbbbb')));
  });

  test('dismissed notice is suppressed after provider reload', () async {
    final notice = _notice();
    final first = ProviderContainer();
    addTearDown(first.dispose);
    await first.read(pkUnmappedFrontersNoticeProvider.future);
    await first.read(pkUnmappedFrontersNoticeProvider.notifier).dismiss(notice);

    final second = ProviderContainer();
    addTearDown(second.dispose);
    await second.read(pkUnmappedFrontersNoticeProvider.future);
    await second
        .read(pkUnmappedFrontersNoticeProvider.notifier)
        .publish(notice);

    expect(
      second.read(pkUnmappedFrontersNoticeProvider).value?.currentNotice,
      isNull,
    );

    final changedNotice = _notice(switchId: 'switch-2');
    await second
        .read(pkUnmappedFrontersNoticeProvider.notifier)
        .publish(changedNotice);
    expect(
      second.read(pkUnmappedFrontersNoticeProvider).value?.currentNotice,
      changedNotice,
    );
  });

  test('clear hides current notice without adding a dismissal', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notice = _notice();

    await container.read(pkUnmappedFrontersNoticeProvider.future);
    await container
        .read(pkUnmappedFrontersNoticeProvider.notifier)
        .publish(notice);
    await container.read(pkUnmappedFrontersNoticeProvider.notifier).clear();

    final state = container.read(pkUnmappedFrontersNoticeProvider).value!;
    expect(state.currentNotice, isNull);
    expect(state.dismissedFingerprintHashes, isEmpty);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getStringList(pkUnmappedFrontersDismissedHashesPrefsKey),
      isNull,
    );
  });

  test(
    'observed same live-front fingerprint without notice clears current',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notice = _notice();

      await container.read(pkUnmappedFrontersNoticeProvider.future);
      await container
          .read(pkUnmappedFrontersNoticeProvider.notifier)
          .publish(notice);

      await container
          .read(pkUnmappedFrontersNoticeProvider.notifier)
          .applyLiveFrontersSummary(
            PkSyncSummary(
              observedLiveFronters: true,
              observedLiveFrontersDismissalKey: notice.dismissalKey,
            ),
          );

      final state = container.read(pkUnmappedFrontersNoticeProvider).value!;
      expect(state.currentNotice, isNull);
      expect(state.dismissedFingerprintHashes, isEmpty);
    },
  );
}
