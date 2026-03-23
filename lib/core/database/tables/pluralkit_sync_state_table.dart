import 'package:drift/drift.dart';

class PluralKitSyncState extends Table {
  TextColumn get id => text()(); // always 'pk_config'
  TextColumn get systemId => text().nullable()();
  DateTimeColumn get lastSyncDate => dateTime().nullable()();
  DateTimeColumn get lastManualSyncDate => dateTime().nullable()();
  BoolColumn get isConnected =>
      boolean().withDefault(const Constant(false))();
  TextColumn get fieldSyncConfig => text().nullable()(); // JSON map of memberId → field config

  @override
  Set<Column> get primaryKey => {id};
}
