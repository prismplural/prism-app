import 'package:drift/drift.dart';

class FrontingSessions extends Table {
  TextColumn get id => text()();
  IntColumn get sessionType => integer().withDefault(const Constant(0))();
  DateTimeColumn get startTime => dateTime()();
  DateTimeColumn get endTime => dateTime().nullable()();
  TextColumn get memberId => text().nullable()();
  TextColumn get coFronterIds =>
      text().withDefault(const Constant('[]'))(); // JSON list
  TextColumn get notes => text().nullable()();
  IntColumn get confidence => integer().nullable()(); // enum index
  IntColumn get quality => integer().nullable()();
  BoolColumn get isHealthKitImport =>
      boolean().withDefault(const Constant(false))();
  // PluralKit fields
  TextColumn get pluralkitUuid => text().nullable()();
  TextColumn get pkImportSource => text().nullable()();
  TextColumn get pkFileSwitchId => text().nullable()();
  // JSON list of PK short member IDs from the original switch. Lets us
  // re-attribute local memberId / coFronterIds after a later link without
  // re-fetching from PK.
  TextColumn get pkMemberIdsJson => text().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  // -- Plan 02 (PK deletion push) -- see members_table.dart for rationale.
  IntColumn get deleteIntentEpoch => integer().nullable()();
  IntColumn get deletePushStartedAt => integer().nullable()();

  // Per-member fronting refactor (docs/plans/fronting-per-member-sessions.md
  // §2.1, §4.1): a normal session row (session_type = 0) MUST point at a
  // real member_id. Sleep rows (session_type = 1) legitimately have no
  // fronter and continue to allow null. Fresh installs at v14+ get this
  // constraint at `createAll()` time; existing databases pick it up via
  // `ensureFrontingMemberCheckConstraint()` once the per-member migration
  // marks itself complete.
  @override
  List<String> get customConstraints => const [
    'CHECK (session_type != 0 OR member_id IS NOT NULL)',
  ];

  @override
  Set<Column> get primaryKey => {id};
}
