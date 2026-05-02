import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/member_board_posts_dao.dart';
import 'package:prism_plurality/domain/models/member_board_post.dart';
import 'package:prism_plurality/domain/repositories/member_board_posts_repository.dart';
import 'package:prism_plurality/domain/repositories/system_settings_repository.dart';

/// UUID v5 namespace for the SP boards backfill.
///
/// Two devices running the backfill independently will produce identical IDs
/// for the same (targetMemberId, authorId, writtenAt, bodyHash) tuple, so
/// CRDT entity-id merge deduplicates them without a secondary tuple check.
const boardsBackfillNamespace = '6f2c3a4b-8e1d-4c5a-9f7b-1a2b3c4d5e6f';

/// Result returned by [SpBoardsBackfillService.run].
class SpBoardsBackfillResult {
  const SpBoardsBackfillResult({
    required this.postsConverted,
    required this.abortedByPeer,
  });

  /// Number of board posts inserted during this run.
  final int postsConverted;

  /// True when the sentinel arbitration detected a peer already completed the
  /// backfill (HLC clock ordering). The caller should treat this as success.
  final bool abortedByPeer;
}

/// One-time, idempotent service that converts the synthetic board-message
/// DM conversations (created by the old SP importer) into first-class
/// [MemberBoardPost] rows.
///
/// **Backfill algorithm (LOCKED — Subplan F)**
///
/// 1. Write a sentinel `spBoardsBackfilledAt = now()`. Re-read to confirm;
///    if a peer already wrote an earlier timestamp via HLC arbitration, abort.
/// 2. Identify candidate conversations:
///    `is_direct_message = true AND emoji = '📝' AND json_array_length(participant_ids) <= 2
///     AND last_activity_at < sentinel`.
/// 3. For each candidate, in a single Drift transaction:
///    - For each chat_messages row in the conversation:
///      - Derive `targetMemberId`, parse optional title, compute body hash.
///      - Compute deterministic UUID v5 from
///        `(targetMemberId, authorId, writtenAt.ms, sha256(body))` using
///        [boardsBackfillNamespace].
///      - Skip if post already exists (by ID or dedup-tuple).
///      - Insert via [MemberBoardPostsRepository.createPost].
/// 4. Skip tombstoning the synthetic DM conversations (parallel chat-fix).
/// 5. On success, write the actual completion time.
class SpBoardsBackfillService {
  static const _uuid = Uuid();

  SpBoardsBackfillService({
    required AppDatabase db,
    required MemberBoardPostsRepository boardPostsRepo,
    required MemberBoardPostsDao boardPostsDao,
    required SystemSettingsRepository settingsRepo,
  })  : _db = db,
        _boardPostsRepo = boardPostsRepo,
        _boardPostsDao = boardPostsDao,
        _settingsRepo = settingsRepo;

  final AppDatabase _db;
  final MemberBoardPostsRepository _boardPostsRepo;
  final MemberBoardPostsDao _boardPostsDao;
  final SystemSettingsRepository _settingsRepo;

  /// Run the backfill once.
  ///
  /// Returns immediately if [SystemSettings.spBoardsBackfilledAt] is already
  /// set (the sentinel from a peer or a prior run). The caller is responsible
  /// for gating on `spBoardsBackfilledAt == null` before calling this.
  Future<SpBoardsBackfillResult> run() async {
    // --- Step 1: Sentinel write -----------------------------------------------
    // Write a provisional completion timestamp before touching any rows.
    // This is advisory: on a two-device scenario both devices may write
    // near-simultaneously, but the deterministic UUID v5 IDs mean inserts
    // converge via entity-id LWW merge on the CRDT layer.
    final sentinelTime = DateTime.now().toUtc();
    await _settingsRepo.updateSpBoardsBackfilledAt(sentinelTime);

    // Re-read after write. If a peer already wrote an earlier HLC timestamp
    // (which will win via LWW field arbitration), abort to avoid racing.
    final afterSentinel = await _settingsRepo.getSettings();
    final confirmedSentinel = afterSentinel.spBoardsBackfilledAt;
    if (confirmedSentinel != null &&
        confirmedSentinel.isBefore(sentinelTime.subtract(
          const Duration(seconds: 2),
        ))) {
      // A peer set the sentinel at a strictly earlier moment — it owns this run.
      debugPrint(
        '[BOARDS_BACKFILL] Peer sentinel detected '
        '($confirmedSentinel < $sentinelTime) — aborting.',
      );
      return const SpBoardsBackfillResult(postsConverted: 0, abortedByPeer: true);
    }

    // --- Step 2: Identify candidates ------------------------------------------
    // Candidate heuristic: synthetic board-message DMs created by the old importer.
    // They are is_direct_message=true, emoji='📝', ≤2 participants, and their
    // last_activity_at is before the sentinel (i.e. they are not still-active DMs).
    final candidates = await _db.customSelect(
      '''
      SELECT id, participant_ids, last_activity_at
      FROM conversations
      WHERE is_direct_message = 1
        AND emoji = ?
        AND json_array_length(participant_ids) <= 2
        AND last_activity_at < ?
        AND is_deleted = 0
      ''',
      variables: [
        Variable.withString('\u{1F4DD}'), // 📝
        Variable.withDateTime(sentinelTime),
      ],
    ).get();

    if (candidates.isEmpty) {
      debugPrint('[BOARDS_BACKFILL] No candidate conversations found.');
      final completionTime = DateTime.now().toUtc();
      await _settingsRepo.updateSpBoardsBackfilledAt(completionTime);
      return const SpBoardsBackfillResult(postsConverted: 0, abortedByPeer: false);
    }

    debugPrint(
      '[BOARDS_BACKFILL] Found ${candidates.length} candidate conversation(s).',
    );

    // --- Step 3: Convert each candidate ---------------------------------------
    var totalInserted = 0;

    for (final candidate in candidates) {
      final convId = candidate.read<String>('id');
      final participantIdsJson = candidate.read<String>('participant_ids');
      final participantIds = List<String>.from(
        (jsonDecode(participantIdsJson) as List),
      );

      final messages = await _db.customSelect(
        '''
        SELECT id, content, timestamp, author_id
        FROM chat_messages
        WHERE conversation_id = ?
          AND is_deleted = 0
        ORDER BY timestamp ASC
        ''',
        variables: [Variable.withString(convId)],
      ).get();

      if (messages.isEmpty) continue;

      var insertedInConv = 0;

      await _db.transaction(() async {
        for (final msg in messages) {
          final rawContent = msg.read<String>('content');
          final authorId = msg.readNullable<String>('author_id');
          // Drift stores DateTimeColumn as Unix SECONDS by default; reading via
          // `read<DateTime>` lets the typeMapping do the conversion correctly.
          final writtenAt = msg.read<DateTime>('timestamp');

          // Determine targetMemberId: the participant who is NOT the author.
          // Fall back to the first participant when author is unknown or
          // this is a self-post.
          final targetMemberId = participantIds.firstWhere(
            (p) => p != authorId,
            orElse: () => participantIds.first,
          );

          // Parse optional title from "**title**\n…" body prefix.
          String? title;
          String body;
          final boldTitlePattern = RegExp(r'^\*\*(.+?)\*\*\n([\s\S]*)$');
          final match = boldTitlePattern.firstMatch(rawContent);
          if (match != null) {
            title = match.group(1);
            body = match.group(2) ?? '';
          } else {
            body = rawContent;
          }

          // Compute dedup tuple hash.
          final bodyHash = sha256
              .convert(utf8.encode(body))
              .toString();

          // Compute deterministic UUID v5 so two-device backfills produce
          // identical IDs and CRDT entity-id merge deduplicates naturally.
          final deterministicId = _uuid.v5(
            boardsBackfillNamespace,
            '$targetMemberId|${authorId ?? ''}|${writtenAt.millisecondsSinceEpoch}|$bodyHash',
          );

          // Skip if already exists by deterministic ID.
          final existingById = await _boardPostsDao.getPostById(deterministicId);
          if (existingById != null) continue;

          // Also skip by dedup tuple (handles posts inserted with different IDs).
          final existingByTuple = await _boardPostsDao.findByDedupTuple(
            targetMemberId: targetMemberId,
            authorId: authorId,
            writtenAt: writtenAt,
          );
          if (existingByTuple != null) continue;

          // Insert the new board post.
          final post = MemberBoardPost(
            id: deterministicId,
            targetMemberId: targetMemberId,
            authorId: authorId,
            audience: 'private',
            title: title?.isEmpty == true ? null : title,
            body: body,
            createdAt: writtenAt,
            writtenAt: writtenAt,
            isDeleted: false,
          );

          await _boardPostsRepo.createPost(post);
          insertedInConv++;
        }
      });

      totalInserted += insertedInConv;
    }

    debugPrint('[BOARDS_BACKFILL] Inserted $totalInserted post(s).');

    // --- Step 5: Write final completion timestamp -----------------------------
    // Overwrites the sentinel with the actual completion time.
    final completionTime = DateTime.now().toUtc();
    await _settingsRepo.updateSpBoardsBackfilledAt(completionTime);

    return SpBoardsBackfillResult(
      postsConverted: totalInserted,
      abortedByPeer: false,
    );
  }

  /// Compute the deterministic UUID v5 for a given backfill input tuple.
  ///
  /// Exposed as a static helper so G2's tests can assert a known fixture
  /// produces a known ID without constructing a full service instance.
  static String computeDeterministicId({
    required String targetMemberId,
    required String? authorId,
    required DateTime writtenAt,
    required String bodyHash,
  }) {
    const uuid = Uuid();
    return uuid.v5(
      boardsBackfillNamespace,
      '$targetMemberId|${authorId ?? ''}|${writtenAt.millisecondsSinceEpoch}|$bodyHash',
    );
  }
}
