import 'package:drift/drift.dart';

@DataClassName('Habit')
class Habits extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get icon => text().nullable()();
  TextColumn get colorHex => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get modifiedAt => dateTime()();
  TextColumn get frequency => text().withDefault(const Constant('daily'))();
  TextColumn get weeklyDays => text().nullable()();
  IntColumn get intervalDays => integer().nullable()();
  TextColumn get reminderTime => text().nullable()();
  BoolColumn get notificationsEnabled =>
      boolean().withDefault(const Constant(false))();
  TextColumn get notificationMessage => text().nullable()();
  TextColumn get assignedMemberId => text().nullable()();
  BoolColumn get onlyNotifyWhenFronting =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get isPrivate => boolean().withDefault(const Constant(false))();
  IntColumn get currentStreak => integer().withDefault(const Constant(0))();
  IntColumn get bestStreak => integer().withDefault(const Constant(0))();
  IntColumn get totalCompletions => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
