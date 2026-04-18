import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/services/local_notification_service.dart';
import 'package:prism_plurality/domain/models/reminder.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/reminders/providers/reminders_providers.dart';

/// Service that schedules and cancels local notifications for reminders.
///
/// Delegates all plugin interaction to [LocalNotificationService] and tracks
/// pending front-change reminders in memory (fired when a front change is
/// detected).
class ReminderSchedulerService {
  ReminderSchedulerService(this._localService);

  final LocalNotificationService _localService;

  static const _channelId = 'reminders';
  static const _channelName = 'Reminders';
  static const _channelDesc = 'Custom reminder notifications';

  /// Start of the notification ID range for reminders. Non-overlapping with
  /// habits (3000–12999) and fronting (1000–2000).
  static const _idRangeStart = 20000;

  /// Active front-change reminders awaiting a front switch.
  final List<Reminder> _pendingFrontChangeReminders = [];

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
    await _localService.cancelRange(
      _notificationIdBase(id),
      LocalNotificationService.maxIntervalOccurrences,
    );
    _pendingFrontChangeReminders.removeWhere((r) => r.id == id);
  }

  /// Cancel all existing reminder notifications and reschedule from the
  /// provided list. Only active reminders are scheduled.
  Future<void> rescheduleAll(List<Reminder> reminders) async {
    // Cancel all existing reminder notifications.
    _pendingFrontChangeReminders.clear();
    for (final r in reminders) {
      await cancelReminder(r.id);
    }

    // Reschedule active ones.
    for (final reminder in reminders) {
      if (reminder.isActive) {
        await scheduleReminder(reminder);
      }
    }
  }

  /// Fire pending front-change reminders filtered by the current fronter set.
  ///
  /// A reminder with [Reminder.targetMemberId] = null fires on any switch.
  /// A reminder with a target member fires only when that member (or the
  /// custom-front-tagged member representing an SP custom front) is in
  /// [currentFronterIds].
  ///
  /// Note: This is local-device-only. These reminders fire when THIS device
  /// observes the front change — either because it initiated the switch, or
  /// because it received the switch via sync while Prism was running (or
  /// during an iOS/Android background sync run). They will NOT fire promptly
  /// when the app is closed and a co-fronter switches on another device.
  /// The CreateReminderSheet discloses this to users.
  Future<void> fireFrontChangeReminders(Set<String> currentFronterIds) async {
    for (final reminder in _pendingFrontChangeReminders) {
      final target = reminder.targetMemberId;
      if (target != null && !currentFronterIds.contains(target)) {
        continue;
      }
      await _showImmediate(reminder);
    }
  }

  // ── Private helpers ─────────────────────────────────────────────

  Future<void> _scheduleRepeating(Reminder reminder) async {
    final time =
        _parseTime(reminder.timeOfDay) ?? const TimeOfDay(hour: 9, minute: 0);

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

    // Cancel ALL slots first — covers the single-ID case (daily), the
    // multi-ID weekly case (base+0..base+6), and the interval case
    // (base+0..base+N) to prevent stale notifications.
    await _localService.cancelRange(
      _notificationIdBase(reminder.id),
      LocalNotificationService.maxIntervalOccurrences,
    );

    final baseId = _notificationIdBase(reminder.id);

    switch (reminder.frequency) {
      case ReminderFrequency.daily:
        await _localService.scheduleExactDaily(
          id: baseId,
          title: reminder.name,
          body: reminder.message,
          time: time,
          details: details,
        );

      case ReminderFrequency.weekly:
        // Defense-in-depth: even though the mapper guards corrupt rows,
        // direct callers via providers could bypass it. Drop out-of-range
        // weekdays and dedupe so each weekday schedules exactly once.
        final days = (reminder.weeklyDays ?? const <int>[])
            .where((d) => d >= 0 && d <= 6)
            .toSet()
            .toList()
          ..sort();
        if (days.isEmpty) return;
        for (var i = 0; i < days.length; i++) {
          await _localService.scheduleExactWeekly(
            id: baseId + i,
            title: reminder.name,
            body: reminder.message,
            time: time,
            weekday: days[i],
            details: details,
          );
        }

      case ReminderFrequency.interval:
        final intervalDays = reminder.intervalDays ?? 1;
        if (intervalDays <= 1) {
          await _localService.scheduleExactDaily(
            id: baseId,
            title: reminder.name,
            body: reminder.message,
            time: time,
            details: details,
          );
        } else {
          await _localService.scheduleExactInterval(
            idBase: baseId,
            title: reminder.name,
            body: reminder.message,
            time: time,
            intervalDays: intervalDays,
            details: details,
          );
        }
    }
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
    await _localService.showImmediate(
      id: _notificationIdBase(reminder.id),
      title: reminder.name,
      body: reminder.message,
      details: details,
    );
  }

  /// Generates a stable base notification ID from a reminder ID string.
  ///
  /// Weekly scheduling uses `base + i` for each selected weekday (i in 0..6);
  /// interval scheduling uses `base + i` for each occurrence. The 10000-wide
  /// collision space keeps the range bounded for [LocalNotificationService.cancelRange].
  int _notificationIdBase(String id) {
    return _idRangeStart + (id.hashCode.abs() % 10000);
  }

  /// Parses a time string in "HH:mm" format into a [TimeOfDay].
  /// Returns null if the string is null or malformed.
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

/// Provides the [ReminderSchedulerService] singleton instance.
final reminderSchedulerServiceProvider =
    Provider<ReminderSchedulerService>((ref) {
  return ReminderSchedulerService(ref.watch(localNotificationServiceProvider));
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

  // Debounce timer for rescheduleAll — prevents rapid-fire rescheduling
  // during sync bursts where many reminder entities arrive in quick
  // succession. Only the last emission within the 500ms window fires.
  Timer? debounceTimer;
  ref.onDispose(() => debounceTimer?.cancel());

  // Watch active reminders and reschedule when they change (debounced).
  ref.listen(
    activeRemindersProvider,
    (previous, next) {
      final reminders = next.value;
      if (reminders != null) {
        debounceTimer?.cancel();
        debounceTimer = Timer(const Duration(milliseconds: 500), () {
          service.rescheduleAll(reminders).catchError((e) {
            debugPrint('Reminder reschedule failed (non-fatal): $e');
          });
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
        // Current fronter member IDs — include co-fronters, skip sessions
        // with no member_id (shouldn't happen for active sessions, but be
        // defensive).
        final fronterIds = <String>{};
        for (final s in currentSessions) {
          final mid = s.memberId;
          if (mid != null) fronterIds.add(mid);
          fronterIds.addAll(s.coFronterIds);
        }
        service.fireFrontChangeReminders(fronterIds).catchError((e) {
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
