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

  /// Base notification ID offset for reminders (habits use 3000+, fronting
  /// uses 1000-2000).
  static const _notificationIdBase = 5000;

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
      _notificationId(id),
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

  /// Fire all pending front-change reminders. Called when active fronting
  /// sessions change.
  Future<void> fireFrontChangeReminders() async {
    for (final reminder in _pendingFrontChangeReminders) {
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

    // Cancel ALL slots first — covers both the single-ID case (daily) and
    // multi-ID interval cases (base+0, base+1, ...) to prevent stale notifications.
    await _localService.cancelRange(
      _notificationId(reminder.id),
      LocalNotificationService.maxIntervalOccurrences,
    );

    final intervalDays = reminder.intervalDays ?? 1;
    if (intervalDays <= 1) {
      await _localService.scheduleExactDaily(
        id: _notificationId(reminder.id),
        title: reminder.name,
        body: reminder.message,
        time: time,
        details: details,
      );
    } else {
      await _localService.scheduleExactInterval(
        idBase: _notificationId(reminder.id),
        title: reminder.name,
        body: reminder.message,
        time: time,
        intervalDays: intervalDays,
        details: details,
      );
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
      id: _notificationId(reminder.id),
      title: reminder.name,
      body: reminder.message,
      details: details,
    );
  }

  /// Generates a stable notification ID from reminder ID.
  int _notificationId(String id) {
    return _notificationIdBase + (id.hashCode.abs() % 10000);
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
