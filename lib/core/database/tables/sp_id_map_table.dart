import 'package:drift/drift.dart';

@DataClassName('SpIdMapRow')
class SpIdMapTable extends Table {
  TextColumn get spId => text()(); // SP entity _id
  TextColumn get entityType => text()(); // 'member', 'channel', 'session', etc.
  TextColumn get prismId => text()(); // Prism UUID

  @override
  String get tableName => 'sp_id_map';

  @override
  Set<Column> get primaryKey => {spId, entityType};
}
