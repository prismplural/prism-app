import 'dart:async';

import 'package:flutter/foundation.dart'
    show
        kIsWeb,
        visibleForTesting,
        defaultTargetPlatform,
        TargetPlatform,
        debugPrint;
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;

/// Unified owner of [FlutterLocalNotificationsPlugin].
///
/// All notification scheduling in the app goes through this service.
/// Web is guarded with [kIsWeb] throughout — flutter_local_notifications
/// has no web implementation.
class LocalNotificationService {
  LocalNotificationService({
    FlutterLocalNotificationsPlugin? plugin,
    DateTime Function()? now,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _now = now ?? DateTime.now;

  final FlutterLocalNotificationsPlugin _plugin;
  final DateTime Function() _now;
  bool _initialized = false;
  bool _disposed = false;
  Future<void>? _initializing;
  final _generations = <int, int>{};
  final _desktopSchedules = <int, _DesktopNotification>{};

  bool get _usesTimers => defaultTargetPlatform == TargetPlatform.linux;
  bool get _usesRepeatTimers =>
      _usesTimers || defaultTargetPlatform == TargetPlatform.windows;

  /// Maximum number of pre-scheduled occurrences for interval-based
  /// notifications. Guarantees at least 30 days coverage for any interval.
  static const int maxIntervalOccurrences = 30;

  Future<void> initialize() async {
    if (kIsWeb || _initialized || _disposed) return;
    final pending = _initializing;
    if (pending != null) return pending;
    final initializing = _initializePlugin();
    _initializing = initializing;
    try {
      await initializing;
    } finally {
      _initializing = null;
    }
  }

  Future<void> _initializePlugin() async {
    // Keep this a flat, alpha-only drawable: an adaptive launcher icon as the
    // small icon crash-loops System UI on Android 8.0.
    const androidSettings = AndroidInitializationSettings(
      '@drawable/ic_stat_prism',
    );
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
        linux: LinuxInitializationSettings(defaultActionName: 'Open Prism'),
        windows: WindowsInitializationSettings(
          appName: 'Prism',
          appUserModelId: 'PrismPlural.Prism',
          guid: 'fbd55210-f31c-4cef-b398-c5745ef77cc2',
        ),
      ),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );
    // Defensive timezone refresh — main() sets this at startup, but
    // guard against cases where initialize() is called in isolation.
    try {
      if (!kIsWeb) {
        final localTz = (await FlutterTimezone.getLocalTimezone()).identifier;
        tz.setLocalLocation(tz.getLocation(localTz));
      }
    } catch (_) {}
    if (!_disposed) _initialized = true;
  }

  void _onNotificationTap(NotificationResponse details) {
    // No-op — wire deep-link navigation here when tap routing is added.
  }

  // ── Exact-time scheduling ─────────────────────────────────────────

  /// Schedules a repeating daily notification at [time].
  ///
  /// Uses [DateTimeComponents.time] so the OS fires it every day at
  /// that clock time without requiring the app to reschedule.
  ///
  /// [notBefore] floors the first occurrence — pass tomorrow's date to skip
  /// today's fire (matchDateTimeComponents continues the daily repeat after).
  Future<void> scheduleExactDaily({
    required int id,
    required String title,
    required String body,
    required TimeOfDay time,
    required NotificationDetails details,
    DateTime? notBefore,
    String? payload,
  }) async {
    if (kIsWeb) return;
    final generation = _replace(id);
    await _ensureInitialized();
    if (!_isCurrent(id, generation)) return;
    final scheduled = _nextOccurrence(time, notBefore: notBefore);
    if (_usesRepeatTimers) {
      _scheduleDesktop(
        id,
        generation,
        title,
        body,
        scheduled,
        details,
        payload: payload,
        next: (now) => _nextCalendarOccurrence(now, time, 1, scheduled.weekday),
      );
      return;
    }
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduled,
      notificationDetails: _desktopDetails(details),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: payload,
    );
  }

  /// Schedules a repeating weekly notification on [weekday] at [time].
  ///
  /// [weekday] uses [DateTime] weekday constants (Monday=1, Sunday=7).
  /// Uses [DateTimeComponents.dayOfWeekAndTime] for OS-managed repeating.
  ///
  /// [notBefore] floors the first occurrence — pass tomorrow's date to skip
  /// this week's fire when the user just completed today's instance.
  Future<void> scheduleExactWeekly({
    required int id,
    required String title,
    required String body,
    required TimeOfDay time,
    required int weekday,
    required NotificationDetails details,
    DateTime? notBefore,
    String? payload,
  }) async {
    if (kIsWeb) return;
    final generation = _replace(id);
    await _ensureInitialized();
    if (!_isCurrent(id, generation)) return;
    final scheduled = _nextWeekdayOccurrence(
      time,
      weekday,
      notBefore: notBefore,
    );
    if (_usesRepeatTimers) {
      _scheduleDesktop(
        id,
        generation,
        title,
        body,
        scheduled,
        details,
        payload: payload,
        next: (now) => _nextCalendarOccurrence(now, time, 7, scheduled.weekday),
      );
      return;
    }
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduled,
      notificationDetails: _desktopDetails(details),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      payload: payload,
    );
  }

  /// Schedules N one-shot notifications spaced [intervalDays] apart.
  ///
  /// N = ceil(30 / intervalDays).clamp(2, [maxIntervalOccurrences]).
  ///
  /// Prefer this over [scheduleExactDaily] / [scheduleExactWeekly] when
  /// [notBefore] matters: the matchDateTimeComponents path on iOS/macOS
  /// extracts only the clock-time from `scheduledDate` and ignores the
  /// date, firing at the next matching time-of-day regardless.
  ///
  /// Callers must cancel stale IDs with [cancelRange] before calling.
  Future<void> scheduleExactInterval({
    required int idBase,
    required String title,
    required String body,
    required TimeOfDay time,
    required int intervalDays,
    required NotificationDetails details,
    int? maxOccurrences,
    DateTime? notBefore,
    String? payload,
  }) async {
    if (kIsWeb) return;
    final n =
        maxOccurrences ??
        (30 / intervalDays).ceil().clamp(2, maxIntervalOccurrences);
    final generations = List.generate(n, (i) => _replace(idBase + i));
    await _ensureInitialized();
    var next = _nextOccurrence(time, notBefore: notBefore);
    for (var i = 0; i < n; i++) {
      await _scheduleOneShot(
        idBase + i,
        generations[i],
        title,
        body,
        next,
        details,
        payload,
        seriesId: idBase,
      );
      next = _advanceWallClockDays(next, intervalDays, time);
    }
  }

  /// Schedules [occurrences] one-shot notifications for [weekday], 7 days apart.
  ///
  /// The iOS/macOS-safe alternative to [scheduleExactWeekly] when [notBefore]
  /// matters — see [scheduleExactInterval] for the underlying platform quirk.
  ///
  /// [weekday] follows the app convention (0=Sun..6=Sat). Out-of-range
  /// values are not validated — callers should filter.
  ///
  /// Callers must cancel stale IDs with [cancelRange] before calling.
  Future<void> scheduleExactWeeklyOneShots({
    required int idBase,
    required String title,
    required String body,
    required TimeOfDay time,
    required int weekday,
    required NotificationDetails details,
    required int occurrences,
    DateTime? notBefore,
    String? payload,
  }) async {
    if (kIsWeb) return;
    final generations = List.generate(occurrences, (i) => _replace(idBase + i));
    await _ensureInitialized();
    var next = _nextWeekdayOccurrence(time, weekday, notBefore: notBefore);
    for (var i = 0; i < occurrences; i++) {
      await _scheduleOneShot(
        idBase + i,
        generations[i],
        title,
        body,
        next,
        details,
        payload,
        seriesId: idBase,
      );
      next = _advanceWallClockDays(next, 7, time);
    }
  }

  /// Schedules a coarse repeating notification with [RepeatInterval].
  ///
  /// Used for fronting reminders where approximate interval is acceptable
  /// and no specific clock time is needed.
  Future<void> scheduleRepeating({
    required int id,
    required String title,
    required String body,
    required RepeatInterval interval,
    required NotificationDetails details,
  }) async {
    if (kIsWeb) return;
    final generation = _replace(id);
    await _ensureInitialized();
    if (!_isCurrent(id, generation)) return;
    final duration = switch (interval) {
      RepeatInterval.everyMinute => const Duration(minutes: 1),
      RepeatInterval.hourly => const Duration(hours: 1),
      RepeatInterval.daily => const Duration(days: 1),
      RepeatInterval.weekly => const Duration(days: 7),
    };
    if (duration <= Duration.zero) {
      throw ArgumentError.value(duration, 'interval');
    }
    if (_usesRepeatTimers) {
      _scheduleDesktop(
        id,
        generation,
        title,
        body,
        _now().add(duration),
        details,
        next: (now) => now.add(duration),
      );
      return;
    }
    await _plugin.periodicallyShow(
      id: id,
      title: title,
      body: body,
      repeatInterval: interval,
      notificationDetails: _desktopDetails(details),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  /// Schedules a repeating notification using the exact duration selected.
  ///
  /// This is used for fronting reminders where sub-hour intervals like
  /// 15 minutes need to remain 15 minutes instead of collapsing to the
  /// plugin's coarse hourly/daily/weekly buckets.
  Future<void> scheduleRepeatingWithDuration({
    required int id,
    required String title,
    required String body,
    required Duration interval,
    required NotificationDetails details,
  }) async {
    if (kIsWeb) return;
    final generation = _replace(id);
    await _ensureInitialized();
    if (!_isCurrent(id, generation)) return;
    if (interval <= Duration.zero) {
      throw ArgumentError.value(interval, 'interval');
    }
    if (_usesRepeatTimers) {
      _scheduleDesktop(
        id,
        generation,
        title,
        body,
        _now().add(interval),
        details,
        next: (now) => now.add(interval),
      );
      return;
    }
    await _plugin.periodicallyShowWithDuration(
      id: id,
      title: title,
      body: body,
      repeatDurationInterval: interval,
      notificationDetails: _desktopDetails(details),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  /// Schedules a one-shot notification for a future wall-clock time.
  Future<void> scheduleOneShot({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledFor,
    required NotificationDetails details,
    String? payload,
  }) async {
    if (kIsWeb) return;
    final generation = _replace(id);
    await _ensureInitialized();
    if (!_isCurrent(id, generation)) return;
    await _scheduleOneShot(
      id,
      generation,
      title,
      body,
      tz.TZDateTime.from(scheduledFor, tz.local),
      details,
      payload,
    );
  }

  Future<void> _scheduleOneShot(
    int id,
    int generation,
    String title,
    String body,
    tz.TZDateTime scheduled,
    NotificationDetails details,
    String? payload, {
    int? seriesId,
  }) async {
    if (!_isCurrent(id, generation)) return;
    if (_usesTimers) {
      _scheduleDesktop(
        id,
        generation,
        title,
        body,
        scheduled,
        details,
        payload: payload,
        seriesId: seriesId,
      );
      return;
    }
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduled,
      notificationDetails: _desktopDetails(details),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload,
    );
  }

  /// Shows an immediate one-shot notification.
  Future<void> showImmediate({
    required int id,
    required String title,
    required String body,
    required NotificationDetails details,
  }) async {
    if (kIsWeb) return;
    await _ensureInitialized();
    if (_disposed) return;
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: _desktopDetails(details),
    );
  }

  // ── Cancellation ──────────────────────────────────────────────────

  /// Cancels a single notification by [id].
  Future<void> cancel(int id) async {
    if (kIsWeb) return;
    final generation = _replace(id);
    await _ensureInitialized();
    if (!_isCurrent(id, generation)) return;
    await _plugin.cancel(id: id);
  }

  /// Cancels all notification IDs in the range [base, base + count).
  ///
  /// Use this to clean up interval occurrence IDs and weekly-per-weekday
  /// IDs before rescheduling, so stale slots don't linger when frequency
  /// or timing changes.
  Future<void> cancelRange(int base, int count) async {
    if (kIsWeb) return;
    final cancellations = List.generate(count, (i) => cancel(base + i));
    await Future.wait(cancellations);
  }

  /// Returns all future notifications currently scheduled with the platform.
  Future<List<PendingNotificationRequest>> pendingNotificationRequests() async {
    if (kIsWeb) return const [];
    await _ensureInitialized();
    final local = _desktopSchedules.values.map(
      (entry) => PendingNotificationRequest(
        entry.id,
        entry.title,
        entry.body,
        entry.payload,
      ),
    );
    if (_usesTimers) return local.toList();
    return [...await _plugin.pendingNotificationRequests(), ...local];
  }

  // ── Permissions ───────────────────────────────────────────────────

  /// Requests notification permission from the platform.
  Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    await _ensureInitialized();
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return (await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          )) ??
          false;
    }
    final mac = _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >();
    if (mac != null) {
      return (await mac.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          )) ??
          false;
    }
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return (await android.requestNotificationsPermission()) ?? false;
    }
    // Linux and Windows expose no runtime permission prompt through this plugin.
    return _usesRepeatTimers;
  }

  /// Returns whether notification permission is currently granted.
  Future<bool> isPermissionGranted() async {
    if (kIsWeb) return false;
    await _ensureInitialized();
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      final permissions = await ios.checkPermissions();
      return permissions?.isEnabled ?? false;
    }
    final mac = _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >();
    if (mac != null) {
      final permissions = await mac.checkPermissions();
      return permissions?.isEnabled ?? false;
    }
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return (await android.areNotificationsEnabled()) ?? false;
    }
    // Availability only: system notification settings can still suppress delivery.
    return _usesRepeatTimers;
  }

  // ── Helpers ───────────────────────────────────────────────────────

  NotificationDetails _desktopDetails(NotificationDetails details) =>
      NotificationDetails(
        android: details.android,
        iOS: details.iOS,
        macOS: details.macOS,
        linux: details.linux ?? const LinuxNotificationDetails(),
        windows: details.windows ?? const WindowsNotificationDetails(),
      );

  int _replace(int id) {
    _desktopSchedules.remove(id)?.timer?.cancel();
    return _generations.update(id, (value) => value + 1, ifAbsent: () => 1);
  }

  bool _isCurrent(int id, int generation) =>
      !_disposed && _generations[id] == generation;

  void _scheduleDesktop(
    int id,
    int generation,
    String title,
    String body,
    DateTime scheduled,
    NotificationDetails details, {
    String? payload,
    DateTime Function(DateTime)? next,
    int? seriesId,
  }) {
    final entry = _DesktopNotification(
      id,
      generation,
      title,
      body,
      scheduled,
      _desktopDetails(details),
      payload,
      next,
      seriesId ?? id,
    );
    _desktopSchedules[id] = entry;
    _arm(entry);
  }

  void _arm(_DesktopNotification entry) {
    entry.timer?.cancel();
    final delay = entry.scheduled.difference(_now());
    entry.timer = Timer(delay.isNegative ? Duration.zero : delay, () {
      if (!_isCurrent(entry.id, entry.generation)) return;
      // Recheck wall time after suspend or a clock adjustment.
      final now = _now();
      if (now.isBefore(entry.scheduled)) {
        _arm(entry);
        return;
      }
      if (entry.next == null) {
        final overdue = _desktopSchedules.values
            .where(
              (other) =>
                  other.next == null &&
                  other.seriesId == entry.seriesId &&
                  !other.scheduled.isAfter(now),
            )
            .toList();
        // One catch-up per series after sleep; preserve every future occurrence.
        if (overdue.any((other) => other.scheduled.isAfter(entry.scheduled))) {
          _desktopSchedules.remove(entry.id);
          return;
        }
        for (final other in overdue) {
          if (other.id != entry.id) {
            other.timer?.cancel();
            _desktopSchedules.remove(other.id);
          }
        }
      }
      if (entry.next case final next?) {
        entry.scheduled = next(now);
        _arm(entry);
      } else {
        _desktopSchedules.remove(entry.id);
      }
      unawaited(
        _plugin
            .show(
              id: entry.id,
              title: entry.title,
              body: entry.body,
              notificationDetails: entry.details,
              payload: entry.payload,
            )
            .catchError((Object error) {
              debugPrint(
                'Desktop notification delivery failed: ${error.runtimeType}',
              );
            }),
      );
    });
  }

  DateTime _nextCalendarOccurrence(
    DateTime now,
    TimeOfDay time,
    int days,
    int weekday,
  ) {
    var next = _nextOccurrence(time);
    while (!next.isAfter(now) || (days == 7 && next.weekday != weekday)) {
      next = _advanceWallClockDays(next, 1, time);
    }
    return next;
  }

  /// Re-anchor desktop timers after sleep. Missed repeats deliver at most once.
  void refreshDesktopSchedules() {
    for (final entry in _desktopSchedules.values) {
      _arm(entry);
    }
  }

  /// Stops process-owned timers; native schedules remain owned by the OS.
  void dispose() {
    _disposed = true;
    for (final entry in _desktopSchedules.values) {
      entry.timer?.cancel();
    }
    _desktopSchedules.clear();
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) await initialize();
  }

  /// Returns the next [TZDateTime] at [time] in the local timezone.
  /// If today's occurrence has already passed (or is before [notBefore]),
  /// the search advances forward day by day.
  tz.TZDateTime _nextOccurrence(TimeOfDay time, {DateTime? notBefore}) {
    final now = tz.TZDateTime.from(_now(), tz.local);
    final floor = notBefore == null
        ? now
        : (() {
            final tzNotBefore = tz.TZDateTime.from(notBefore, tz.local);
            return tzNotBefore.isAfter(now) ? tzNotBefore : now;
          })();
    var scheduled = tz.TZDateTime(
      tz.local,
      floor.year,
      floor.month,
      floor.day,
      time.hour,
      time.minute,
    );
    if (scheduled.isBefore(floor)) {
      scheduled = tz.TZDateTime(
        tz.local,
        scheduled.year,
        scheduled.month,
        scheduled.day + 1,
        time.hour,
        time.minute,
      );
    }
    return scheduled;
  }

  /// Returns the next [TZDateTime] for [weekday] at [time].
  tz.TZDateTime _nextWeekdayOccurrence(
    TimeOfDay time,
    int weekday, {
    DateTime? notBefore,
  }) => nextWeekdayOccurrenceFrom(
    _nextOccurrence(time, notBefore: notBefore),
    weekday,
  );

  /// Advances [from] by [days] calendar days, re-anchoring the wall-clock
  /// [time]. Plain `Duration(days: N)` shifts by 86400 s per day and
  /// drifts the hour by ±1 across DST transitions.
  tz.TZDateTime _advanceWallClockDays(
    tz.TZDateTime from,
    int days,
    TimeOfDay time,
  ) {
    return tz.TZDateTime(
      tz.local,
      from.year,
      from.month,
      from.day + days,
      time.hour,
      time.minute,
    );
  }
}

/// Walks forward from [from] until landing on [weekday] (the app's picker
/// convention: 0=Sunday..6=Saturday). Dart's [DateTime.weekday] is
/// 1=Monday..7=Sunday, so 0 is rewritten to 7 before matching. The walk is
/// bounded to 7 iterations so an out-of-range input can never lock the
/// UI isolate.
@visibleForTesting
tz.TZDateTime nextWeekdayOccurrenceFrom(tz.TZDateTime from, int weekday) {
  final target = weekday == 0 ? DateTime.sunday : weekday;
  var candidate = from;
  for (var i = 0; i < 7 && candidate.weekday != target; i++) {
    candidate = tz.TZDateTime(
      from.location,
      candidate.year,
      candidate.month,
      candidate.day + 1,
      candidate.hour,
      candidate.minute,
    );
  }
  return candidate;
}

/// Provides the [LocalNotificationService] singleton.
final localNotificationServiceProvider = Provider<LocalNotificationService>((
  ref,
) {
  final service = LocalNotificationService();
  ref.onDispose(service.dispose);
  return service;
});

class _DesktopNotification {
  _DesktopNotification(
    this.id,
    this.generation,
    this.title,
    this.body,
    this.scheduled,
    this.details,
    this.payload,
    this.next,
    this.seriesId,
  );
  final int id;
  final int generation;
  final int seriesId;
  final String title;
  final String body;
  DateTime scheduled;
  final NotificationDetails details;
  final String? payload;
  final DateTime Function(DateTime)? next;
  Timer? timer;
}
