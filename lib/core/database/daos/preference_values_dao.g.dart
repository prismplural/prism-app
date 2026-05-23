// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'preference_values_dao.dart';

// ignore_for_file: type=lint
mixin _$PreferenceValuesDaoMixin on DatabaseAccessor<AppDatabase> {
  $AppPreferenceValuesTable get appPreferenceValues =>
      attachedDatabase.appPreferenceValues;
  $MemberProfilePreferenceValuesTable get memberProfilePreferenceValues =>
      attachedDatabase.memberProfilePreferenceValues;
  $MembersTable get members => attachedDatabase.members;
  PreferenceValuesDaoManager get managers => PreferenceValuesDaoManager(this);
}

class PreferenceValuesDaoManager {
  final _$PreferenceValuesDaoMixin _db;
  PreferenceValuesDaoManager(this._db);
  $$AppPreferenceValuesTableTableManager get appPreferenceValues =>
      $$AppPreferenceValuesTableTableManager(
        _db.attachedDatabase,
        _db.appPreferenceValues,
      );
  $$MemberProfilePreferenceValuesTableTableManager
  get memberProfilePreferenceValues =>
      $$MemberProfilePreferenceValuesTableTableManager(
        _db.attachedDatabase,
        _db.memberProfilePreferenceValues,
      );
  $$MembersTableTableManager get members =>
      $$MembersTableTableManager(_db.attachedDatabase, _db.members);
}
