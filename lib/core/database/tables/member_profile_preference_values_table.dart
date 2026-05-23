import 'package:drift/drift.dart';

@DataClassName('MemberProfilePreferenceValueRow')
class MemberProfilePreferenceValues extends Table {
  @override
  String get tableName => 'member_profile_preference_values';

  TextColumn get id => text()();
  TextColumn get memberId => text()();
  TextColumn get key => text()();
  TextColumn get valueType => text()();
  TextColumn get valueJson => text().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
