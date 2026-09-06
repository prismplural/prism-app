import 'package:drift/drift.dart';

/// Imported interchange records and opaque data retained for re-export.
/// Payloads are immutable, bounded chunks; a complete document is verified by
/// its digest before use, including when chunks arrive separately over sync.
@DataClassName('PluralPortUnsupportedRow')
class PluralPortUnsupported extends Table {
  TextColumn get id => text()();
  TextColumn get documentId => text()();
  IntColumn get chunkIndex => integer()();
  IntColumn get chunkCount => integer()();
  TextColumn get payload => text()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
