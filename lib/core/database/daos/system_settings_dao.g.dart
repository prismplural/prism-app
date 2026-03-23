// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'system_settings_dao.dart';

// ignore_for_file: type=lint
mixin _$SystemSettingsDaoMixin on DatabaseAccessor<AppDatabase> {
  $SystemSettingsTableTable get systemSettingsTable =>
      attachedDatabase.systemSettingsTable;
  SystemSettingsDaoManager get managers => SystemSettingsDaoManager(this);
}

class SystemSettingsDaoManager {
  final _$SystemSettingsDaoMixin _db;
  SystemSettingsDaoManager(this._db);
  $$SystemSettingsTableTableTableManager get systemSettingsTable =>
      $$SystemSettingsTableTableTableManager(
        _db.attachedDatabase,
        _db.systemSettingsTable,
      );
}
