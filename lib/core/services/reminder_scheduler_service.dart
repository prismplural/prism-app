import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/reminder.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/reminders/providers/reminders_providers.dart';

/// Service that schedules and cancels local notifications for reminders.
///
/// Uses [FlutterLocalNotificationsPlugin] for scheduled reminders and tracks
/// pending front-change reminders in memory (fired when a front change is
/// detected).
class ReminderSchedulerService {
  ReminderSchedulerService();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'reminders';
  static const _channelName = 'Reminders';
  static const _channelDesc = 'Custom reminder notifications';

  /// Base notification ID offset for reminders (habits use 3000+, fronting
  /// uses 1000-2000).
  static const _notificationIdBase = 5000;

  bool _initialized = false;

  /// Active front-change reminders awaiting a front switch.
  final List<Reminder> _pendingFrontChangeReminders = [];

  /// Initialize the notification plugin with platform-specific settings.
  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _plugin.initialize(settings: initSettings);
    _initialized = true;
  }

  /// Schedule a single reminder notification.
  ///
  /// For [ReminderTrigger.scheduled] reminders, a repeating local notification
  /// is scheduled. For [ReminderTrigger.onFrontChange] reminders, the reminder
  /// is stored in [_pendingFrontChangeReminders] and fired when
  /// [fireFrontChangeReminders] is called.
  Future<void> scheduleReminder(Reminder reminder) async {
    if (!reminder.isActive) return;

    switch (reminder.trigger) {
      case ReminderTrigger.scheduled:
        await _scheduleRepeating(reminder);
      case ReminderTrigger.onFrontChange:
        _pendingFrontChangeReminders.removeWhere((r) => r.id == reminder.id);
        _pendingFrontChangeReminders.add(reminder);
    }
  }

  /// Cancel a reminder notification by its id.
  Future<void> cancelReminder(String id) async {
    await _plugin.cancel(id: _notificationId(id));
    _pendingFrontChangeReminders.removeWhere((r) => r.id == id);
  }

  /// Cancel all existing reminder notifications and reschedule from the
  /// provided list. Only active reminders are scheduled.
  Future<void> rescheduleAll(List<Reminder> reminders) async {
    await _ensureInitialized();

    // Cancel all existing reminder notifications.
    _pendingFrontChangeReminders.clear();
    for (final r in reminders) {
      await _plugin.cancel(id: _notificationId(r.id));
    }

    // Reschedule active ones.
    for (final reminder in reminders) {
      if (reminder.isActive) {
        await scheduleReminder(reminder);
      }
    }
  }

  /// Fire all pending front-change reminders. Called when active fronting
  /// sessions change.
  Future<void> fireFrontChangeReminders() async {
    await _ensureInitialized();

    for (final reminder in _pendingFrontChangeReminders) {
      await _showImmediate(reminder);
    }
  }

  // ── Private helpers ─────────────────────────────────────────────

  Future<void> _ensureInitialized() async {
    if (!_initialized) await initialize();
  }

  Future<void> _scheduleRepeating(Reminder reminder) async {
    await _ensureInitialized();

    // Cancel existing notification for this reminder first.
    await _plugin.cancel(id: _notificationId(reminder.id));

    final interval = _repeatIntervalFrom(reminder.intervalDays);

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );

    const darwinDetails = DarwinNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _plugin.periodicallyShow(
      id: _notificationId(reminder.id),
      title: reminder.name,
      body: reminder.message,
      repeatInterval: interval,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> _showImmediate(Reminder reminder) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
    );

    const darwinDetails = DarwinNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _plugin.show(
      id: _notificationId(reminder.id),
      title: reminder.name,
      body: reminder.message,
      notificationDetails: details,
    );
  }

  /// Generates a stable notification ID from reminder ID.
  int _notificationId(String id) {
    return _notificationIdBase + (id.hashCode.abs() % 10000);
  }

  RepeatInterval _repeatIntervalFrom(int? intervalDays) {
    if (intervalDays == null || intervalDays <= 1) return RepeatInterval.daily;
    if (intervalDays <= 7) return RepeatInterval.weekly;
    return RepeatInterval.weekly;
  }
}

/// Provides the [ReminderSchedulerService] singleton instance.
final reminderSchedulerServiceProvider =
    Provider<ReminderSchedulerService>((ref) {
  return ReminderSchedulerService();
});

/// Provider that watches active reminders and reschedules notifications
/// whenever the list changes (from local edits or remote sync).
///
/// Also watches active fronting sessions and fires front-change reminders
/// when sessions change.
///
/// This provider should be kept alive at the app level via `ref.listen`
/// in [PrismApp].
final reminderSchedulerListenerProvider = Provider<void>((ref) {
  final service = ref.watch(reminderSchedulerServiceProvider);

  // Watch active reminders and reschedule when they change.
  ref.listen(
    activeRemindersProvider,
    (previous, next) {
      final reminders = next.value;
      if (reminders != null) {
        service.rescheduleAll(reminders).catchError((e) {
          debugPrint('Reminder reschedule failed (non-fatal): $e');
        });
      }
    },
    fireImmediately: true,
  );

  // Watch active fronting sessions and fire front-change reminders when
  // sessions change.
  ref.listen(
    activeSessionsProvider,
    (previous, next) {
      final previousSessions = previous?.value;
      final currentSessions = next.value;

      // Only fire on actual changes, not on initial load.
      if (previousSessions == null || currentSessions == null) return;

      // Detect if the set of active sessions has changed.
      final previousIds = previousSessions.map((s) => s.id).toSet();
      final currentIds = currentSessions.map((s) => s.id).toSet();
      if (!_setsEqual(previousIds, currentIds)) {
        service.fireFrontChangeReminders().catchError((e) {
          debugPrint('Front-change reminder fire failed (non-fatal): $e');
        });
      }
    },
  );
});

bool _setsEqual<T>(Set<T> a, Set<T> b) {
  if (a.length != b.length) return false;
  return a.containsAll(b);
}
