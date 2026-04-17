import 'package:drift/drift.dart';

@DataClassName('SpSyncStateRow')
class SpSyncStateTable extends Table {
  TextColumn get id => text()(); // always 'singleton'
  DateTimeColumn get lastImportAt => dateTime().nullable()();
  TextColumn get spSystemId => text().nullable()();

  @override
  String get tableName => 'sp_sync_state';

  @override
  Set<Column> get primaryKey => {id};
}
