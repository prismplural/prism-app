// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'custom_fields_dao.dart';

// ignore_for_file: type=lint
mixin _$CustomFieldsDaoMixin on DatabaseAccessor<AppDatabase> {
  $CustomFieldsTable get customFields => attachedDatabase.customFields;
  $CustomFieldValuesTable get customFieldValues =>
      attachedDatabase.customFieldValues;
  CustomFieldsDaoManager get managers => CustomFieldsDaoManager(this);
}

class CustomFieldsDaoManager {
  final _$CustomFieldsDaoMixin _db;
  CustomFieldsDaoManager(this._db);
  $$CustomFieldsTableTableManager get customFields =>
      $$CustomFieldsTableTableManager(_db.attachedDatabase, _db.customFields);
  $$CustomFieldValuesTableTableManager get customFieldValues =>
      $$CustomFieldValuesTableTableManager(
        _db.attachedDatabase,
        _db.customFieldValues,
      );
}
