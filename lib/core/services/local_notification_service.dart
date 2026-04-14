import 'package:flutter/foundation.dart' show kIsWeb;
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
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Maximum number of pre-scheduled occurrences for interval-based
  /// notifications. Guarantees at least 30 days coverage for any interval.
  static const int maxIntervalOccurrences = 30;

  Future<void> initialize() async {
    if (kIsWeb || _initialized) return;
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
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
      ),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );
    // Defensive timezone refresh — main() sets this at startup, but
    // guard against cases where initialize() is called in isolation.
    try {
      if (!kIsWeb) {
        final localTz = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(localTz));
      }
    } catch (_) {}
    _initialized = true;
  }

  void _onNotificationTap(NotificationResponse details) {
    // No-op — wire deep-link navigation here when tap routing is added.
  }

  // ── Exact-time scheduling ─────────────────────────────────────────

  /// Schedules a repeating daily notification at [time].
  ///
  /// Uses [DateTimeComponents.time] so the OS fires it every day at
  /// that clock time without requiring the app to reschedule.
  Future<void> scheduleExactDaily({
    required int id,
    required String title,
    required String body,
    required TimeOfDay time,
    required NotificationDetails details,
  }) async {
    if (kIsWeb) return;
    await _ensureInitialized();
    final scheduled = _nextOccurrence(time);
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduled,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// Schedules a repeating weekly notification on [weekday] at [time].
  ///
  /// [weekday] uses [DateTime] weekday constants (Monday=1, Sunday=7).
  /// Uses [DateTimeComponents.dayOfWeekAndTime] for OS-managed repeating.
  Future<void> scheduleExactWeekly({
    required int id,
    required String title,
    required String body,
    required TimeOfDay time,
    required int weekday,
    required NotificationDetails details,
  }) async {
    if (kIsWeb) return;
    await _ensureInitialized();
    final scheduled = _nextWeekdayOccurrence(time, weekday);
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduled,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  /// Schedules N individual one-shot notifications spaced [intervalDays] apart.
  ///
  /// N = ceil(30 / intervalDays).clamp(2, [maxIntervalOccurrences]),
  /// guaranteeing ≥ 30 days of future coverage.
  ///
  /// Note: do NOT call this with intervalDays == 1; use [scheduleExactDaily].
  /// Callers are responsible for cancelling stale IDs with [cancelRange]
  /// before calling this.
  Future<void> scheduleExactInterval({
    required int idBase,
    required String title,
    required String body,
    required TimeOfDay time,
    required int intervalDays,
    required NotificationDetails details,
    int? maxOccurrences,
  }) async {
    if (kIsWeb) return;
    await _ensureInitialized();
    final n = maxOccurrences ??
        (30 / intervalDays).ceil().clamp(2, maxIntervalOccurrences);
    var next = _nextOccurrence(time);
    for (var i = 0; i < n; i++) {
      await _plugin.zonedSchedule(
        id: idBase + i,
        title: title,
        body: body,
        scheduledDate: next,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
      next = next.add(Duration(days: intervalDays));
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
    await _ensureInitialized();
    await _plugin.periodicallyShow(
      id: id,
      title: title,
      body: body,
      repeatInterval: interval,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
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
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  // ── Cancellation ──────────────────────────────────────────────────

  /// Cancels a single notification by [id].
  Future<void> cancel(int id) async {
    if (kIsWeb) return;
    await _plugin.cancel(id: id);
  }

  /// Cancels all notification IDs in the range [base, base + count).
  ///
  /// Use this to clean up interval occurrence IDs and weekly-per-weekday
  /// IDs before rescheduling, so stale slots don't linger when frequency
  /// or timing changes.
  Future<void> cancelRange(int base, int count) async {
    if (kIsWeb) return;
    for (var i = 0; i < count; i++) {
      await _plugin.cancel(id: base + i);
    }
  }

  // ── Permissions ───────────────────────────────────────────────────

  /// Requests notification permission from the platform.
  Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    await _ensureInitialized();
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return (await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          )) ??
          false;
    }
    final mac = _plugin.resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin>();
    if (mac != null) {
      return (await mac.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          )) ??
          false;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return (await android.requestNotificationsPermission()) ?? false;
    }
    return false;
  }

  /// Returns whether notification permission is currently granted.
  Future<bool> isPermissionGranted() async {
    if (kIsWeb) return false;
    await _ensureInitialized();
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return (await ios.requestPermissions()) ?? false;
    }
    final mac = _plugin.resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin>();
    if (mac != null) {
      return (await mac.requestPermissions()) ?? false;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return (await android.areNotificationsEnabled()) ?? false;
    }
    // Fallback: assume granted on unsupported platforms.
    return true;
  }

  // ── Helpers ───────────────────────────────────────────────────────

  Future<void> _ensureInitialized() async {
    if (!_initialized) await initialize();
  }

  /// Returns the next [TZDateTime] at [time] in the local timezone.
  /// If today's occurrence has already passed, returns tomorrow's.
  tz.TZDateTime _nextOccurrence(TimeOfDay time) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  /// Returns the next [TZDateTime] for [weekday] at [time].
  tz.TZDateTime _nextWeekdayOccurrence(TimeOfDay time, int weekday) {
    var candidate = _nextOccurrence(time);
    while (candidate.weekday != weekday) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }
}

/// Provides the [LocalNotificationService] singleton.
final localNotificationServiceProvider =
    Provider<LocalNotificationService>((ref) => LocalNotificationService());
