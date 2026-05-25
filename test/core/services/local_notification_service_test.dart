import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/services/local_notification_service.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('permission checks', () {
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return switch (call.method) {
              'initialize' => true,
              'checkPermissions' => <String, Object>{
                'isEnabled': true,
                'isSoundEnabled': true,
                'isAlertEnabled': true,
                'isBadgeEnabled': true,
                'isProvisionalEnabled': false,
                'isCriticalEnabled': false,
                'isProvidesAppNotificationSettingsEnabled': false,
                'isCarPlayEnabled': false,
              },
              _ => null,
            };
          });
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test(
      'iOS uses checkPermissions for status instead of requestPermissions',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        IOSFlutterLocalNotificationsPlugin.registerWith();

        final granted = await LocalNotificationService().isPermissionGranted();

        expect(granted, isTrue);
        expect(calls.map((c) => c.method), contains('checkPermissions'));
        expect(
          calls.map((c) => c.method),
          isNot(contains('requestPermissions')),
        );
      },
    );

    test(
      'macOS uses checkPermissions for status instead of requestPermissions',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        MacOSFlutterLocalNotificationsPlugin.registerWith();

        final granted = await LocalNotificationService().isPermissionGranted();

        expect(granted, isTrue);
        expect(calls.map((c) => c.method), contains('checkPermissions'));
        expect(
          calls.map((c) => c.method),
          isNot(contains('requestPermissions')),
        );
      },
    );
  });

  // ── nextWeekdayOccurrenceFrom ──────────────────────────────────────
  //
  // Regression: the picker emits 0=Sunday..6=Saturday but Dart's
  // DateTime.weekday is 1=Monday..7=Sunday. The pre-fix walk used a
  // synchronous `while (candidate.weekday != weekday)` loop, which never
  // terminated for `weekday == 0` and froze the UI isolate. These tests
  // pin the picker→Dart conversion and confirm the loop is bounded.

  group('nextWeekdayOccurrenceFrom', () {
    setUpAll(tzdata.initializeTimeZones);

    // Anchor on a known weekday so each case has a deterministic expected
    // jump. 2026-04-20 is a Monday in UTC.
    final monday = tz.TZDateTime.utc(2026, 4, 20, 9);

    test('weekday=0 (picker Sunday) lands on Dart Sunday=7 within 7 days', () {
      final result = nextWeekdayOccurrenceFrom(monday, 0);
      expect(result.weekday, DateTime.sunday);
      // Mon → next Sun is 6 days away.
      expect(result.difference(monday).inDays, 6);
    });

    test('weekday=1..6 already match Dart weekdays', () {
      for (var w = 1; w <= 6; w++) {
        final result = nextWeekdayOccurrenceFrom(monday, w);
        expect(result.weekday, w, reason: 'weekday=$w');
      }
    });

    test('weekday=1 on a Monday returns the same day', () {
      final result = nextWeekdayOccurrenceFrom(monday, 1);
      expect(result, monday);
    });

    test('out-of-range weekday cannot lock the loop', () {
      // 99 will never match candidate.weekday (1..7). Pre-fix this hung.
      // Post-fix the bounded loop returns after ≤ 7 day-adds; the result
      // weekday is undefined for bad input — only the bound matters.
      final result = nextWeekdayOccurrenceFrom(monday, 99);
      expect(result.difference(monday).inDays, lessThanOrEqualTo(7));
    });

    test('weekday=0 returns within 100 ms (no infinite loop)', () {
      final sw = Stopwatch()..start();
      nextWeekdayOccurrenceFrom(monday, 0);
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(100));
    });
  });

  // ── Occurrence count formula ───────────────────────────────────────

  group('scheduleExactInterval occurrence count', () {
    // Formula: n = ceil(30 / intervalDays).clamp(2, maxIntervalOccurrences)

    int occurrences(int intervalDays) => (30 / intervalDays).ceil().clamp(
      2,
      LocalNotificationService.maxIntervalOccurrences,
    );

    test('intervalDays=1 → 30 occurrences', () {
      // ceil(30/1) = 30, clamp(2,30) = 30
      expect(occurrences(1), 30);
    });

    test('intervalDays=2 → 15 occurrences', () {
      // ceil(30/2) = 15, clamp(2,30) = 15
      expect(occurrences(2), 15);
    });

    test('intervalDays=3 → 10 occurrences', () {
      // ceil(30/3) = 10, clamp(2,30) = 10
      expect(occurrences(3), 10);
    });

    test('intervalDays=7 → 5 occurrences', () {
      // ceil(30/7) = 5, clamp(2,30) = 5
      expect(occurrences(7), 5);
    });

    test('intervalDays=14 → 3 occurrences', () {
      // ceil(30/14) = 3, clamp(2,30) = 3
      expect(occurrences(14), 3);
    });

    test('intervalDays=30 → 2 occurrences', () {
      // ceil(30/30) = 1, clamp(2,30) = 2 (minimum guaranteed)
      expect(occurrences(30), 2);
    });

    test('intervalDays=90 → 2 occurrences (minimum clamp)', () {
      // ceil(30/90) = 1, clamp(2,30) = 2
      expect(occurrences(90), 2);
    });

    test('any interval produces at least 2 occurrences', () {
      for (final d in [1, 2, 3, 7, 14, 30, 60, 365]) {
        expect(occurrences(d), greaterThanOrEqualTo(2));
      }
    });

    test('no interval exceeds maxIntervalOccurrences', () {
      for (final d in [1, 2, 3, 7, 14]) {
        expect(
          occurrences(d),
          lessThanOrEqualTo(LocalNotificationService.maxIntervalOccurrences),
        );
      }
    });
  });

  // ── maxIntervalOccurrences constant ──────────────────────────────────

  test('maxIntervalOccurrences is 30', () {
    expect(LocalNotificationService.maxIntervalOccurrences, 30);
  });

  // ── Plugin-channel contract regression ──────────────────────────────
  //
  // iOS bug we worked around: when matchDateTimeComponents == "Time" or
  // "DayOfWeekAndTime", the iOS FLN plugin extracts ONLY the clock-time
  // components from scheduledDate and discards the year/month/day. The
  // resulting UNCalendarNotificationTrigger fires at the next matching
  // time-of-day, which can be later today — defeating notBefore for the
  // skip-current-period case after a habit completion. Plugin source:
  // `~/.pub-cache/.../flutter_local_notifications-21.0.0/ios/.../
  // FlutterLocalNotificationsPlugin.m`, `buildUserNotificationCalendarTrigger`.
  //
  // Daily and weekly habits now route through scheduleExactInterval and
  // scheduleExactWeeklyOneShots respectively, which schedule each
  // occurrence as a one-shot. These tests lock in the contract: each
  // zonedSchedule call must include the full scheduledDate and must NOT
  // set matchDateTimeComponents — otherwise the iOS bug reappears.

  group('plugin-channel contract for one-shot scheduling', () {
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final calls = <MethodCall>[];

    setUpAll(() {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('UTC'));
      // Register iOS impl so the plugin's zonedSchedule has a platform.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      IOSFlutterLocalNotificationsPlugin.registerWith();
    });

    tearDownAll(() {
      debugDefaultTargetPlatformOverride = null;
    });

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            // Return a sensible default; most methods on the FLN channel
            // return null or true. We don't care about the response.
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test(
      'scheduleExactInterval emits zonedSchedule with full date, no matchDateTimeComponents',
      () async {
        await LocalNotificationService().scheduleExactInterval(
          idBase: 1,
          title: 't',
          body: 'b',
          time: const TimeOfDay(hour: 9, minute: 0),
          intervalDays: 1,
          maxOccurrences: 3,
          details: const NotificationDetails(),
        );

        final zonedScheduleCalls = calls
            .where((c) => c.method == 'zonedSchedule')
            .toList();
        // 3 one-shots scheduled.
        expect(zonedScheduleCalls, hasLength(3));
        for (final call in zonedScheduleCalls) {
          final args = call.arguments as Map<Object?, Object?>;
          // No matchDateTimeComponents → iOS keeps the full date in the
          // calendar trigger. This is the heart of the iOS fix.
          expect(
            args['matchDateTimeComponents'],
            isNull,
            reason:
                'scheduleExactInterval must use one-shot semantics; setting '
                'matchDateTimeComponents would re-introduce the iOS bug where '
                'the date portion of scheduledDate is silently dropped.',
          );
          // scheduledDateTime is an ISO8601 string with the full Y-M-D-h-m.
          expect(args['scheduledDateTime'], isA<String>());
          final scheduledIso = args['scheduledDateTime']! as String;
          expect(
            scheduledIso,
            matches(RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}')),
            reason: 'scheduledDateTime must include the date portion',
          );
        }
      },
    );

    test(
      'scheduleExactWeeklyOneShots emits zonedSchedule with full date, no matchDateTimeComponents',
      () async {
        await LocalNotificationService().scheduleExactWeeklyOneShots(
          idBase: 1,
          title: 't',
          body: 'b',
          time: const TimeOfDay(hour: 9, minute: 0),
          weekday: 3, // Wednesday
          occurrences: 2,
          details: const NotificationDetails(),
        );

        final zonedScheduleCalls = calls
            .where((c) => c.method == 'zonedSchedule')
            .toList();
        expect(zonedScheduleCalls, hasLength(2));
        for (final call in zonedScheduleCalls) {
          final args = call.arguments as Map<Object?, Object?>;
          expect(
            args['matchDateTimeComponents'],
            isNull,
            reason:
                'scheduleExactWeeklyOneShots must use one-shot semantics; '
                'using matchDateTimeComponents.dayOfWeekAndTime would let '
                'iOS drop the date and fire today regardless of notBefore.',
          );
        }
      },
    );
  });

  // ── DST regression ─────────────────────────────────────────────────
  //
  // Plain `next.add(Duration(days: 1))` adds 86400 seconds, not a
  // calendar day. Across a DST transition the wall-clock hour shifts:
  // a 9am reminder lands at 8am (fall-back) or 10am (spring-forward).
  // The fix re-anchors the time component each iteration. America/New_York
  // is a stable DST locale; the 2026-03-08 spring-forward and 2026-11-01
  // fall-back are predictable test fixtures.

  group('DST stability of one-shot iteration', () {
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final calls = <MethodCall>[];

    setUpAll(() {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('America/New_York'));
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      IOSFlutterLocalNotificationsPlugin.registerWith();
    });

    tearDownAll(() {
      debugDefaultTargetPlatformOverride = null;
      tz.setLocalLocation(tz.UTC);
    });

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test(
      'daily reminder stays at the configured wall-clock time across DST',
      () async {
        // Schedule across the 2026-03-08 spring-forward in America/New_York
        // (clocks jump 2:00 → 3:00 EST → EDT). 9am reminders before and
        // after the transition must both be 9am local time.
        await LocalNotificationService().scheduleExactInterval(
          idBase: 100,
          title: 't',
          body: 'b',
          time: const TimeOfDay(hour: 9, minute: 0),
          intervalDays: 1,
          maxOccurrences: 5,
          details: const NotificationDetails(),
          notBefore: DateTime(2026, 3, 7),
        );

        final scheduled = calls
            .where((c) => c.method == 'zonedSchedule')
            .map(
              (c) =>
                  (c.arguments as Map<Object?, Object?>)['scheduledDateTime']!
                      as String,
            )
            .toList();
        expect(scheduled, hasLength(5));
        for (final iso in scheduled) {
          // ISO format like "2026-03-08T09:00:00.000-0500". Pull out the
          // wall-clock hour; it must always be 09 regardless of date.
          final match = RegExp(r'T(\d{2}):(\d{2})').firstMatch(iso);
          expect(match, isNotNull, reason: 'malformed ISO: $iso');
          expect(
            match!.group(1),
            '09',
            reason: 'wall-clock hour drifted across DST: $iso',
          );
          expect(match.group(2), '00');
        }
      },
    );
  });
}
