import 'package:drift/drift.dart';

/// Stores [DateTime] as int milliseconds-since-epoch — Drift's default
/// `dateTime()` rounds to whole seconds and ties same-second messages on
/// the sort key. `fromSql` returns local-zone to match Drift's old read
/// behavior; chat UI reads `.hour`/`.day` directly without `.toLocal()`.
class ChatTimestampConverter extends TypeConverter<DateTime, int> {
  const ChatTimestampConverter();

  @override
  DateTime fromSql(int fromDb) => DateTime.fromMillisecondsSinceEpoch(fromDb);

  @override
  int toSql(DateTime value) => value.millisecondsSinceEpoch;
}

class ChatMessages extends Table {
  TextColumn get id => text()();
  TextColumn get content => text()();
  IntColumn get timestamp =>
      integer().map(const ChatTimestampConverter())();
  BoolColumn get isSystemMessage =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get editedAt => dateTime().nullable()();
  TextColumn get authorId => text().nullable()();
  TextColumn get conversationId => text()();
  TextColumn get reactions =>
      text().withDefault(const Constant('[]'))(); // JSON list
  TextColumn get replyToId => text().nullable()();
  TextColumn get replyToAuthorId => text().nullable()();
  TextColumn get replyToContent => text().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
