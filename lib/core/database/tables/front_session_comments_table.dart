import 'package:drift/drift.dart';

@DataClassName('FrontSessionCommentRow')
class FrontSessionComments extends Table {
  TextColumn get id => text()();
  // Legacy FK to fronting_sessions.  Kept in v7 as unread storage; dropped in
  // v8 cleanup via TableMigration rebuild.  All new reads/writes use
  // target_time instead (see below).
  TextColumn get sessionId => text()();
  TextColumn get body => text()();
  // Legacy "what time is this comment about" field.  In v7 this drives
  // target_time backfill during app-layer migration (§4.1 step 5).
  DateTimeColumn get timestamp => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  // -- Phase 1: per-member fronting refactor (docs/plans/fronting-per-member-sessions.md §3.5) --
  //
  // Comments attach to a timestamp, not a session.  A period's comment list
  // shows all comments whose target_time falls within the period range.
  //
  // Nullable in v7 because existing rows haven't been backfilled yet — the
  // app-layer migration (§4.1 step 5) writes target_time from the old
  // `timestamp` column for each preserved comment.  NOT NULL enforced in v8
  // cleanup once every row has been migrated.
  DateTimeColumn get targetTime => dateTime().nullable()();

  // Optional: who wrote this comment (member id).  Nullable — comments may
  // be anonymous or authored by the system (e.g., migration-generated notes).
  TextColumn get authorMemberId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
