import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/upload_queue_entries_table.dart';

part 'upload_queue_dao.g.dart';

/// Lightweight projection of a due upload-queue row — everything needed to
/// drive an upload EXCEPT the (potentially multi-MiB) ciphertext, which is
/// loaded per-row just before upload via [UploadQueueDao.loadCiphertext].
class UploadQueueDue {
  final String mediaId;
  final String contentHash;
  final int? ttlSecs;
  final int attempts;

  const UploadQueueDue({
    required this.mediaId,
    required this.contentHash,
    required this.ttlSecs,
    required this.attempts,
  });
}

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

  /// Metadata for pending rows due to run now (`nextAttemptAt <= nowMs`),
  /// oldest-enqueued first (FIFO). Deliberately does NOT select the `ciphertext`
  /// BLOB: a backlog of due rows would otherwise materialise hundreds of MiB at
  /// once. The bytes are loaded per-row via [loadCiphertext] immediately before
  /// upload.
  Future<List<UploadQueueDue>> duePending(int nowMs) async {
    final q = selectOnly(uploadQueueEntries)
      ..addColumns([
        uploadQueueEntries.mediaId,
        uploadQueueEntries.contentHash,
        uploadQueueEntries.ttlSecs,
        uploadQueueEntries.attempts,
      ])
      ..where(
        uploadQueueEntries.state.equals(statePending) &
            uploadQueueEntries.nextAttemptAt.isSmallerOrEqualValue(nowMs),
      )
      ..orderBy([OrderingTerm(expression: uploadQueueEntries.createdAt)]);
    final rows = await q.get();
    return rows
        .map(
          (r) => UploadQueueDue(
            mediaId: r.read(uploadQueueEntries.mediaId)!,
            contentHash: r.read(uploadQueueEntries.contentHash)!,
            ttlSecs: r.read(uploadQueueEntries.ttlSecs),
            attempts: r.read(uploadQueueEntries.attempts)!,
          ),
        )
        .toList();
  }

  /// Load just the ciphertext bytes for one entry (or `null` if it's gone).
  Future<Uint8List?> loadCiphertext(String mediaId) async {
    final q = selectOnly(uploadQueueEntries)
      ..addColumns([uploadQueueEntries.ciphertext])
      ..where(uploadQueueEntries.mediaId.equals(mediaId))
      ..limit(1);
    final row = await q.getSingleOrNull();
    return row?.read(uploadQueueEntries.ciphertext);
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

  /// Retries exhausted — retain a metadata tombstone in a terminal state (the
  /// row is never silently dropped) but DROP the ciphertext bytes so a stream of
  /// failed sends can't grow the encrypted DB without bound. A future "retry
  /// failed sends" UI would re-derive bytes from the source, not this row.
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
            ciphertext: Value(Uint8List(0)),
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
