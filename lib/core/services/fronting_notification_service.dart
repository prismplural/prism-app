import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:prism_plurality/core/services/local_notification_service.dart';

/// Service that manages fronting-related local notifications.
class FrontingNotificationService {
  FrontingNotificationService(this._localService);

  final LocalNotificationService _localService;

  static const _reminderChannelId = 'fronting_reminders';
  static const _reminderChannelName = 'Fronting Reminders';
  static const _reminderChannelDesc =
      'Periodic reminders to check who is fronting';

  static const _changeChannelId = 'fronting_changes';
  static const _changeChannelName = 'Fronting Changes';
  static const _changeChannelDesc =
      'Notifications when the current fronter changes';

  static const _reminderNotificationId = 1000;
  static const _changeNotificationId = 2000;

  /// Schedule a repeating fronting reminder notification.
  Future<void> scheduleFrontingReminder({
    required Duration interval,
    required String currentFronterName,
  }) async {
    await cancelFrontingReminder();

    const androidDetails = AndroidNotificationDetails(
      _reminderChannelId,
      _reminderChannelName,
      channelDescription: _reminderChannelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const darwinDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _localService.scheduleRepeating(
      id: _reminderNotificationId,
      title: 'Fronting Reminder',
      body: '$currentFronterName is currently fronting. Is this still accurate?',
      interval: _repeatIntervalFrom(interval),
      details: details,
    );
  }

  /// Cancel the scheduled fronting reminder.
  Future<void> cancelFrontingReminder() async {
    await _localService.cancel(_reminderNotificationId);
  }

  /// Show an immediate notification when the fronter changes.
  Future<void> showFrontingChange({required String newFronterName}) async {
    const androidDetails = AndroidNotificationDetails(
      _changeChannelId,
      _changeChannelName,
      channelDescription: _changeChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
    );
    const darwinDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _localService.showImmediate(
      id: _changeNotificationId,
      title: 'Fronting Change',
      body: '$newFronterName is now fronting.',
      details: details,
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────

  RepeatInterval _repeatIntervalFrom(Duration duration) {
    if (duration.inMinutes <= 60) return RepeatInterval.hourly;
    if (duration.inHours <= 24) return RepeatInterval.daily;
    return RepeatInterval.weekly;
  }
}
