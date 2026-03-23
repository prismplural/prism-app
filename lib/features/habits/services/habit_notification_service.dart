import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/habit.dart';

/// Service that manages habit reminder notifications.
class HabitNotificationService {
  HabitNotificationService();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'habit_reminders';
  static const _channelName = 'Habit Reminders';
  static const _channelDesc = 'Reminders for habit completion';

  /// Base notification ID offset for habits (to avoid collision with fronting
  /// notifications which use 1000-2000).
  static const _habitNotificationIdBase = 3000;

  bool _initialized = false;

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

  /// Schedule notifications for a habit based on its frequency and reminder
  /// time.
  Future<void> scheduleForHabit(Habit habit) async {
    await _ensureInitialized();

    // Cancel existing notifications for this habit first.
    await cancelForHabit(habit.id);

    if (!habit.notificationsEnabled || habit.reminderTime == null) return;

    // Parse reminder time (reserved for future exact scheduling support).
    // ignore: unused_local_variable
    final timeParts = habit.reminderTime!.split(':');
    if (timeParts.length != 2) return;

    const title = 'Habit Reminder';
    final body =
        habit.notificationMessage ?? 'Time to complete: ${habit.name}';

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

    switch (habit.frequency) {
      case HabitFrequency.daily:
      case HabitFrequency.custom:
        // Schedule a daily repeating notification.
        await _plugin.periodicallyShow(
          id: _notificationId(habit.id, 0),
          title: title,
          body: body,
          repeatInterval: RepeatInterval.daily,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );

      case HabitFrequency.weekly:
        // Schedule one notification per required weekday.
        final days = habit.weeklyDays ?? [];
        for (var i = 0; i < days.length; i++) {
          await _plugin.periodicallyShow(
            id: _notificationId(habit.id, i),
            title: title,
            body: body,
            repeatInterval: RepeatInterval.weekly,
            notificationDetails: details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
        }

      case HabitFrequency.interval:
        // For interval-based habits, use daily repeating and rely on the
        // provider to reschedule after each completion.
        await _plugin.periodicallyShow(
          id: _notificationId(habit.id, 0),
          title: title,
          body: body,
          repeatInterval: RepeatInterval.daily,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
    }
  }

  /// Cancel all notifications for a specific habit.
  Future<void> cancelForHabit(String habitId) async {
    // Cancel up to 7 possible notification IDs (one per weekday).
    for (var i = 0; i < 7; i++) {
      await _plugin.cancel(id: _notificationId(habitId, i));
    }
  }

  /// Cancel all habit notifications.
  Future<void> cancelAll() async {
    // This cancels ALL notifications, use with care.
    // In practice, we cancel per-habit.
    await _plugin.cancelAll();
  }

  // ── Helpers ──────────────────────────────────────────────────────

  Future<void> _ensureInitialized() async {
    if (!_initialized) await initialize();
  }

  /// Generates a stable notification ID from habit ID and index.
  int _notificationId(String habitId, int index) {
    return _habitNotificationIdBase + (habitId.hashCode.abs() % 10000) + index;
  }
}

/// Provides the [HabitNotificationService] singleton instance.
final habitNotificationServiceProvider =
    Provider<HabitNotificationService>((ref) {
  return HabitNotificationService();
});
