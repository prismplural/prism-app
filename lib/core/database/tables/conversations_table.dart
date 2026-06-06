import 'package:drift/drift.dart';

class Conversations extends Table {
  TextColumn get id => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get lastActivityAt => dateTime()();
  TextColumn get title => text().nullable()();
  TextColumn get emoji => text().nullable()();
  BoolColumn get isDirectMessage =>
      boolean().withDefault(const Constant(false))();
  TextColumn get creatorId => text().nullable()();
  TextColumn get participantIds =>
      text().withDefault(const Constant('[]'))(); // JSON list
  TextColumn get lastReadTimestamps =>
      text().withDefault(const Constant('{}'))(); // JSON map
  TextColumn get archivedByMemberIds =>
      text().withDefault(const Constant('[]'))(); // JSON list
  TextColumn get mutedByMemberIds =>
      text().withDefault(const Constant('[]'))(); // JSON list
  TextColumn get description => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  IntColumn get displayOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  // When true, every active member is implicitly a participant — no need
  // to list each in participantIds.
  BoolColumn get includesAllMembers =>
      boolean().withDefault(const Constant(false))();
  // Convo-level "archived for everyone" flag (vs per-member archivedByMemberIds).
  BoolColumn get archivedForEveryone =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
