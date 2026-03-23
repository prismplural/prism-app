import 'package:drift/drift.dart';

@DataClassName('MemberGroupEntryRow')
class MemberGroupEntries extends Table {
  TextColumn get id => text()();
  TextColumn get groupId => text()();
  TextColumn get memberId => text()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
