import 'package:drift/drift.dart';

@DataClassName('SharingRequestRow')
class SharingRequests extends Table {
  TextColumn get initId => text()();
  TextColumn get senderSharingId => text()();
  TextColumn get displayName => text()();

  /// JSON-encoded list of offered scope strings.
  TextColumn get offeredScopes => text().withDefault(const Constant('[]'))();
  BlobColumn get senderIdentity => blob().nullable()();
  BlobColumn get pairwiseSecret => blob().nullable()();
  TextColumn get fingerprint => text().nullable()();
  TextColumn get trustDecision => text()();
  TextColumn get errorMessage => text().nullable()();
  BoolColumn get isResolved => boolean().withDefault(const Constant(false))();
  DateTimeColumn get receivedAt => dateTime()();
  DateTimeColumn get resolvedAt => dateTime().nullable()();

  @override
  String get tableName => 'sharing_requests';

  @override
  Set<Column> get primaryKey => {initId};
}
