import 'dart:io';

import 'package:drift/drift.dart' show TableUpdate, Value;
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    show
        AppDatabase,
        MembersCompanion,
        SpIdMapTableCompanion,
        SpSyncStateTableCompanion;
import 'package:prism_plurality/core/database/daos/sp_import_dao.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
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
import 'package:prism_plurality/shared/utils/avatar_fetcher.dart';

/// Import progress state.
enum ImportState {
  idle,
  parsing,
  verifying,
  fetching,
  previewing,
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
  static const _uuid = Uuid();
  static const _uiYieldEveryItems = 20;

  SpImporter({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;

  /// Parse an export file and return structured data.
  SpExportData parseFile(String filePath) {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw FileSystemException('File not found', filePath);
    }
    final contents = file.readAsStringSync();
    return SpParser.parse(contents);
  }

  /// Parse an export JSON string directly.
  SpExportData parseString(String jsonString) {
    return SpParser.parse(jsonString);
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
    bool downloadAvatars = true,
    String? avatarZipPath,
    bool clearExistingData = false,
    Map<String, CfDisposition>? customFrontDispositions,
    void Function(int current, int total, String label)? onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();

    // Load existing SP→Prism ID mappings so a re-import reuses stable UUIDs.
    final existingMappings = await _loadExistingMappings(spImportDao);
    _discardUnknownSentinelMemberMappings(existingMappings, data.members);
    if (!clearExistingData) {
      await _seedMemberMappingsFromExistingLocals(
        existingMappings,
        data.members,
        memberRepo,
      );
    }

    final mapper = SpMapper(
      existingMappings: existingMappings,
      customFrontDispositions: customFrontDispositions,
    );
    final mapped = mapper.mapAll(data);
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

    await db.transaction(() async {
      // Scrub stale CF-as-member persisted mappings (plan §Classification)
      // inside the transaction so a failed import rolls back the scrub too.
      // Done before upserting new mappings so the DAO ends up consistent
      // with the user's updated disposition choices.
      if (spImportDao != null && mapper.pendingStaleMappingDeletes.isNotEmpty) {
        await spImportDao.deleteMappings(
          mapper.pendingStaleMappingDeletes,
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

      // 1. Import members.
      for (final member in mapped.members) {
        onProgress?.call(currentItem, totalItems, 'Importing members...');
        final existing = await memberRepo.getMemberById(member.id);
        if (existing != null) {
          await didImportOne();
          continue;
        }
        await memberRepo.createMember(member);
        membersImported++;
        await didImportOne();
      }

      // 2. Import custom field definitions.
      if (customFieldsRepo != null) {
        for (final field in mapped.customFields) {
          onProgress?.call(
            currentItem,
            totalItems,
            'Importing custom fields...',
          );
          await customFieldsRepo.createField(field);
          await didImportOne();
        }
        for (final value in mapped.customFieldValues) {
          onProgress?.call(
            currentItem,
            totalItems,
            'Importing field values...',
          );
          await customFieldsRepo.upsertValue(value);
          await didImportOne();
        }
      }

      // 3. Import groups + memberships.
      if (groupsRepo != null) {
        for (final group in mapped.groups) {
          onProgress?.call(currentItem, totalItems, 'Importing groups...');
          await groupsRepo.createGroup(group);
          await didImportOne();
        }
        for (final entry in mapped.groupMemberships) {
          onProgress?.call(
            currentItem,
            totalItems,
            'Importing group members...',
          );
          await groupsRepo.addMemberToGroup(entry.key, entry.value, _uuid.v4());
          await didImportOne();
        }
      }

      // 4. Import fronting sessions.
      for (final session in mapped.sessions) {
        onProgress?.call(currentItem, totalItems, 'Importing front history...');
        await sessionRepo.createSession(session);
        await didImportOne();
      }

      // 5. Import notes.
      if (notesRepo != null) {
        for (final note in mapped.notes) {
          onProgress?.call(currentItem, totalItems, 'Importing notes...');
          await notesRepo.createNote(note);
          await didImportOne();
        }
      }

      // 6. Import front session comments.
      if (commentsRepo != null) {
        for (final comment in mapped.frontComments) {
          onProgress?.call(currentItem, totalItems, 'Importing comments...');
          await commentsRepo.createComment(comment);
          await didImportOne();
        }
      }

      // 7. Import conversation categories.
      if (categoriesRepo != null) {
        for (final cat in mapped.conversationCategories) {
          onProgress?.call(currentItem, totalItems, 'Importing categories...');
          await categoriesRepo.create(cat);
          await didImportOne();
        }
      }

      // 8. Import conversations.
      for (final conversation in mapped.conversations) {
        onProgress?.call(currentItem, totalItems, 'Importing conversations...');
        await conversationRepo.createConversation(conversation);
        await didImportOne();
      }

      // 9. Import messages.
      for (final message in mapped.messages) {
        onProgress?.call(currentItem, totalItems, 'Importing messages...');
        await messageRepo.createMessage(message);
        await didImportOne();
      }

      // 10. Import polls.
      // createPoll already inserts all options — only cast votes separately.
      for (final poll in mapped.polls) {
        onProgress?.call(currentItem, totalItems, 'Importing polls...');
        await pollRepo.createPoll(poll);
        for (final option in poll.options) {
          for (final vote in option.votes) {
            await pollRepo.castVote(vote, option.id);
          }
        }
        await didImportOne();
      }

      // 10. Import reminders (from SP timers).
      if (remindersRepo != null) {
        for (final reminder in mapped.reminders) {
          onProgress?.call(currentItem, totalItems, 'Importing reminders...');
          await remindersRepo.create(reminder);
          await didImportOne();
        }
      }

      // 11. Import board posts (SP boardMessages as first-class MemberBoardPost rows).
      if (boardPostsRepo != null) {
        for (final post in mapped.boardPosts) {
          onProgress?.call(currentItem, totalItems, 'Importing board posts...');
          await boardPostsRepo.createPost(post);
          await didImportOne();
        }
        // Propagate SP read state: set boardLastReadAt for recipients of
        // already-read messages, so the Prism inbox starts in a matching state.
        if (mapped.boardLastReadAtUpdates.isNotEmpty) {
          final membersDao = db.membersDao;
          for (final entry in mapped.boardLastReadAtUpdates.entries) {
            final memberId = entry.key;
            final readAt = entry.value.toUtc();
            // Only update if the new timestamp is later than any existing value.
            final existing = await membersDao.getMemberById(memberId);
            if (existing != null) {
              final currentReadAt = existing.boardLastReadAt;
              if (currentReadAt == null || readAt.isAfter(currentReadAt)) {
                await membersDao.updateMember(
                  MembersCompanion(
                    id: Value(memberId),
                    boardLastReadAt: Value(readAt),
                  ),
                );
              }
            }
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
          await settingsRepo.updateSystemDescription(mapped.systemDescription);
        }
      }
    });

    // Persist SP→Prism ID mappings so subsequent imports reuse the same UUIDs.
    if (spImportDao != null) {
      final mappingRows = <SpIdMapTableCompanion>[];
      for (final (type, idMap) in [
        ('member', mapper.memberIdMap),
        ('channel', mapper.channelIdMap),
        ('session', mapper.sessionIdMap),
        ('group', mapper.groupIdMap),
        ('field', mapper.fieldIdMap),
        ('category', mapper.categoryIdMap),
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
          lastImportAt: Value(DateTime.now()),
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
        warnings: warnings,
        onProgress: (count) {
          onProgress?.call(
            totalItems,
            totalItems,
            'Downloading avatars ($count/${mapped.avatarUrls.length})...',
          );
        },
      );
      avatarsDownloaded = result.downloaded;
      if (result.failed > 0) {
        warnings.add('${result.failed} avatar(s) failed to download');
      }
    }

    if (avatarZipPath != null && avatarZipPath.isNotEmpty) {
      onProgress?.call(totalItems, totalItems, 'Importing avatar ZIP...');
      try {
        final zipResult = await SpAvatarZipImporter().importZipFile(
          filePath: avatarZipPath,
          memberRepo: memberRepo,
          settingsRepo: settingsRepo,
          spImportDao: spImportDao,
          exportData: data,
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
        onProgress: (count) {
          onProgress?.call(
            count,
            totalAvatarSources,
            'Retrying avatars ($count/${mapped.avatarUrls.length})...',
          );
        },
      );
      avatarsDownloaded = result.downloaded;
      if (result.failed > 0) {
        warnings.add('${result.failed} avatar(s) failed to download');
      }
      avatarsDownloaded = await _countMembersWithAvatars(
        mapped.members,
        memberRepo,
      );
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

  /// Download avatar images from URLs and update members.
  Future<({int downloaded, int failed})> _downloadAvatars(
    List<Member> members,
    Map<String, String> avatarUrls,
    MemberRepository memberRepo, {
    List<String>? warnings,
    void Function(int count)? onProgress,
  }) async {
    var downloaded = 0;
    var failed = 0;

    for (final member in members) {
      final url = avatarUrls[member.id];
      if (url == null) continue;

      final bytes = await fetchAvatarBytes(url, client: _http);
      if (bytes != null) {
        final current = await memberRepo.getMemberById(member.id);
        await memberRepo.updateMember(
          (current ?? member).copyWith(avatarImageData: bytes),
        );
        downloaded++;
      } else {
        warnings?.add('Avatar download failed for ${member.id}');
        failed++;
      }

      onProgress?.call(downloaded);
    }

    return (downloaded: downloaded, failed: failed);
  }

  Future<int> _countMembersWithAvatars(
    List<Member> members,
    MemberRepository memberRepo,
  ) async {
    var count = 0;
    for (final member in members) {
      final current = await memberRepo.getMemberById(member.id);
      if (current?.avatarImageData != null) count++;
    }
    return count;
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

  Future<void> _seedMemberMappingsFromExistingLocals(
    Map<String, Map<String, String>> existingMappings,
    List<SpMember> members,
    MemberRepository memberRepo,
  ) async {
    final memberMappings = existingMappings.putIfAbsent('member', () => {});
    final unmappedPkIds = {
      for (final member in members)
        if (!memberMappings.containsKey(member.id) &&
            member.pkId != null &&
            member.pkId!.isNotEmpty)
          member.pkId!,
    };
    final unmappedNames = <String, int>{};
    for (final member in members) {
      if (memberMappings.containsKey(member.id)) continue;
      final normalized = _normalizedMemberName(member.name);
      if (normalized == null) continue;
      unmappedNames[normalized] = (unmappedNames[normalized] ?? 0) + 1;
    }
    if (unmappedPkIds.isEmpty && unmappedNames.isEmpty) return;

    final localsByPkId = <String, String>{};
    final localNameCounts = <String, int>{};
    final localsByName = <String, String>{};
    for (final local in await memberRepo.getAllMembers()) {
      if (local.id == unknownSentinelMemberId) continue;

      final pkId = local.pluralkitId;
      if (pkId != null && pkId.isNotEmpty && unmappedPkIds.contains(pkId)) {
        localsByPkId.putIfAbsent(pkId, () => local.id);
      }

      final normalizedName = _normalizedMemberName(local.name);
      if (normalizedName != null && unmappedNames.containsKey(normalizedName)) {
        localNameCounts[normalizedName] =
            (localNameCounts[normalizedName] ?? 0) + 1;
        localsByName.putIfAbsent(normalizedName, () => local.id);
      }
    }

    for (final member in members) {
      if (memberMappings.containsKey(member.id)) continue;
      final pkId = member.pkId;
      final localId = pkId == null || pkId.isEmpty ? null : localsByPkId[pkId];
      if (localId != null) {
        memberMappings[member.id] = localId;
        continue;
      }

      final normalizedName = _normalizedMemberName(member.name);
      if (normalizedName == null ||
          unmappedNames[normalizedName] != 1 ||
          localNameCounts[normalizedName] != 1) {
        continue;
      }
      final nameMatchedLocalId = localsByName[normalizedName];
      if (nameMatchedLocalId != null) {
        memberMappings[member.id] = nameMatchedLocalId;
      }
    }
  }

  String? _normalizedMemberName(String name) {
    final normalized = name
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
    return normalized.isEmpty ? null : normalized;
  }
}
