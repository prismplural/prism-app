import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    show AppDatabase, MediaAttachmentsCompanion, PluralKitSyncStateCompanion;
import 'package:prism_plurality/core/database/daos/pluralkit_sync_dao.dart';
import 'package:prism_plurality/core/database/sqlite_constraint.dart';
import 'package:uuid/uuid.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/domain/repositories/chat_message_repository.dart';
import 'package:prism_plurality/domain/repositories/conversation_repository.dart';
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/domain/repositories/habit_repository.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/domain/repositories/poll_repository.dart';
import 'package:prism_plurality/domain/repositories/system_settings_repository.dart';
import 'package:prism_plurality/domain/repositories/member_groups_repository.dart';
import 'package:prism_plurality/domain/repositories/custom_fields_repository.dart';
import 'package:prism_plurality/domain/repositories/notes_repository.dart';
import 'package:prism_plurality/domain/repositories/front_session_comments_repository.dart';
import 'package:prism_plurality/domain/repositories/conversation_categories_repository.dart';
import 'package:prism_plurality/domain/repositories/reminders_repository.dart';
import 'package:prism_plurality/domain/repositories/friends_repository.dart';
import 'package:prism_plurality/features/data_management/models/export_models.dart';
import 'package:prism_plurality/features/data_management/services/export_crypto.dart';

/// Preview of what an import file contains, without actually importing.
class ImportPreview {
  const ImportPreview({
    this.headmates = 0,
    this.frontSessions = 0,
    this.sleepSessions = 0,
    this.conversations = 0,
    this.messages = 0,
    this.polls = 0,
    this.pollOptions = 0,
    this.systemSettings = 0,
    this.habits = 0,
    this.habitCompletions = 0,
    this.memberGroups = 0,
    this.memberGroupEntries = 0,
    this.customFields = 0,
    this.customFieldValues = 0,
    this.notes = 0,
    this.frontSessionComments = 0,
    this.conversationCategories = 0,
    this.reminders = 0,
    this.friends = 0,
    this.mediaAttachments = 0,
    this.formatVersion = '',
    this.exportDate = '',
  });

  final int headmates;
  final int frontSessions;
  final int sleepSessions;
  final int conversations;
  final int messages;
  final int polls;
  final int pollOptions;
  final int systemSettings;
  final int habits;
  final int habitCompletions;
  final int memberGroups;
  final int memberGroupEntries;
  final int customFields;
  final int customFieldValues;
  final int notes;
  final int frontSessionComments;
  final int conversationCategories;
  final int reminders;
  final int friends;
  final int mediaAttachments;
  final String formatVersion;
  final String exportDate;

  int get totalRecords =>
      headmates +
      frontSessions +
      sleepSessions +
      conversations +
      messages +
      polls +
      pollOptions +
      systemSettings +
      habits +
      habitCompletions +
      memberGroups +
      memberGroupEntries +
      customFields +
      customFieldValues +
      notes +
      frontSessionComments +
      conversationCategories +
      reminders +
      friends +
      mediaAttachments;
}

/// Result of a completed import operation.
class ImportResult {
  ImportResult({
    this.membersCreated = 0,
    this.frontSessionsCreated = 0,
    this.sleepSessionsCreated = 0,
    this.conversationsCreated = 0,
    this.messagesCreated = 0,
    this.pollsCreated = 0,
    this.pollOptionsCreated = 0,
    this.settingsUpdated = false,
    this.habitsCreated = 0,
    this.habitCompletionsCreated = 0,
    this.memberGroupsCreated = 0,
    this.memberGroupEntriesCreated = 0,
    this.customFieldsCreated = 0,
    this.customFieldValuesCreated = 0,
    this.notesCreated = 0,
    this.frontSessionCommentsCreated = 0,
    this.conversationCategoriesCreated = 0,
    this.remindersCreated = 0,
    this.friendsCreated = 0,
    this.mediaAttachmentsCreated = 0,
    this.legacyPkShortIdsSkipped = 0,
    this.legacyCorruptCoFronterRows = const [],
    this.unknownSentinelCreated = false,
  });

  final int membersCreated;
  final int frontSessionsCreated;
  final int sleepSessionsCreated;
  final int conversationsCreated;
  final int messagesCreated;
  final int pollsCreated;
  final int pollOptionsCreated;
  final bool settingsUpdated;
  final int habitsCreated;
  final int habitCompletionsCreated;
  final int memberGroupsCreated;
  final int memberGroupEntriesCreated;
  final int customFieldsCreated;
  final int customFieldValuesCreated;
  final int notesCreated;
  final int frontSessionCommentsCreated;
  final int conversationCategoriesCreated;
  final int remindersCreated;
  final int friendsCreated;
  final int mediaAttachmentsCreated;

  // -- PRISM1 rescue-importer diagnostics (Phase 5D, spec §4.7) ---------
  //
  // Number of (PK switch, PK short id) rescue-row fan-outs that couldn't
  // resolve to a local member. Surfaced in the import-result UI so users
  // can spot under-imported PK histories (typically because the matching
  // local member was deleted or never imported).
  final int legacyPkShortIdsSkipped;
  // Legacy native session ids whose `co_fronter_ids` JSON failed to
  // parse. Per §6 edge cases the importer falls back to single-member
  // migration (primary only) and surfaces these for user review.
  final List<String> legacyCorruptCoFronterRows;
  // Whether the rescue importer created the Unknown sentinel member to
  // hold orphan native rows (`member_id IS NULL`, `session_type = 0`).
  // Surfaced so the upgrade flow can remind the user the sentinel is
  // non-deletable and can be renamed.
  final bool unknownSentinelCreated;

  int get totalRecordsCreated =>
      membersCreated +
      frontSessionsCreated +
      sleepSessionsCreated +
      conversationsCreated +
      messagesCreated +
      pollsCreated +
      pollOptionsCreated +
      (settingsUpdated ? 1 : 0) +
      habitsCreated +
      habitCompletionsCreated +
      memberGroupsCreated +
      memberGroupEntriesCreated +
      customFieldsCreated +
      customFieldValuesCreated +
      notesCreated +
      frontSessionCommentsCreated +
      conversationCategoriesCreated +
      remindersCreated +
      friendsCreated +
      mediaAttachmentsCreated;
}

class DataImportService {
  DataImportService({
    required this.db,
    required this.memberRepository,
    required this.frontingSessionRepository,
    required this.conversationRepository,
    required this.chatMessageRepository,
    required this.pollRepository,
    required this.systemSettingsRepository,
    required this.habitRepository,
    required this.pluralKitSyncDao,
    required this.memberGroupsRepository,
    required this.customFieldsRepository,
    required this.notesRepository,
    required this.frontSessionCommentsRepository,
    required this.conversationCategoriesRepository,
    required this.remindersRepository,
    required this.friendsRepository,
    Future<Directory> Function()? appSupportDirectoryProvider,
  }) : _appSupportDirectoryProvider =
           appSupportDirectoryProvider ?? getApplicationSupportDirectory;

  final AppDatabase db;
  final MemberRepository memberRepository;
  final FrontingSessionRepository frontingSessionRepository;
  final ConversationRepository conversationRepository;
  final ChatMessageRepository chatMessageRepository;
  final PollRepository pollRepository;
  final SystemSettingsRepository systemSettingsRepository;
  final HabitRepository habitRepository;
  final PluralKitSyncDao pluralKitSyncDao;
  final MemberGroupsRepository memberGroupsRepository;
  final CustomFieldsRepository customFieldsRepository;
  final NotesRepository notesRepository;
  final FrontSessionCommentsRepository frontSessionCommentsRepository;
  final ConversationCategoriesRepository conversationCategoriesRepository;
  final RemindersRepository remindersRepository;
  final FriendsRepository friendsRepository;
  final Future<Directory> Function() _appSupportDirectoryProvider;

  static final _uuidRegex = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  /// Resolve raw file bytes to a JSON string and optional media blobs.
  ///
  /// PRISM3 encrypted files return both the JSON and any embedded media blobs.
  /// Third-party JSON files (e.g. Simply Plural exports) return empty mediaBlobs.
  /// Unencrypted Prism backups are rejected — all Prism backups must be encrypted.
  /// Wrapper for use with Flutter's [compute()] function.
  ///
  /// [compute()] requires a top-level or static function so the callback has
  /// no implicit [this] capture. Passing [resolveBytes] directly would work
  /// but its optional named parameter doesn't fit the [M Function(M)] shape,
  /// so this wrapper packs the args into a sendable record.
  static ({String json, List<({String mediaId, Uint8List blob})> mediaBlobs})
  resolveForCompute(({Uint8List bytes, String password}) args) =>
      resolveBytes(args.bytes, password: args.password);

  static ({String json, List<({String mediaId, Uint8List blob})> mediaBlobs})
  resolveBytes(Uint8List bytes, {String? password}) {
    if (ExportCrypto.isEncrypted(bytes)) {
      if (password == null || password.isEmpty) {
        throw const FormatException(
          'This file is encrypted. Please provide a password.',
        );
      }
      final result = ExportCrypto.decrypt(bytes, password);
      _validateMediaManifest(result.json, result.mediaBlobs);
      return (json: result.json, mediaBlobs: result.mediaBlobs);
    }
    final String raw;
    try {
      raw = utf8.decode(bytes);
    } catch (_) {
      throw const FormatException('File is not a valid export');
    }
    // Unencrypted Prism backups are not accepted — re-export from the app.
    if (raw.contains('"formatVersion"')) {
      throw const FormatException('unencrypted-prism-backup');
    }
    return (json: raw, mediaBlobs: const []);
  }

  /// Validate that every outer media blob has an ID present in the authenticated
  /// JSON manifest (mediaAttachments array). Checks both mediaId and thumbnailMediaId.
  static void _validateMediaManifest(
    String json,
    List<({String mediaId, Uint8List blob})> blobs,
  ) {
    if (blobs.isEmpty) return;
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final attachments = (decoded['mediaAttachments'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final allowed = <String>{};
    for (final a in attachments) {
      final id = a['mediaId'] as String? ?? '';
      final tid = a['thumbnailMediaId'] as String? ?? '';
      if (id.isNotEmpty) allowed.add(id);
      if (tid.isNotEmpty) allowed.add(tid);
    }
    for (final entry in blobs) {
      if (!allowed.contains(entry.mediaId)) {
        throw const FormatException(
          'Backup file is corrupted or cannot be verified',
        );
      }
    }
  }

  /// Recognized format versions that this service can import.
  ///
  /// `'2025.1'` is the pre-beta envelope version kept for back-compat with
  /// PRISM3-era export files (now convertible via `tools/prism3-to-prism1`);
  /// the envelope itself is encrypted, so the converter cannot rewrite it.
  static const supportedVersions = ['1.0', '2025.1'];

  /// Parse a JSON string and return a preview without importing.
  ///
  /// Throws [FormatException] if the format version is unrecognized.
  ImportPreview parsePreview(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    final export = V1Export.fromJson(map);

    if (!supportedVersions.contains(export.formatVersion)) {
      throw FormatException(
        'Unsupported export format version: ${export.formatVersion}. '
        'Supported versions: ${supportedVersions.join(', ')}',
      );
    }

    return ImportPreview(
      headmates: export.headmates.length,
      frontSessions: export.frontSessions.length,
      sleepSessions: export.sleepSessions.length,
      conversations: export.conversations.length,
      messages: export.messages.length,
      polls: export.polls.length,
      pollOptions: export.pollOptions.length,
      systemSettings: export.systemSettings.length,
      habits: export.habits.length,
      habitCompletions: export.habitCompletions.length,
      memberGroups: export.memberGroups.length,
      memberGroupEntries: export.memberGroupEntries.length,
      customFields: export.customFields.length,
      customFieldValues: export.customFieldValues.length,
      notes: export.notes.length,
      frontSessionComments: export.frontSessionComments.length,
      conversationCategories: export.conversationCategories.length,
      reminders: export.reminders.length,
      friends: export.friends.length,
      mediaAttachments: export.mediaAttachments.length,
      formatVersion: export.formatVersion,
      exportDate: export.exportDate,
    );
  }

  /// Import data from a JSON string.
  ///
  /// The entire import runs inside a single database transaction. If any
  /// entity fails to insert the transaction is rolled back automatically and
  /// the exception propagates to the caller — the database is left unchanged.
  Future<ImportResult> importData(
    String json, {
    List<({String mediaId, Uint8List blob})> mediaBlobs = const [],
    bool preserveImportedOnboardingState = true,
  }) async {
    final map = jsonDecode(json) as Map<String, dynamic>;
    final export = V1Export.fromJson(map);

    if (!supportedVersions.contains(export.formatVersion)) {
      throw FormatException(
        'Unsupported export format version: ${export.formatVersion}. '
        'Supported versions: ${supportedVersions.join(', ')}',
      );
    }

    // Write media blobs to temp files BEFORE the DB transaction so a failed
    // transaction doesn't leave metadata rows pointing at missing .enc files.
    Directory? mediaDir;
    if (mediaBlobs.isNotEmpty) {
      mediaDir = await _mediaDirectory();
      await _writeMediaToTemp(mediaBlobs, mediaDir);
    }

    final ImportResult result;
    try {
      result = await db.transaction(() async {
      // 1. Import members (first pass: create)
      //
      // Dedup against ALL local members, including soft-deleted tombstones.
      // The partial unique indexes idx_members_pluralkit_uuid /
      // idx_members_pluralkit_id cover tombstones (no `is_deleted = 0` clause
      // in the index \u2014 tombstones still hold `pluralkit_uuid` / `pluralkit_id`
      // until the corresponding delete-push completes), so an import row whose
      // PK link matches a tombstoned local row would otherwise hit the unique
      // index and roll back the entire import transaction. See
      // docs/plans/data-import-tombstone-collision.md.
      var membersCreated = 0;
      final allMemberRows = await db.membersDao.getAllMembersIncludingDeleted();
      final existingMemberIds = {for (final m in allMemberRows) m.id};
      final existingMemberPkUuids = {
        for (final m in allMemberRows)
          if (m.pluralkitUuid != null && m.pluralkitUuid!.isNotEmpty)
            m.pluralkitUuid!,
      };
      final existingMemberPkIds = {
        for (final m in allMemberRows)
          if (m.pluralkitId != null && m.pluralkitId!.isNotEmpty)
            m.pluralkitId!,
      };
      // Members eligible for the second-pass parentSystemId update \u2014 only
      // active rows we either already had or just created. Tombstones are
      // excluded so the second pass can't accidentally revive a deletion.
      final activeMemberIdsAfterImport = <String>{
        for (final m in allMemberRows) if (!m.isDeleted) m.id,
      };

      for (final h in export.headmates) {
        if (existingMemberIds.contains(h.id)) continue;
        // Tombstone PK-link collision: skip rather than throw on the unique
        // index. The user's local intent is "deleted"; we preserve that.
        if (h.pluralkitUuid != null &&
            h.pluralkitUuid!.isNotEmpty &&
            existingMemberPkUuids.contains(h.pluralkitUuid)) {
          debugPrint(
            '[Import] Skipped member ${h.id}: pluralkitUuid='
            '${h.pluralkitUuid} collides with an existing local member.',
          );
          continue;
        }
        if (h.pluralkitId != null &&
            h.pluralkitId!.isNotEmpty &&
            existingMemberPkIds.contains(h.pluralkitId)) {
          debugPrint(
            '[Import] Skipped member ${h.id}: pluralkitId=${h.pluralkitId} '
            'collides with an existing local member.',
          );
          continue;
        }
        try {
          await memberRepository.createMember(
            Member(
              id: h.id,
              name: h.name,
              pronouns: h.pronouns,
              emoji: h.emoji ?? '\u2754',
              age: h.age,
              bio: h.notes,
              avatarImageData: h.avatarImageData,
              isActive: h.isActive,
              createdAt: DateTime.parse(h.createdAt),
              displayOrder: h.displayOrder,
              isAdmin: h.isAdmin,
              customColorEnabled: h.customColorEnabled,
              customColorHex: h.customColorHex,
              pluralkitUuid: h.pluralkitUuid,
              pluralkitId: h.pluralkitId,
              markdownEnabled: h.markdownEnabled,
              displayName: h.displayName,
              birthday: h.birthday,
              proxyTagsJson: h.proxyTagsJson,
              pluralkitSyncIgnored: h.pluralkitSyncIgnored,
            ),
          );
        } catch (e) {
          // Belt-and-braces: if a future code path introduces a hole the
          // dedup above missed, swallow the unique-constraint and skip
          // rather than abort the entire import transaction. The dedup
          // is the primary defense; this is the safety net.
          if (isUniqueConstraintViolation(e)) {
            debugPrint(
              '[Import] Member ${h.id} insert hit a unique-constraint '
              'collision past dedup; skipping.',
            );
            continue;
          }
          rethrow;
        }
        membersCreated++;
        existingMemberIds.add(h.id);
        activeMemberIdsAfterImport.add(h.id);
        if (h.pluralkitUuid != null && h.pluralkitUuid!.isNotEmpty) {
          existingMemberPkUuids.add(h.pluralkitUuid!);
        }
        if (h.pluralkitId != null && h.pluralkitId!.isNotEmpty) {
          existingMemberPkIds.add(h.pluralkitId!);
        }
      }

      // Second pass: set parentSystemId for members.
      //
      // Gate by the active-id set so we never call updateMember on a
      // tombstone \u2014 `getMemberById` does NOT filter `is_deleted`, and
      // `updateMember` would emit a sync op with `is_deleted: false`,
      // effectively reviving the row and undoing the user's local delete.
      for (final h in export.headmates) {
        if (h.parentSystemId == null) continue;
        if (!activeMemberIdsAfterImport.contains(h.id)) continue;
        final member = await memberRepository.getMemberById(h.id);
        if (member != null &&
            !member.isDeleted &&
            member.parentSystemId != h.parentSystemId) {
          await memberRepository.updateMember(
            member.copyWith(parentSystemId: h.parentSystemId),
          );
        }
      }

      // 2. Import fronting sessions
      //
      // Same shape as members: dedup against all sessions including
      // tombstones, because idx_fronting_sessions_pluralkit_uuid covers
      // tombstones too. existingSessionIds is also reused for the sleep
      // loop below since both session types share the same primary key
      // namespace in `fronting_sessions`.
      //
      // Rows tagged `isLegacyShape == true` (any pre-0.7.0 export marker:
      // `coFronterIds`, `pkMemberIdsJson`, `headmateId` without `memberId`
      // / `sessionType`) are routed through the PRISM1 rescue importer
      // (§4.7) to fan out PK + native multi-member rows into the new
      // per-member shape with deterministic v5 ids. New-shape rows go
      // straight through the standard write.
      //
      // Per-row sniff is intentional: a single file can mix shapes if a
      // user partially re-exports between versions, and the rescue path
      // must never run on already-migrated rows (would double-fan-out).
      var frontSessionsCreated = 0;
      var legacyPkShortIdsSkipped = 0;
      final legacyCorruptCoFronterRows = <String>[];
      var unknownSentinelCreated = false;
      // Map from legacy session id → (memberId, startTime) used by the
      // legacy comments branch to derive `target_time` / `author_member_id`
      // when joining a comment back to its parent session row.
      final legacySessionParents = <String, _LegacyParentInfo>{};
      // Cached lookup: PK short id → local member full UUID, populated
      // lazily so we only scan the members table when a legacy PK rescue
      // row actually arrives.
      Map<String, String>? pkShortIdToLocalUuid;
      Future<Map<String, String>> resolvePkShortIdMap() async {
        if (pkShortIdToLocalUuid != null) return pkShortIdToLocalUuid!;
        final allMembers = await memberRepository.getAllMembers();
        pkShortIdToLocalUuid = {
          for (final m in allMembers)
            if (m.pluralkitId != null &&
                m.pluralkitId!.isNotEmpty &&
                m.pluralkitUuid != null &&
                m.pluralkitUuid!.isNotEmpty)
              m.pluralkitId!: m.pluralkitUuid!,
        };
        return pkShortIdToLocalUuid!;
      }

      // Cached: SP id-map session-entity rows keyed by local prismId. The
      // rescue importer treats SP-imported rows as already-1:1 (§2.2);
      // any legacy session whose id appears here is migrated 1:1 with the
      // existing `headmateId` as `member_id`.
      Set<String>? spSessionPrismIds;
      Future<Set<String>> resolveSpSessionPrismIds() async {
        if (spSessionPrismIds != null) return spSessionPrismIds!;
        final all = await db.spImportDao.getAllMappings();
        spSessionPrismIds = {
          for (final r in all)
            if (r.entityType == 'session') r.prismId,
        };
        return spSessionPrismIds!;
      }

      // Lazy creation of the Unknown sentinel for orphan native rows
      // (member_id IS NULL, session_type = 0). Delegates to the shared
      // helper on MemberRepository so the id matches what 5B migration
      // and the SP importer use; concurrent migrations on paired devices
      // converge on the same sentinel row.
      String? unknownSentinelId;
      Future<String> ensureUnknownSentinel() async {
        if (unknownSentinelId != null) return unknownSentinelId!;
        final ensured = await memberRepository.ensureUnknownSentinelMember();
        if (ensured.wasCreated) {
          unknownSentinelCreated = true;
        }
        unknownSentinelId = ensured.member.id;
        return unknownSentinelId!;
      }

      final allSessionRows = await db.frontingSessionsDao
          .getAllSessionsIncludingDeleted();
      final existingSessionIds = {for (final s in allSessionRows) s.id};
      // Composite (pluralkit_uuid, member_id) tracking per §3.7. The
      // post-Phase-5 unique index is composite, not single-column on
      // pluralkit_uuid alone — fanned-out PK rescue rows MUST be allowed
      // to share a switch UUID across different members.
      final existingPkPairs = <String>{
        for (final s in allSessionRows)
          if (s.pluralkitUuid != null && s.pluralkitUuid!.isNotEmpty)
            '${s.pluralkitUuid!}|${s.memberId ?? ''}',
      };

      Future<bool> writeSession({
        required String id,
        required DateTime startTime,
        DateTime? endTime,
        String? memberId,
        String? notes,
        FrontConfidence? confidence,
        String? pluralkitUuid,
        SessionType sessionType = SessionType.normal,
        SleepQuality? quality,
        bool isHealthKitImport = false,
      }) async {
        if (existingSessionIds.contains(id)) return false;
        if (pluralkitUuid != null && pluralkitUuid.isNotEmpty) {
          final key = '$pluralkitUuid|${memberId ?? ''}';
          if (existingPkPairs.contains(key)) {
            // Pre-existing local row already covers this (switch_uuid,
            // member_id) pair (e.g., a prior API import wrote a row with
            // the same composite key). Skip rather than collide. CRDT
            // field-LWW handles the boundary correction on later API
            // sync.
            debugPrint(
              '[Import][rescue] Skipped fronting session $id: '
              '(pluralkitUuid=$pluralkitUuid, memberId=$memberId) already '
              'present locally.',
            );
            return false;
          }
        }
        try {
          await frontingSessionRepository.createSession(
            FrontingSession(
              id: id,
              startTime: startTime,
              endTime: endTime,
              memberId: memberId,
              notes: notes,
              sessionType: sessionType,
              confidence: confidence,
              pluralkitUuid: pluralkitUuid,
              quality: quality,
              isHealthKitImport: isHealthKitImport,
            ),
          );
        } catch (e) {
          if (isUniqueConstraintViolation(e)) {
            debugPrint(
              '[Import] Fronting session $id insert hit a unique-'
              'constraint collision past dedup; skipping.',
            );
            return false;
          }
          rethrow;
        }
        existingSessionIds.add(id);
        if (pluralkitUuid != null && pluralkitUuid.isNotEmpty) {
          existingPkPairs.add('$pluralkitUuid|${memberId ?? ''}');
        }
        return true;
      }

      const uuid = Uuid();

      for (final s in export.frontSessions) {
        final start = DateTime.parse(s.startTime);
        final end = s.endTime != null ? DateTime.parse(s.endTime!) : null;
        final conf = s.confidence != null &&
                s.confidence! >= 0 &&
                s.confidence! < FrontConfidence.values.length
            ? FrontConfidence.values[s.confidence!]
            : null;

        if (!s.isLegacyShape) {
          // -------- New-shape import path --------
          //
          // Post-0.7.0 exports already carry per-member rows with
          // `memberId` + `sessionType`. The new-shape path doesn't fan
          // out, doesn't derive ids, and doesn't touch `coFronterIds` /
          // `pkMemberIdsJson` (those columns are dropped in v8 and
          // unread in v7). HealthKit + sleep rows arrive in this same
          // array with `sessionType = 1`.
          final st = (s.sessionType ?? 0) == 1
              ? SessionType.sleep
              : SessionType.normal;
          final q = s.quality != null &&
                  s.quality! >= 0 &&
                  s.quality! < SleepQuality.values.length
              ? SleepQuality.values[s.quality!]
              : (st == SessionType.sleep ? SleepQuality.unknown : null);
          final created = await writeSession(
            id: s.id,
            startTime: start,
            endTime: end,
            memberId: s.headmateId,
            notes: s.notes,
            confidence: conf,
            pluralkitUuid: s.pluralkitUuid,
            sessionType: st,
            quality: q,
            isHealthKitImport: s.isHealthKitImport ?? false,
          );
          if (created) frontSessionsCreated++;
          // Track for the legacy-comment join even if a parallel new-shape
          // write happens — the join only fires for legacy comments.
          legacySessionParents[s.id] = _LegacyParentInfo(
            memberId: s.headmateId,
            startTime: start,
          );
          continue;
        }

        // -------- PRISM1 rescue path (§4.7) --------
        //
        // Legacy-shape rows split four ways:
        //   1. PK-imported (pluralkitUuid != null) — fan out per
        //      pkMemberIdsJson short id, derive deterministic v5 ids,
        //      preserve lossy boundaries (one row per old switch).
        //   2. SP-imported (sp_id_map carries an entry for this id) —
        //      migrate 1:1, preserve id, headmateId already 1:1.
        //   3. Native multi-member (coFronterIds non-empty) — primary
        //      keeps the legacy id, additional co-fronters get
        //      derived ids from `migrationFrontingNamespace`.
        //   4. Native single-member / orphan / HealthKit — keep id,
        //      assign Unknown sentinel for the orphan case.
        //
        // The four branches DO NOT preserve `coFronterIds` /
        // `pkMemberIdsJson` on the new row — those columns are
        // intentionally dropped in v8 and unread from 0.7.0 onward.
        // Re-importing from the PK API later collides on the
        // deterministic id and CRDT field-LWW takes the API's
        // correctly-bounded row.

        final isPk = s.pluralkitUuid != null && s.pluralkitUuid!.isNotEmpty;
        if (isPk) {
          // PK fan-out. The `pk_member_ids_json` column on each old row
          // carries the short ids (e.g., "abcde") of the members that
          // were fronting at the entry switch. Resolve each to the
          // local Prism member's full UUID via the pluralkit_id ->
          // pluralkit_uuid lookup, then derive the deterministic id
          // per §2.6: `v5(_pkFrontingNamespace, "${switch}:${uuid}")`.
          //
          // Boundaries are intentionally lossy here (one row per old
          // switch with the same start/end). A later API re-import
          // produces correctly-bounded rows; the rescue row's id
          // collides on (switch, member) and the API row's fresher
          // HLC wins via field-LWW. We MUST go through `createSession`
          // (which calls `syncRecordCreate` → fresh HLCs at write
          // time) rather than `insertOnConflictUpdate` so the rescue
          // row's HLCs don't accidentally outlive the API import's.
          final pkShortIdsRaw = s.pkMemberIdsJson;
          final shortIds = <String>[];
          if (pkShortIdsRaw != null && pkShortIdsRaw.isNotEmpty) {
            try {
              final parsed = jsonDecode(pkShortIdsRaw);
              if (parsed is List) {
                for (final e in parsed) {
                  if (e is String) shortIds.add(e);
                }
              }
            } catch (_) {
              // Treat as no fan-out targets; loop below produces zero
              // rows and counts as skipped via the empty-list path.
            }
          }
          if (shortIds.isEmpty) {
            // Pre-v7 PK exports may carry `pluralkit_uuid` without the
            // `pk_member_ids_json` column (the column was added in
            // Phase 2). Fall back to the legacy `headmateId` as the
            // single fronter so the row still imports — same lossy
            // boundary deal as the fan-out path. A later API
            // re-import collides on the (switch, member) deterministic
            // id and field-LWW takes the API's correct rows.
            //
            // If even `headmateId` is absent (truly empty PK row),
            // log and skip; the API re-import is the recovery path.
            if (s.headmateId == null) {
              debugPrint(
                '[Import][rescue] PK row ${s.id} has neither '
                'pkMemberIdsJson nor headmateId; skipping.',
              );
              legacySessionParents[s.id] = _LegacyParentInfo(
                memberId: null,
                startTime: start,
              );
              continue;
            }
            // Derive the SAME deterministic id the live PK API importer
            // would derive — `derivePkSessionId(switch_uuid,
            // member_pk_uuid)`. Reusing the legacy v4 `s.id` here would
            // create two distinct rows for the same (switch, member)
            // pair on a future API re-import, hitting the composite
            // unique index and the diff-sweep's collision-handler path.
            // Skip rows whose local member has no `pluralkit_uuid` —
            // we can't derive a stable id without it; counted as
            // skipped per the existing PK short-id-without-mapping
            // pattern.
            final memberPkUuid = await _pkUuidForLocalMemberId(
              s.headmateId!,
            );
            if (memberPkUuid == null) {
              debugPrint(
                '[Import][rescue] PK row ${s.id} headmateId '
                '"${s.headmateId}" has no pluralkit_uuid; skipping.',
              );
              legacyPkShortIdsSkipped++;
              legacySessionParents[s.id] = _LegacyParentInfo(
                memberId: s.headmateId,
                startTime: start,
              );
              continue;
            }
            final derivedId =
                derivePkSessionId(s.pluralkitUuid!, memberPkUuid);
            final created = await writeSession(
              id: derivedId,
              startTime: start,
              endTime: end,
              memberId: s.headmateId,
              notes: s.notes,
              confidence: conf,
              pluralkitUuid: s.pluralkitUuid,
              sessionType: SessionType.normal,
            );
            if (created) frontSessionsCreated++;
            legacySessionParents[s.id] = _LegacyParentInfo(
              memberId: s.headmateId,
              startTime: start,
            );
            continue;
          }
          final shortToUuid = await resolvePkShortIdMap();
          final resolvedMemberUuids = <String>[];
          for (final shortId in shortIds) {
            final localUuid = shortToUuid[shortId];
            if (localUuid == null) {
              legacyPkShortIdsSkipped++;
              continue;
            }
            resolvedMemberUuids.add(localUuid);
          }
          // Use the first resolved member UUID for the comment author
          // fallback if a comment joins to this PK switch (per spec).
          final firstResolvedLocalId =
              await _localMemberIdForPkUuid(resolvedMemberUuids.isNotEmpty
                  ? resolvedMemberUuids.first
                  : null);
          legacySessionParents[s.id] = _LegacyParentInfo(
            memberId: firstResolvedLocalId,
            startTime: start,
          );
          for (final memberPkUuid in resolvedMemberUuids) {
            final derivedId =
                derivePkSessionId(s.pluralkitUuid!, memberPkUuid);
            final localMemberId =
                await _localMemberIdForPkUuid(memberPkUuid);
            if (localMemberId == null) {
              // Defensive: shouldn't happen since we just resolved
              // memberPkUuid from a local member, but fall through
              // safely.
              legacyPkShortIdsSkipped++;
              continue;
            }
            final created = await writeSession(
              id: derivedId,
              startTime: start,
              endTime: end,
              memberId: localMemberId,
              notes: s.notes,
              confidence: conf,
              pluralkitUuid: s.pluralkitUuid,
              sessionType: SessionType.normal,
            );
            if (created) frontSessionsCreated++;
          }
          continue;
        }

        final spIds = await resolveSpSessionPrismIds();
        final isSp = spIds.contains(s.id);
        if (isSp) {
          // SP rescue — already 1:1 per-member by SP source semantics.
          // Preserve id; rely on existing sp_id_map entry to keep the
          // SP re-import idempotent (§2.6).
          final created = await writeSession(
            id: s.id,
            startTime: start,
            endTime: end,
            memberId: s.headmateId,
            notes: s.notes,
            confidence: conf,
            sessionType: SessionType.normal,
          );
          if (created) frontSessionsCreated++;
          legacySessionParents[s.id] = _LegacyParentInfo(
            memberId: s.headmateId,
            startTime: start,
          );
          continue;
        }

        // Native rescue.
        //
        // HealthKit/sleep rows aren't represented in V1FrontSession in
        // legacy exports (they live in V1SleepSession), so anything
        // landing here is a `session_type = 0` native row. The corrupt
        // co_fronter_ids fallback per §6 collapses to single-member.
        final hasCorrupt = s.coFronterIds.isEmpty &&
            s.coFronterIdsRawJson != null &&
            s.coFronterIdsRawJson!.isNotEmpty &&
            s.coFronterIdsRawJson != '[]';
        if (hasCorrupt) {
          legacyCorruptCoFronterRows.add(s.id);
        }
        final coFronters = hasCorrupt ? const <String>[] : s.coFronterIds;

        if (s.headmateId == null && coFronters.isEmpty) {
          // Orphan: assign Unknown sentinel.
          final sentinelId = await ensureUnknownSentinel();
          final created = await writeSession(
            id: s.id,
            startTime: start,
            endTime: end,
            memberId: sentinelId,
            notes: s.notes,
            confidence: conf,
            sessionType: SessionType.normal,
          );
          if (created) frontSessionsCreated++;
          legacySessionParents[s.id] = _LegacyParentInfo(
            memberId: sentinelId,
            startTime: start,
          );
          continue;
        }

        // Native single-member or multi-member. Primary keeps the legacy
        // id; additional co-fronters get deterministic v5 ids derived
        // from `(legacy_session_id, member_id)` so paired devices
        // migrating concurrently converge on the same per-member rows.
        final primaryCreated = await writeSession(
          id: s.id,
          startTime: start,
          endTime: end,
          memberId: s.headmateId,
          notes: s.notes,
          confidence: conf,
          sessionType: SessionType.normal,
        );
        if (primaryCreated) frontSessionsCreated++;
        legacySessionParents[s.id] = _LegacyParentInfo(
          memberId: s.headmateId,
          startTime: start,
        );
        for (final coId in coFronters) {
          if (coId == s.headmateId) continue; // sanity guard
          final derivedId = uuid.v5(
            migrationFrontingNamespace,
            '${s.id}:$coId',
          );
          final created = await writeSession(
            id: derivedId,
            startTime: start,
            endTime: end,
            memberId: coId,
            notes: s.notes,
            confidence: conf,
            sessionType: SessionType.normal,
          );
          if (created) frontSessionsCreated++;
        }
      }

      // 3. Import sleep sessions
      //
      // Sleep and normal sessions share the same `fronting_sessions` table
      // and primary-key namespace, so dedup against the table-wide
      // existingSessionIds (already populated above and including
      // tombstones). Sleep rows don't carry a `pluralkit_uuid` so the
      // PK-link sets aren't relevant here.
      var sleepSessionsCreated = 0;

      for (final s in export.sleepSessions) {
        if (existingSessionIds.contains(s.id)) continue;
        try {
          await frontingSessionRepository.createSession(
            FrontingSession(
              id: s.id,
              startTime: DateTime.parse(s.startTime),
              endTime: s.endTime != null ? DateTime.parse(s.endTime!) : null,
              sessionType: SessionType.sleep,
              quality: s.quality >= 0 && s.quality < SleepQuality.values.length
                  ? SleepQuality.values[s.quality]
                  : SleepQuality.unknown,
              notes: s.notes,
              isHealthKitImport: s.isHealthKitImport,
            ),
          );
        } catch (e) {
          if (isUniqueConstraintViolation(e)) {
            debugPrint(
              '[Import] Sleep session ${s.id} insert hit a unique-'
              'constraint collision past dedup; skipping.',
            );
            continue;
          }
          rethrow;
        }
        sleepSessionsCreated++;
        existingSessionIds.add(s.id);
      }

      // 4. Import conversations
      var conversationsCreated = 0;
      final existingConvs = await conversationRepository.getAllConversations();
      final existingConvIds = existingConvs.map((c) => c.id).toSet();

      for (final c in export.conversations) {
        if (existingConvIds.contains(c.id)) continue;
        // Rebuild lastReadTimestamps from String:String map
        final timestamps = c.lastReadTimestamps.map(
          (k, v) => MapEntry(k, DateTime.parse(v)),
        );

        await conversationRepository.createConversation(
          Conversation(
            id: c.id,
            createdAt: DateTime.parse(c.createdAt),
            lastActivityAt: DateTime.parse(c.lastActivityAt),
            title: c.title,
            emoji: c.emoji,
            isDirectMessage: c.isDirectMessage,
            creatorId: c.creatorId,
            participantIds: c.participantIds,
            archivedByMemberIds: c.archivedByMemberIds != null
                ? (jsonDecode(c.archivedByMemberIds!) as List).cast<String>()
                : [],
            mutedByMemberIds: c.mutedByMemberIds != null
                ? (jsonDecode(c.mutedByMemberIds!) as List).cast<String>()
                : [],
            lastReadTimestamps: timestamps,
            description: c.description,
            categoryId: c.categoryId,
            displayOrder: c.displayOrder,
          ),
        );
        conversationsCreated++;
      }

      // 5. Import messages
      var messagesCreated = 0;
      // Preload existing message IDs to avoid per-record queries
      final allExistingMsgs = await chatMessageRepository.getAllMessages();
      final existingMessageIds = allExistingMsgs.map((m) => m.id).toSet();
      for (final m in export.messages) {
        if (existingMessageIds.contains(m.id)) continue;

        await chatMessageRepository.createMessage(
          ChatMessage(
            id: m.id,
            content: m.content,
            timestamp: DateTime.parse(m.timestamp),
            isSystemMessage: m.isSystemMessage,
            editedAt: m.editedAt != null ? DateTime.parse(m.editedAt!) : null,
            authorId: m.authorId,
            conversationId: m.conversationId,
            reactions: m.reactions
                .map(
                  (r) => MessageReaction(
                    id: r.id,
                    emoji: r.emoji,
                    memberId: r.memberId,
                    timestamp: DateTime.parse(r.timestamp),
                  ),
                )
                .toList(),
            replyToId: m.replyToId,
            replyToAuthorId: m.replyToAuthorId,
            replyToContent: m.replyToContent,
          ),
        );
        messagesCreated++;
      }

      // 6. Import polls + options + votes
      var pollsCreated = 0;
      var pollOptionsCreated = 0;
      final existingPolls = await pollRepository.getAllPolls();
      final existingPollIds = existingPolls.map((p) => p.id).toSet();

      for (final p in export.polls) {
        if (existingPollIds.contains(p.id)) continue;
        await pollRepository.createPoll(
          Poll(
            id: p.id,
            question: p.question,
            description: p.description,
            isAnonymous: p.isAnonymous,
            allowsMultipleVotes: p.allowsMultipleVotes,
            isClosed: p.isClosed,
            expiresAt: p.expiresAt != null
                ? DateTime.parse(p.expiresAt!)
                : null,
            createdAt: DateTime.parse(p.createdAt),
          ),
        );
        pollsCreated++;
      }

      // Batch-load all existing poll option IDs in one query.
      final allOptions = await pollRepository.getAllOptions();
      final existingOptionIds = <String>{
        for (final opt in allOptions) opt.id,
      };
      for (final o in export.pollOptions) {
        if (existingOptionIds.contains(o.id)) continue;

        await pollRepository.createOption(
          PollOption(
            id: o.id,
            text: o.text,
            sortOrder: o.sortOrder,
            isOtherOption: o.isOtherOption,
            colorHex: o.colorHex,
          ),
          o.pollId,
        );
        pollOptionsCreated++;

        // Import votes for this option
        for (final v in o.votes) {
          await pollRepository.castVote(
            PollVote(
              id: v.id,
              memberId: v.memberId,
              votedAt: DateTime.parse(v.votedAt),
              responseText: v.responseText,
            ),
            o.id,
          );
        }
      }

      // 7. Import system settings
      var settingsUpdated = false;
      if (export.systemSettings.isNotEmpty) {
        final s = export.systemSettings.first;
        await systemSettingsRepository.updateSettings(
          SystemSettings(
            systemName: s.systemName,
            sharingId: s.sharingId,
            showQuickFront: s.showQuickFront,
            accentColorHex: s.accentColorHex,
            perMemberAccentColors: s.perMemberAccentColors,
            terminology:
                s.terminology >= 0 &&
                    s.terminology < SystemTerminology.values.length
                ? SystemTerminology.values[s.terminology]
                : SystemTerminology.headmates,
            customTerminology: s.customTerminology,
            customPluralTerminology: s.customPluralTerminology,
            terminologyUseEnglish: s.terminologyUseEnglish,
            frontingRemindersEnabled: s.frontingRemindersEnabled,
            frontingReminderIntervalMinutes: s.frontingReminderIntervalMinutes,
            themeMode:
                s.themeMode >= 0 && s.themeMode < AppThemeMode.values.length
                ? AppThemeMode.values[s.themeMode]
                : AppThemeMode.system,
            themeBrightness:
                s.themeBrightness >= 0 &&
                    s.themeBrightness < ThemeBrightness.values.length
                ? ThemeBrightness.values[s.themeBrightness]
                : ThemeBrightness.system,
            themeStyle:
                s.themeStyle >= 0 && s.themeStyle < ThemeStyle.values.length
                ? ThemeStyle.values[s.themeStyle]
                : ThemeStyle.standard,
            chatEnabled: s.chatEnabled,
            pollsEnabled: s.pollsEnabled,
            habitsEnabled: s.habitsEnabled,
            sleepTrackingEnabled: s.sleepTrackingEnabled,
            quickSwitchThresholdSeconds: s.quickSwitchThresholdSeconds,
            identityGeneration: s.identityGeneration,
            chatLogsFront: s.chatLogsFront,
            hasCompletedOnboarding: preserveImportedOnboardingState
                ? s.hasCompletedOnboarding
                : false,
            syncThemeEnabled: s.syncThemeEnabled,
            timingMode:
                (s.timingMode ?? 0) >= 0 &&
                    (s.timingMode ?? 0) < FrontingTimingMode.values.length
                ? FrontingTimingMode.values[s.timingMode ?? 0]
                : FrontingTimingMode.flexible,
            habitsBadgeEnabled: s.habitsBadgeEnabled,
            notesEnabled: s.notesEnabled,
            previousAccentColorHex: s.previousAccentColorHex,
            systemDescription: s.systemDescription,
            systemAvatarData: s.systemAvatarData != null
                ? base64Decode(s.systemAvatarData!)
                : null,
            remindersEnabled: s.remindersEnabled,
            fontScale: s.fontScale,
            fontFamily:
                s.fontFamily >= 0 && s.fontFamily < FontFamily.values.length
                ? FontFamily.values[s.fontFamily]
                : FontFamily.system,
            // Force device-local security settings to false on import —
            // PIN/biometric lock must be configured through the settings UI
            // where the user actually sets a PIN on this device.
            pinLockEnabled: false,
            biometricLockEnabled: false,
            autoLockDelaySeconds: s.autoLockDelaySeconds,
            navBarItems: s.navBarItems,
            navBarOverflowItems: s.navBarOverflowItems,
            syncNavigationEnabled: s.syncNavigationEnabled,
            chatBadgePreferences: s.chatBadgePreferences,
          ),
        );
        settingsUpdated = true;
      }

      // 8. Import habits
      var habitsCreated = 0;
      final existingHabits = await habitRepository.getAllHabits();
      final existingHabitIds = existingHabits.map((h) => h.id).toSet();

      for (final h in export.habits) {
        if (existingHabitIds.contains(h.id)) continue;
        await habitRepository.createHabit(
          Habit(
            id: h.id,
            name: h.name,
            description: h.description,
            icon: h.icon,
            colorHex: h.colorHex,
            isActive: h.isActive,
            createdAt: DateTime.parse(h.createdAt),
            modifiedAt: DateTime.parse(h.modifiedAt),
            frequency: HabitFrequency.values.firstWhere(
              (f) => f.name == h.frequency,
              orElse: () => HabitFrequency.daily,
            ),
            weeklyDays: h.weeklyDays != null
                ? (jsonDecode(h.weeklyDays!) as List).cast<int>()
                : null,
            intervalDays: h.intervalDays,
            reminderTime: h.reminderTime,
            notificationsEnabled: h.notificationsEnabled,
            notificationMessage: h.notificationMessage,
            assignedMemberId: h.assignedMemberId,
            onlyNotifyWhenFronting: h.onlyNotifyWhenFronting,
            isPrivate: h.isPrivate,
            currentStreak: h.currentStreak,
            bestStreak: h.bestStreak,
            totalCompletions: h.totalCompletions,
          ),
        );
        habitsCreated++;
      }

      // 9. Import habit completions
      var habitCompletionsCreated = 0;
      // Batch-load all existing completion IDs in one query.
      final allCompletions = await habitRepository.getAllCompletions();
      final existingCompletionIds = <String>{
        for (final c in allCompletions) c.id,
      };
      for (final c in export.habitCompletions) {
        if (existingCompletionIds.contains(c.id)) continue;

        await habitRepository.createCompletion(
          HabitCompletion(
            id: c.id,
            habitId: c.habitId,
            completedAt: DateTime.parse(c.completedAt),
            completedByMemberId: c.completedByMemberId,
            notes: c.notes,
            wasFronting: c.wasFronting,
            rating: c.rating,
            createdAt: DateTime.parse(c.createdAt),
            modifiedAt: DateTime.parse(c.modifiedAt),
          ),
        );
        habitCompletionsCreated++;
      }

      // 10. Import PluralKit sync state
      if (export.pluralKitSyncState != null) {
        final pk = export.pluralKitSyncState!;
        final current = await pluralKitSyncDao.getSyncState();
        final existingId = current.systemId;
        if (existingId != null && pk.systemId != null && existingId != pk.systemId) {
          // Backup is from a different PluralKit system — skip to avoid overwriting
          // the current system's connection state with a foreign system ID.
          debugPrint(
            '[Import] Skipped PluralKit sync state: '
            'backup systemId (${pk.systemId}) != current ($existingId)',
          );
        } else {
          await pluralKitSyncDao.upsertSyncState(
            PluralKitSyncStateCompanion(
              id: const Value('pk_config'),
              systemId: Value(pk.systemId),
              isConnected: Value(pk.isConnected),
              lastSyncDate: Value(
                pk.lastSyncDate != null ? DateTime.parse(pk.lastSyncDate!) : null,
              ),
              lastManualSyncDate: Value(
                pk.lastManualSyncDate != null
                    ? DateTime.parse(pk.lastManualSyncDate!)
                    : null,
              ),
            ),
          );
        }
      }

      // 11. Import member groups
      var memberGroupsCreated = 0;
      final existingGroups = await memberGroupsRepository
          .watchAllGroups()
          .first;
      final existingGroupIds = existingGroups.map((g) => g.id).toSet();

      for (final g in export.memberGroups) {
        if (existingGroupIds.contains(g.id)) continue;
        await memberGroupsRepository.createGroup(
          MemberGroup(
            id: g.id,
            name: g.name,
            description: g.description,
            colorHex: g.colorHex,
            emoji: g.emoji,
            displayOrder: g.displayOrder,
            parentGroupId: g.parentGroupId,
            createdAt: DateTime.parse(g.createdAt),
          ),
        );
        memberGroupsCreated++;
      }

      // 12. Import member group entries
      var memberGroupEntriesCreated = 0;
      final existingEntries = await memberGroupsRepository.getAllGroupEntries();
      final existingEntryIds = existingEntries.map((e) => e.id).toSet();
      for (final e in export.memberGroupEntries) {
        if (existingEntryIds.contains(e.id)) continue;
        await memberGroupsRepository.addMemberToGroup(
          e.groupId,
          e.memberId,
          e.id,
        );
        memberGroupEntriesCreated++;
      }

      // 13. Import custom fields
      var customFieldsCreated = 0;
      final existingFields = await customFieldsRepository
          .watchAllFields()
          .first;
      final existingFieldIds = existingFields.map((f) => f.id).toSet();

      for (final f in export.customFields) {
        if (existingFieldIds.contains(f.id)) continue;
        await customFieldsRepository.createField(
          CustomField(
            id: f.id,
            name: f.name,
            fieldType:
                f.fieldType >= 0 && f.fieldType < CustomFieldType.values.length
                ? CustomFieldType.values[f.fieldType]
                : CustomFieldType.text,
            datePrecision:
                f.datePrecision != null &&
                    f.datePrecision! >= 0 &&
                    f.datePrecision! < DatePrecision.values.length
                ? DatePrecision.values[f.datePrecision!]
                : null,
            displayOrder: f.displayOrder,
            createdAt: DateTime.parse(f.createdAt),
          ),
        );
        customFieldsCreated++;
      }

      // 14. Import custom field values
      var customFieldValuesCreated = 0;
      final existingValues = await customFieldsRepository.getAllValues();
      final existingValueKeys =
          existingValues.map((v) => '${v.customFieldId}:${v.memberId}').toSet();
      for (final v in export.customFieldValues) {
        if (existingValueKeys.contains('${v.customFieldId}:${v.memberId}')) {
          continue;
        }
        await customFieldsRepository.upsertValue(
          CustomFieldValue(
            id: v.id,
            customFieldId: v.customFieldId,
            memberId: v.memberId,
            value: v.value,
          ),
        );
        customFieldValuesCreated++;
      }

      // 15. Import notes
      var notesCreated = 0;
      final existingNotes = await notesRepository.watchAllNotes().first;
      final existingNoteIds = existingNotes.map((n) => n.id).toSet();

      for (final n in export.notes) {
        if (existingNoteIds.contains(n.id)) continue;
        await notesRepository.createNote(
          Note(
            id: n.id,
            title: n.title,
            body: n.body,
            colorHex: n.colorHex,
            memberId: n.memberId,
            date: DateTime.parse(n.date),
            createdAt: DateTime.parse(n.createdAt),
            modifiedAt: DateTime.parse(n.modifiedAt),
          ),
        );
        notesCreated++;
      }

      // 16. Import front session comments
      //
      // Per spec §3.5, comments anchor to `target_time` + optional
      // `author_member_id` rather than a session FK. New-shape exports
      // already carry those fields directly; legacy-shape exports carry
      // only `sessionId` + `timestamp`, and we synthesize the new-shape
      // fields by joining `sessionId` against the just-imported parent
      // row map (`legacySessionParents`, populated above by the
      // fronting-session loop).
      //
      // Per spec §4.1 step 5: `target_time` MUST come from the comment's
      // own `timestamp` field, NOT from `created_at`. Anchoring to
      // `created_at` would shift backfilled or edited comments to the
      // wrong period.
      //
      // PK rescue rows fan out to multiple per-member rows; the spec
      // says: "Choose author_member_id from the first resolved PK
      // member of the parent switch." We stored that on
      // `legacySessionParents[s.id].memberId` above.
      var frontSessionCommentsCreated = 0;
      final existingComments =
          await frontSessionCommentsRepository.getAllComments();
      final existingCommentIds =
          existingComments.map((c) => c.id).toSet();
      for (final c in export.frontSessionComments) {
        if (existingCommentIds.contains(c.id)) continue;
        final timestamp = DateTime.parse(c.timestamp);
        final createdAt = DateTime.parse(c.createdAt);
        DateTime? targetTime;
        String? authorMemberId;
        if (c.isLegacyShape) {
          final parent = c.sessionId == null
              ? null
              : legacySessionParents[c.sessionId];
          if (parent == null) {
            // Orphaned legacy comment (parent session wasn't in the
            // file, or was already deleted before the PRISM1 export
            // ran). Fall back to the comment's own timestamp; leave
            // author null. Better than dropping the row — the user
            // can still see what was written.
            targetTime = timestamp;
            authorMemberId = null;
          } else {
            // §4.1 step 5: target_time = comment's own timestamp;
            // author = parent session's member_id.
            targetTime = timestamp;
            authorMemberId = parent.memberId;
          }
        } else {
          // New-shape comment — fields already carried on the row.
          targetTime = c.targetTime != null
              ? DateTime.parse(c.targetTime!)
              : timestamp;
          authorMemberId = c.authorMemberId;
        }
        await frontSessionCommentsRepository.createComment(
          FrontSessionComment(
            id: c.id,
            body: c.body,
            timestamp: timestamp,
            createdAt: createdAt,
            targetTime: targetTime,
            authorMemberId: authorMemberId,
          ),
        );
        frontSessionCommentsCreated++;
      }

      // 17. Import conversation categories
      var conversationCategoriesCreated = 0;
      final existingCategories = await conversationCategoriesRepository
          .watchAll()
          .first;
      final existingCategoryIds = existingCategories.map((c) => c.id).toSet();

      for (final c in export.conversationCategories) {
        if (existingCategoryIds.contains(c.id)) continue;
        await conversationCategoriesRepository.create(
          ConversationCategory(
            id: c.id,
            name: c.name,
            displayOrder: c.displayOrder,
            createdAt: DateTime.parse(c.createdAt),
            modifiedAt: DateTime.parse(c.modifiedAt),
          ),
        );
        conversationCategoriesCreated++;
      }

      // 18. Import reminders
      var remindersCreated = 0;
      final existingReminders = await remindersRepository.watchAll().first;
      final existingReminderIds = existingReminders.map((r) => r.id).toSet();

      for (final r in export.reminders) {
        if (existingReminderIds.contains(r.id)) continue;
        await remindersRepository.create(
          Reminder(
            id: r.id,
            name: r.name,
            message: r.message,
            trigger: r.trigger >= 0 && r.trigger < ReminderTrigger.values.length
                ? ReminderTrigger.values[r.trigger]
                : ReminderTrigger.scheduled,
            intervalDays: r.intervalDays,
            timeOfDay: r.timeOfDay,
            delayHours: r.delayHours,
            isActive: r.isActive,
            createdAt: DateTime.parse(r.createdAt),
            modifiedAt: DateTime.parse(r.modifiedAt),
          ),
        );
        remindersCreated++;
      }

      // 19. Import friends
      var friendsCreated = 0;
      final existingFriends = await friendsRepository.watchAll().first;
      final existingFriendIds = existingFriends.map((f) => f.id).toSet();

      for (final f in export.friends) {
        if (existingFriendIds.contains(f.id)) continue;
        await friendsRepository.createFriend(
          FriendRecord(
            id: f.id,
            displayName: f.displayName,
            peerSharingId: f.peerSharingId,
            offeredScopes: f.offeredScopes,
            publicKeyHex: f.publicKeyHex,
            // Export intentionally omits sharedSecretHex to avoid plaintext
            // secrets in backups. Re-pairing is required after restore.
            sharedSecretHex: null,
            grantedScopes: f.grantedScopes,
            isVerified: f.isVerified,
            initId: f.initId,
            createdAt: DateTime.parse(f.createdAt),
            establishedAt: f.establishedAt != null
                ? DateTime.parse(f.establishedAt!)
                : null,
            lastSyncAt: f.lastSyncAt != null
                ? DateTime.parse(f.lastSyncAt!)
                : null,
          ),
        );
        friendsCreated++;
      }

      // 20. Import media attachment metadata
      var mediaAttachmentsCreated = 0;
      final existingMediaIds = (await db.mediaAttachmentsDao.getAll())
          .map((a) => a.id)
          .toSet();

      for (final a in export.mediaAttachments) {
        if (existingMediaIds.contains(a.id)) continue;
        await db.mediaAttachmentsDao.insertAttachment(
          MediaAttachmentsCompanion.insert(
            id: a.id,
            messageId: Value(a.messageId),
            mediaId: Value(a.mediaId),
            mediaType: Value(a.mediaType),
            encryptionKeyB64: Value(a.encryptionKeyB64),
            contentHash: Value(a.contentHash),
            plaintextHash: Value(a.plaintextHash),
            mimeType: Value(a.mimeType),
            sizeBytes: Value(a.sizeBytes),
            width: Value(a.width),
            height: Value(a.height),
            durationMs: Value(a.durationMs),
            blurhash: Value(a.blurhash),
            waveformB64: Value(a.waveformB64),
            thumbnailMediaId: Value(a.thumbnailMediaId),
            isDeleted: Value(a.isDeleted),
          ),
        );
        mediaAttachmentsCreated++;
      }

      return ImportResult(
        membersCreated: membersCreated,
        frontSessionsCreated: frontSessionsCreated,
        sleepSessionsCreated: sleepSessionsCreated,
        conversationsCreated: conversationsCreated,
        messagesCreated: messagesCreated,
        pollsCreated: pollsCreated,
        pollOptionsCreated: pollOptionsCreated,
        settingsUpdated: settingsUpdated,
        habitsCreated: habitsCreated,
        habitCompletionsCreated: habitCompletionsCreated,
        memberGroupsCreated: memberGroupsCreated,
        memberGroupEntriesCreated: memberGroupEntriesCreated,
        customFieldsCreated: customFieldsCreated,
        customFieldValuesCreated: customFieldValuesCreated,
        notesCreated: notesCreated,
        frontSessionCommentsCreated: frontSessionCommentsCreated,
        conversationCategoriesCreated: conversationCategoriesCreated,
        remindersCreated: remindersCreated,
        friendsCreated: friendsCreated,
        mediaAttachmentsCreated: mediaAttachmentsCreated,
        legacyPkShortIdsSkipped: legacyPkShortIdsSkipped,
        legacyCorruptCoFronterRows: List.unmodifiable(
          legacyCorruptCoFronterRows,
        ),
        unknownSentinelCreated: unknownSentinelCreated,
      );
      });
    } catch (e) {
      // Transaction failed — delete temp media files to avoid orphans
      if (mediaDir != null) await _cleanupTempMedia(mediaBlobs, mediaDir);
      rethrow;
    }

    // Atomically rename temp media files to final paths after DB commit
    if (mediaDir != null) await _finalizeMedia(mediaBlobs, mediaDir);

    return result;
  }

  Future<Directory> _mediaDirectory() async {
    final appSupport = await _appSupportDirectoryProvider();
    final dir = Directory('${appSupport.path}/prism_media');
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> _writeMediaToTemp(
    List<({String mediaId, Uint8List blob})> blobs,
    Directory mediaDir,
  ) async {
    for (final entry in blobs) {
      if (!_uuidRegex.hasMatch(entry.mediaId)) {
        throw FormatException('Invalid media ID: ${entry.mediaId}');
      }
      final tmp = File('${mediaDir.path}/${entry.mediaId}.enc.tmp');
      await tmp.writeAsBytes(entry.blob);
    }
  }

  Future<void> _finalizeMedia(
    List<({String mediaId, Uint8List blob})> blobs,
    Directory mediaDir,
  ) async {
    for (final entry in blobs) {
      final tmp = File('${mediaDir.path}/${entry.mediaId}.enc.tmp');
      await tmp.rename('${mediaDir.path}/${entry.mediaId}.enc');
    }
  }

  Future<void> _cleanupTempMedia(
    List<({String mediaId, Uint8List blob})> blobs,
    Directory mediaDir,
  ) async {
    for (final entry in blobs) {
      try {
        final tmp = File('${mediaDir.path}/${entry.mediaId}.enc.tmp');
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }
  }

  /// Resolve a PK member full UUID to the local Prism member id by
  /// scanning the members table. Used by the PRISM1 rescue importer
  /// (§4.7) to derive `author_member_id` for legacy comments anchored
  /// to PK switches and to populate `member_id` on the per-member
  /// fan-out rows.
  ///
  /// Returns null when no local member matches — the rescue path
  /// counts that as a skip rather than crashing.
  Future<String?> _localMemberIdForPkUuid(String? pkUuid) async {
    if (pkUuid == null || pkUuid.isEmpty) return null;
    final allMembers = await memberRepository.getAllMembers();
    for (final m in allMembers) {
      if (m.pluralkitUuid == pkUuid) return m.id;
    }
    return null;
  }

  /// Reverse of [_localMemberIdForPkUuid] — returns the local member's
  /// `pluralkit_uuid` (the FULL UUID, not the 5-char `pluralkit_id`
  /// short id) given its local Prism member id. Used by the rescue
  /// importer's empty-`pkMemberIdsJson` fallback (§4.7) to derive the
  /// canonical (switch, member) id that the live PK API importer would
  /// produce — without it, the rescue and API legs land on different
  /// ids and lose the field-LWW boundary correction.
  Future<String?> _pkUuidForLocalMemberId(String localId) async {
    if (localId.isEmpty) return null;
    final allMembers = await memberRepository.getAllMembers();
    for (final m in allMembers) {
      if (m.id == localId) {
        final uuid = m.pluralkitUuid;
        return (uuid == null || uuid.isEmpty) ? null : uuid;
      }
    }
    return null;
  }
}

/// Legacy-shape parent-session info captured during the fronting-session
/// rescue pass and consumed by the comments rescue pass to derive
/// `target_time` / `author_member_id` per spec §4.1 step 5.
///
/// Populated for every legacy session row regardless of its rescue
/// disposition (PK fan-out, SP 1:1, native primary, native co-fronter,
/// orphan sentinel) so the comment join always finds a parent. For PK
/// rescue rows, `memberId` is the local id of the **first resolved PK
/// member** of the parent switch — the spec's chosen author proxy when
/// the original switch had multiple fronters.
class _LegacyParentInfo {
  const _LegacyParentInfo({this.memberId, required this.startTime});
  final String? memberId;
  final DateTime startTime;
}
