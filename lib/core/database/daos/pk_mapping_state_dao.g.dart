// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pk_mapping_state_dao.dart';

// ignore_for_file: type=lint
mixin _$PkMappingStateDaoMixin on DatabaseAccessor<AppDatabase> {
  $PkMappingStateTable get pkMappingState => attachedDatabase.pkMappingState;
  PkMappingStateDaoManager get managers => PkMappingStateDaoManager(this);
}

class PkMappingStateDaoManager {
  final _$PkMappingStateDaoMixin _db;
  PkMappingStateDaoManager(this._db);
  $$PkMappingStateTableTableManager get pkMappingState =>
      $$PkMappingStateTableTableManager(
        _db.attachedDatabase,
        _db.pkMappingState,
      );
}
