import 'package:drift/drift.dart';

/// Durable, resumable queue of media blobs waiting to upload to the relay
/// (durable media upload queue). Replaces the old in-memory `UploadQueue` that dropped
/// sends after 3 retries and lost everything on restart.
///
/// The encrypted bytes are stored in-row (`ciphertext`) rather than referenced
/// from the `.enc` cache, so a queued send survives app restart, reinstall, and
/// backup-restore (the `.enc` cache is backup-excluded). Rows are short-lived:
/// deleted on a successful (committed) upload. A row that exhausts its retries
/// moves to `state = 'terminal'` and is retained (never silently dropped) so it
/// can be surfaced or retried later.
@DataClassName('UploadQueueEntry')
class UploadQueueEntries extends Table {
  /// The blob's media id (relay `X-Media-Id`). One queue entry per blob.
  TextColumn get mediaId => text()();

  /// SHA-256 of the ciphertext (relay `X-Content-Hash`).
  TextColumn get contentHash => text()();

  /// The encrypted blob bytes to upload.
  BlobColumn get ciphertext => blob()();

  /// Optional short per-blob TTL (seconds) for the relay's re-supply variant.
  /// `null` ⇒ a normal fresh send ⇒ the relay's default retention.
  IntColumn get ttlSecs => integer().nullable()();

  /// Failed upload attempts so far. Drives the backoff schedule.
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// Unix epoch **milliseconds** the entry is next eligible to upload. `0`
  /// means "now". (Integer-ms, not DateTime, to avoid the seconds/ms decode
  /// trap this DB has been bitten by before.)
  IntColumn get nextAttemptAt => integer().withDefault(const Constant(0))();

  /// Unix epoch milliseconds the entry was first enqueued (FIFO ordering).
  IntColumn get createdAt => integer()();

  /// `pending` (eligible / backing off) or `terminal` (retries exhausted,
  /// retained for visibility / manual retry — never silently dropped).
  TextColumn get state => text().withDefault(const Constant('pending'))();

  /// Last upload error, for diagnostics / the terminal state.
  TextColumn get lastError => text().nullable()();

  @override
  String get tableName => 'upload_queue_entries';

  @override
  Set<Column> get primaryKey => {mediaId};
}
