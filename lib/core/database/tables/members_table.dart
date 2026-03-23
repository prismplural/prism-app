import 'package:drift/drift.dart';

class Members extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get pronouns => text().nullable()();
  TextColumn get emoji => text().withDefault(const Constant('❔'))();
  IntColumn get age => integer().nullable()();
  TextColumn get bio => text().nullable()();
  BlobColumn get avatarImageData => blob().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get displayOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isAdmin => boolean().withDefault(const Constant(false))();
  BoolColumn get customColorEnabled =>
      boolean().withDefault(const Constant(false))();
  TextColumn get customColorHex => text().nullable()();
  TextColumn get parentSystemId => text().nullable()();
  // PluralKit fields
  TextColumn get pluralkitUuid => text().nullable()();
  TextColumn get pluralkitId => text().nullable()();
  BoolColumn get markdownEnabled =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
