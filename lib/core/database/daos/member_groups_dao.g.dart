// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'member_groups_dao.dart';

// ignore_for_file: type=lint
mixin _$MemberGroupsDaoMixin on DatabaseAccessor<AppDatabase> {
  $MemberGroupsTable get memberGroups => attachedDatabase.memberGroups;
  $MemberGroupEntriesTable get memberGroupEntries =>
      attachedDatabase.memberGroupEntries;
  MemberGroupsDaoManager get managers => MemberGroupsDaoManager(this);
}

class MemberGroupsDaoManager {
  final _$MemberGroupsDaoMixin _db;
  MemberGroupsDaoManager(this._db);
  $$MemberGroupsTableTableManager get memberGroups =>
      $$MemberGroupsTableTableManager(_db.attachedDatabase, _db.memberGroups);
  $$MemberGroupEntriesTableTableManager get memberGroupEntries =>
      $$MemberGroupEntriesTableTableManager(
        _db.attachedDatabase,
        _db.memberGroupEntries,
      );
}
