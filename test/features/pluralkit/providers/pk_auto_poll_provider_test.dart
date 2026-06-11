import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_auto_poll_provider.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

/// Fake service that only counts pollFrontersOnly calls. Everything else
/// throws — this test never exercises other paths.
class _FakePkSyncService implements PluralKitSyncService {
  int pollCount = 0;
  int liveFrontsOnlyCount = 0;
  bool? lastLiveIsManual;
  PkSyncDirection? lastLiveDirection;
  Object? pollThrows;
  bool storedTokenPresent = true;

  /// 2026-06 PK audit M3: pollFrontersOnly now classifies its outcome instead
  /// of returning a bare bool. Defaults to `ok` (a healthy tick); tests set it
  /// to drive the auth/429/transient mappings in the auto-poll notifier.
  PkPollOutcome pollOutcome = PkPollOutcome.ok;

  @override
  Future<PkPollOutcome> pollFrontersOnly() async {
    pollCount++;
    final err = pollThrows;
    if (err != null) throw err;
    return pollOutcome;
  }

  @override
  Future<PkSyncSummary?> syncLiveFrontersOnly({
    bool isManual = false,
    required PkSyncDirection direction,
    PKSwitch? knownCurrentFronters,
  }) async {
    liveFrontsOnlyCount++;
    lastLiveIsManual = isManual;
    lastLiveDirection = direction;
    return null;
  }

  @override
  Future<bool> hasStoredToken() async => storedTokenPresent;

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

class _FakePkSyncModeNotifier extends PkSyncModeNotifier {
  _FakePkSyncModeNotifier(this._mode);

  final PkSyncMode _mode;

  @override
  PkSyncMode build() => _mode;

  @override
  Future<void> load() async {
    state = _mode;
  }

  @override
  Future<void> setMode(PkSyncMode mode) async {
    state = mode;
  }
}

class _FakePkSyncDirectionNotifier extends PkSyncDirectionNotifier {
  _FakePkSyncDirectionNotifier([this._direction = PkSyncDirection.pullOnly]);

  final PkSyncDirection _direction;

  @override
  PkSyncDirection build() => _direction;

  @override
  Future<void> load() async {
    state = _direction;
  }
}

final _fakePkSyncProvider =
    NotifierProvider<_FakePkSyncNotifier, PluralKitSyncState>(
      _FakePkSyncNotifier.new,
    );

ProviderContainer _container(
  _FakePkSyncService service, {
  PkSyncMode syncMode = PkSyncMode.fullSync,
  PkSyncDirection direction = PkSyncDirection.pullOnly,
  PkSyncEventBus? bus,
}) {
  return ProviderContainer(
    overrides: [
      pluralKitSyncServiceProvider.overrideWithValue(service),
      pluralKitSyncProvider.overrideWith(_ProxyPkSync.new),
      pkSyncModeProvider.overrideWith(() => _FakePkSyncModeNotifier(syncMode)),
      pkSyncDirectionProvider.overrideWith(
        () => _FakePkSyncDirectionNotifier(direction),
      ),
      if (bus != null) pkSyncEventBusProvider.overrideWithValue(bus),
    ],
  );
}

/// Proxies `pluralKitSyncProvider` reads to `_fakePkSyncProvider` so the
/// real notifier (which requires the service + DAO + repos) doesn't build.
class _ProxyPkSync extends PluralKitSyncNotifier {
  @override
  PluralKitSyncState build() {
    final state = ref.watch(_fakePkSyncProvider);
    return state;
  }

  @override
  Future<PkSyncSummary?> syncLiveFrontersOnly({
    bool isManual = false,
    PkSyncDirection direction = PkSyncDirection.pullOnly,
    PKSwitch? knownCurrentFronters,
  }) {
    return ref
        .read(pluralKitSyncServiceProvider)
        .syncLiveFrontersOnly(
          isManual: isManual,
          direction: direction,
          knownCurrentFronters: knownCurrentFronters,
        );
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

    test('setIntervalSeconds rejects values outside the choice list', () async {
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
      await c.read(pkAutoPollSettingsProvider.notifier).setIntervalSeconds(120);
      expect(c.read(pkAutoPollSettingsProvider).value?.intervalSeconds, 120);
    });
  });

  group('PkAutoPollNotifier', () {
    setUp(
      () => SharedPreferences.setMockInitialValues({
        'pk_auto_poll_enabled': true,
        'pk_auto_poll_interval_seconds': 60,
      }),
    );

    test('does not tick when not foregrounded', () async {
      final fake = _FakePkSyncService();
      final c = _container(fake);
      addTearDown(c.dispose);

      // Connected + mapped → canAutoSync = true.
      c
          .read(_fakePkSyncProvider.notifier)
          .set(
            const PluralKitSyncState(
              isConnected: true,
              directionConfirmed: true,
              mappingAcknowledged: true,
            ),
          );
      await c.read(pkAutoPollSettingsProvider.future);
      c.read(pkAutoPollProvider); // instantiate notifier

      // Without markForegrounded(true), no tick fires.
      await Future<void>.delayed(Duration.zero);
      expect(fake.pollCount, 0);
    });

    test(
      'markForegrounded(true) triggers an immediate catch-up tick',
      () async {
        final fake = _FakePkSyncService();
        final c = _container(fake);
        addTearDown(c.dispose);

        c
            .read(_fakePkSyncProvider.notifier)
            .set(
              const PluralKitSyncState(
                isConnected: true,
                directionConfirmed: true,
                mappingAcknowledged: true,
              ),
            );
        await c.read(pkAutoPollSettingsProvider.future);
        c.read(pkAutoPollProvider.notifier).markForegrounded(true);

        await Future<void>.delayed(Duration.zero);
        expect(fake.pollCount, 1);
      },
    );

    test(
      'live-fronts-only mode dispatches live sync instead of full poll',
      () async {
        final fake = _FakePkSyncService();
        final c = _container(fake, syncMode: PkSyncMode.liveFrontsOnly);
        addTearDown(c.dispose);

        c
            .read(_fakePkSyncProvider.notifier)
            .set(
              const PluralKitSyncState(
                isConnected: true,
                directionConfirmed: true,
                mappingAcknowledged: true,
              ),
            );
        await c.read(pkAutoPollSettingsProvider.future);
        c.read(pkAutoPollProvider.notifier).markForegrounded(true);

        await Future<void>.delayed(Duration.zero);
        expect(fake.liveFrontsOnlyCount, 1);
        expect(fake.pollCount, 0);
        expect(fake.lastLiveIsManual, isFalse);
        expect(fake.lastLiveDirection, PkSyncDirection.pullOnly);
      },
    );

    test('!canAutoSync gates the tick even when foregrounded', () async {
      final fake = _FakePkSyncService();
      final c = _container(fake);
      addTearDown(c.dispose);

      // isConnected=false → canAutoSync=false
      c.read(_fakePkSyncProvider.notifier).set(const PluralKitSyncState());
      await c.read(pkAutoPollSettingsProvider.future);
      c.read(pkAutoPollProvider.notifier).markForegrounded(true);

      await Future<void>.delayed(Duration.zero);
      expect(fake.pollCount, 0);
    });

    test('noteLocalPush suppresses the immediate catch-up tick', () async {
      final fake = _FakePkSyncService();
      final c = _container(fake);
      addTearDown(c.dispose);

      c
          .read(_fakePkSyncProvider.notifier)
          .set(
            const PluralKitSyncState(
              isConnected: true,
              directionConfirmed: true,
              mappingAcknowledged: true,
            ),
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

        c
            .read(_fakePkSyncProvider.notifier)
            .set(
              const PluralKitSyncState(
                isConnected: true,
                directionConfirmed: true,
                mappingAcknowledged: true,
              ),
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

  group('event emission', () {
    setUp(() {
      markPkBusMainIsolate();
      SharedPreferences.setMockInitialValues({
        'pk_auto_poll_enabled': true,
        'pk_auto_poll_interval_seconds': 60,
      });
    });
    tearDown(resetPkBusMainIsolateForTest);

    Iterable<PkAutoPollTick> autoPollTicks(PkSyncEventBusCapture capture) =>
        capture.events.whereType<PkAutoPollTick>();

    test('successful tick emits PkAutoPollTick(outcome: "ok")', () async {
      final capture = PkSyncEventBusCapture();
      final fake = _FakePkSyncService();
      final c = _container(fake, bus: capture.bus);
      addTearDown(c.dispose);

      c
          .read(_fakePkSyncProvider.notifier)
          .set(
            const PluralKitSyncState(
              isConnected: true,
              directionConfirmed: true,
              mappingAcknowledged: true,
            ),
          );
      await c.read(pkAutoPollSettingsProvider.future);
      c.read(pkAutoPollProvider.notifier).markForegrounded(true);

      await Future<void>.delayed(Duration.zero);

      final ticks = autoPollTicks(capture).toList();
      expect(ticks, hasLength(1));
      expect(ticks.single.outcome, 'ok');
      expect(ticks.single.reason, isNull);
      expect(ticks.single.error, isNull);
    });

    test(
      'M3: an authFailed poll outcome emits PkAutoPollTick(outcome: '
      '"auth_failed") — a revoked token no longer logs as healthy',
      () async {
        final capture = PkSyncEventBusCapture();
        final fake = _FakePkSyncService()
          ..pollOutcome = PkPollOutcome.authFailed;
        final c = _container(fake, bus: capture.bus);
        addTearDown(c.dispose);

        c.read(_fakePkSyncProvider.notifier).set(
              const PluralKitSyncState(
                isConnected: true,
                directionConfirmed: true,
                mappingAcknowledged: true,
              ),
            );
        await c.read(pkAutoPollSettingsProvider.future);
        c.read(pkAutoPollProvider.notifier).markForegrounded(true);
        await Future<void>.delayed(Duration.zero);

        final ticks = autoPollTicks(capture).toList();
        expect(ticks, hasLength(1));
        expect(ticks.single.outcome, 'auth_failed');
        expect(fake.pollCount, 1);
      },
    );

    test(
      'M3: a rateLimited poll outcome emits a skipped tick (reason '
      '"rate_limited") and routes into the 429 backoff path',
      () async {
        final capture = PkSyncEventBusCapture();
        final fake = _FakePkSyncService()
          ..pollOutcome = PkPollOutcome.rateLimited;
        final c = _container(fake, bus: capture.bus);
        addTearDown(c.dispose);

        c.read(_fakePkSyncProvider.notifier).set(
              const PluralKitSyncState(
                isConnected: true,
                directionConfirmed: true,
                mappingAcknowledged: true,
              ),
            );
        await c.read(pkAutoPollSettingsProvider.future);
        c.read(pkAutoPollProvider.notifier).markForegrounded(true);
        await Future<void>.delayed(Duration.zero);

        final ticks = autoPollTicks(capture).toList();
        expect(ticks, hasLength(1));
        expect(ticks.single.outcome, 'skipped');
        expect(ticks.single.reason, 'rate_limited');
        expect(fake.pollCount, 1);
      },
    );

    test(
      'failed tick (service throws) emits PkAutoPollTick(outcome: "failed") without error payload',
      () async {
        final capture = PkSyncEventBusCapture();
        final fake = _FakePkSyncService()..pollThrows = Exception('boom');
        final c = _container(fake, bus: capture.bus);
        addTearDown(c.dispose);

        c
            .read(_fakePkSyncProvider.notifier)
            .set(
              const PluralKitSyncState(
                isConnected: true,
                directionConfirmed: true,
                mappingAcknowledged: true,
              ),
            );
        await c.read(pkAutoPollSettingsProvider.future);
        c.read(pkAutoPollProvider.notifier).markForegrounded(true);

        await Future<void>.delayed(Duration.zero);

        final ticks = autoPollTicks(capture).toList();
        expect(ticks, hasLength(1));
        expect(ticks.single.outcome, 'failed');
        // The auto-poll notifier has no captured token to redact against, so it
        // intentionally omits the exception message from the emitted event to
        // avoid leaking tokens embedded in error strings.
        expect(ticks.single.error, isNull);
      },
    );

    test(
      'failed tick does not leak a token embedded in the exception toString()',
      () async {
        final capture = PkSyncEventBusCapture();
        const token = 'pk-test-token-leak-vector-xyz';
        final fake = _FakePkSyncService()
          ..pollThrows = Exception('upstream failed with token=$token');
        final c = _container(fake, bus: capture.bus);
        addTearDown(c.dispose);

        c
            .read(_fakePkSyncProvider.notifier)
            .set(
              const PluralKitSyncState(
                isConnected: true,
                directionConfirmed: true,
                mappingAcknowledged: true,
              ),
            );
        await c.read(pkAutoPollSettingsProvider.future);
        c.read(pkAutoPollProvider.notifier).markForegrounded(true);

        await Future<void>.delayed(Duration.zero);

        final ticks = autoPollTicks(capture).toList();
        expect(ticks, hasLength(1));
        final tick = ticks.single;
        expect(tick.outcome, 'failed');
        // Neither the dedicated `error` field nor the serialized JSON payload
        // (which is what feeds the on-device log UI) may contain the token.
        expect(tick.error, isNull);
        expect(
          tick.summary.contains(token),
          isFalse,
          reason: 'token must not appear in the tile summary',
        );
        final jsonString = tick.toJson().toString();
        expect(
          jsonString.contains(token),
          isFalse,
          reason: 'token must not appear anywhere in the serialized event',
        );
      },
    );

    test(
      'recent_push skip path emits PkAutoPollTick(outcome: "skipped", reason: "recent_push")',
      () async {
        final capture = PkSyncEventBusCapture();
        final fake = _FakePkSyncService();
        final c = _container(fake, bus: capture.bus);
        addTearDown(c.dispose);

        c
            .read(_fakePkSyncProvider.notifier)
            .set(
              const PluralKitSyncState(
                isConnected: true,
                directionConfirmed: true,
                mappingAcknowledged: true,
              ),
            );
        await c.read(pkAutoPollSettingsProvider.future);
        final notifier = c.read(pkAutoPollProvider.notifier);
        notifier.noteLocalPush();
        notifier.markForegrounded(true);

        await Future<void>.delayed(Duration.zero);

        final ticks = autoPollTicks(capture).toList();
        expect(ticks, hasLength(1));
        expect(ticks.single.outcome, 'skipped');
        expect(ticks.single.reason, 'recent_push');
        expect(fake.pollCount, 0);
      },
    );

    test(
      'cannot_auto_sync skip path emits PkAutoPollTick(outcome: "skipped", reason: "cannot_auto_sync")',
      () async {
        final capture = PkSyncEventBusCapture();
        final fake = _FakePkSyncService();
        final c = _container(fake, bus: capture.bus);
        addTearDown(c.dispose);

        // isConnected=false → canAutoSync=false. _reschedule won't set a timer,
        // but markForegrounded(true) still triggers an immediate _tickOnce.
        c.read(_fakePkSyncProvider.notifier).set(const PluralKitSyncState());
        await c.read(pkAutoPollSettingsProvider.future);
        c.read(pkAutoPollProvider.notifier).markForegrounded(true);

        await Future<void>.delayed(Duration.zero);

        final ticks = autoPollTicks(capture).toList();
        expect(ticks, hasLength(1));
        final tick = ticks.single;
        expect(tick.outcome, 'skipped');
        expect(tick.reason, 'cannot_auto_sync');
        expect(tick.gate, containsPair('is_connected', false));
        expect(tick.gate, containsPair('direction_confirmed', false));
        expect(tick.gate, containsPair('mapping_acknowledged', false));
        expect(tick.gate, containsPair('can_auto_sync', false));
        expect(tick.gate, containsPair('is_syncing', false));
        expect(tick.gate, containsPair('token_present', true));
        expect(tick.toJson()['gate'], tick.gate);
        expect(fake.pollCount, 0);
      },
    );

    test(
      'missing token skip path stays separate from disconnected setup state',
      () async {
        final capture = PkSyncEventBusCapture();
        final fake = _FakePkSyncService()..storedTokenPresent = false;
        final c = _container(fake, bus: capture.bus);
        addTearDown(c.dispose);

        c
            .read(_fakePkSyncProvider.notifier)
            .set(
              const PluralKitSyncState(
                isConnected: true,
                directionConfirmed: true,
                mappingAcknowledged: true,
              ),
            );
        await c.read(pkAutoPollSettingsProvider.future);
        c.read(pkAutoPollProvider.notifier).markForegrounded(true);

        await Future<void>.delayed(Duration.zero);

        final ticks = autoPollTicks(capture).toList();
        expect(ticks, hasLength(1));
        final tick = ticks.single;
        expect(tick.outcome, 'skipped');
        expect(tick.reason, 'token_missing');
        expect(tick.gate, containsPair('is_connected', true));
        expect(tick.gate, containsPair('direction_confirmed', true));
        expect(tick.gate, containsPair('mapping_acknowledged', true));
        expect(tick.gate, containsPair('can_auto_sync', true));
        expect(tick.gate, containsPair('token_present', false));
        expect(fake.pollCount, 0);
      },
    );

    test(
      'busy skip path emits PkAutoPollTick(outcome: "skipped", reason: "busy")',
      () async {
        final capture = PkSyncEventBusCapture();
        final fake = _FakePkSyncService();
        final c = _container(fake, bus: capture.bus);
        addTearDown(c.dispose);

        c
            .read(_fakePkSyncProvider.notifier)
            .set(
              const PluralKitSyncState(
                isConnected: true,
                directionConfirmed: true,
                mappingAcknowledged: true,
                isSyncing: true,
              ),
            );
        await c.read(pkAutoPollSettingsProvider.future);
        c.read(pkAutoPollProvider.notifier).markForegrounded(true);

        await Future<void>.delayed(Duration.zero);

        final ticks = autoPollTicks(capture).toList();
        expect(ticks, hasLength(1));
        expect(ticks.single.outcome, 'skipped');
        expect(ticks.single.reason, 'busy');
        expect(fake.pollCount, 0);
      },
    );

    test(
      'pull_disabled skip path emits PkAutoPollTick(outcome: "skipped", reason: "pull_disabled") in liveFrontsOnly mode',
      () async {
        final capture = PkSyncEventBusCapture();
        final fake = _FakePkSyncService();
        final c = _container(
          fake,
          bus: capture.bus,
          syncMode: PkSyncMode.liveFrontsOnly,
          direction: PkSyncDirection.pushOnly, // pullEnabled=false
        );
        addTearDown(c.dispose);

        c
            .read(_fakePkSyncProvider.notifier)
            .set(
              const PluralKitSyncState(
                isConnected: true,
                directionConfirmed: true,
                mappingAcknowledged: true,
              ),
            );
        await c.read(pkAutoPollSettingsProvider.future);
        c.read(pkAutoPollProvider.notifier).markForegrounded(true);

        await Future<void>.delayed(Duration.zero);

        final ticks = autoPollTicks(capture).toList();
        expect(ticks, hasLength(1));
        expect(ticks.single.outcome, 'skipped');
        expect(ticks.single.reason, 'pull_disabled');
        expect(fake.liveFrontsOnlyCount, 0);
      },
    );

    // SKIP: The `not_foregrounded` early-return path inside `_tickOnce`
    // (line 167: `if (!_foreground) return;`) is effectively unreachable from
    // tests. The only way to invoke `_tickOnce` from the public API is via
    // `markForegrounded(true)` (which sets `_foreground = true` BEFORE
    // calling `_tickOnce`) or via the timer set by `_reschedule()` (which
    // bails out unless `_foreground` is true). The guard exists as a
    // belt-and-suspenders check; emitting `'not_foregrounded'` is verified
    // by code review rather than a runtime test.
  });
}
