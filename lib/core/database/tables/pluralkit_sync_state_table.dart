import 'package:drift/drift.dart';

class PluralKitSyncState extends Table {
  TextColumn get id => text()(); // always 'pk_config'
  TextColumn get systemId => text().nullable()();
  DateTimeColumn get lastSyncDate => dateTime().nullable()();
  DateTimeColumn get lastManualSyncDate => dateTime().nullable()();
  BoolColumn get isConnected =>
      boolean().withDefault(const Constant(false))();
  TextColumn get fieldSyncConfig => text().nullable()(); // JSON map of memberId → field config

  /// True once the user has completed (or explicitly dismissed) the member
  /// mapping flow for the current PK connection. While false, the connection
  /// is in `connected_pending_map` — auto-push and auto-sync are gated off.
  /// Reset to false on re-connect (new token).
  BoolColumn get mappingAcknowledged =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
