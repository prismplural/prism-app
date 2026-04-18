import 'package:drift/drift.dart';

@DataClassName('ReminderRow')
class Reminders extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get message => text()();
  IntColumn get trigger => integer().withDefault(const Constant(0))(); // ReminderTrigger enum index
  TextColumn get frequency => text().nullable()();
  IntColumn get intervalDays => integer().nullable()();
  TextColumn get weeklyDays => text().nullable()();
  TextColumn get timeOfDay => text().nullable()();
  IntColumn get delayHours => integer().nullable()();
  /// Optional member ID this reminder targets. When null, a front-change
  /// reminder fires on any switch; when set, it fires only when the referenced
  /// member (or custom-front-tagged member) is in the current fronter set.
  TextColumn get targetMemberId => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get modifiedAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
