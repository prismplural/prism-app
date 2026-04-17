import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/reminder.dart';

/// All reminders (non-deleted), streamed for reactivity.
final remindersProvider = StreamProvider<List<Reminder>>((ref) {
  final repo = ref.watch(remindersRepositoryProvider);
  return repo.watchAll();
});

/// Active reminders only, streamed for reactivity.
final activeRemindersProvider = StreamProvider<List<Reminder>>((ref) {
  final repo = ref.watch(remindersRepositoryProvider);
  return repo.watchActive();
});

/// Reminders notifier for CRUD operations.
class RemindersNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> createReminder({
    required String name,
    required String message,
    required ReminderTrigger trigger,
    int? intervalDays,
    String? timeOfDay,
    int? delayHours,
    ReminderFrequency frequency = ReminderFrequency.daily,
    List<int>? weeklyDays,
  }) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(remindersRepositoryProvider);
      final now = DateTime.now();
      final reminder = Reminder(
        id: const Uuid().v4(),
        name: name,
        message: message,
        trigger: trigger,
        intervalDays: intervalDays,
        timeOfDay: timeOfDay,
        delayHours: delayHours,
        frequency: frequency,
        weeklyDays: weeklyDays,
        isActive: true,
        createdAt: now,
        modifiedAt: now,
      );
      await repo.create(reminder);
    });
  }

  Future<void> updateReminder(Reminder reminder) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(remindersRepositoryProvider);
      await repo.update(reminder.copyWith(modifiedAt: DateTime.now()));
    });
  }

  Future<void> toggleActive(Reminder reminder) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(remindersRepositoryProvider);
      await repo.update(reminder.copyWith(
        isActive: !reminder.isActive,
        modifiedAt: DateTime.now(),
      ));
    });
  }

  Future<void> deleteReminder(String id) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(remindersRepositoryProvider);
      await repo.delete(id);
    });
  }
}

final remindersNotifierProvider = AsyncNotifierProvider<RemindersNotifier, void>(
  RemindersNotifier.new,
);
