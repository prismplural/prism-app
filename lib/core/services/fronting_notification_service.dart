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

  int _generation = 0;

  static const _reminderChannelId = 'fronting_reminders';

  static const _reminderNotificationId = 1000;

  /// Schedule a repeating fronting reminder notification.
  Future<void> scheduleFrontingReminder({required Duration interval}) async {
    final generation = ++_generation;
    await _localService.cancel(_reminderNotificationId);
    if (generation != _generation) return;

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

  /// Invalidates work started by a provider that has since been replaced.
  void dispose() => _generation++;

  /// Cancel the scheduled fronting reminder.
  Future<void> cancelFrontingReminder() async {
    _generation++;
    await _localService.cancel(_reminderNotificationId);
  }
}
