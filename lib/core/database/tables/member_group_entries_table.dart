import 'package:drift/drift.dart';

@DataClassName('MemberGroupEntryRow')
class MemberGroupEntries extends Table {
  TextColumn get id => text()();
  TextColumn get groupId => text()();
  TextColumn get memberId => text()();
  TextColumn get pkGroupUuid => text().nullable()();
  TextColumn get pkMemberUuid => text().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
