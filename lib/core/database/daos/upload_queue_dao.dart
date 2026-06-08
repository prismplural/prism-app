import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/upload_queue_entries_table.dart';

part 'upload_queue_dao.g.dart';

/// Persistent store for the resumable media upload queue (upload queue).
@DriftAccessor(tables: [UploadQueueEntries])
class UploadQueueDao extends DatabaseAccessor<AppDatabase>
    with _$UploadQueueDaoMixin {
  UploadQueueDao(super.db);

  static const statePending = 'pending';
  static const stateTerminal = 'terminal';

  /// Enqueue (or re-enqueue) a blob. Idempotent on `mediaId`: a repeat enqueue
  /// of the same blob refreshes its bytes/TTL and resets it to a due `pending`
  /// state rather than creating a duplicate.
  Future<void> upsert({
    required String mediaId,
    required String contentHash,
    required Uint8List ciphertext,
    int? ttlSecs,
    required int createdAtMs,
  }) {
    return into(uploadQueueEntries).insertOnConflictUpdate(
      UploadQueueEntriesCompanion.insert(
        mediaId: mediaId,
        contentHash: contentHash,
        ciphertext: ciphertext,
        ttlSecs: Value(ttlSecs),
        createdAt: createdAtMs,
        attempts: const Value(0),
        nextAttemptAt: const Value(0),
        state: const Value(statePending),
        lastError: const Value(null),
      ),
    );
  }

  /// Pending rows due to run now (`nextAttemptAt <= nowMs`), oldest-enqueued
  /// first (FIFO).
  Future<List<UploadQueueEntry>> duePending(int nowMs) {
    return (select(uploadQueueEntries)
          ..where(
            (t) =>
                t.state.equals(statePending) &
                t.nextAttemptAt.isSmallerOrEqualValue(nowMs),
          )
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .get();
  }

  /// The earliest `nextAttemptAt` among pending rows not yet due — so the
  /// processor can schedule a wake instead of busy-polling. `null` if no
  /// pending rows are waiting in the future.
  Future<int?> earliestFutureAttempt(int nowMs) async {
    final row = await (select(uploadQueueEntries)
          ..where(
            (t) =>
                t.state.equals(statePending) &
                t.nextAttemptAt.isBiggerThanValue(nowMs),
          )
          ..orderBy([(t) => OrderingTerm(expression: t.nextAttemptAt)])
          ..limit(1))
        .getSingleOrNull();
    return row?.nextAttemptAt;
  }

  Future<UploadQueueEntry?> getById(String mediaId) {
    return (select(uploadQueueEntries)
          ..where((t) => t.mediaId.equals(mediaId)))
        .getSingleOrNull();
  }

  /// Remove a successfully-uploaded entry.
  Future<void> markCompleted(String mediaId) {
    return (delete(uploadQueueEntries)
          ..where((t) => t.mediaId.equals(mediaId)))
        .go();
  }

  /// Record a failed attempt and schedule the next retry.
  Future<void> recordFailure({
    required String mediaId,
    required int attempts,
    required int nextAttemptAtMs,
    required String error,
  }) {
    return (update(uploadQueueEntries)
          ..where((t) => t.mediaId.equals(mediaId)))
        .write(
          UploadQueueEntriesCompanion(
            attempts: Value(attempts),
            nextAttemptAt: Value(nextAttemptAtMs),
            lastError: Value(error),
          ),
        );
  }

  /// Retries exhausted — retain the row in a terminal state (never dropped).
  Future<void> markTerminal({
    required String mediaId,
    required int attempts,
    required String error,
  }) {
    return (update(uploadQueueEntries)
          ..where((t) => t.mediaId.equals(mediaId)))
        .write(
          UploadQueueEntriesCompanion(
            state: const Value(stateTerminal),
            attempts: Value(attempts),
            lastError: Value(error),
          ),
        );
  }

  Future<int> pendingCount() async {
    final row = await customSelect(
      "SELECT COUNT(*) AS c FROM upload_queue_entries WHERE state = 'pending'",
      readsFrom: {uploadQueueEntries},
    ).getSingle();
    return row.read<int>('c');
  }

  Future<int> terminalCount() async {
    final row = await customSelect(
      "SELECT COUNT(*) AS c FROM upload_queue_entries WHERE state = 'terminal'",
      readsFrom: {uploadQueueEntries},
    ).getSingle();
    return row.read<int>('c');
  }
}
