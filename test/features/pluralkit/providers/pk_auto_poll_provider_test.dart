import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/features/pluralkit/providers/pk_auto_poll_provider.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

/// Fake service that only counts pollFrontersOnly calls. Everything else
/// throws — this test never exercises other paths.
class _FakePkSyncService implements PluralKitSyncService {
  int pollCount = 0;

  @override
  Future<bool> pollFrontersOnly() async {
    pollCount++;
    return false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// Minimal Notifier that lets tests swap the PK sync state on demand.
class _FakePkSyncNotifier extends Notifier<PluralKitSyncState> {
  @override
  PluralKitSyncState build() => const PluralKitSyncState();

  void set(PluralKitSyncState next) => state = next;
}

final _fakePkSyncProvider =
    NotifierProvider<_FakePkSyncNotifier, PluralKitSyncState>(
  _FakePkSyncNotifier.new,
);

ProviderContainer _container(_FakePkSyncService service) {
  return ProviderContainer(overrides: [
    pluralKitSyncServiceProvider.overrideWithValue(service),
    pluralKitSyncProvider.overrideWith(_ProxyPkSync.new),
  ]);
}

/// Proxies `pluralKitSyncProvider` reads to `_fakePkSyncProvider` so the
/// real notifier (which requires the service + DAO + repos) doesn't build.
class _ProxyPkSync extends PluralKitSyncNotifier {
  @override
  PluralKitSyncState build() {
    final state = ref.watch(_fakePkSyncProvider);
    return state;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PkAutoPollSettingsNotifier', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('defaults: disabled, 30s interval', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final settings = await c.read(pkAutoPollSettingsProvider.future);
      expect(settings.enabled, isFalse);
      expect(settings.intervalSeconds, 30);
    });

    test('setEnabled persists and updates state', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(pkAutoPollSettingsProvider.future);
      await c.read(pkAutoPollSettingsProvider.notifier).setEnabled(true);
      expect(c.read(pkAutoPollSettingsProvider).value?.enabled, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('pk_auto_poll_enabled'), isTrue);
    });

    test('setIntervalSeconds rejects values outside the choice list',
        () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(pkAutoPollSettingsProvider.future);
      await c
          .read(pkAutoPollSettingsProvider.notifier)
          .setIntervalSeconds(7); // not in pkAutoPollIntervalChoices
      expect(c.read(pkAutoPollSettingsProvider).value?.intervalSeconds, 30);
    });

    test('setIntervalSeconds accepts a valid choice', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(pkAutoPollSettingsProvider.future);
      await c
          .read(pkAutoPollSettingsProvider.notifier)
          .setIntervalSeconds(120);
      expect(c.read(pkAutoPollSettingsProvider).value?.intervalSeconds, 120);
    });
  });

  group('PkAutoPollNotifier', () {
    setUp(() => SharedPreferences.setMockInitialValues({
          'pk_auto_poll_enabled': true,
          'pk_auto_poll_interval_seconds': 60,
        }));

    test('does not tick when not foregrounded', () async {
      final fake = _FakePkSyncService();
      final c = _container(fake);
      addTearDown(c.dispose);

      // Connected + mapped → canAutoSync = true.
      c.read(_fakePkSyncProvider.notifier).set(
            const PluralKitSyncState(isConnected: true),
          );
      await c.read(pkAutoPollSettingsProvider.future);
      c.read(pkAutoPollProvider); // instantiate notifier

      // Without markForegrounded(true), no tick fires.
      await Future<void>.delayed(Duration.zero);
      expect(fake.pollCount, 0);
    });

    test('markForegrounded(true) triggers an immediate catch-up tick',
        () async {
      final fake = _FakePkSyncService();
      final c = _container(fake);
      addTearDown(c.dispose);

      c.read(_fakePkSyncProvider.notifier).set(
            const PluralKitSyncState(isConnected: true),
          );
      await c.read(pkAutoPollSettingsProvider.future);
      c.read(pkAutoPollProvider.notifier).markForegrounded(true);

      await Future<void>.delayed(Duration.zero);
      expect(fake.pollCount, 1);
    });

    test('!canAutoSync gates the tick even when foregrounded', () async {
      final fake = _FakePkSyncService();
      final c = _container(fake);
      addTearDown(c.dispose);

      // isConnected=false → canAutoSync=false
      c.read(_fakePkSyncProvider.notifier).set(
            const PluralKitSyncState(),
          );
      await c.read(pkAutoPollSettingsProvider.future);
      c.read(pkAutoPollProvider.notifier).markForegrounded(true);

      await Future<void>.delayed(Duration.zero);
      expect(fake.pollCount, 0);
    });

    test('noteLocalPush suppresses the immediate catch-up tick', () async {
      final fake = _FakePkSyncService();
      final c = _container(fake);
      addTearDown(c.dispose);

      c.read(_fakePkSyncProvider.notifier).set(
            const PluralKitSyncState(isConnected: true),
          );
      await c.read(pkAutoPollSettingsProvider.future);
      final notifier = c.read(pkAutoPollProvider.notifier);
      notifier.noteLocalPush();
      notifier.markForegrounded(true);

      await Future<void>.delayed(Duration.zero);
      expect(fake.pollCount, 0);
    });

    test('periodic tick fires after interval + jitter window', () {
      fakeAsync((async) {
        final fake = _FakePkSyncService();
        final c = _container(fake);
        addTearDown(c.dispose);

        c.read(_fakePkSyncProvider.notifier).set(
              const PluralKitSyncState(isConnected: true),
            );
        c.read(pkAutoPollSettingsProvider);
        async.elapse(const Duration(milliseconds: 10)); // let prefs load
        c.read(pkAutoPollProvider.notifier).markForegrounded(true);
        async.flushMicrotasks();
        final afterImmediate = fake.pollCount;
        expect(afterImmediate, greaterThanOrEqualTo(1));

        // 60s interval ±5s jitter — 70s is past the worst case.
        async.elapse(const Duration(seconds: 70));
        expect(fake.pollCount, greaterThan(afterImmediate));
      });
    });
  });
}
