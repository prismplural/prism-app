import 'package:drift/drift.dart';

/// The persistent **missing-media set** (media heal): blobs this device
/// *references* (via a `media_attachments` row) but that are absent from its
/// local cache AND confirmed absent on the relay (batch-exists). The demand-
/// driven heal re-requests these from peers on a bounded cadence — on app
/// resume and each sync-pull cycle — with a per-media cooldown + backoff, and a
/// terminal-unavailable state after a long window (revivable if a holder later
/// returns).
///
/// This is **demand-gated, not a sweep**: an entry only ever exists for a blob
/// the device references and lacks. It is not claimed monotonically shrinking
/// (the referenced set grows as sync adds rows; terminal entries can revive).
///
/// Timestamps are Unix epoch **milliseconds** (integer, not DateTime) to avoid
/// the seconds/ms decode trap this DB has been bitten by before — matching
/// `upload_queue_entries`.
@DataClassName('MissingMediaEntry')
class MissingMediaEntries extends Table {
  /// The referenced+absent blob's media id. One entry per blob.
  TextColumn get mediaId => text()();

  /// Heal priority: `0` = profile / member images (heal first, tighter
  /// cooldown), `1` = chat-history images. So an avatar isn't a blurhash for
  /// days behind a 2019 photo.
  IntColumn get priority => integer().withDefault(const Constant(1))();

  /// Unix epoch ms this blob was first confirmed absent (added to the set).
  /// Basis for the terminal-unavailable cutoff. Preserved across re-confirmation
  /// so the terminal clock isn't reset by every cadence tick.
  IntColumn get firstMissingAt => integer()();

  /// Unix epoch ms of the last `media_request` broadcast for this blob, or null
  /// if never requested yet. Diagnostics / cooldown reference.
  IntColumn get lastRequestedAt => integer().nullable()();

  /// Re-request attempts so far. Drives the backoff schedule.
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// Unix epoch ms the entry is next eligible to be re-requested (`0` = now).
  /// The cooldown + backoff gate.
  IntColumn get nextEligibleAt => integer().withDefault(const Constant(0))();

  /// `pending` (awaiting a holder to come online) or `terminal` (unavailable
  /// after the long window — retained, never silently dropped, and revivable
  /// when a holder returns or the user taps "Request Missing Media").
  TextColumn get state => text().withDefault(const Constant('pending'))();

  @override
  String get tableName => 'missing_media';

  @override
  Set<Column> get primaryKey => {mediaId};
}
