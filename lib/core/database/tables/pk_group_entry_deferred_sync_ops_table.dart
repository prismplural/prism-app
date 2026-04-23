import 'package:drift/drift.dart';

@DataClassName('PkGroupEntryDeferredSyncOpRow')
class PkGroupEntryDeferredSyncOps extends Table {
  TextColumn get id => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get fieldsJson => text()();
  TextColumn get reason => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get lastRetryAt => dateTime().nullable()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();

  @override
  String get tableName => 'pk_group_entry_deferred_sync_ops';

  @override
  Set<Column> get primaryKey => {id};
}
