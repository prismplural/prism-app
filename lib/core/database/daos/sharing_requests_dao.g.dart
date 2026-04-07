// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sharing_requests_dao.dart';

// ignore_for_file: type=lint
mixin _$SharingRequestsDaoMixin on DatabaseAccessor<AppDatabase> {
  $SharingRequestsTable get sharingRequests => attachedDatabase.sharingRequests;
  SharingRequestsDaoManager get managers => SharingRequestsDaoManager(this);
}

class SharingRequestsDaoManager {
  final _$SharingRequestsDaoMixin _db;
  SharingRequestsDaoManager(this._db);
  $$SharingRequestsTableTableManager get sharingRequests =>
      $$SharingRequestsTableTableManager(
        _db.attachedDatabase,
        _db.sharingRequests,
      );
}
