import 'package:drift/drift.dart';

@DataClassName('MemberGroupEntryRow')
class MemberGroupEntries extends Table {
  TextColumn get id => text()();
  TextColumn get groupId => text()();
  TextColumn get memberId => text()();
  TextColumn get pkGroupUuid => text().nullable()();
  TextColumn get pkMemberUuid => text().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  // Local-only push intent for PluralKit bidirectional group membership sync.
  // Stored as a string ('none' | 'push_add' | 'push_remove') because Drift's
  // textEnum() generates an extra import; bare text + repository-side parsing
  // matches existing enum-as-string columns (e.g. pendingFrontingMigrationMode).
  // NOT in prismSyncSchema — push intent is per-device and never crosses Prism's
  // own CRDT sync. See docs/plans/pk-group-membership-push.md.
  TextColumn get pendingPkOp =>
      text().withDefault(const Constant('none')).clientDefault(() => 'none')();

  @override
  Set<Column> get primaryKey => {id};
}
