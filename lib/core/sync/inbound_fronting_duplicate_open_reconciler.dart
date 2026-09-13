import 'package:synchronized/synchronized.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/features/fronting/services/collapse_open_duplicate_sessions.dart';

/// Result of one inbound duplicate-open reconciliation pass.
class InboundFrontingDuplicateOpenReconcileResult {
  const InboundFrontingDuplicateOpenReconcileResult({
    required this.frontingTableTouched,
    required this.membersWithDuplicateOpens,
    required this.sessionsClosed,
  });

  const InboundFrontingDuplicateOpenReconcileResult.notNeeded()
    : frontingTableTouched = false,
      membersWithDuplicateOpens = 0,
      sessionsClosed = 0;

  final bool frontingTableTouched;
  final int membersWithDuplicateOpens;
  final int sessionsClosed;
}

/// Repairs duplicate open normal sessions after committed inbound sync.
class InboundFrontingDuplicateOpenReconciler {
  InboundFrontingDuplicateOpenReconciler(this._database, this._repository);

  final AppDatabase _database;
  final FrontingSessionRepository _repository;
  final Lock _lock = Lock();

  Future<InboundFrontingDuplicateOpenReconcileResult>
  reconcileAfterCommittedDelivery(Set<String> touchedTables) {
    if (!touchedTables.contains('fronting_sessions')) {
      return Future.value(
        const InboundFrontingDuplicateOpenReconcileResult.notNeeded(),
      );
    }

    return _lock.synchronized(() {
      // Keep scan, closes, and sync records atomic with local writers.
      return SyncRecordMixin.runSyncedDatabaseTransaction(_database, () async {
        final openByMember = <String, List<String>>{};
        for (final session in await _repository.getActiveSessions()) {
          final memberId = session.memberId;
          if (memberId == null || session.isSleep) continue;
          (openByMember[memberId] ??= <String>[]).add(session.id);
        }

        final duplicateMemberIds = [
          for (final entry in openByMember.entries)
            if (entry.value.length > 1) entry.key,
        ];
        if (duplicateMemberIds.isEmpty) {
          return const InboundFrontingDuplicateOpenReconcileResult(
            frontingTableTouched: true,
            membersWithDuplicateOpens: 0,
            sessionsClosed: 0,
          );
        }

        final closed = await collapseOpenDuplicateSessions(
          _repository,
          memberIds: duplicateMemberIds,
        );
        return InboundFrontingDuplicateOpenReconcileResult(
          frontingTableTouched: true,
          membersWithDuplicateOpens: duplicateMemberIds.length,
          sessionsClosed: closed.length,
        );
      });
    });
  }
}
