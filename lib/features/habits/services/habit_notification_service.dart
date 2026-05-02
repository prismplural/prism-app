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

  /// Base notification ID offset for habits. Non-overlapping with fronting
  /// (1000-2000) and reminders (20_000_000–20_100_029). The 100k-wide hash
  /// space keeps birthday-paradox collisions negligible (~1% at 50 items,
  /// ~5% at 100) compared to the previous 10k space (~12% at 50).
  static const _habitNotificationIdBase = 3000000;
  static const _habitNotificationIdMod = 100000;

  AppLocalizations get _l10n => lookupAppLocalizations(_localeResolver());

  /// Schedule notifications for a habit based on its frequency and reminder
  /// time.
  ///
  /// When [skipCurrentPeriod] is true, the next fire is pushed past the
  /// current period — used right after a completion so the user doesn't get
  /// reminded about something they already did.
  /// - daily / custom → first fire shifts to tomorrow
  /// - weekly → only the slot whose weekday matches today shifts to next week
  /// - interval (>1 day) → run starts at `today + intervalDays`
  Future<void> scheduleForHabit(
    Habit habit, {
    bool skipCurrentPeriod = false,
    DateTime? now,
  }) async {
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

    final clock = now ?? DateTime.now();
    final today = DateTime(clock.year, clock.month, clock.day);
    final tomorrow = today.add(const Duration(days: 1));

    switch (habit.frequency) {
      case HabitFrequency.daily:
      case HabitFrequency.custom:
        await _localService.scheduleExactDaily(
          id: _baseId(habit.id),
          title: title,
          body: body,
          time: time,
          details: details,
          notBefore: skipCurrentPeriod ? tomorrow : null,
        );

      case HabitFrequency.weekly:
        // Defense-in-depth: even though the mapper guards corrupt rows,
        // direct callers via providers could bypass it. Drop out-of-range
        // weekdays and dedupe so each weekday schedules exactly once.
        final days = (habit.weeklyDays ?? const <int>[])
            .where((d) => d >= 0 && d <= 6)
            .toSet()
            .toList()
          ..sort();
        if (days.isEmpty) return;
        // 0=Sun..6=Sat per the app's weekly weekday convention.
        final todayIdx = clock.weekday % 7;
        for (var i = 0; i < days.length; i++) {
          final isTodaySlot = skipCurrentPeriod && days[i] == todayIdx;
          await _localService.scheduleExactWeekly(
            id: _baseId(habit.id) + i,
            title: title,
            body: body,
            time: time,
            weekday: days[i],
            details: details,
            notBefore: isTodaySlot ? tomorrow : null,
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
            notBefore: skipCurrentPeriod ? tomorrow : null,
          );
        } else {
          await _localService.scheduleExactInterval(
            idBase: _baseId(habit.id),
            title: title,
            body: body,
            time: time,
            intervalDays: intervalDays,
            details: details,
            notBefore: skipCurrentPeriod
                ? today.add(Duration(days: intervalDays))
                : null,
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
  ///
  /// [skipCurrentPeriodFor] is consulted per-habit to suppress same-period
  /// reminders for habits whose current period is already completed.
  Future<void> rescheduleAll(
    List<Habit> habits, {
    bool Function(Habit habit)? skipCurrentPeriodFor,
  }) async {
    for (final habit in habits) {
      final skip = skipCurrentPeriodFor?.call(habit) ?? false;
      await scheduleForHabit(habit, skipCurrentPeriod: skip);
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────

  /// Generates a stable base notification ID from a habit ID string.
  int _baseId(String id) =>
      _habitNotificationIdBase + (id.hashCode.abs() % _habitNotificationIdMod);

  /// Parses a "HH:mm" reminder time string into a [TimeOfDay].
  /// Returns null if the string is null, malformed, or out of range.
  /// Out-of-range values like "25:70" would silently normalize to a wrong
  /// time when fed through DateTime, so reject them up front.
  TimeOfDay? _parseTime(String? time) {
    if (time == null) return null;
    final parts = time.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
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
