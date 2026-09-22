import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// Path-provider's exported platform interface is supplied transitively.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_sync/generated/frb_generated.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_event_loop.dart';
import 'package:prism_plurality/core/sync/sync_runtime_state.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _Handle implements ffi.PrismSyncHandle {
  final seeded = <String, Uint8List>{};
  int seedCalls = 0;
  int restored = 0;
  int configured = 0;
  int enabled = 0;
  int emitted = 0;
  int emitAttempts = 0;
  int locks = 0;
  int drains = 0;
  bool unlocked = false;
  bool disposed = false;
  @override
  void dispose() => disposed = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Writer with SyncRecordMixin {
  _Writer(this.syncHandle, this.syncOutboxDatabase);
  @override
  final ffi.PrismSyncHandle? syncHandle;
  @override
  final AppDatabase syncOutboxDatabase;
}

// Native crypto/transport are mocked; provider, secure-storage reads, mutation
// capture, and the Drift outbox/drainer are the production implementations.
late _Api _activeApi;

class _ApiProxy implements RustLibApi {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      _activeApi.noSuchMethod(invocation);
}

class _Api implements RustLibApi {
  final handles = <_Handle>[];
  Future<ffi.PrismSyncHandle> Function()? onCreate;
  Future<void> Function(_Handle)? onSeed;
  Future<void> Function(_Handle)? onRestore;
  Future<void> Function(_Handle)? onConfigure;
  Future<void> Function(_Handle)? onLock;
  Future<void> Function(_Handle)? onUnlock;
  Future<void> Function(_Handle)? onResume;
  Future<void> Function(_Handle)? onDrain;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #crateApiCreatePrismSync) {
      final create = onCreate;
      if (create != null) return create();
      final handle = _Handle();
      handles.add(handle);
      return Future<ffi.PrismSyncHandle>.value(handle);
    }
    if (invocation.memberName == #crateApiMnemonicToBytes) {
      return Future<Uint8List>.value(Uint8List(16));
    }
    if (invocation.memberName == #crateApiHexDecode) {
      return Future<Uint8List>.value(Uint8List(32));
    }
    final handle = invocation.namedArguments[#handle] as _Handle;
    expect(
      handle.disposed,
      isFalse,
      reason: 'no native calls on obsolete handles',
    );
    switch (invocation.memberName) {
      case #crateApiExportDek:
        return Future<Uint8List>.value(Uint8List(32));
      case #crateApiIsUnlocked:
        return Future<bool>.value(handle.unlocked);
      case #crateApiSeedSecureStore:
        handle.seedCalls++;
        handle.seeded.addAll(
          invocation.namedArguments[#entries] as Map<String, Uint8List>,
        );
        return onSeed?.call(handle) ?? Future<void>.value();
      case #crateApiRestoreRuntimeKeys:
        handle.restored++;
        handle.unlocked = true;
        return onRestore?.call(handle) ?? Future<void>.value();
      case #crateApiConfigureEngine:
        expect(handle.seeded.containsKey('device_secret'), isTrue);
        handle.configured++;
        return onConfigure?.call(handle) ?? Future<void>.value();
      case #crateApiSetAutoSync:
        if (invocation.namedArguments[#enabled] == true) handle.enabled++;
        return Future<void>.value();
      case #crateApiRecordCreateAt:
      case #crateApiRecordCreate:
        handle.emitAttempts++;
        if (handle.configured == 0) {
          return Future<void>.error(StateError('sync not configured'));
        }
        handle.emitted++;
        return Future<void>.value();
      case #crateApiDrainSecureStore:
        handle.drains++;
        final snapshot = Map<String, Uint8List>.of(handle.seeded);
        return (onDrain?.call(handle) ?? Future<void>.value()).then(
          (_) => snapshot,
        );
      case #crateApiUnlock:
        return (onUnlock?.call(handle) ?? Future<void>.value()).then((_) {
          handle.unlocked = true;
        });
      case #crateApiLock:
        handle.locks++;
        handle.unlocked = false;
        return onLock?.call(handle) ?? Future<void>.value();
      case #crateApiOnResume:
        return onResume?.call(handle) ?? Future<void>.value();
      case #crateApiRecordUpdate:
        return Future<void>.value();
      default:
        return super.noSuchMethod(invocation);
    }
  }
}

class _ManualTimer implements Timer {
  _ManualTimer(this.delay, this.callback);
  final Duration delay;
  final void Function() callback;
  bool _active = true;
  int _tick = 0;
  @override
  bool get isActive => _active;
  @override
  int get tick => _tick;
  @override
  void cancel() => _active = false;
  void fire() {
    expect(isActive, isTrue);
    _active = false;
    _tick++;
    callback();
  }
}

// Control only long one-shot timers through Dart's normal Timer zone hook.
// Short storage retries and real database I/O still run normally.
class _Timers {
  final all = <_ManualTimer>[];
  Iterable<_ManualTimer> get pending => all.where((timer) => timer.isActive);
  Future<T> run<T>(Future<T> Function() body) => runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        if (duration < const Duration(seconds: 1)) {
          return parent.createTimer(zone, duration, callback);
        }
        final timer = _ManualTimer(
          duration,
          zone.bindCallbackGuarded(callback),
        );
        all.add(timer);
        return timer;
      },
    ),
  );
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition did not settle');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _Fixture {
  late final Directory dir;
  late final PathProviderPlatform oldPaths;
  late final AppDatabase db;
  late final ProviderContainer container;
  final api = _Api();
  final store = <String, String>{
    for (final e in <String, List<int>>{
      'sync_id': utf8.encode('sync-1'),
      'device_id': utf8.encode('a1b2c3d4e5f6'),
      'device_secret': List.filled(32, 1),
      'relay_url': utf8.encode('https://localhost:8080'),
      'session_token': utf8.encode('session-1'),
      'wrapped_dek': List.filled(32, 2),
      // Synthetic legacy cache makes the mocked runtime restore deterministic.
      'runtime_dek': List.filled(32, 3),
    }.entries)
      'prism_sync.${e.key}': base64Encode(e.value),
  };
  bool failReads = true;
  bool disposed = false;
  int failedSeedReads = 0;
  Future<void> Function()? beforeReadAll;
  static const channel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  static const runtimeChannel = MethodChannel(
    'com.prism.prism_plurality/runtime_dek_wrap',
  );

  _Handle get handle => api.handles.first;
  PrismSyncHandleNotifier get notifier =>
      container.read(prismSyncHandleProvider.notifier);
  SyncHealthState get health => container.read(syncHealthProvider);

  Future<void> initialize() async {
    dir = await Directory.systemTemp.createTemp('prism-seed-retry-');
    oldPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(dir.path);
    SharedPreferences.setMockInitialValues({});
    _activeApi = api;
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        syncEventStreamProvider.overrideWith(
          (ref) => const Stream<SyncEvent>.empty(),
        ),
        syncDatabaseStartupProvider.overrideWithValue(
          DbStartupReport(
            state: DbStartupState.ready,
            keyInMemory: '00' * 32,
            usedRecoverySlot: 'primary',
            diagnostic: SecureStorageDiagnostic(),
          ),
        ),
      ],
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'readAll') {
            await beforeReadAll?.call();
            if (failReads) {
              throw PlatformException(code: 'temporary_scan_failure');
            }
            return Map<String, String>.of(store);
          }
          final key = call.arguments['key'] as String;
          if (call.method == 'read') {
            if (failReads && key == 'prism_sync.sharing_prekey_store') {
              failedSeedReads++;
              throw PlatformException(code: 'temporary_read_failure');
            }
            return store[key];
          }
          if (call.method == 'write') {
            store[key] = call.arguments['value'];
            return null;
          }
          if (call.method == 'delete') {
            store.remove(key);
            return null;
          }
          if (call.method == 'containsKey') return store.containsKey(key);
          throw UnimplementedError(call.method);
        });
    addTearDown(() async {
      dispose();
      debugDisposeOutboxDrainForTesting();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await db.close();
      PathProviderPlatform.instance = oldPaths;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(runtimeChannel, null);
      await dir.delete(recursive: true);
    });
  }

  Future<void> start({_Timers? timers}) async {
    Future<void> build() async {
      expect(
        await container.read(prismSyncHandleProvider.future),
        same(handle),
      );
    }

    if (timers == null) {
      await build();
    } else {
      await timers.run(build);
    }
    await _until(() => !syncAutoConfigureInProgress.value);
    // Allow the unrelated diagnostic snapshot to finish before intercepting
    // a later readAll or asserting retry counts.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(syncCredentialsPersisted.value, isTrue);
  }

  void dispose() {
    if (disposed) return;
    disposed = true;
    container.dispose();
  }

  void resetBarrier() =>
      container.read(syncStatusProvider.notifier).prepareForCredentialReset();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => RustLib.initMock(api: _ApiProxy()));
  tearDownAll(RustLib.dispose);

  test(
    'deferred seed automatically recovers and drains retained operations',
    () async {
      final fixture = _Fixture();
      await fixture.initialize();
      await fixture.start();
      expect(fixture.health, SyncHealthState.runtimeDekRestoreDeferred);
      expect(fixture.handle.seedCalls, 0);
      expect(fixture.handle.configured, 0);
      final writer = _Writer(fixture.handle, fixture.db);
      for (var i = 0; i < 2; i++) {
        await writer.syncRecordCreate('members', 'pending-$i', {
          'name': 'Pending',
        });
        await triggerOutboxDrain(fixture.db, fixture.handle);
      }
      expect(await fixture.db.syncOutboxDao.count(), 2);
      fixture.failReads = false;
      // Real timer, same foreground session: no manual sync/ensure/resume call.
      await Future<void>.delayed(const Duration(seconds: 4));
      expect(fixture.health, SyncHealthState.healthy);
      expect(fixture.handle.seedCalls, 1);
      expect(fixture.handle.configured, 1);
      expect(fixture.handle.enabled, 1);
      expect(await fixture.db.syncOutboxDao.count(), 0);
      expect(fixture.handle.emitted, 2);
      await writer.syncRecordCreate('members', 'after-recovery', {
        'name': 'New',
      });
      await triggerOutboxDrain(fixture.db, fixture.handle);
      expect(await fixture.db.syncOutboxDao.count(), 0);
      expect(fixture.handle.emitted, 3);
    },
  );

  test(
    'persistent seed failure backs off and caps without a busy loop',
    () async {
      final fixture = _Fixture();
      final timers = _Timers();
      await fixture.initialize();
      await fixture.start(timers: timers);
      for (final seconds in [1, 2, 4, 8, 16, 30, 30]) {
        final timer = timers.pending.single;
        expect(timer.delay, Duration(seconds: seconds));
        final oldCount = timers.all.length;
        timer.fire();
        await _until(() => timers.all.length > oldCount);
        expect(timers.pending, hasLength(1));
        expect(fixture.health, SyncHealthState.runtimeDekRestoreDeferred);
        expect(fixture.handle.seedCalls, 0);
        expect(fixture.handle.restored, 0);
        expect(fixture.handle.configured, 0);
      }
      final attempts = fixture.failedSeedReads;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(fixture.failedSeedReads, attempts);
      expect(fixture.store, contains('prism_sync.device_secret'));
    },
  );

  for (final operation in [
    'dispose',
    'reset',
    'needsPassword',
    'disconnected',
    'unpaired',
    'websocketAuthFailed',
  ]) {
    test('$operation cancels a pending seed retry', () async {
      final fixture = _Fixture();
      final timers = _Timers();
      await fixture.initialize();
      await fixture.start(timers: timers);
      final timer = timers.pending.single;
      fixture.failReads = false;
      if (operation == 'dispose') {
        fixture.dispose();
      } else if (operation == 'reset') {
        fixture.resetBarrier();
        expect(
          await fixture.notifier.ensureConfigured(fixture.handle),
          SyncHealthState.disconnected,
        );
      } else {
        fixture.container
            .read(syncHealthProvider.notifier)
            .setState(SyncHealthState.values.byName(operation));
      }
      expect(timer.isActive, isFalse);
      // Even a callback already dispatched by the event loop is fenced.
      timer.callback();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(fixture.handle.seedCalls, 0);
      expect(fixture.handle.restored, 0);
      expect(fixture.handle.configured, 0);
    });
  }

  for (final boundary in ['storage', 'seed', 'restore', 'configure']) {
    test('reset during $boundary fences the remaining initialization', () async {
      final fixture = _Fixture();
      final timers = _Timers();
      await fixture.initialize();
      await fixture.start(timers: timers);
      fixture.failReads = false;
      final entered = Completer<void>();
      final release = Completer<void>();
      Future<void> block() {
        entered.complete();
        return release.future;
      }

      switch (boundary) {
        case 'storage':
          fixture.beforeReadAll = block;
        case 'seed':
          fixture.api.onSeed = (_) => block();
        case 'restore':
          fixture.api.onRestore = (_) => block();
        case 'configure':
          fixture.api.onConfigure = (_) => block();
      }
      timers.pending.single.fire();
      await entered.future;
      fixture.resetBarrier();
      // Clear the capture gate as reset does; stale completion must not reopen it.
      syncCredentialsPersisted.value = false;
      release.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(fixture.handle.enabled, 0);
      if (boundary == 'storage') expect(fixture.handle.seedCalls, 0);
      if (boundary == 'storage' || boundary == 'seed') {
        expect(fixture.handle.restored, 0);
      }
      if (boundary != 'configure') expect(fixture.handle.configured, 0);
      expect(syncCredentialsPersisted.value, isFalse);
      expect(syncAutoConfigureInProgress.value, isFalse);
      expect(fixture.health, SyncHealthState.runtimeDekRestoreDeferred);
    });
  }

  test('manual ensure joins an automatic retry in flight', () async {
    final fixture = _Fixture();
    final timers = _Timers();
    await fixture.initialize();
    await fixture.start(timers: timers);
    fixture.failReads = false;
    final entered = Completer<void>();
    final release = Completer<void>();
    fixture.api.onSeed = (_) {
      entered.complete();
      return release.future;
    };
    timers.pending.single.fire();
    await entered.future;
    final manual = fixture.notifier.ensureConfigured(fixture.handle);
    expect(fixture.handle.seedCalls, 1);
    expect(timers.pending, isEmpty);
    release.complete();
    expect(await manual, SyncHealthState.healthy);
    expect(fixture.handle.seedCalls, 1);
    expect(fixture.handle.configured, 1);
    expect(fixture.handle.enabled, 1);
    expect(timers.pending, isEmpty);
  });

  test(
    'manual ensure joins ordinary boot configure after retry cancellation',
    () async {
      final fixture = _Fixture();
      await fixture.initialize();
      fixture.failReads = false;
      final entered = Completer<void>();
      final release = Completer<void>();
      fixture.api.onConfigure = (_) {
        entered.complete();
        return release.future;
      };
      final boot = fixture.container.read(prismSyncHandleProvider.future);
      await entered.future;
      final handle = fixture.api.handles.single;
      await fixture.container.read(syncHealthProvider.notifier).lock();
      final manual = fixture.notifier.ensureConfigured(handle);
      expect(handle.configured, 1);
      release.complete();

      expect(await boot, same(handle));
      expect(await manual, SyncHealthState.healthy);
      expect(handle.configured, 1);
    },
  );

  test('replacement fences an old seed and owns its own retry', () async {
    final fixture = _Fixture();
    final timers = _Timers();
    await fixture.initialize();
    await fixture.start(timers: timers);
    fixture.failReads = false;
    final entered = Completer<void>();
    final release = Completer<void>();
    fixture.api.onSeed = (handle) {
      if (identical(handle, fixture.handle)) {
        entered.complete();
        return release.future;
      }
      return Future<void>.value();
    };
    timers.pending.single.fire();
    await entered.future;
    fixture.failReads = true;
    final replacement =
        await timers.run(
              () => fixture.notifier.createHandle(
                relayUrl: 'https://localhost:8080',
              ),
            )
            as _Handle;
    expect(fixture.handle.disposed, isTrue);
    expect(syncCurrentHandle.value, same(replacement));
    expect(timers.pending, hasLength(1));
    release.complete();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(fixture.handle.restored, 0);
    expect(fixture.handle.configured, 0);
    expect(fixture.handle.enabled, 0);
    expect(fixture.health, SyncHealthState.runtimeDekRestoreDeferred);
    fixture.failReads = false;
    timers.pending.single.fire();
    await _until(() => !syncAutoConfigureInProgress.value);
    expect(fixture.health, SyncHealthState.healthy);
    expect(replacement.configured, 1);
    expect(replacement.enabled, 1);
  });

  test(
    'dispose during a seed prevents restore and state publication',
    () async {
      final fixture = _Fixture();
      final timers = _Timers();
      await fixture.initialize();
      await fixture.start(timers: timers);
      fixture.failReads = false;
      final entered = Completer<void>();
      final release = Completer<void>();
      fixture.api.onSeed = (_) {
        entered.complete();
        return release.future;
      };
      timers.pending.single.fire();
      await entered.future;
      fixture.dispose();
      release.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(fixture.handle.restored, 0);
      expect(fixture.handle.configured, 0);
      expect(fixture.handle.enabled, 0);
      expect(timers.pending, isEmpty);
      expect(syncCurrentHandle.value, isNull);
    },
  );

  test('hard lock fences a retry and permits later explicit unlock', () async {
    final fixture = _Fixture();
    final timers = _Timers();
    await fixture.initialize();
    await fixture.start(timers: timers);
    fixture.failReads = false;
    final entered = Completer<void>();
    final releaseSeed = Completer<void>();
    final releaseLock = Completer<void>();
    fixture.api.onSeed = (_) {
      if (!entered.isCompleted) {
        entered.complete();
        return releaseSeed.future;
      }
      return Future<void>.value();
    };
    fixture.api.onLock = (_) => releaseLock.future;
    timers.pending.single.fire();
    await entered.future;
    final lock = fixture.container
        .read(syncHealthProvider.notifier)
        .lock(hard: true);
    expect(fixture.handle.locks, 1);
    releaseSeed.complete();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(fixture.handle.restored, 0);
    expect(fixture.handle.configured, 0);
    releaseLock.complete();
    await lock;
    expect(fixture.health, SyncHealthState.needsPassword);
    expect(timers.pending, isEmpty);
    final unlocked = await fixture.container
        .read(syncHealthProvider.notifier)
        .attemptUnlock(pin: '123456', mnemonic: 'synthetic mnemonic');
    expect(
      unlocked,
      isTrue,
      reason:
          'locks=${fixture.handle.locks} seeded=${fixture.handle.seedCalls} '
          'configured=${fixture.handle.configured} enabled=${fixture.handle.enabled} '
          'unlocked=${fixture.handle.unlocked} health=${fixture.health}',
    );
    expect(
      await fixture.notifier.ensureConfigured(fixture.handle),
      SyncHealthState.healthy,
    );
    expect(fixture.handle.configured, 2);
    expect(fixture.handle.enabled, 2);
  });

  test(
    'successful reseed does not turn deferred DEK unwrap into a retry loop',
    () async {
      final fixture = _Fixture();
      final timers = _Timers();
      await fixture.initialize();
      await fixture.start(timers: timers);
      fixture.failReads = false;
      fixture.store.remove('prism_sync.runtime_dek');
      fixture.store[kRuntimeDekWrappedKey] = jsonEncode({'version': 1});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_Fixture.runtimeChannel, (call) async {
            throw PlatformException(code: 'runtime_dek_wrap_failed');
          });
      timers.pending.single.fire();
      await _until(() => !syncAutoConfigureInProgress.value);
      expect(fixture.handle.seedCalls, 1);
      expect(fixture.health, SyncHealthState.runtimeDekRestoreDeferred);
      expect(fixture.handle.configured, 0);
      expect(timers.pending, isEmpty);
    },
    // Linux uses Secret Service instead of the native wrapping channel.
    skip: Platform.isLinux,
  );
  for (final nativeCall in ['wrapRuntimeDek', 'unwrapRuntimeDek']) {
    test(
      'reset during $nativeCall preserves the replacement runtime cache',
      () async {
        final fixture = _Fixture();
        final timers = _Timers();
        await fixture.initialize();
        await fixture.start(timers: timers);
        fixture.failReads = false;
        if (nativeCall == 'unwrapRuntimeDek') {
          fixture.store[kRuntimeDekWrappedKey] = jsonEncode({'version': 1});
        }
        final entered = Completer<void>();
        final release = Completer<void>();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_Fixture.runtimeChannel, (call) async {
              expect(call.method, nativeCall);
              entered.complete();
              await release.future;
              return nativeCall == 'wrapRuntimeDek'
                  ? {'version': 1, 'blob': 'old'}
                  : Uint8List(32);
            });
        timers.pending.single.fire();
        await entered.future;
        fixture.resetBarrier();
        fixture.store[kRuntimeDekWrappedKey] = 'replacement-wrapped-cache';
        fixture.store[kRuntimeDekKey] = 'replacement-legacy-cache';
        release.complete();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(
          fixture.store[kRuntimeDekWrappedKey],
          'replacement-wrapped-cache',
        );
        expect(fixture.store[kRuntimeDekKey], 'replacement-legacy-cache');
        expect(fixture.handle.restored, 0);
        expect(fixture.handle.configured, 0);
        expect(fixture.handle.enabled, 0);
      },
      // Linux uses Secret Service instead of the native wrapping channel.
      skip: Platform.isLinux,
    );
  }
  for (final resetBeforeLock in [true, false]) {
    test(
      'lock preserves reset barrier (reset first: $resetBeforeLock)',
      () async {
        final fixture = _Fixture();
        final timers = _Timers();
        await fixture.initialize();
        await fixture.start(timers: timers);
        fixture.failReads = false;
        final releaseLock = Completer<void>();
        fixture.api.onLock = (_) => releaseLock.future;
        if (resetBeforeLock) fixture.resetBarrier();
        final lock = fixture.container
            .read(syncHealthProvider.notifier)
            .lock(hard: true);
        if (!resetBeforeLock) fixture.resetBarrier();
        releaseLock.complete();
        await lock;
        expect(
          await fixture.notifier.ensureConfigured(fixture.handle),
          SyncHealthState.disconnected,
        );
        expect(fixture.handle.seedCalls, 0);
        expect(fixture.handle.enabled, 0);
      },
    );
  }

  for (final boundary in ['resume', 'drain']) {
    test(
      'reset during catch-up $boundary cannot restore old credentials',
      () async {
        final fixture = _Fixture();
        final timers = _Timers();
        await fixture.initialize();
        await fixture.start(timers: timers);
        fixture.failReads = false;
        final entered = Completer<void>();
        final release = Completer<void>();
        Future<void> block(_Handle handle) {
          entered.complete();
          return release.future;
        }

        if (boundary == 'resume') {
          fixture.api.onResume = block;
        } else {
          fixture.api.onDrain = block;
        }
        timers.pending.single.fire();
        await _until(() => entered.isCompleted);
        expect(fixture.handle.configured, 1);
        expect(fixture.handle.enabled, 1);
        fixture.resetBarrier();
        fixture.store['prism_sync.device_secret'] = 'replacement-secret';
        release.complete();
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(fixture.store['prism_sync.device_secret'], 'replacement-secret');
        expect(fixture.handle.drains, boundary == 'resume' ? 0 : 1);
        expect(syncAutoConfigureInProgress.value, isFalse);
      },
    );
  }
  test(
    'reset during manually started retry catch-up clears startup ownership',
    () async {
      final fixture = _Fixture();
      final timers = _Timers();
      await fixture.initialize();
      await fixture.start(timers: timers);
      fixture.failReads = false;
      final entered = Completer<void>();
      final release = Completer<void>();
      fixture.api.onResume = (_) {
        entered.complete();
        return release.future;
      };

      final recovery = fixture.notifier.ensureConfigured(fixture.handle);
      await entered.future;
      expect(syncAutoConfigureInProgress.value, isTrue);
      fixture.resetBarrier();
      release.complete();

      expect(await recovery, SyncHealthState.healthy);
      await _until(() => !syncAutoConfigureInProgress.value);
      expect(syncAutoConfigureInProgress.value, isFalse);
      expect(fixture.handle.drains, 0);
      expect(timers.pending, isEmpty);
    },
  );
  test(
    'a cancelled old callback cannot disown the replacement timer',
    () async {
      final fixture = _Fixture();
      final timers = _Timers();
      await fixture.initialize();
      await fixture.start(timers: timers);
      final oldTimer = timers.pending.single;
      final replacement = await timers.run(
        () => fixture.notifier.createHandle(relayUrl: 'https://localhost:8080'),
      );
      final replacementTimer = timers.pending.single;
      expect(oldTimer.isActive, isFalse);
      oldTimer.callback();
      await timers.run(() => fixture.notifier.ensureConfigured(replacement));
      expect(replacementTimer.isActive, isFalse);
      expect(timers.pending, hasLength(1));
      expect(fixture.handle.configured, 0);
    },
  );
}
