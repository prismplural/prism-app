// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'habits_dao.dart';

// ignore_for_file: type=lint
mixin _$HabitsDaoMixin on DatabaseAccessor<AppDatabase> {
  $HabitsTable get habits => attachedDatabase.habits;
  $HabitCompletionsTable get habitCompletions =>
      attachedDatabase.habitCompletions;
  HabitsDaoManager get managers => HabitsDaoManager(this);
}

class HabitsDaoManager {
  final _$HabitsDaoMixin _db;
  HabitsDaoManager(this._db);
  $$HabitsTableTableManager get habits =>
      $$HabitsTableTableManager(_db.attachedDatabase, _db.habits);
  $$HabitCompletionsTableTableManager get habitCompletions =>
      $$HabitCompletionsTableTableManager(
        _db.attachedDatabase,
        _db.habitCompletions,
      );
}
