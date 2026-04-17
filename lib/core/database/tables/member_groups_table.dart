import 'package:drift/drift.dart';

@DataClassName('MemberGroupRow')
class MemberGroups extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get colorHex => text().nullable()();
  TextColumn get emoji => text().nullable()();
  IntColumn get displayOrder => integer().withDefault(const Constant(0))();
  TextColumn get parentGroupId => text().nullable()();
  IntColumn get groupType => integer().withDefault(const Constant(0))();
  TextColumn get filterRules => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
