import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/missing_media_entries_table.dart';

part 'missing_media_dao.g.dart';

/// A missing-media entry that is due to be re-requested now. Carries just what
/// the cadence needs to decide whether to broadcast a `media_request` (or move
/// the entry to terminal) — not a full row.
class MissingMediaDue {
  const MissingMediaDue({
    required this.mediaId,
    required this.priority,
    required this.attempts,
    required this.firstMissingAt,
  });

  final String mediaId;
  final int priority;
  final int attempts;
  final int firstMissingAt;
}

/// Persistent store for the demand-driven heal's missing-media set (media heal).
@DriftAccessor(tables: [MissingMediaEntries])
class MissingMediaDao extends DatabaseAccessor<AppDatabase>
    with _$MissingMediaDaoMixin {
  MissingMediaDao(super.db);

  static const statePending = 'pending';
  static const stateTerminal = 'terminal';

  /// Profile / member images — heal first.
  static const priorityProfile = 0;

  /// Chat-history images — heal after profile images.
  static const priorityChat = 1;

  /// Record `mediaId` as referenced-and-absent. Idempotent: a repeat call for an
  /// existing entry does NOT reset its terminal clock / cooldown / attempts — it
  /// only *lowers* the priority if the blob is now referenced in a
  /// higher-priority context. A brand-new entry starts `pending`, immediately
  /// eligible (`nextEligibleAt = 0`), with `firstMissingAt = nowMs`.
  Future<void> markMissing({
    required String mediaId,
    required int priority,
    required int nowMs,
  }) {
    return customStatement(
      'INSERT INTO missing_media '
      '(media_id, priority, first_missing_at, attempts, next_eligible_at, state) '
      'VALUES (?, ?, ?, 0, 0, ?) '
      'ON CONFLICT(media_id) DO UPDATE SET priority = MIN(priority, excluded.priority)',
      [mediaId, priority, nowMs, statePending],
    );
  }

  /// Every pending entry's media id — the input to the coalesced batch-exists
  /// the cadence runs over the whole set (one chunked call, not one per blob).
  Future<List<String>> pendingMediaIds() async {
    final q = selectOnly(missingMediaEntries)
      ..addColumns([missingMediaEntries.mediaId])
      ..where(missingMediaEntries.state.equals(statePending));
    final rows = await q.get();
    return rows.map((r) => r.read(missingMediaEntries.mediaId)!).toList();
  }

  /// Pending entries due to re-request now (`nextEligibleAt <= nowMs`), highest
  /// priority first (profile/member ahead of chat), then oldest-eligible.
  Future<List<MissingMediaDue>> dueForRequest(int nowMs, {int? limit}) async {
    final q = selectOnly(missingMediaEntries)
      ..addColumns([
        missingMediaEntries.mediaId,
        missingMediaEntries.priority,
        missingMediaEntries.attempts,
        missingMediaEntries.firstMissingAt,
      ])
      ..where(
        missingMediaEntries.state.equals(statePending) &
            missingMediaEntries.nextEligibleAt.isSmallerOrEqualValue(nowMs),
      )
      ..orderBy([
        OrderingTerm(expression: missingMediaEntries.priority),
        OrderingTerm(expression: missingMediaEntries.nextEligibleAt),
      ]);
    if (limit != null) q.limit(limit);
    final rows = await q.get();
    return rows
        .map(
          (r) => MissingMediaDue(
            mediaId: r.read(missingMediaEntries.mediaId)!,
            priority: r.read(missingMediaEntries.priority)!,
            attempts: r.read(missingMediaEntries.attempts)!,
            firstMissingAt: r.read(missingMediaEntries.firstMissingAt)!,
          ),
        )
        .toList();
  }

  /// Record that a `media_request` was just broadcast for `mediaId`: bump
  /// attempts, stamp `lastRequestedAt`, and gate the next attempt.
  Future<void> recordRequested({
    required String mediaId,
    required int attempts,
    required int nextEligibleAtMs,
    required int nowMs,
  }) {
    return (update(missingMediaEntries)
          ..where((t) => t.mediaId.equals(mediaId)))
        .write(
          MissingMediaEntriesCompanion(
            attempts: Value(attempts),
            lastRequestedAt: Value(nowMs),
            nextEligibleAt: Value(nextEligibleAtMs),
          ),
        );
  }

  /// Move an entry to terminal-unavailable (the long window elapsed with no
  /// holder). Retained, never dropped, and revivable via [requestAllNow].
  Future<void> markTerminal(String mediaId) {
    return (update(missingMediaEntries)
          ..where((t) => t.mediaId.equals(mediaId)))
        .write(const MissingMediaEntriesCompanion(state: Value(stateTerminal)));
  }

  /// Remove an entry — the blob healed (cached) or the relay now holds it
  /// (a holder returned). The heal succeeded; it is no longer "missing".
  Future<void> remove(String mediaId) {
    return (delete(missingMediaEntries)..where((t) => t.mediaId.equals(mediaId)))
        .go();
  }

  /// Re-arm every entry (pending AND terminal) for an immediate, fresh retry —
  /// the user-initiated "Request Missing Media" action and terminal revival.
  /// Resets `firstMissingAt` (restarts the terminal clock) and `attempts` so a
  /// long-terminal blob actually gets a request broadcast instead of being
  /// immediately re-terminalized by the next cadence.
  Future<void> requestAllNow(int nowMs) {
    return (update(missingMediaEntries)).write(
      MissingMediaEntriesCompanion(
        state: const Value(statePending),
        nextEligibleAt: const Value(0),
        attempts: const Value(0),
        firstMissingAt: Value(nowMs),
      ),
    );
  }

  Future<MissingMediaEntry?> getById(String mediaId) {
    return (select(missingMediaEntries)
          ..where((t) => t.mediaId.equals(mediaId)))
        .getSingleOrNull();
  }

  /// Count of entries still awaiting a holder (`pending`).
  Future<int> pendingCount() async {
    final row = await customSelect(
      "SELECT COUNT(*) AS c FROM missing_media WHERE state = 'pending'",
      readsFrom: {missingMediaEntries},
    ).getSingle();
    return row.read<int>('c');
  }

  /// Count of entries judged terminal-unavailable.
  Future<int> terminalCount() async {
    final row = await customSelect(
      "SELECT COUNT(*) AS c FROM missing_media WHERE state = 'terminal'",
      readsFrom: {missingMediaEntries},
    ).getSingle();
    return row.read<int>('c');
  }
}
