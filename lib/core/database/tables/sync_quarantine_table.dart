import 'package:drift/drift.dart';

@DataClassName('SyncQuarantineData')
class SyncQuarantineTable extends Table {
  TextColumn get id => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get fieldName => text().nullable()();
  TextColumn get expectedType => text()();
  TextColumn get receivedType => text()();
  TextColumn get receivedValue => text().nullable()();
  TextColumn get sourceDevice => text().nullable()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastRetryAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get errorMessage => text().nullable()();

  @override
  String get tableName => 'sync_quarantine';

  @override
  Set<Column> get primaryKey => {id};
}
