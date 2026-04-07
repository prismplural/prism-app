import 'package:drift/drift.dart';

@DataClassName('FriendRow')
class Friends extends Table {
  TextColumn get id => text()();
  TextColumn get displayName => text()();
  TextColumn get peerSharingId => text().nullable()();
  BlobColumn get pairwiseSecret => blob().nullable()();
  BlobColumn get pinnedIdentity => blob().nullable()();

  /// JSON-encoded list of scope strings the peer offered us.
  TextColumn get offeredScopes => text().withDefault(const Constant('[]'))();
  TextColumn get publicKeyHex => text()();
  TextColumn get sharedSecretHex => text().nullable()();

  /// JSON-encoded list of granted scope strings.
  TextColumn get grantedScopes => text().withDefault(const Constant('[]'))();
  BoolColumn get isVerified => boolean().withDefault(const Constant(false))();
  TextColumn get initId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get establishedAt => dateTime().nullable()();
  DateTimeColumn get lastSyncAt => dateTime().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
