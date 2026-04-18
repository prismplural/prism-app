import 'package:drift/drift.dart';

/// Per-decision state for the PK member mapping flow (plan 08 Phase 1+).
///
/// Each row represents one user-made mapping decision (link an existing local
/// member to a PK member, import a PK member as new, push a local member to
/// PK, or skip). The table backs the resumable, idempotent applier — rows
/// move from `pending` to `applied` (or `failed`) so a mid-Apply interruption
/// can resume without re-doing completed work.
class PkMappingState extends Table {
  /// Deterministic decision ID — stable across retries so the applier can
  /// resume. Typically derived from the target (e.g. `link:<pkUuid>`).
  TextColumn get id => text()();

  /// One of: `link`, `import`, `push`, `skip`.
  TextColumn get decisionType => text()();

  /// PK short 5-char member ID, if known.
  TextColumn get pkMemberId => text().nullable()();

  /// PK member UUID, if known.
  TextColumn get pkMemberUuid => text().nullable()();

  /// Local Prism member ID, if the decision touches an existing local member.
  TextColumn get localMemberId => text().nullable()();

  /// Lifecycle: `pending` | `applied` | `failed` | `rejected`.
  TextColumn get status => text().withDefault(const Constant('pending'))();

  /// Populated when `status == 'failed'` so the UI can surface per-item errors.
  TextColumn get errorMessage => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
