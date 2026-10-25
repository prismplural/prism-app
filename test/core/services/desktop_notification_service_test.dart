import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/core/router/notification_navigation_providers.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/services/local_notification_service.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class _Plugin implements FlutterLocalNotificationsPlugin {
  final calls = <Invocation>[];
  Completer<bool?>? initialization;
  NotificationAppLaunchDetails? launch;

  Iterable<Invocation> named(String name) =>
      calls.where((call) => call.memberName == Symbol(name));

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation);
    return switch (invocation.memberName) {
      #initialize => initialization?.future ?? Future<bool?>.value(true),
      #resolvePlatformSpecificImplementation => null,
      #getNotificationAppLaunchDetails =>
        Future<NotificationAppLaunchDetails?>.value(launch),
      #pendingNotificationRequests => Future.value(
        <PendingNotificationRequest>[],
      ),
      _ => Future<void>.value(),
    };
  }
}

class _ForbiddenBootstrapHandle extends PrismSyncHandleNotifier {
  _ForbiddenBootstrapHandle(this.forbidden);
  final Never Function() forbidden;
  @override
  Future<ffi.PrismSyncHandle?> build() async => forbidden();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const details = NotificationDetails();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (_) => throw PlatformException(code: 'unavailable'),
        );
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.UTC);
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          null,
        );
  });

  test(
    'production bootstrap initializes once with no protected reads or permissions',
    () async {
      final plugin = _Plugin()
        ..launch = const NotificationAppLaunchDetails(
          true,
          notificationResponse: NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            payload: 'prism:reminder:scheduled:synthetic-id',
          ),
        );
      final service = LocalNotificationService(plugin: plugin);
      var protectedReads = 0;
      Never forbidden() {
        protectedReads++;
        throw StateError(
          'Protected provider resolved during notification bootstrap',
        );
      }

      final container = ProviderContainer(
        overrides: [
          localNotificationServiceProvider.overrideWithValue(service),
          databaseProvider.overrideWith((ref) => forbidden()),
          databaseReadyProvider.overrideWith((ref) => forbidden()),
          prismSyncHandleProvider.overrideWith(
            () => _ForbiddenBootstrapHandle(forbidden),
          ),
          remindersRepositoryProvider.overrideWith((ref) => forbidden()),
          syncIdProvider.overrideWith((ref) => forbidden()),
          syncDeviceIdProvider.overrideWith((ref) => forbidden()),
          syncDeviceSecretPresentProvider.overrideWith((ref) => forbidden()),
          syncWrappedDekPresentProvider.overrideWith((ref) => forbidden()),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(service.dispose);
      await container.read(notificationTapBootstrapProvider.future);
      await container.read(notificationTapBootstrapProvider.future);
      expect(plugin.named('initialize'), hasLength(1));
      expect(plugin.named('getNotificationAppLaunchDetails'), hasLength(1));
      expect(await service.getLaunchPayload(), isNull);
      expect(plugin.named('getNotificationAppLaunchDetails'), hasLength(1));
      expect(protectedReads, 0);
      expect(
        container
            .read(notificationNavigationProvider.notifier)
            .pending
            ?.reminderId,
        'synthetic-id',
      );
      final initialization =
          plugin.named('initialize').single.namedArguments[#settings]
              as InitializationSettings;
      for (final darwin in [initialization.iOS!, initialization.macOS!]) {
        expect(darwin.requestAlertPermission, isFalse);
        expect(darwin.requestSoundPermission, isFalse);
        expect(darwin.requestBadgePermission, isFalse);
        expect(darwin.requestProvisionalPermission, isFalse);
        expect(darwin.requestCriticalPermission, isFalse);
        expect(darwin.requestProvidesAppNotificationSettings, isFalse);
      }
      expect(
        plugin.calls.where(
          (call) => call.memberName.toString().contains('requestPermission'),
        ),
        isEmpty,
      );
    },
  );

  test('immediate and native repeats forward bounded typed payloads', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final plugin = _Plugin();
    final service = LocalNotificationService(plugin: plugin);
    addTearDown(service.dispose);
    await service.showImmediate(
      id: 1,
      title: 'Synthetic',
      body: 'Synthetic',
      details: details,
      payload: 'prism:reminder:immediate:id',
    );
    await service.scheduleRepeating(
      id: 2,
      title: 'Synthetic',
      body: 'Synthetic',
      interval: RepeatInterval.hourly,
      details: details,
      payload: 'prism:fronting:v1',
    );
    await service.scheduleRepeatingWithDuration(
      id: 3,
      title: 'Synthetic',
      body: 'Synthetic',
      interval: const Duration(minutes: 15),
      details: details,
      payload: 'prism:fronting:v1',
    );
    expect(
      plugin.named('show').single.namedArguments[#payload],
      'prism:reminder:immediate:id',
    );
    expect(
      plugin.named('periodicallyShow').single.namedArguments[#payload],
      'prism:fronting:v1',
    );
    expect(
      plugin
          .named('periodicallyShowWithDuration')
          .single
          .namedArguments[#payload],
      'prism:fronting:v1',
    );
  });

  test('notification tap forwards payload without scheduling', () async {
    final plugin = _Plugin();
    final received = <String?>[];
    final service = LocalNotificationService(
      plugin: plugin,
      onNotificationTap: received.add,
    );
    addTearDown(service.dispose);
    await service.initialize();
    final callback =
        plugin
                .named('initialize')
                .single
                .namedArguments[#onDidReceiveNotificationResponse]
            as void Function(NotificationResponse);

    callback(
      const NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        payload: 'prism:reminder:scheduled:synthetic-id',
      ),
    );

    expect(received, ['prism:reminder:scheduled:synthetic-id']);
    expect(plugin.named('show'), isEmpty);
    expect(plugin.named('zonedSchedule'), isEmpty);
  });

  for (final platform in [TargetPlatform.linux, TargetPlatform.windows]) {
    group(platform.name, () {
      setUp(() => debugDefaultTargetPlatformOverride = platform);

      test(
        'initializes once and supplies platform settings and permission availability',
        () async {
          final plugin = _Plugin();
          final service = LocalNotificationService(plugin: plugin);
          await Future.wait([service.initialize(), service.initialize()]);
          await service.initialize();
          expect(plugin.named('initialize'), hasLength(1));
          final settings =
              plugin.named('initialize').single.namedArguments[#settings]
                  as InitializationSettings;
          expect(settings.linux, isNotNull);
          expect(settings.windows?.appUserModelId, 'PrismPlural.Prism');
          expect(await service.requestPermission(), isTrue);
          expect(await service.isPermissionGranted(), isTrue);
        },
      );

      test('repeat delivers correct details and stops on cancellation', () {
        fakeAsync((async) {
          final plugin = _Plugin();
          final service = LocalNotificationService(
            plugin: plugin,
            now: async.getClock(DateTime.utc(2026, 10, 3)).now,
          );
          unawaited(
            service.scheduleRepeatingWithDuration(
              id: 1,
              title: 'Reminder',
              body: 'Body',
              interval: const Duration(minutes: 15),
              details: details,
              payload: 'prism:fronting:v1',
            ),
          );
          async.flushMicrotasks();
          expect(plugin.named('periodicallyShowWithDuration'), isEmpty);
          async.elapse(const Duration(minutes: 14));
          expect(plugin.named('show'), isEmpty);
          async.elapse(const Duration(minutes: 1));
          expect(plugin.named('show'), hasLength(1));
          expect(
            plugin.named('show').single.namedArguments[#payload],
            'prism:fronting:v1',
          );
          final sentDetails =
              plugin.named('show').single.namedArguments[#notificationDetails]
                  as NotificationDetails;
          expect(sentDetails.linux, isNotNull);
          expect(sentDetails.windows, isNotNull);
          unawaited(service.cancel(1));
          async.flushMicrotasks();
          async.elapse(const Duration(hours: 1));
          expect(plugin.named('show'), hasLength(1));
          service.dispose();
        });
      });

      test('disable during initialization cannot recreate a timer', () {
        fakeAsync((async) {
          final plugin = _Plugin()..initialization = Completer<bool?>();
          final service = LocalNotificationService(
            plugin: plugin,
            now: async.getClock(DateTime.utc(2026, 10, 3)).now,
          );
          unawaited(
            service.scheduleRepeatingWithDuration(
              id: 1,
              title: 'Reminder',
              body: 'Body',
              interval: const Duration(minutes: 15),
              details: details,
            ),
          );
          unawaited(service.cancel(1));
          plugin.initialization!.complete(true);
          async.flushMicrotasks();
          async.elapse(const Duration(hours: 2));
          expect(plugin.named('show'), isEmpty);
          expect(async.pendingTimers, isEmpty);
          service.dispose();
        });
      });

      test('rescheduling replaces the timer and disposal stops delivery', () {
        fakeAsync((async) {
          final plugin = _Plugin();
          final service = LocalNotificationService(
            plugin: plugin,
            now: async.getClock(DateTime.utc(2026, 10, 3)).now,
          );
          unawaited(
            service.scheduleRepeatingWithDuration(
              id: 1,
              title: 'Old',
              body: 'Body',
              interval: const Duration(minutes: 1),
              details: details,
            ),
          );
          unawaited(
            service.scheduleRepeatingWithDuration(
              id: 1,
              title: 'New',
              body: 'Body',
              interval: const Duration(minutes: 2),
              details: details,
            ),
          );
          async.flushMicrotasks();
          async.elapse(const Duration(minutes: 2));
          expect(plugin.named('show'), hasLength(1));
          expect(plugin.named('show').single.namedArguments[#title], 'New');
          service.dispose();
          unawaited(service.initialize());
          async.elapse(const Duration(hours: 2));
          expect(plugin.named('show'), hasLength(1));
          expect(async.pendingTimers, isEmpty);
        });
      });

      test(
        'resume skips missed repeat intervals instead of replaying them',
        () {
          fakeAsync((async) {
            final plugin = _Plugin();
            var now = DateTime.utc(2026, 10, 3);
            final service = LocalNotificationService(
              plugin: plugin,
              now: () => now,
            );
            unawaited(
              service.scheduleRepeatingWithDuration(
                id: 1,
                title: 'Reminder',
                body: 'Body',
                interval: const Duration(minutes: 15),
                details: details,
              ),
            );
            async.flushMicrotasks();
            now = now.add(const Duration(hours: 8));
            service.refreshDesktopSchedules();
            async.elapse(Duration.zero);
            expect(plugin.named('show'), hasLength(1));
            async.elapse(const Duration(minutes: 14));
            expect(plugin.named('show'), hasLength(1));
            now = now.add(const Duration(minutes: 15));
            async.elapse(const Duration(minutes: 1));
            expect(plugin.named('show'), hasLength(2));
            service.dispose();
          });
        },
      );

      test(
        'daily wall-clock repeat survives fall-back without a same-day loop',
        () {
          fakeAsync((async) {
            tz.setLocalLocation(tz.getLocation('America/New_York'));
            final plugin = _Plugin();
            final start = tz.TZDateTime(tz.local, 2026, 11, 1, 9);
            final service = LocalNotificationService(
              plugin: plugin,
              now: async.getClock(start).now,
            );
            unawaited(
              service.scheduleExactDaily(
                id: 1,
                title: 'Reminder',
                body: 'Body',
                time: const TimeOfDay(hour: 9, minute: 1),
                details: details,
                payload: 'route',
              ),
            );
            async.flushMicrotasks();
            async.elapse(const Duration(minutes: 1));
            expect(plugin.named('show'), hasLength(1));
            expect(
              plugin.named('show').single.namedArguments[#payload],
              'route',
            );
            async.elapse(const Duration(days: 1));
            expect(plugin.named('show'), hasLength(2));
            service.dispose();
          });
        },
      );
    });
  }

  test(
    'Linux one-shots expose pending payloads and cancel the whole range',
    () {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      fakeAsync((async) {
        final plugin = _Plugin();
        final service = LocalNotificationService(
          plugin: plugin,
          now: async.getClock(DateTime.utc(2026, 10, 3, 9)).now,
        );
        unawaited(
          service.scheduleExactInterval(
            idBase: 100,
            title: 'Habit',
            body: 'Body',
            time: const TimeOfDay(hour: 10, minute: 0),
            intervalDays: 1,
            maxOccurrences: 7,
            details: details,
            payload: 'habit',
          ),
        );
        async.flushMicrotasks();
        List<PendingNotificationRequest>? pending;
        unawaited(
          service.pendingNotificationRequests().then(
            (value) => pending = value,
          ),
        );
        async.flushMicrotasks();
        expect(pending, hasLength(7));
        expect(pending!.first.payload, 'habit');
        expect(plugin.named('pendingNotificationRequests'), isEmpty);
        expect(plugin.named('zonedSchedule'), isEmpty);
        unawaited(service.cancelRange(100, 7));
        async.flushMicrotasks();
        async.elapse(const Duration(days: 8));
        expect(plugin.named('show'), isEmpty);
        service.dispose();
      });
    },
  );

  test(
    'Windows one-shots stay native and cancellation initializes first',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final plugin = _Plugin();
      final service = LocalNotificationService(plugin: plugin);
      await service.cancel(42);
      expect(plugin.calls.first.memberName, #initialize);
      await service.scheduleOneShot(
        id: 42,
        title: 'Reminder',
        body: 'Body',
        scheduledFor: DateTime.now().add(const Duration(hours: 1)),
        details: details,
        payload: 'route',
      );
      expect(plugin.named('zonedSchedule'), hasLength(1));
      expect(
        plugin.named('zonedSchedule').single.namedArguments[#payload],
        'route',
      );
      expect(plugin.named('show'), isEmpty);
      service.dispose();
    },
  );
  test(
    'Linux resume delivers one catch-up per series without a backlog burst',
    () {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      fakeAsync((async) {
        final plugin = _Plugin();
        var now = DateTime.utc(2026, 10, 3, 9);
        final service = LocalNotificationService(
          plugin: plugin,
          now: () => now,
        );
        unawaited(
          service.scheduleExactInterval(
            idBase: 100,
            title: 'Habit',
            body: 'Body',
            time: const TimeOfDay(hour: 10, minute: 0),
            intervalDays: 1,
            maxOccurrences: 7,
            details: details,
          ),
        );
        async.flushMicrotasks();
        now = DateTime.utc(2026, 10, 6, 12);
        service.refreshDesktopSchedules();
        async.elapse(Duration.zero);
        expect(plugin.named('show'), hasLength(1));
        now = DateTime.utc(2026, 10, 7, 10);
        service.refreshDesktopSchedules();
        async.elapse(Duration.zero);
        expect(plugin.named('show'), hasLength(2));
        service.dispose();
      });
    },
  );

  test(
    'native interval dates advance once per calendar day across fall-back',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      tz.setLocalLocation(tz.getLocation('America/New_York'));
      final plugin = _Plugin();
      final service = LocalNotificationService(
        plugin: plugin,
        now: () => tz.TZDateTime(tz.local, 2026, 11, 1),
      );
      await service.scheduleExactInterval(
        idBase: 100,
        title: 'Habit',
        body: 'Body',
        time: const TimeOfDay(hour: 0, minute: 30),
        intervalDays: 1,
        maxOccurrences: 3,
        details: details,
      );
      final dates = plugin
          .named('zonedSchedule')
          .map((call) => call.namedArguments[#scheduledDate] as tz.TZDateTime)
          .toList();
      expect(dates.map((date) => date.day), [1, 2, 3]);
      expect(dates.map((date) => date.hour), [0, 0, 0]);
      expect(dates[1].difference(dates[0]), const Duration(hours: 25));
      service.dispose();
    },
  );
  test(
    'an older cancel cannot remove a newer schedule after deferred init',
    () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      fakeAsync((async) {
        final plugin = _Plugin()..initialization = Completer<bool?>();
        final service = LocalNotificationService(plugin: plugin);
        final cancellation = service.cancel(42);
        final scheduling = service.scheduleOneShot(
          id: 42,
          title: 'New',
          body: 'Body',
          scheduledFor: DateTime.now().add(const Duration(hours: 1)),
          details: details,
        );
        unawaited(Future.wait([cancellation, scheduling]));
        plugin.initialization!.complete(true);
        async.flushMicrotasks();
        expect(plugin.named('zonedSchedule'), hasLength(1));
        expect(plugin.named('cancel'), isEmpty);
        service.dispose();
      });
    },
  );
}
