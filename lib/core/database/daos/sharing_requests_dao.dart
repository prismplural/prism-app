import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/sharing_requests_table.dart';

part 'sharing_requests_dao.g.dart';

@DriftAccessor(tables: [SharingRequests])
class SharingRequestsDao extends DatabaseAccessor<AppDatabase>
    with _$SharingRequestsDaoMixin {
  SharingRequestsDao(super.db);

  Stream<List<SharingRequestRow>> watchPending() =>
      (select(sharingRequests)
            ..where((t) => t.isResolved.equals(false))
            ..orderBy([(t) => OrderingTerm.desc(t.receivedAt)]))
          .watch();

  Future<List<SharingRequestRow>> getAll() => (select(
    sharingRequests,
  )..orderBy([(t) => OrderingTerm.desc(t.receivedAt)])).get();

  Future<SharingRequestRow?> getByInitId(String initId) => (select(
    sharingRequests,
  )..where((t) => t.initId.equals(initId))).getSingleOrNull();

  Future<void> upsertRequest(SharingRequestsCompanion request) =>
      into(sharingRequests).insertOnConflictUpdate(request);

  Future<void> markResolved(String initId) =>
      (update(sharingRequests)..where((t) => t.initId.equals(initId))).write(
        SharingRequestsCompanion(
          isResolved: const Value(true),
          resolvedAt: Value(DateTime.now()),
        ),
      );

  Future<void> deleteByInitId(String initId) =>
      (delete(sharingRequests)..where((t) => t.initId.equals(initId))).go();
}
