import 'package:drift/drift.dart';

class FrontingSessions extends Table {
  TextColumn get id => text()();
  IntColumn get sessionType => integer().withDefault(const Constant(0))();
  DateTimeColumn get startTime => dateTime()();
  DateTimeColumn get endTime => dateTime().nullable()();
  TextColumn get memberId => text().nullable()();
  TextColumn get coFronterIds =>
      text().withDefault(const Constant('[]'))(); // JSON list
  TextColumn get notes => text().nullable()();
  IntColumn get confidence => integer().nullable()(); // enum index
  IntColumn get quality => integer().nullable()();
  BoolColumn get isHealthKitImport =>
      boolean().withDefault(const Constant(false))();
  // PluralKit fields
  TextColumn get pluralkitUuid => text().nullable()();
  // JSON list of PK short member IDs from the original switch. Lets us
  // re-attribute local memberId / coFronterIds after a later link without
  // re-fetching from PK.
  TextColumn get pkMemberIdsJson => text().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
