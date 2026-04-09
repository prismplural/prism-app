import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/database/app_database.dart' show AppDatabase;
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
import 'package:prism_plurality/features/migration/services/sp_parser.dart';
import 'package:prism_plurality/features/migration/services/sp_mapper.dart';

/// Import progress state.
enum ImportState {
  idle,
  parsing,
  verifying,
  fetching,
  previewing,
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
  final int avatarsDownloaded;
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
    required this.avatarsDownloaded,
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
      remindersImported;
}

/// Handles the full SP import workflow.
class SpImporter {
  static const _uuid = Uuid();

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
    bool downloadAvatars = true,
    bool clearExistingData = false,
    void Function(int current, int total, String label)? onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();
    final mapper = SpMapper();
    final mapped = mapper.mapAll(data);

    final totalItems = mapped.members.length +
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
        mapped.reminders.length;
    var currentItem = 0;

    // Import all entity data atomically. If any insert fails the entire
    // transaction is rolled back and the exception propagates to the caller.
    // When clearExistingData is true, the wipe happens inside the same
    // transaction so a failed import rolls back everything — no data loss.
    await db.transaction(() async {
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
        await db.customStatement('DELETE FROM members');
      }

      // 1. Import members.
      for (final member in mapped.members) {
        onProgress?.call(currentItem, totalItems, 'Importing members...');
        await memberRepo.createMember(member);
        currentItem++;
      }

      // 2. Import custom field definitions.
      if (customFieldsRepo != null) {
        for (final field in mapped.customFields) {
          onProgress?.call(
              currentItem, totalItems, 'Importing custom fields...');
          await customFieldsRepo.createField(field);
          currentItem++;
        }
        for (final value in mapped.customFieldValues) {
          onProgress?.call(
              currentItem, totalItems, 'Importing field values...');
          await customFieldsRepo.upsertValue(value);
          currentItem++;
        }
      }

      // 3. Import groups + memberships.
      if (groupsRepo != null) {
        for (final group in mapped.groups) {
          onProgress?.call(currentItem, totalItems, 'Importing groups...');
          await groupsRepo.createGroup(group);
          currentItem++;
        }
        for (final entry in mapped.groupMemberships) {
          onProgress?.call(
              currentItem, totalItems, 'Importing group members...');
          await groupsRepo.addMemberToGroup(
              entry.key, entry.value, _uuid.v4());
          currentItem++;
        }
      }

      // 4. Import fronting sessions.
      for (final session in mapped.sessions) {
        onProgress?.call(currentItem, totalItems, 'Importing front history...');
        await sessionRepo.createSession(session);
        currentItem++;
      }

      // 5. Import notes.
      if (notesRepo != null) {
        for (final note in mapped.notes) {
          onProgress?.call(currentItem, totalItems, 'Importing notes...');
          await notesRepo.createNote(note);
          currentItem++;
        }
      }

      // 6. Import front session comments.
      if (commentsRepo != null) {
        for (final comment in mapped.frontComments) {
          onProgress?.call(currentItem, totalItems, 'Importing comments...');
          await commentsRepo.createComment(comment);
          currentItem++;
        }
      }

      // 7. Import conversation categories.
      if (categoriesRepo != null) {
        for (final cat in mapped.conversationCategories) {
          onProgress?.call(
              currentItem, totalItems, 'Importing categories...');
          await categoriesRepo.create(cat);
          currentItem++;
        }
      }

      // 8. Import conversations.
      for (final conversation in mapped.conversations) {
        onProgress?.call(currentItem, totalItems, 'Importing conversations...');
        await conversationRepo.createConversation(conversation);
        currentItem++;
      }

      // 9. Import messages.
      for (final message in mapped.messages) {
        onProgress?.call(currentItem, totalItems, 'Importing messages...');
        await messageRepo.createMessage(message);
        currentItem++;
      }

      // 10. Import polls.
      for (final poll in mapped.polls) {
        onProgress?.call(currentItem, totalItems, 'Importing polls...');
        await pollRepo.createPoll(poll);
        for (final option in poll.options) {
          await pollRepo.createOption(option, poll.id);
          for (final vote in option.votes) {
            await pollRepo.castVote(vote, option.id);
          }
        }
        currentItem++;
      }

      // 10. Import reminders (from SP timers).
      if (remindersRepo != null) {
        for (final reminder in mapped.reminders) {
          onProgress?.call(currentItem, totalItems, 'Importing reminders...');
          await remindersRepo.create(reminder);
          currentItem++;
        }
      }

      // 11. Update system settings from SP profile.
      if (settingsRepo != null) {
        if (mapped.systemName != null && mapped.systemName!.isNotEmpty) {
          await settingsRepo.updateSystemName(mapped.systemName);
        }
        if (mapped.systemColor != null && mapped.systemColor!.isNotEmpty) {
          await settingsRepo.updateAccentColorHex(
              mapped.systemColor!.replaceFirst('#', ''));
        }
        if (mapped.systemDescription != null &&
            mapped.systemDescription!.isNotEmpty) {
          await settingsRepo.updateSystemDescription(mapped.systemDescription);
        }
      }
    });

    // 6. Download avatars (best-effort, outside the transaction).
    //    Network I/O cannot be rolled back; failures here are silently skipped.
    var avatarsDownloaded = 0;
    final warnings = List<String>.of(mapped.warnings);
    if (downloadAvatars && mapped.avatarUrls.isNotEmpty) {
      final result = await _downloadAvatars(
        mapped.members,
        mapped.avatarUrls,
        memberRepo,
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

    stopwatch.stop();

    return ImportResult(
      membersImported: mapped.members.length,
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
      avatarsDownloaded: avatarsDownloaded,
      warnings: warnings,
      duration: stopwatch.elapsed,
    );
  }

  /// Download avatar images from URLs and update members.
  Future<({int downloaded, int failed})> _downloadAvatars(
    List<Member> members,
    Map<String, String> avatarUrls,
    MemberRepository memberRepo, {
    void Function(int count)? onProgress,
  }) async {
    var downloaded = 0;
    var failed = 0;

    for (final member in members) {
      final url = avatarUrls[member.id];
      if (url == null) continue;

      try {
        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 10));

        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          await memberRepo.updateMember(
            member.copyWith(avatarImageData: response.bodyBytes),
          );
          downloaded++;
        }
      } catch (_) {
        failed++;
      }

      onProgress?.call(downloaded);
    }

    return (downloaded: downloaded, failed: failed);
  }
}
