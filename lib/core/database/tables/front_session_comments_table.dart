import 'package:drift/drift.dart';

@DataClassName('FrontSessionCommentRow')
class FrontSessionComments extends Table {
  TextColumn get id => text()();
  // Legacy FK to fronting_sessions. Kept as unread storage in the
  // current schema; the planned cleanup migration drops it via a
  // TableMigration rebuild. All new reads/writes use target_time
  // instead (see below).
  TextColumn get sessionId => text()();
  TextColumn get body => text()();
  // Legacy "what time is this comment about" field. Drives target_time
  // backfill during the app-layer migration (§4.1 step 5).
  DateTimeColumn get timestamp => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  // Per-member fronting refactor (docs/plans/fronting-per-member-sessions.md §3.5):
  //
  // Comments attach to a timestamp, not a session. A period's comment
  // list shows all comments whose target_time falls within the period
  // range.
  //
  // Nullable until the app-layer migration backfills existing rows from
  // the legacy `timestamp` column. The schema cleanup will enforce
  // NOT NULL once every row has been migrated.
  DateTimeColumn get targetTime => dateTime().nullable()();

  // Optional: who wrote this comment (member id).  Nullable — comments may
  // be anonymous or authored by the system (e.g., migration-generated notes).
  TextColumn get authorMemberId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
