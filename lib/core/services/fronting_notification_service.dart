import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:prism_plurality/core/services/local_notification_service.dart';

/// Service that manages fronting-related local notifications.
class FrontingNotificationService {
  FrontingNotificationService(
    this._localService, {
    this.reminderTitle = 'Fronting Reminder',
    this.reminderBody = 'Consider logging who\'s fronting right now.',
    this.reminderChannelName = 'Fronting Reminders',
    this.reminderChannelDescription =
        'Periodic reminders to check who is fronting',
  });

  final LocalNotificationService _localService;
  final String reminderTitle;
  final String reminderBody;
  final String reminderChannelName;
  final String reminderChannelDescription;

  static const _reminderChannelId = 'fronting_reminders';

  static const _reminderNotificationId = 1000;

  /// Schedule a repeating fronting reminder notification.
  Future<void> scheduleFrontingReminder({required Duration interval}) async {
    await cancelFrontingReminder();

    final androidDetails = AndroidNotificationDetails(
      _reminderChannelId,
      reminderChannelName,
      channelDescription: reminderChannelDescription,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const darwinDetails = DarwinNotificationDetails();
    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _localService.scheduleRepeatingWithDuration(
      id: _reminderNotificationId,
      title: reminderTitle,
      body: reminderBody,
      interval: interval,
      details: details,
    );
  }

  /// Cancel the scheduled fronting reminder.
  Future<void> cancelFrontingReminder() async {
    await _localService.cancel(_reminderNotificationId);
  }
}
