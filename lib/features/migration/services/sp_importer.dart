import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show TableUpdate, Value;
import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    show
        AppDatabase,
        ChatMessagesCompanion,
        ConversationCategoriesCompanion,
        ConversationsCompanion,
        CustomFieldValuesCompanion,
        CustomFieldsCompanion,
        FrontSessionCommentsCompanion,
        FrontingSessionsCompanion,
        MemberBoardPostsCompanion,
        MemberGroupEntriesCompanion,
        MemberGroupEntryRow,
        MemberGroupRow,
        MemberGroupsCompanion,
        MembersCompanion,
        NotesCompanion,
        PollOptionsCompanion,
        PollVotesCompanion,
        PollsCompanion,
        RemindersCompanion,
        SpIdMapTableCompanion,
        SpSyncStateTableCompanion;
import 'package:prism_plurality/core/database/daos/sp_import_dao.dart';
import 'package:prism_plurality/core/services/media/media_service.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart'
    show triggerOutboxDrain;
import 'package:prism_plurality/core/sync/sync_runtime_state.dart';
import 'package:prism_plurality/data/mappers/chat_message_mapper.dart';
import 'package:prism_plurality/data/mappers/conversation_category_mapper.dart';
import 'package:prism_plurality/data/mappers/conversation_mapper.dart';
import 'package:prism_plurality/data/mappers/custom_field_mapper.dart';
import 'package:prism_plurality/data/mappers/custom_field_value_mapper.dart';
import 'package:prism_plurality/data/mappers/front_session_comment_mapper.dart';
import 'package:prism_plurality/data/mappers/fronting_session_mapper.dart';
import 'package:prism_plurality/data/mappers/member_board_post_mapper.dart';
import 'package:prism_plurality/data/mappers/member_group_mapper.dart';
import 'package:prism_plurality/data/mappers/member_mapper.dart';
import 'package:prism_plurality/data/mappers/note_mapper.dart';
import 'package:prism_plurality/data/mappers/poll_mapper.dart';
import 'package:prism_plurality/data/mappers/poll_option_mapper.dart';
import 'package:prism_plurality/data/mappers/poll_vote_mapper.dart';
import 'package:prism_plurality/data/mappers/reminder_mapper.dart';
import 'package:prism_plurality/data/repositories/drift_chat_message_repository.dart';
import 'package:prism_plurality/data/repositories/drift_conversation_categories_repository.dart';
import 'package:prism_plurality/data/repositories/drift_conversation_repository.dart';
import 'package:prism_plurality/data/repositories/drift_custom_fields_repository.dart';
import 'package:prism_plurality/data/repositories/drift_front_session_comments_repository.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_board_posts_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_groups_repository.dart';
import 'package:prism_plurality/data/repositories/drift_media_attachment_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/data/repositories/drift_notes_repository.dart';
import 'package:prism_plurality/data/repositories/drift_poll_repository.dart';
import 'package:prism_plurality/data/repositories/drift_reminders_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/repositories/media_attachment_repository.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/members/services/bio_image_importer.dart';
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/domain/repositories/conversation_repository.dart';
import 'package:prism_plurality/domain/repositories/chat_message_repository.dart';
import 'package:prism_plurality/domain/repositories/poll_repository.dart';
import 'package:prism_plurality/domain/repositories/notes_repository.dart';
import 'package:prism_plurality/domain/repositories/front_session_comments_repository.dart';
import 'package:prism_plurality/domain/repositories/custom_fields_repository.dart';
import 'package:prism_plurality/domain/repositories/member_groups_repository.dart';
import 'package:prism_plurality/domain/repositories/reminders_repository.dart';
import 'package:prism_plurality/domain/repositories/conversation_categories_repository.dart';
import 'package:prism_plurality/domain/repositories/system_settings_repository.dart';
import 'package:prism_plurality/domain/repositories/member_board_posts_repository.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';
import 'package:prism_plurality/features/migration/services/sp_mapper.dart';
import 'package:prism_plurality/features/migration/services/sp_avatar_zip_importer.dart';
import 'package:prism_plurality/features/migration/services/sp_custom_front_disposition.dart';
import 'package:prism_plurality/features/migration/services/sp_member_mapping.dart';
import 'package:prism_plurality/shared/utils/avatar_fetcher.dart';

/// Import progress state.
enum ImportState {
  idle,
  parsing,
  verifying,
  fetching,
  encryptedChatsDetected,
  previewing,
  matchMembers,
  chooseDispositions,
  importing,
  downloadingAvatars,
  complete,
  error,
}

/// Where the import data came from.
enum ImportSource { file, api }

/// Result of a completed import.
class ImportResult {
  final int membersImported;
  final int membersLinked;
  final int sessionsImported;
  final int conversationsImported;
  final int messagesImported;
  final int pollsImported;
  final int notesImported;
  final int commentsImported;
  final int customFieldsImported;
  final int groupsImported;
  final int remindersImported;
  final int boardPostsImported;
  final int avatarsDownloaded;
  final bool systemAvatarDownloaded;
  final int avatarsImportedFromZip;
  final bool systemAvatarImportedFromZip;
  final List<String> warnings;
  final Duration duration;

  const ImportResult({
    required this.membersImported,
    this.membersLinked = 0,
    required this.sessionsImported,
    required this.conversationsImported,
    required this.messagesImported,
    required this.pollsImported,
    this.notesImported = 0,
    this.commentsImported = 0,
    this.customFieldsImported = 0,
    this.groupsImported = 0,
    this.remindersImported = 0,
    this.boardPostsImported = 0,
    required this.avatarsDownloaded,
    this.systemAvatarDownloaded = false,
    this.avatarsImportedFromZip = 0,
    this.systemAvatarImportedFromZip = false,
    required this.warnings,
    required this.duration,
  });

  int get totalImported =>
      membersImported +
      sessionsImported +
      conversationsImported +
      messagesImported +
      pollsImported +
      notesImported +
      commentsImported +
      customFieldsImported +
      groupsImported +
      remindersImported +
      boardPostsImported;

  static bool isAvatarDownloadWarning(String warning) {
    final normalized = warning.toLowerCase();
    return normalized.contains('avatar') && normalized.contains('download');
  }

  bool get hasAvatarDownloadFailures => warnings.any(isAvatarDownloadWarning);

  ImportResult copyWith({
    int? membersImported,
    int? membersLinked,
    int? sessionsImported,
    int? conversationsImported,
    int? messagesImported,
    int? pollsImported,
    int? notesImported,
    int? commentsImported,
    int? customFieldsImported,
    int? groupsImported,
    int? remindersImported,
    int? boardPostsImported,
    int? avatarsDownloaded,
    bool? systemAvatarDownloaded,
    int? avatarsImportedFromZip,
    bool? systemAvatarImportedFromZip,
    List<String>? warnings,
    Duration? duration,
  }) {
    return ImportResult(
      membersImported: membersImported ?? this.membersImported,
      membersLinked: membersLinked ?? this.membersLinked,
      sessionsImported: sessionsImported ?? this.sessionsImported,
      conversationsImported:
          conversationsImported ?? this.conversationsImported,
      messagesImported: messagesImported ?? this.messagesImported,
      pollsImported: pollsImported ?? this.pollsImported,
      notesImported: notesImported ?? this.notesImported,
      commentsImported: commentsImported ?? this.commentsImported,
      customFieldsImported: customFieldsImported ?? this.customFieldsImported,
      groupsImported: groupsImported ?? this.groupsImported,
      remindersImported: remindersImported ?? this.remindersImported,
      boardPostsImported: boardPostsImported ?? this.boardPostsImported,
      avatarsDownloaded: avatarsDownloaded ?? this.avatarsDownloaded,
      systemAvatarDownloaded:
          systemAvatarDownloaded ?? this.systemAvatarDownloaded,
      avatarsImportedFromZip:
          avatarsImportedFromZip ?? this.avatarsImportedFromZip,
      systemAvatarImportedFromZip:
          systemAvatarImportedFromZip ?? this.systemAvatarImportedFromZip,
      warnings: warnings ?? this.warnings,
      duration: duration ?? this.duration,
    );
  }
}

/// Handles the full SP import workflow.
class SpImporter {
  static const _defaultUuid = Uuid();
  static String _defaultNewId() => _defaultUuid.v4();
  static DateTime _defaultNow() => DateTime.now();

  static const _uiYieldEveryItems = 20;

  /// [newId] and [now] are determinism seams matching `SpMapper`'s.
  /// Production callers leave them defaulted (`Uuid().v4()`, `DateTime.now`);
  /// the Phase 0 parity harness injects seeded versions so golden artifacts
  /// are byte-stable across runs.
  ///
  /// When seams are injected, the parse+map path bypasses [compute] because
  /// closures over test-only instance state (seeded RNG / fixed clock) are
  /// not sendable across an isolate boundary. Production callers leave the
  /// seams defaulted, so parse+map runs on a background isolate via
  /// [compute] to keep the UI thread responsive — see Phase 1 of
  /// `docs/plans/sp-import-perf-quick-wins.md`.
  SpImporter({
    http.Client? httpClient,
    String Function()? newId,
    DateTime Function()? now,
  }) : _http = httpClient ?? http.Client(),
       _newId = newId ?? _defaultNewId,
       _now = now ?? _defaultNow,
       _seamsInjected = newId != null || now != null;

  final http.Client _http;
  final String Function() _newId;
  final DateTime Function() _now;

  /// True iff the caller injected a non-default `newId` or `now` seam.
  /// Used to decide whether parse+map can cross an isolate boundary via
  /// [compute] — injected seams cannot, default top-level functions can.
  final bool _seamsInjected;

  /// Parse an export file and return structured data.
  ///
  /// The file read is async and the JSON parse runs on a background isolate
  /// via [compute] so multi-MB SP exports don't stall the UI thread —
  /// Phase 1 of `docs/plans/sp-import-perf-quick-wins.md`.
  Future<SpExportData> parseFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File not found', filePath);
    }
    final contents = await file.readAsString();
    return compute(_parseJson, contents);
  }

  /// Parse an export JSON string directly.
  SpExportData parseString(String jsonString) {
    return SpParser.parse(jsonString);
  }

  /// Parse export bytes directly.
  ///
  /// Used by file pickers that provide in-memory bytes instead of a durable
  /// local path. Decoding and JSON parsing both run on a background isolate so
  /// large onboarding imports do not stall the UI thread.
  Future<SpExportData> parseBytes(Uint8List bytes) {
    return compute(_parseBytes, bytes);
  }

  /// Execute the import after user confirmation.
  ///
  /// Entity data is imported inside a single database transaction so that a
  /// mid-import failure rolls back all changes, leaving the database unchanged.
  ///
  /// Avatar downloads happen via network and cannot be transactional, so they
  /// run after the transaction commits (best-effort).
  ///
  /// [onProgress] is called with (current, total) counts during import.
  Future<ImportResult> executeImport({
    required AppDatabase db,
    required SpExportData data,
    required MemberRepository memberRepo,
    required FrontingSessionRepository sessionRepo,
    required ConversationRepository conversationRepo,
    required ChatMessageRepository messageRepo,
    required PollRepository pollRepo,
    NotesRepository? notesRepo,
    FrontSessionCommentsRepository? commentsRepo,
    CustomFieldsRepository? customFieldsRepo,
    MemberGroupsRepository? groupsRepo,
    RemindersRepository? remindersRepo,
    ConversationCategoriesRepository? categoriesRepo,
    SystemSettingsRepository? settingsRepo,
    MemberBoardPostsRepository? boardPostsRepo,
    SpImportDao? spImportDao,
    MediaService? mediaService,
    MediaAttachmentRepository? mediaAttachmentRepo,
    bool downloadAvatars = true,
    String? avatarZipPath,
    List<int>? avatarZipBytes,
    bool clearExistingData = false,
    Map<String, CfDisposition>? customFrontDispositions,
    Map<String, SpMemberMappingDecision> memberMappingDecisions = const {},
    void Function(int current, int total, String label)? onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();

    // Load existing SP→Prism ID mappings so a re-import reuses stable UUIDs.
    final existingMappings = await _loadExistingMappings(spImportDao);
    _discardUnknownSentinelMemberMappings(existingMappings, data.members);
    final linkedExistingMemberIds = <String>{};
    final importAsNewSpIds = {
      for (final decision in memberMappingDecisions.values)
        if (decision is SpImportMemberDecision) decision.spMemberId,
    };
    if (!clearExistingData) {
      await _sanitizeMemberMappings(existingMappings, data.members, memberRepo);
      linkedExistingMemberIds.addAll(
        await _applyMemberMappingDecisions(
          existingMappings,
          memberMappingDecisions,
          data.members,
          memberRepo,
        ),
      );
      linkedExistingMemberIds.addAll(
        await _seedMemberMappingsFromExistingLocals(
          existingMappings,
          data.members,
          memberRepo,
          claimedLocalIds: linkedExistingMemberIds,
          blockedSpIds: importAsNewSpIds,
        ),
      );
      await _sanitizeMemberMappings(existingMappings, data.members, memberRepo);
    }

    // Phase 1: run SP mapping on a background isolate to keep the UI thread
    // responsive on multi-MB exports. The isolate hop only happens on the
    // production path; tests inject seeded `newId`/`now` closures that close
    // over instance state and therefore cannot cross an isolate boundary,
    // so they fall through to the inline path.
    //
    // The result carries every mapper-instance field downstream code reads
    // (`pendingStaleMappingDeletes`, per-entity ID maps) because the mapper
    // object itself doesn't survive the isolate boundary.
    final _MapResult mapResult;
    if (_seamsInjected) {
      final mapper = SpMapper(
        existingMappings: existingMappings,
        customFrontDispositions: customFrontDispositions,
        importAsNewSpMemberIds: importAsNewSpIds,
        newId: _newId,
        now: _now,
      );
      final mapped = mapper.mapAll(data);
      mapResult = _MapResult.fromMapper(mapped, mapper);
    } else {
      mapResult = await compute(
        _mapOnIsolate,
        _MapArgs(
          data: data,
          existingMappings: existingMappings,
          customFrontDispositions: customFrontDispositions,
          importAsNewSpMemberIds: importAsNewSpIds,
        ),
      );
    }
    final mapped = mapResult.mapped;
    final pendingStaleMappingDeletes = mapResult.pendingStaleMappingDeletes;
    final memberIdMap = mapResult.memberIdMap;
    final channelIdMap = mapResult.channelIdMap;
    final sessionIdMap = mapResult.sessionIdMap;
    final groupIdMap = mapResult.groupIdMap;
    final fieldIdMap = mapResult.fieldIdMap;
    final categoryIdMap = mapResult.categoryIdMap;
    await _yieldToUi();

    final totalItems =
        mapped.members.length +
        mapped.sessions.length +
        mapped.conversationCategories.length +
        mapped.conversations.length +
        mapped.messages.length +
        mapped.polls.length +
        mapped.notes.length +
        mapped.frontComments.length +
        mapped.customFields.length +
        mapped.customFieldValues.length +
        mapped.groups.length +
        mapped.groupMemberships.length +
        mapped.reminders.length +
        mapped.boardPosts.length;
    var currentItem = 0;
    Future<void> didImportOne() async {
      currentItem++;
      if (currentItem % _uiYieldEveryItems == 0) {
        await _yieldToUi();
      }
    }

    // Import all entity data atomically. If any insert fails the entire
    // transaction is rolled back and the exception propagates to the caller.
    // When clearExistingData is true, the wipe happens inside the same
    // transaction so a failed import rolls back everything — no data loss.
    var membersImported = 0;
    var membersLinked = 0;

    // Phase 5 of `docs/plans/sp-import-perf-quick-wins.md`: every repo-issued
    // sync emission inside the transaction is intercepted into `captured`,
    // and replayed via FFI *after* the transaction commits. Removing FFI
    // calls (and their `jsonEncode` payload work) from the transaction
    // critical path is the dominant performance win — on unpaired devices
    // it also bypasses `SyncRecordMixin`'s 1s-per-row retry spin during
    // `syncAutoConfigureInProgress`. If the transaction throws, the exception
    // propagates out of `suppressAndCapture` (whose suppression zone exits)
    // and out of this method before the replay loop below — the captured list
    // is dropped and replay never runs (zero emissions on rollback —
    // `sp_import_parity_test.dart` assertion 4).
    final captured = <CapturedSyncOp>[];
    await SyncRecordMixin.suppressAndCapture(() async {
      await db.transaction(() async {
        // Scrub stale CF-as-member persisted mappings (plan §Classification)
        // inside the transaction so a failed import rolls back the scrub too.
        // Done before upserting new mappings so the DAO ends up consistent
        // with the user's updated disposition choices.
        if (spImportDao != null && pendingStaleMappingDeletes.isNotEmpty) {
          await spImportDao.deleteMappings(
            pendingStaleMappingDeletes,
            'member',
          );
        }

        if (clearExistingData) {
          onProgress?.call(0, totalItems, 'Clearing existing data...');
          await db.customStatement('DELETE FROM habit_completions');
          await db.customStatement('DELETE FROM habits');
          await db.customStatement('DELETE FROM poll_votes');
          await db.customStatement('DELETE FROM poll_options');
          await db.customStatement('DELETE FROM polls');
          await db.customStatement('DELETE FROM chat_messages');
          await db.customStatement('DELETE FROM conversation_categories');
          await db.customStatement('DELETE FROM conversations');
          await db.customStatement('DELETE FROM front_session_comments');
          await db.customStatement('DELETE FROM fronting_sessions');
          await db.customStatement('DELETE FROM custom_field_values');
          await db.customStatement('DELETE FROM custom_fields');
          await db.customStatement('DELETE FROM member_group_entries');
          await db.customStatement('DELETE FROM member_groups');
          await db.customStatement('DELETE FROM notes');
          await db.customStatement('DELETE FROM reminders');
          await db.customStatement('DELETE FROM member_board_posts');
          await db.customStatement('DELETE FROM members');
          // customStatement bypasses Drift's typed-write notification.
          // The SP import is followed by an app reload, so live UI never
          // observes the intermediate truncated state — but we notify
          // defensively in case a future caller skips the reload, so the
          // frontingTableTickerProvider and any active streams refresh.
          db.notifyUpdates({
            const TableUpdate('habit_completions'),
            const TableUpdate('habits'),
            const TableUpdate('poll_votes'),
            const TableUpdate('poll_options'),
            const TableUpdate('polls'),
            const TableUpdate('chat_messages'),
            const TableUpdate('conversation_categories'),
            const TableUpdate('conversations'),
            const TableUpdate('front_session_comments'),
            const TableUpdate('fronting_sessions'),
            const TableUpdate('custom_field_values'),
            const TableUpdate('custom_fields'),
            const TableUpdate('member_group_entries'),
            const TableUpdate('member_groups'),
            const TableUpdate('notes'),
            const TableUpdate('reminders'),
            const TableUpdate('member_board_posts'),
            const TableUpdate('members'),
          });
          await _yieldToUi();
        }

        // Phase 6 (`docs/plans/sp-import-perf-quick-wins.md`): every SP entity
        // is batch-inserted via Drift `batch()` instead of looped repository
        // create*() calls. The batch DAO methods bypass `SyncRecordMixin`, so
        // we push captured tuples manually using the public-static field-map
        // helper for each entity. Combined with Phase 5's suppressAndCapture
        // scaffold, the transaction does one round-trip per entity type
        // instead of one per row — and the replay loop after commit fires
        // byte-equal emissions matching the per-row path.

        // 1. Import members — one batch insert + one captured tuple per new row.
        //    Pre-resolve existing-member/tombstone detection with a single
        //    getAllMembersIncludingDeleted pass instead of N getMemberById()
        //    round-trips (review).
        final existingMembers = await memberRepo
            .getAllMembersIncludingDeleted();
        final existingMemberIds = {for (final m in existingMembers) m.id};
        final existingPluralKitIds = {
          for (final m in existingMembers)
            if (m.pluralkitId != null && m.pluralkitId!.isNotEmpty)
              m.pluralkitId!,
        };
        final existingPluralKitUuids = {
          for (final m in existingMembers)
            if (m.pluralkitUuid != null && m.pluralkitUuid!.isNotEmpty)
              m.pluralkitUuid!,
        };
        final newMemberCompanions = <MembersCompanion>[];
        final newMemberFieldsById = <String, Map<String, dynamic>>{};
        for (final member in mapped.members) {
          onProgress?.call(currentItem, totalItems, 'Importing members...');
          if (existingMemberIds.contains(member.id)) {
            membersLinked++;
            await didImportOne();
            continue;
          }
          final pkIdCollides =
              member.pluralkitId != null &&
              member.pluralkitId!.isNotEmpty &&
              existingPluralKitIds.contains(member.pluralkitId);
          final pkUuidCollides =
              member.pluralkitUuid != null &&
              member.pluralkitUuid!.isNotEmpty &&
              existingPluralKitUuids.contains(member.pluralkitUuid);
          final memberForInsert = pkIdCollides || pkUuidCollides
              ? member.copyWith(pluralkitId: null, pluralkitUuid: null)
              : member;
          newMemberCompanions.add(MemberMapper.toCompanion(memberForInsert));
          newMemberFieldsById[member.id] = DriftMemberRepository.memberFields(
            memberForInsert,
          );
          membersImported++;
          await didImportOne();
        }
        if (newMemberCompanions.isNotEmpty) {
          await db.membersDao.batchInsertMembers(newMemberCompanions);
          for (final entry in newMemberFieldsById.entries) {
            captured.add(
              CapturedSyncOp(
                'members',
                entry.key,
                SyncRecordOpType.create,
                entry.value,
              ),
            );
          }
        }

        // 2. Import custom field definitions + values.
        if (customFieldsRepo != null) {
          final fieldCompanions = <CustomFieldsCompanion>[];
          final fieldEmissions = <CapturedSyncOp>[];
          for (final field in mapped.customFields) {
            onProgress?.call(
              currentItem,
              totalItems,
              'Importing custom fields...',
            );
            fieldCompanions.add(CustomFieldMapper.toCompanion(field));
            fieldEmissions.add(
              CapturedSyncOp(
                'custom_fields',
                field.id,
                SyncRecordOpType.create,
                DriftCustomFieldsRepository.fieldFields(field),
              ),
            );
            await didImportOne();
          }
          if (fieldCompanions.isNotEmpty) {
            await db.customFieldsDao.batchInsertFields(fieldCompanions);
            captured.addAll(fieldEmissions);
          }

          final valueCompanions = <CustomFieldValuesCompanion>[];
          final valueEmissions = <CapturedSyncOp>[];
          for (final value in mapped.customFieldValues) {
            onProgress?.call(
              currentItem,
              totalItems,
              'Importing field values...',
            );
            valueCompanions.add(CustomFieldValueMapper.toCompanion(value));
            valueEmissions.add(
              CapturedSyncOp(
                'custom_field_values',
                value.id,
                SyncRecordOpType.create,
                DriftCustomFieldsRepository.valueFields(value),
              ),
            );
            await didImportOne();
          }
          if (valueCompanions.isNotEmpty) {
            await db.customFieldsDao.batchUpsertValues(valueCompanions);
            captured.addAll(valueEmissions);
          }
        }

        // 3. Import groups + memberships.
        //
        // The repository's `createGroup` overrides `displayOrder` via
        // `nextDisplayOrder(parentGroupId)` per row. We mirror that here by
        // computing a per-parent counter once, starting from the current max,
        // and incrementing in-memory as we walk the mapped list. This keeps
        // the on-wire `display_order` byte-equal to the live-edit path.
        if (groupsRepo != null) {
          final groupCompanions = <MemberGroupsCompanion>[];
          final groupRows = <MemberGroupRow>[];
          final nextOrderByParent = <String?, int>{};
          for (final group in mapped.groups) {
            onProgress?.call(currentItem, totalItems, 'Importing groups...');
            final parent = group.parentGroupId;
            final nextOrder =
                nextOrderByParent[parent] ??
                await db.memberGroupsDao.nextDisplayOrder(parent);
            nextOrderByParent[parent] = nextOrder + 1;
            final withOrder = group.copyWith(displayOrder: nextOrder);
            groupCompanions.add(MemberGroupMapper.toCompanion(withOrder));
            await didImportOne();
          }
          if (groupCompanions.isNotEmpty) {
            await db.memberGroupsDao.batchInsertGroups(groupCompanions);
            // Re-read stored rows so the captured emission carries the exact
            // on-disk shape (matches the repo's `_requireGroupRow` → emit
            // pattern in `createGroup`).
            for (final companion in groupCompanions) {
              final stored = await db.memberGroupsDao.getGroupById(
                companion.id.value,
              );
              if (stored != null) groupRows.add(stored);
            }
            for (final row in groupRows) {
              // SP groups have no PluralKit link, so `_shouldEmitPkBackedGroupSync`
              // returns true (non-PK groups always emit). `isGroupSyncSuppressed`
              // is false for freshly imported rows. The canonical entity id is
              // the row id itself (no `pk-group:` prefix without a PK uuid).
              captured.add(
                CapturedSyncOp(
                  'member_groups',
                  row.id,
                  SyncRecordOpType.create,
                  DriftMemberGroupsRepository.groupFields(row),
                ),
              );
            }
          }

          // Group memberships. SP groups never carry a PluralKit link, so:
          //   * `isPkLinked` is always false → `pendingPkOp = 'none'`, no
          //     SHA-deterministic id, plain insert with the caller-supplied
          //     entryId.
          //   * The captured entity id is the entry's row id (fallback path
          //     in `_entryEntityId`).
          //   * `isGroupSyncSuppressed` is false for freshly-imported groups.
          //   * `_canEmitPkBackedEntry` returns true when no pk uuids are set.
          // We still build the captured tuple via the public-static
          // `memberGroupEntryFields` helper so the wire-level payload is
          // single-sourced — field-map drift here would surface as a
          // unit-test failure in `field_map_helper_test.dart`. The mandatory
          // parity test (`test/data/repositories/member_groups_batch_parity_test.dart`)
          // covers the PK-linked, suppressed, duplicate, and soft-deleted
          // scenarios the SP path doesn't hit.
          final entryCompanions = <MemberGroupEntriesCompanion>[];
          final entryEmissions = <CapturedSyncOp>[];
          final entryIdsByGroup = <String, List<String>>{};
          // Cache group rows by id so we don't issue N getGroupById round-trips
          // when building the captured tuples; we already inserted the rows in
          // this transaction and have them in `groupRows`.
          final groupRowsById = {for (final g in groupRows) g.id: g};
          for (final entry in mapped.groupMemberships) {
            onProgress?.call(
              currentItem,
              totalItems,
              'Importing group members...',
            );
            final entryId = _newId();
            final groupId = entry.key;
            final memberId = entry.value;
            final companion = MemberGroupEntriesCompanion(
              id: Value(entryId),
              groupId: Value(groupId),
              memberId: Value(memberId),
              pkGroupUuid: const Value(null),
              pkMemberUuid: const Value(null),
              isDeleted: const Value(false),
              pendingPkOp: const Value('none'),
            );
            entryCompanions.add(companion);
            (entryIdsByGroup[groupId] ??= <String>[]).add(entryId);

            final groupRow = groupRowsById[groupId];
            if (groupRow == null) {
              // Should never happen — the mapper only emits memberships for
              // imported groups. Skip the emission rather than crash if a
              // future mapper change violates the invariant.
              await didImportOne();
              continue;
            }
            // Synthesize the stored entry row from the companion so the field
            // helper sees the same shape as the live-edit `findEntry(...)`
            // result. is_deleted=false, pending_pk_op='none', null pk uuids.
            final storedEntry = MemberGroupEntryRow(
              id: entryId,
              groupId: groupId,
              memberId: memberId,
              pkGroupUuid: null,
              pkMemberUuid: null,
              isDeleted: false,
              pendingPkOp: 'none',
              // SP entries are never PK-linked: random v4 id, gen 0, no
              // deterministic-id collision to gate against.
              syncGeneration: 0,
            );
            entryEmissions.add(
              CapturedSyncOp(
                'member_group_entries',
                entryId,
                SyncRecordOpType.create,
                DriftMemberGroupsRepository.memberGroupEntryFields(
                  storedEntry,
                  group: groupRow,
                  member: null, // non-PK SP path; member uuid not consulted.
                ),
              ),
            );
            await didImportOne();
          }
          if (entryCompanions.isNotEmpty) {
            await db.memberGroupsDao.batchInsertEntries(entryCompanions);
            final groupSortEmissions = <CapturedSyncOp>[];
            for (final groupEntry in entryIdsByGroup.entries) {
              final groupRow = groupRowsById[groupEntry.key];
              if (groupRow == null) continue;
              final current = tryDecodeSortState(groupRow.sortState);
              if (current == null || !current.isManual) continue;

              final seen = current.manualOrder.toSet();
              final appended = <String>[];
              for (final entryId in groupEntry.value) {
                if (seen.add(entryId)) appended.add(entryId);
              }
              if (appended.isEmpty) continue;

              final nextState = current.copyWith(
                manualOrder: [...current.manualOrder, ...appended],
              );
              await db.memberGroupsDao.updateGroupSortState(
                groupEntry.key,
                MemberGroupMapper.encodeSortStateForColumn(nextState),
              );
              final refreshed = await db.memberGroupsDao.getGroupById(
                groupEntry.key,
              );
              if (refreshed == null) continue;
              groupRowsById[groupEntry.key] = refreshed;
              groupSortEmissions.add(
                CapturedSyncOp(
                  'member_groups',
                  refreshed.id,
                  SyncRecordOpType.update,
                  <String, dynamic>{
                    'sort_state': sanitizeSortStateForEmission(
                      refreshed.sortState,
                      contextId: refreshed.id,
                    ),
                  },
                ),
              );
            }
            captured.addAll(entryEmissions);
            captured.addAll(groupSortEmissions);
          }
        }

        // 4. Import fronting sessions.
        final sessionCompanions = <FrontingSessionsCompanion>[];
        final sessionEmissions = <CapturedSyncOp>[];
        for (final session in mapped.sessions) {
          onProgress?.call(
            currentItem,
            totalItems,
            'Importing front history...',
          );
          sessionCompanions.add(FrontingSessionMapper.toCompanion(session));
          sessionEmissions.add(
            CapturedSyncOp(
              'fronting_sessions',
              session.id,
              SyncRecordOpType.create,
              DriftFrontingSessionRepository.sessionFields(session),
            ),
          );
          await didImportOne();
        }
        if (sessionCompanions.isNotEmpty) {
          await db.frontingSessionsDao.batchInsertSessions(sessionCompanions);
          captured.addAll(sessionEmissions);
        }

        // 5. Import notes.
        if (notesRepo != null) {
          final noteCompanions = <NotesCompanion>[];
          final noteEmissions = <CapturedSyncOp>[];
          for (final note in mapped.notes) {
            onProgress?.call(currentItem, totalItems, 'Importing notes...');
            noteCompanions.add(NoteMapper.toCompanion(note));
            noteEmissions.add(
              CapturedSyncOp(
                'notes',
                note.id,
                SyncRecordOpType.create,
                DriftNotesRepository.noteFields(note),
              ),
            );
            await didImportOne();
          }
          if (noteCompanions.isNotEmpty) {
            await db.notesDao.batchInsertNotes(noteCompanions);
            captured.addAll(noteEmissions);
          }
        }

        // 6. Import front session comments.
        if (commentsRepo != null) {
          final commentCompanions = <FrontSessionCommentsCompanion>[];
          final commentEmissions = <CapturedSyncOp>[];
          for (final comment in mapped.frontComments) {
            onProgress?.call(currentItem, totalItems, 'Importing comments...');
            commentCompanions.add(
              FrontSessionCommentMapper.toCompanion(comment),
            );
            commentEmissions.add(
              CapturedSyncOp(
                'front_session_comments',
                comment.id,
                SyncRecordOpType.create,
                DriftFrontSessionCommentsRepository.commentFields(comment),
              ),
            );
            await didImportOne();
          }
          if (commentCompanions.isNotEmpty) {
            await db.frontSessionCommentsDao.batchInsertComments(
              commentCompanions,
            );
            captured.addAll(commentEmissions);
          }
        }

        // 7. Import conversation categories.
        if (categoriesRepo != null) {
          final categoryCompanions = <ConversationCategoriesCompanion>[];
          final categoryEmissions = <CapturedSyncOp>[];
          for (final cat in mapped.conversationCategories) {
            onProgress?.call(
              currentItem,
              totalItems,
              'Importing categories...',
            );
            categoryCompanions.add(ConversationCategoryMapper.toCompanion(cat));
            categoryEmissions.add(
              CapturedSyncOp(
                'conversation_categories',
                cat.id,
                SyncRecordOpType.create,
                DriftConversationCategoriesRepository.categoryFields(cat),
              ),
            );
            await didImportOne();
          }
          if (categoryCompanions.isNotEmpty) {
            await db.conversationCategoriesDao.batchInsertCategories(
              categoryCompanions,
            );
            captured.addAll(categoryEmissions);
          }
        }

        // 8. Import conversations.
        final conversationCompanions = <ConversationsCompanion>[];
        final conversationEmissions = <CapturedSyncOp>[];
        for (final conversation in mapped.conversations) {
          onProgress?.call(
            currentItem,
            totalItems,
            'Importing conversations...',
          );
          conversationCompanions.add(
            ConversationMapper.toCompanion(conversation),
          );
          final convFields = DriftConversationRepository.conversationFields(
            conversation,
          );
          // Sparse-emit for pre-schema peers — `conversationFields` deliberately
          // omits these fields (carve-out for the patch-style update flow);
          // mirror `createConversation`'s inline-emit-when-true contract so the
          // captured create op matches the local row (else peers diverge).
          if (conversation.includesAllMembers) {
            convFields['includes_all_members'] = true;
          }
          if (conversation.archivedForEveryone) {
            convFields['archived_for_everyone'] = true;
          }
          conversationEmissions.add(
            CapturedSyncOp(
              'conversations',
              conversation.id,
              SyncRecordOpType.create,
              convFields,
            ),
          );
          await didImportOne();
        }
        if (conversationCompanions.isNotEmpty) {
          await db.conversationsDao.batchInsertConversations(
            conversationCompanions,
          );
          captured.addAll(conversationEmissions);
        }

        // 9. Import messages — highest cardinality (~10k+ rows in big systems).
        final messageCompanions = <ChatMessagesCompanion>[];
        final messageEmissions = <CapturedSyncOp>[];
        for (final message in mapped.messages) {
          onProgress?.call(currentItem, totalItems, 'Importing messages...');
          messageCompanions.add(ChatMessageMapper.toCompanion(message));
          messageEmissions.add(
            CapturedSyncOp(
              'chat_messages',
              message.id,
              SyncRecordOpType.create,
              DriftChatMessageRepository.messageFields(message),
            ),
          );
          await didImportOne();
        }
        if (messageCompanions.isNotEmpty) {
          await db.chatMessagesDao.batchInsertMessages(messageCompanions);
          captured.addAll(messageEmissions);
        }

        // 10. Import polls + options + votes.
        //
        // Polls and options are batched here (Phase 6); votes were batched in
        // Phase 5. Per-poll progress notification is preserved so the user's
        // "Importing polls..." progress label still ticks even though the DB
        // work has collapsed into three batches.
        final pollCompanions = <PollsCompanion>[];
        final pollEmissions = <CapturedSyncOp>[];
        final optionCompanions = <PollOptionsCompanion>[];
        final optionEmissions = <CapturedSyncOp>[];
        final voteRows = <PollVotesCompanion>[];
        for (final poll in mapped.polls) {
          onProgress?.call(currentItem, totalItems, 'Importing polls...');
          pollCompanions.add(PollMapper.toCompanion(poll));
          pollEmissions.add(
            CapturedSyncOp(
              'polls',
              poll.id,
              SyncRecordOpType.create,
              DriftPollRepository.pollFields(poll),
            ),
          );
          for (final option in poll.options) {
            optionCompanions.add(PollOptionMapper.toCompanion(option, poll.id));
            optionEmissions.add(
              CapturedSyncOp(
                'poll_options',
                option.id,
                SyncRecordOpType.create,
                DriftPollRepository.pollOptionFields(option, poll.id),
              ),
            );
            for (final vote in option.votes) {
              voteRows.add(PollVoteMapper.toCompanion(vote, option.id));
              // Phase 5 mandates field-map reuse — the helper is the single
              // source of truth for the poll-vote emission payload, shared
              // between the live-edit path (`castVote()`) and this
              // batch-import path. Inlining the field map here is the exact
              // bug the plan's "Field-map reuse — mandatory" subsection
              // forbids.
              captured.add(
                CapturedSyncOp(
                  'poll_votes',
                  vote.id,
                  SyncRecordOpType.create,
                  DriftPollRepository.pollVoteFields(vote, option.id),
                ),
              );
            }
          }
          await didImportOne();
        }
        if (pollCompanions.isNotEmpty) {
          await db.pollsDao.batchInsertPolls(pollCompanions);
          captured.addAll(pollEmissions);
        }
        if (optionCompanions.isNotEmpty) {
          await db.pollOptionsDao.batchInsertOptions(optionCompanions);
          captured.addAll(optionEmissions);
        }
        if (voteRows.isNotEmpty) {
          await db.pollVotesDao.batchInsertVotes(voteRows);
        }

        // 11. Import reminders (from SP timers).
        if (remindersRepo != null) {
          final reminderCompanions = <RemindersCompanion>[];
          final reminderEmissions = <CapturedSyncOp>[];
          for (final reminder in mapped.reminders) {
            onProgress?.call(currentItem, totalItems, 'Importing reminders...');
            reminderCompanions.add(ReminderMapper.toCompanion(reminder));
            reminderEmissions.add(
              CapturedSyncOp(
                'reminders',
                reminder.id,
                SyncRecordOpType.create,
                DriftRemindersRepository.reminderFields(reminder),
              ),
            );
            await didImportOne();
          }
          if (reminderCompanions.isNotEmpty) {
            await db.remindersDao.batchInsertReminders(reminderCompanions);
            captured.addAll(reminderEmissions);
          }
        }

        // 12. Import board posts (SP boardMessages as first-class
        //     MemberBoardPost rows).
        if (boardPostsRepo != null) {
          final postCompanions = <MemberBoardPostsCompanion>[];
          final postEmissions = <CapturedSyncOp>[];
          for (final post in mapped.boardPosts) {
            onProgress?.call(
              currentItem,
              totalItems,
              'Importing board posts...',
            );
            postCompanions.add(MemberBoardPostMapper.toCompanion(post));
            postEmissions.add(
              CapturedSyncOp(
                'member_board_posts',
                post.id,
                SyncRecordOpType.create,
                DriftMemberBoardPostsRepository.postFields(post),
              ),
            );
            await didImportOne();
          }
          if (postCompanions.isNotEmpty) {
            await db.memberBoardPostsDao.batchInsertPosts(postCompanions);
            captured.addAll(postEmissions);
          }

          // Propagate SP read state: set boardLastReadAt for recipients of
          // already-read messages, so the Prism inbox starts in a matching state.
          //
          // Replace the per-row `getMemberById` + `updateMember` loop with one
          // bulk-fetch + one batch update. boardLastReadAt updates are pure
          // local read-state — repo-emit semantics didn't surface them anyway
          // (membersDao.updateMember bypasses the repo's syncRecordUpdate), so
          // no captured tuple is pushed here. This matches pre-Phase-6
          // behavior byte-for-byte.
          if (mapped.boardLastReadAtUpdates.isNotEmpty) {
            final membersDao = db.membersDao;
            final referencedIds = mapped.boardLastReadAtUpdates.keys.toList(
              growable: false,
            );
            final existingById = {
              for (final m in await membersDao.getMembersByIds(referencedIds))
                m.id: m,
            };
            final updates = <String, DateTime>{};
            for (final entry in mapped.boardLastReadAtUpdates.entries) {
              final existing = existingById[entry.key];
              if (existing == null) continue;
              final readAt = entry.value.toUtc();
              final currentReadAt = existing.boardLastReadAt;
              if (currentReadAt == null || readAt.isAfter(currentReadAt)) {
                updates[entry.key] = readAt;
              }
            }
            if (updates.isNotEmpty) {
              await membersDao.batchUpdateBoardLastReadAt(updates);
            }
            await _yieldToUi();
          }
        }

        // 12. Update system settings from SP profile.
        if (settingsRepo != null) {
          if (mapped.systemName != null && mapped.systemName!.isNotEmpty) {
            await settingsRepo.updateSystemName(mapped.systemName);
          }
          if (mapped.systemColor != null && mapped.systemColor!.isNotEmpty) {
            await settingsRepo.updateSystemColor(mapped.systemColor);
          }
          if (mapped.systemDescription != null &&
              mapped.systemDescription!.isNotEmpty) {
            await settingsRepo.updateSystemDescription(
              mapped.systemDescription,
            );
          }
        }

        // Persist the captured emissions into the durable outbox INSIDE
        // this transaction so the imported data rows and their sync-op intents
        // commit atomically. The drainer dispatches them to the FFI strictly
        // AFTER commit (triggered below), replacing the old in-memory
        // post-commit replay and closing its commit-to-replay gap — a crash
        // after this commit can no longer lose the import's emissions. A
        // rolled-back import rolls back both the data and the outbox rows (zero
        // emissions, the existing parity-test guarantee). Gated on persisted
        // credentials: a never-paired device persists nothing
        // (`bootstrapExistingData` seeds field_versions at pairing).
        if (syncCredentialsPersisted.value) {
          await SyncRecordMixin.persistCapturedOpsToOutbox(db, captured);
        }
      });
    }, captured.add);

    // Post-commit drain. The transaction committed atomically with the
    // outbox rows persisted above (no in-memory replay leg anymore — the old
    // capture-then-replay path could lose the import's emissions on a crash
    // between commit and replay). Trigger the durable drainer to dispatch the
    // rows to the FFI strictly after commit; it owns failure/retry/quarantine,
    // so a transient engine-unconfigured state defers rather than drops, and
    // there is no longer a no-emitter / replay-failure warning to surface.
    if (syncCredentialsPersisted.value && captured.isNotEmpty) {
      await triggerOutboxDrain(db, syncCurrentHandle.value);
    }

    // Persist SP→Prism ID mappings so subsequent imports reuse the same UUIDs.
    if (spImportDao != null) {
      final mappingRows = <SpIdMapTableCompanion>[];
      for (final (type, idMap) in [
        ('member', memberIdMap),
        ('channel', channelIdMap),
        ('session', sessionIdMap),
        ('group', groupIdMap),
        ('field', fieldIdMap),
        ('category', categoryIdMap),
        // board_message entries enable idempotent re-import: same SP _id
        // always maps to the same deterministic UUID v5.
        ('board_message', mapped.boardMessageIdMap),
      ]) {
        for (final entry in idMap.entries) {
          mappingRows.add(
            SpIdMapTableCompanion(
              spId: Value(entry.key),
              entityType: Value(type),
              prismId: Value(entry.value),
            ),
          );
        }
      }
      await spImportDao.upsertMappings(mappingRows);
      await spImportDao.upsertSyncState(
        SpSyncStateTableCompanion(
          id: const Value('singleton'),
          lastImportAt: Value(_now()),
        ),
      );
    }

    // 6. Download avatars (best-effort, outside the transaction).
    //    Network I/O cannot be rolled back; failures here are silently skipped.
    var avatarsDownloaded = 0;
    var systemAvatarDownloaded = false;
    var avatarsImportedFromZip = 0;
    var systemAvatarImportedFromZip = false;
    final warnings = List<String>.of(mapped.warnings);

    // 6a. System-level avatar. SP stores this on users[0] (separate from
    //     member avatars); mirror the member flow — fetch+store best-effort
    //     outside the transaction.
    if (downloadAvatars &&
        settingsRepo != null &&
        mapped.systemAvatarUrl != null &&
        mapped.systemAvatarUrl!.isNotEmpty) {
      final bytes = await fetchAvatarBytes(
        mapped.systemAvatarUrl!,
        client: _http,
      );
      if (bytes != null) {
        await settingsRepo.updateSystemAvatarData(bytes);
        systemAvatarDownloaded = true;
      } else {
        warnings.add('System avatar failed to download');
      }
    }

    if (downloadAvatars && mapped.avatarUrls.isNotEmpty) {
      final result = await _downloadAvatars(
        mapped.members,
        mapped.avatarUrls,
        memberRepo,
        skipMemberIds: linkedExistingMemberIds,
        warnings: warnings,
        onProgress: (processed, total) {
          onProgress?.call(processed, total, 'Downloading avatars...');
        },
      );
      avatarsDownloaded = result.downloaded;
      if (result.failed > 0) {
        warnings.add('${result.failed} avatar(s) failed to download');
      }
    }

    // Bio images: SP bios reference hotlinked external image URLs
    // (![](https://...)). Fetch+encrypt each into the shared library and
    // rewrite to a tag so the viewer never contacts the original host.
    // Best-effort, post-transaction (network), like avatars.
    if (mediaService != null &&
        mediaAttachmentRepo is DriftMediaAttachmentRepository) {
      await _processBioImages(
        mapped.members,
        memberRepo,
        mediaService,
        mediaAttachmentRepo,
        skipMemberIds: linkedExistingMemberIds,
        warnings: warnings,
        onProgress: (count, total) {
          onProgress?.call(count, total, 'Importing bio images...');
        },
      );
    }

    if ((avatarZipPath != null && avatarZipPath.isNotEmpty) ||
        (avatarZipBytes != null && avatarZipBytes.isNotEmpty)) {
      onProgress?.call(totalItems, totalItems, 'Importing avatar ZIP...');
      try {
        final zipImporter = SpAvatarZipImporter();
        final zipResult = avatarZipBytes != null
            ? await zipImporter.importZipFileBytes(
                bytes: avatarZipBytes,
                memberRepo: memberRepo,
                settingsRepo: settingsRepo,
                spImportDao: spImportDao,
                exportData: data,
                skipMemberIds: linkedExistingMemberIds,
              )
            : await zipImporter.importZipFile(
                filePath: avatarZipPath!,
                memberRepo: memberRepo,
                settingsRepo: settingsRepo,
                spImportDao: spImportDao,
                exportData: data,
                skipMemberIds: linkedExistingMemberIds,
              );
        avatarsImportedFromZip = zipResult.memberAvatarsUpdated;
        systemAvatarImportedFromZip = zipResult.systemAvatarUpdated;
        warnings.addAll(zipResult.warnings);
      } catch (e) {
        warnings.add('Could not import avatar ZIP: $e');
      }
    }

    // After import: if board posts were imported and we have a settings repo,
    // auto-enable boardsEnabled and append 'boards' to the nav overflow so the
    // user can immediately navigate to their imported posts.
    final boardPostsImported = mapped.boardPosts.length;
    if (boardPostsImported > 0 && settingsRepo != null) {
      final currentSettings = await settingsRepo.getSettings();
      final wasEnabled = currentSettings.boardsEnabled;
      if (!wasEnabled) {
        await settingsRepo.updateBoardsEnabled(true);
      }
      // Idempotently append 'boards' to the nav overflow if not already present
      // in either the primary nav or the overflow list.
      final refreshed = await settingsRepo.getSettings();
      final primaryIds = refreshed.navBarItems;
      final overflowIds = refreshed.navBarOverflowItems;
      final alreadyPresent =
          primaryIds.contains('boards') || overflowIds.contains('boards');
      if (!alreadyPresent) {
        await settingsRepo.updateNavBarOverflowItems([
          ...overflowIds,
          'boards',
        ]);
      }
    }

    stopwatch.stop();

    return ImportResult(
      membersImported: membersImported,
      membersLinked: membersLinked,
      sessionsImported: mapped.sessions.length,
      conversationsImported: mapped.conversations.length,
      messagesImported: mapped.messages.length,
      pollsImported: mapped.polls.length,
      notesImported: mapped.notes.length,
      commentsImported: mapped.frontComments.length,
      customFieldsImported:
          mapped.customFields.length + mapped.customFieldValues.length,
      groupsImported: mapped.groups.length,
      remindersImported: mapped.reminders.length,
      boardPostsImported: boardPostsImported,
      avatarsDownloaded: avatarsDownloaded,
      systemAvatarDownloaded: systemAvatarDownloaded,
      avatarsImportedFromZip: avatarsImportedFromZip,
      systemAvatarImportedFromZip: systemAvatarImportedFromZip,
      warnings: warnings,
      duration: stopwatch.elapsed,
    );
  }

  /// Re-run only the avatar download phase for an already-imported SP export.
  ///
  /// This depends on [spImportDao] holding the original SP→Prism ID mappings,
  /// so it is suitable for a same-session retry after transient image/CDN
  /// failures without re-importing or overwriting the rest of the user's data.
  Future<ImportResult> retryAvatarDownloads({
    required SpExportData data,
    required MemberRepository memberRepo,
    SystemSettingsRepository? settingsRepo,
    SpImportDao? spImportDao,
    Map<String, CfDisposition>? customFrontDispositions,
    void Function(int current, int total, String label)? onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();
    final existingMappings = await _loadExistingMappings(spImportDao);
    final mapper = SpMapper(
      existingMappings: existingMappings,
      customFrontDispositions: customFrontDispositions,
      newId: _newId,
      now: _now,
    );
    final mapped = mapper.mapAll(data);

    var avatarsDownloaded = 0;
    var systemAvatarDownloaded = false;
    final warnings = <String>[];
    final hasSystemAvatarUrl =
        mapped.systemAvatarUrl != null && mapped.systemAvatarUrl!.isNotEmpty;
    final totalAvatarSources =
        mapped.avatarUrls.length + (hasSystemAvatarUrl ? 1 : 0);

    if (settingsRepo != null && hasSystemAvatarUrl) {
      onProgress?.call(0, totalAvatarSources, 'Retrying system avatar...');
      final bytes = await fetchAvatarBytes(
        mapped.systemAvatarUrl!,
        client: _http,
      );
      if (bytes != null) {
        await settingsRepo.updateSystemAvatarData(bytes);
        systemAvatarDownloaded = true;
      } else {
        warnings.add('System avatar failed to download');
      }
    }

    if (mapped.avatarUrls.isNotEmpty) {
      final result = await _downloadAvatars(
        mapped.members,
        mapped.avatarUrls,
        memberRepo,
        warnings: warnings,
        onProgress: (processed, total) {
          onProgress?.call(processed, total, 'Retrying avatars...');
        },
      );
      avatarsDownloaded = result.downloaded;
      if (result.failed > 0) {
        warnings.add('${result.failed} avatar(s) failed to download');
      }
      // Retry callers report the TOTAL number of members currently carrying
      // avatar bytes (including avatars persisted by an earlier partial
      // attempt), not just this retry's freshly-downloaded count. Read all
      // referenced members in ONE query instead of the N-query loop the
      // previous `_countMembersWithAvatars` helper used.
      avatarsDownloaded = (await memberRepo.getMembersByIds(
        mapped.members.map((m) => m.id).toList(),
      )).where((m) => m.avatarImageData != null).length;
    }

    stopwatch.stop();
    return ImportResult(
      membersImported: 0,
      sessionsImported: 0,
      conversationsImported: 0,
      messagesImported: 0,
      pollsImported: 0,
      avatarsDownloaded: avatarsDownloaded,
      systemAvatarDownloaded: systemAvatarDownloaded,
      warnings: warnings,
      duration: stopwatch.elapsed,
    );
  }

  /// Bounded concurrency for parallel avatar fetches.
  ///
  /// 12 is the middle of the conservative-(8)/reasonable-(16) range called
  /// out in `docs/plans/sp-import-perf-quick-wins.md` (Phase 2). Above ~16
  /// the gain saturates on cellular uplinks and risks tripping CDN
  /// per-source rate limits; below ~8 the chunked Future.wait can't hide
  /// HTTP RTT for systems with dozens of avatars.
  static const int _avatarFetchConcurrency = 12;

  /// Download avatar images from URLs and update members.
  ///
  /// Network fetches run in bounded-concurrency chunks
  /// (`_avatarFetchConcurrency` per chunk). After all chunks resolve, all
  /// successful fetches are committed in a single Drift batch update via
  /// `DriftMemberRepository.batchUpdateAvatars` so DB write volume drops
  /// from N round-trips to one. Per-member `syncRecordUpdate` emissions
  /// are preserved by the repository batch helper, keeping wire-level
  /// event shape unchanged from the pre-Phase-2 serial loop.
  ///
  /// Per-member error semantics match the pre-Phase-2 behavior: a single
  /// failed fetch (null bytes or a thrown exception) is recorded as a
  /// warning and that member is skipped — it does NOT poison the chunk
  /// or fail the import.
  Future<({int downloaded, int failed})> _downloadAvatars(
    List<Member> members,
    Map<String, String> avatarUrls,
    MemberRepository memberRepo, {
    Set<String> skipMemberIds = const {},
    List<String>? warnings,
    void Function(int processed, int total)? onProgress,
  }) async {
    final eligible = <Member>[];
    final urlsByMemberId = <String, String>{};
    for (final member in members) {
      if (skipMemberIds.contains(member.id)) continue;
      final url = avatarUrls[member.id];
      if (url == null) continue;
      eligible.add(member);
      urlsByMemberId[member.id] = url;
    }

    if (eligible.isEmpty) {
      return (downloaded: 0, failed: 0);
    }

    // Track successful (member-id, bytes) pairs while downloads run. We do
    // NOT read the current DB row here — downloads can take tens of seconds
    // on a slow CDN, and a user renaming/editing a member during that window
    // would otherwise have their edit clobbered on peers via field-LWW when
    // the emission payload ships from a pre-download snapshot. The DB row
    // read is deferred to immediately before the batch write below.
    final successfulBytesByMemberId = <String, Uint8List>{};
    final downloadedMembersInOrder = <Member>[];
    var downloaded = 0;
    var failed = 0;

    for (var i = 0; i < eligible.length; i += _avatarFetchConcurrency) {
      final end = (i + _avatarFetchConcurrency < eligible.length)
          ? i + _avatarFetchConcurrency
          : eligible.length;
      final chunk = eligible.sublist(i, end);

      final results = await Future.wait(
        chunk.map((member) async {
          // Per-task try/catch: an exception escaping fetchAvatarBytes
          // (e.g. an unexpected client error) must not poison the chunk
          // — match the pre-Phase-2 null-return failure path.
          try {
            return (
              member: member,
              bytes: await fetchAvatarBytes(
                urlsByMemberId[member.id]!,
                client: _http,
              ),
            );
          } catch (_) {
            return (member: member, bytes: null);
          }
        }),
      );

      for (final result in results) {
        if (result.bytes != null) {
          successfulBytesByMemberId[result.member.id] = result.bytes!;
          downloadedMembersInOrder.add(result.member);
          downloaded++;
        } else {
          warnings?.add('Avatar download failed for ${result.member.id}');
          failed++;
        }
        onProgress?.call(downloaded + failed, eligible.length);
      }
    }

    if (successfulBytesByMemberId.isEmpty) {
      return (downloaded: downloaded, failed: failed);
    }

    // Re-read current DB rows ONLY for IDs whose downloads succeeded,
    // immediately before constructing the emission payload. Two reasons:
    //
    //   1. Stale-snapshot bug — see the comment at the top of the loop.
    //      Reading here, after all downloads finished, means the emitted
    //      `syncRecordUpdate` carries post-download member state (e.g. a
    //      mid-flight rename) instead of clobbering peers via field-LWW.
    //   2. Retry path — the user may have edited the member (e.g. renamed)
    //      between the failed initial import and a `retryAvatarDownloads`
    //      call. The DB row carries those edits; the in-memory `mapped`
    //      member doesn't. Same precedence as the pre-Phase-2
    //      `current ?? member` line: prefer DB row, fall back to mapped
    //      if the row isn't in the DB yet.
    final currentRowsById = <String, Member>{
      for (final row in await memberRepo.getMembersByIds(
        successfulBytesByMemberId.keys.toList(),
      ))
        row.id: row,
    };

    final successfulUpdates = <Member>[
      for (final downloadedMember in downloadedMembersInOrder)
        (currentRowsById[downloadedMember.id] ?? downloadedMember).copyWith(
          avatarImageData: successfulBytesByMemberId[downloadedMember.id],
        ),
    ];

    if (memberRepo is DriftMemberRepository) {
      // Batched DB write + per-member emission (preserved emission shape).
      await memberRepo.batchUpdateAvatars(successfulUpdates);
    } else {
      // Fallback for non-Drift fakes in tests: per-member update so the
      // emission contract still holds without requiring fakes to
      // implement the batch helper. Future non-Drift production
      // `MemberRepository` implementations would silently take this slow
      // path and regress avatar import perf, so warn in debug builds.
      assert(() {
        debugPrint(
          'SpImporter: MemberRepository is not Drift-backed; falling back '
          'to per-member updateMember() during avatar import. Consider '
          'implementing batchUpdateAvatars on this repository.',
        );
        return true;
      }());
      for (final member in successfulUpdates) {
        await memberRepo.updateMember(member);
      }
    }

    return (downloaded: downloaded, failed: failed);
  }

  /// Post-transaction pass: fetch+encrypt external image URLs in member bios
  /// into the shared library, rewriting `![](https://...)` → `![](tag)`.
  /// Best-effort — failures leave the original URL (renders as missing).
  Future<void> _processBioImages(
    List<Member> members,
    MemberRepository memberRepo,
    MediaService mediaService,
    DriftMediaAttachmentRepository mediaAttachmentRepo, {
    Set<String> skipMemberIds = const {},
    List<String>? warnings,
    void Function(int count, int total)? onProgress,
  }) async {
    final eligible = members
        .where(
          (m) =>
              !skipMemberIds.contains(m.id) &&
              (m.bio?.contains('http') ?? false),
        )
        .toList();
    if (eligible.isEmpty) return;

    final importer = BioImageImporter(
      mediaService: mediaService,
      repository: mediaAttachmentRepo,
    );

    var processed = 0;
    for (final member in eligible) {
      try {
        final rewritten = await importer.processBio(member.bio);
        if (rewritten != member.bio) {
          final current =
              (await memberRepo.getMembersByIds([member.id])).firstOrNull ??
              member;
          await memberRepo.updateMember(current.copyWith(bio: rewritten));
        }
      } catch (e) {
        warnings?.add('Bio image import failed for ${member.id}');
        debugPrint('SpImporter: bio image import failed for ${member.id}: $e');
      }
      processed++;
      onProgress?.call(processed, eligible.length);
      if (processed % _uiYieldEveryItems == 0) await _yieldToUi();
    }
  }

  Future<void> _yieldToUi() => Future<void>.delayed(Duration.zero);

  Future<Map<String, Map<String, String>>> _loadExistingMappings(
    SpImportDao? spImportDao,
  ) async {
    final existingMappings = <String, Map<String, String>>{};
    if (spImportDao == null) return existingMappings;

    final rows = await spImportDao.getAllMappings();
    for (final row in rows) {
      existingMappings.putIfAbsent(row.entityType, () => {})[row.spId] =
          row.prismId;
    }
    return existingMappings;
  }

  void _discardUnknownSentinelMemberMappings(
    Map<String, Map<String, String>> existingMappings,
    List<SpMember> members,
  ) {
    final memberMappings = existingMappings['member'];
    if (memberMappings == null || memberMappings.isEmpty) return;

    final exportedMemberIds = {for (final member in members) member.id};
    memberMappings.removeWhere(
      (spId, prismId) =>
          exportedMemberIds.contains(spId) &&
          prismId == unknownSentinelMemberId,
    );
  }

  Future<Set<String>> _applyMemberMappingDecisions(
    Map<String, Map<String, String>> existingMappings,
    Map<String, SpMemberMappingDecision> decisions,
    List<SpMember> members,
    MemberRepository memberRepo,
  ) async {
    if (decisions.isEmpty) return const {};

    final memberMappings = existingMappings.putIfAbsent('member', () => {});
    final exportedMemberIds = {for (final member in members) member.id};
    final localIds = {
      for (final member in await memberRepo.getAllMembers())
        if (member.id != unknownSentinelMemberId && !member.isDeleted)
          member.id,
    };
    final linkedLocalIds = <String>{};

    for (final decision in decisions.values) {
      if (!exportedMemberIds.contains(decision.spMemberId)) continue;

      switch (decision) {
        case SpImportMemberDecision():
          memberMappings.remove(decision.spMemberId);
        case SpLinkMemberDecision(:final localMemberId):
          if (localIds.contains(localMemberId) &&
              !linkedLocalIds.contains(localMemberId)) {
            memberMappings[decision.spMemberId] = localMemberId;
            linkedLocalIds.add(localMemberId);
          } else {
            memberMappings.remove(decision.spMemberId);
          }
      }
    }

    return linkedLocalIds;
  }

  Future<void> _sanitizeMemberMappings(
    Map<String, Map<String, String>> existingMappings,
    List<SpMember> members,
    MemberRepository memberRepo,
  ) async {
    final memberMappings = existingMappings['member'];
    if (memberMappings == null || memberMappings.isEmpty) return;

    final exportedMemberIds = {for (final member in members) member.id};
    final validLocalIds = {
      for (final member in await memberRepo.getAllMembers())
        if (member.id != unknownSentinelMemberId && !member.isDeleted)
          member.id,
    };

    memberMappings.removeWhere(
      (spId, localId) =>
          exportedMemberIds.contains(spId) && !validLocalIds.contains(localId),
    );

    final targetCounts = <String, int>{};
    for (final entry in memberMappings.entries) {
      if (!exportedMemberIds.contains(entry.key)) continue;
      targetCounts[entry.value] = (targetCounts[entry.value] ?? 0) + 1;
    }

    memberMappings.removeWhere(
      (spId, localId) =>
          exportedMemberIds.contains(spId) && targetCounts[localId] != 1,
    );
  }

  Future<Set<String>> _seedMemberMappingsFromExistingLocals(
    Map<String, Map<String, String>> existingMappings,
    List<SpMember> members,
    MemberRepository memberRepo, {
    Set<String> claimedLocalIds = const {},
    Set<String> blockedSpIds = const {},
  }) async {
    final linkedLocalIds = <String>{};
    final memberMappings = existingMappings.putIfAbsent('member', () => {});
    final unmappedPkIds = {
      for (final member in members)
        if (!blockedSpIds.contains(member.id) &&
            !memberMappings.containsKey(member.id) &&
            member.pkId != null &&
            member.pkId!.isNotEmpty)
          member.pkId!,
    };
    final spPkCounts = <String, int>{};
    for (final member in members) {
      final pkId = member.pkId;
      if (pkId != null && pkId.isNotEmpty) {
        spPkCounts[pkId] = (spPkCounts[pkId] ?? 0) + 1;
      }
    }
    final unmappedNames = <String, int>{};
    for (final member in members) {
      if (blockedSpIds.contains(member.id)) continue;
      if (memberMappings.containsKey(member.id)) continue;
      final normalized = normalizedSpMemberName(member.name);
      if (normalized == null) continue;
      unmappedNames[normalized] = (unmappedNames[normalized] ?? 0) + 1;
    }
    if (unmappedPkIds.isEmpty && unmappedNames.isEmpty) {
      return const {};
    }

    final localsByPkId = <String, String>{};
    final localPkCounts = <String, int>{};
    final localNameCounts = <String, int>{};
    final localsByName = <String, String>{};
    for (final local in await memberRepo.getAllMembers()) {
      if (local.id == unknownSentinelMemberId) continue;
      if (local.isDeleted || claimedLocalIds.contains(local.id)) continue;

      final pkId = local.pluralkitId;
      if (pkId != null && pkId.isNotEmpty && unmappedPkIds.contains(pkId)) {
        localPkCounts[pkId] = (localPkCounts[pkId] ?? 0) + 1;
        localsByPkId.putIfAbsent(pkId, () => local.id);
      }

      final normalizedName = normalizedSpMemberName(local.name);
      if (normalizedName != null && unmappedNames.containsKey(normalizedName)) {
        localNameCounts[normalizedName] =
            (localNameCounts[normalizedName] ?? 0) + 1;
        localsByName.putIfAbsent(normalizedName, () => local.id);
      }
    }

    for (final member in members) {
      if (blockedSpIds.contains(member.id)) continue;
      if (memberMappings.containsKey(member.id)) continue;
      final pkId = member.pkId;
      final localId =
          pkId == null ||
              pkId.isEmpty ||
              spPkCounts[pkId] != 1 ||
              localPkCounts[pkId] != 1
          ? null
          : localsByPkId[pkId];
      if (localId != null && !linkedLocalIds.contains(localId)) {
        memberMappings[member.id] = localId;
        linkedLocalIds.add(localId);
        continue;
      }

      final normalizedName = normalizedSpMemberName(member.name);
      if (normalizedName == null ||
          unmappedNames[normalizedName] != 1 ||
          localNameCounts[normalizedName] != 1) {
        continue;
      }
      final nameMatchedLocalId = localsByName[normalizedName];
      if (nameMatchedLocalId != null &&
          !linkedLocalIds.contains(nameMatchedLocalId)) {
        memberMappings[member.id] = nameMatchedLocalId;
        linkedLocalIds.add(nameMatchedLocalId);
      }
    }
    return linkedLocalIds;
  }
}

// ---------------------------------------------------------------------------
// Phase 1 — `compute()` helpers
//
// `compute()` requires a top-level or static function reference. The arg
// types must be sendable across an isolate boundary (no Drift handles, no
// FFI handles, no streams, no closures over instance state). Defaults for
// the `newId`/`now` seams are baked in inside the isolate — see
// `docs/plans/sp-import-perf-quick-wins.md` Phase 1.
// ---------------------------------------------------------------------------

/// Top-level wrapper for [SpParser.parse] so it can run via [compute].
///
/// The parser uses its default clock for fall-back timestamps because the
/// production caller doesn't inject a `now` seam — tests bypass this helper
/// and call [SpParser.parse] directly with a [FixedClock].
SpExportData _parseJson(String jsonString) {
  return SpParser.parse(jsonString);
}

SpExportData _parseBytes(Uint8List bytes) {
  return SpParser.parse(utf8.decode(bytes));
}

/// Argument carrier for [_mapOnIsolate]. All fields must be sendable across
/// an isolate boundary; `SpExportData` is plain Dart data, and the maps and
/// sets contain only primitives + enums.
class _MapArgs {
  const _MapArgs({
    required this.data,
    required this.existingMappings,
    required this.customFrontDispositions,
    required this.importAsNewSpMemberIds,
  });

  final SpExportData data;
  final Map<String, Map<String, String>> existingMappings;
  final Map<String, CfDisposition>? customFrontDispositions;
  final Set<String> importAsNewSpMemberIds;
}

/// Result carrier for [_mapOnIsolate]. Surfaces every mapper-instance field
/// the importer reads after `mapAll` because the mapper object itself
/// doesn't survive the isolate boundary.
class _MapResult {
  const _MapResult({
    required this.mapped,
    required this.pendingStaleMappingDeletes,
    required this.memberIdMap,
    required this.channelIdMap,
    required this.sessionIdMap,
    required this.groupIdMap,
    required this.fieldIdMap,
    required this.categoryIdMap,
  });

  /// Snapshot of every field the caller reads off a fresh `SpMapper` after
  /// `mapAll` — used by the inline (test) path so production + test routes
  /// produce structurally identical results.
  factory _MapResult.fromMapper(MappedData mapped, SpMapper mapper) {
    return _MapResult(
      mapped: mapped,
      pendingStaleMappingDeletes: List.of(mapper.pendingStaleMappingDeletes),
      memberIdMap: Map.of(mapper.memberIdMap),
      channelIdMap: Map.of(mapper.channelIdMap),
      sessionIdMap: Map.of(mapper.sessionIdMap),
      groupIdMap: Map.of(mapper.groupIdMap),
      fieldIdMap: Map.of(mapper.fieldIdMap),
      categoryIdMap: Map.of(mapper.categoryIdMap),
    );
  }

  final MappedData mapped;
  final List<String> pendingStaleMappingDeletes;
  final Map<String, String> memberIdMap;
  final Map<String, String> channelIdMap;
  final Map<String, String> sessionIdMap;
  final Map<String, String> groupIdMap;
  final Map<String, String> fieldIdMap;
  final Map<String, String> categoryIdMap;
}

/// Top-level entry point for the `compute()` mapping pass.
///
/// Production callers — which leave `newId`/`now` defaulted — route through
/// here so the SP mapping (which does meaningful synchronous work on
/// multi-MB exports) doesn't stall the UI thread. The defaults inside
/// [SpMapper] (`Uuid().v4()`, `DateTime.now`) take over on the worker
/// isolate. Tests inject seam closures that close over instance state and
/// must therefore bypass this helper.
_MapResult _mapOnIsolate(_MapArgs args) {
  final mapper = SpMapper(
    existingMappings: args.existingMappings,
    customFrontDispositions: args.customFrontDispositions,
    importAsNewSpMemberIds: args.importAsNewSpMemberIds,
  );
  final mapped = mapper.mapAll(args.data);
  return _MapResult.fromMapper(mapped, mapper);
}
