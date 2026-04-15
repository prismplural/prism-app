import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/services/local_notification_service.dart';
import 'package:prism_plurality/domain/models/habit.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

/// Service that manages habit reminder notifications.
class HabitNotificationService {
  HabitNotificationService(
    this._localService, [
    Locale Function()? localeResolver,
  ]) : _localeResolver = localeResolver ?? (() => PlatformDispatcher.instance.locale);

  final LocalNotificationService _localService;
  final Locale Function() _localeResolver;

  static const _channelId = 'habit_reminders';
  static const _channelName = 'Habit Reminders';
  static const _channelDesc = 'Reminders for habit completion';

  /// Base notification ID offset for habits (to avoid collision with fronting
  /// notifications which use 1000-2000).
  static const _habitNotificationIdBase = 3000;

  AppLocalizations get _l10n => lookupAppLocalizations(_localeResolver());

  /// Schedule notifications for a habit based on its frequency and reminder
  /// time.
  Future<void> scheduleForHabit(Habit habit) async {
    // Guard: inactive or notifications disabled → cancel and return
    if (!habit.isActive || !habit.notificationsEnabled) {
      await cancelForHabit(habit.id);
      return;
    }

    final time = _parseTime(habit.reminderTime) ?? const TimeOfDay(hour: 9, minute: 0);

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

    final l10n = _l10n;
    final title = l10n.habitsReminderNotificationTitle;
    final body =
        habit.notificationMessage ?? l10n.habitsReminderNotificationBody(habit.name);

    // Cancel all existing IDs for this habit before rescheduling
    await cancelForHabit(habit.id);

    switch (habit.frequency) {
      case HabitFrequency.daily:
      case HabitFrequency.custom:
        await _localService.scheduleExactDaily(
          id: _baseId(habit.id),
          title: title,
          body: body,
          time: time,
          details: details,
        );

      case HabitFrequency.weekly:
        final days = habit.weeklyDays ?? [];
        if (days.isEmpty) return;
        for (var i = 0; i < days.length; i++) {
          await _localService.scheduleExactWeekly(
            id: _baseId(habit.id) + i,
            title: title,
            body: body,
            time: time,
            weekday: days[i],
            details: details,
          );
        }

      case HabitFrequency.interval:
        final intervalDays = habit.intervalDays ?? 1;
        if (intervalDays <= 1) {
          await _localService.scheduleExactDaily(
            id: _baseId(habit.id),
            title: title,
            body: body,
            time: time,
            details: details,
          );
        } else {
          await _localService.scheduleExactInterval(
            idBase: _baseId(habit.id),
            title: title,
            body: body,
            time: time,
            intervalDays: intervalDays,
            details: details,
          );
        }
    }
  }

  /// Cancel all notifications for a specific habit.
  Future<void> cancelForHabit(String id) async {
    await _localService.cancelRange(
      _baseId(id),
      LocalNotificationService.maxIntervalOccurrences,
    );
  }

  /// Reschedule notifications for all habits.
  Future<void> rescheduleAll(List<Habit> habits) async {
    for (final habit in habits) {
      await scheduleForHabit(habit);
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────

  /// Generates a stable base notification ID from a habit ID string.
  int _baseId(String id) =>
      _habitNotificationIdBase + (id.hashCode.abs() % 10000);

  /// Parses a "HH:mm" reminder time string into a [TimeOfDay].
  TimeOfDay? _parseTime(String? time) {
    if (time == null) return null;
    final parts = time.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }
}

/// Provides the [HabitNotificationService] singleton instance.
final habitNotificationServiceProvider =
    Provider<HabitNotificationService>((ref) {
  return HabitNotificationService(
    ref.watch(localNotificationServiceProvider),
    () => ref.read(localeOverrideProvider) ?? PlatformDispatcher.instance.locale,
  );
});
