import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/daos/chat_messages_dao.dart';
import 'package:prism_plurality/core/database/daos/conversations_dao.dart';
import 'package:prism_plurality/core/database/daos/fronting_sessions_dao.dart';
import 'package:prism_plurality/core/database/daos/members_dao.dart';
import 'package:prism_plurality/core/database/daos/poll_options_dao.dart';
import 'package:prism_plurality/core/database/daos/poll_votes_dao.dart';
import 'package:prism_plurality/core/database/daos/polls_dao.dart';
import 'package:prism_plurality/core/database/daos/pluralkit_sync_dao.dart';
import 'package:prism_plurality/core/database/daos/system_settings_dao.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/data/repositories/drift_chat_message_repository.dart';
import 'package:prism_plurality/data/repositories/drift_conversation_repository.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/data/repositories/drift_poll_repository.dart';
import 'package:prism_plurality/data/repositories/drift_system_settings_repository.dart';
import 'package:prism_plurality/domain/repositories/chat_message_repository.dart';
import 'package:prism_plurality/domain/repositories/conversation_repository.dart';
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/domain/repositories/poll_repository.dart';
import 'package:prism_plurality/domain/repositories/system_settings_repository.dart';
import 'package:prism_plurality/core/database/daos/habits_dao.dart';
import 'package:prism_plurality/data/repositories/drift_habit_repository.dart';
import 'package:prism_plurality/domain/repositories/habit_repository.dart';
import 'package:prism_plurality/core/database/daos/member_groups_dao.dart';
import 'package:prism_plurality/data/repositories/drift_member_groups_repository.dart';
import 'package:prism_plurality/domain/repositories/member_groups_repository.dart';
import 'package:prism_plurality/core/database/daos/custom_fields_dao.dart';
import 'package:prism_plurality/core/database/daos/notes_dao.dart';
import 'package:prism_plurality/core/database/daos/front_session_comments_dao.dart';
import 'package:prism_plurality/core/database/daos/conversation_categories_dao.dart';
import 'package:prism_plurality/core/database/daos/reminders_dao.dart';
import 'package:prism_plurality/core/database/daos/friends_dao.dart';
import 'package:prism_plurality/core/database/daos/sharing_requests_dao.dart';
import 'package:prism_plurality/data/repositories/drift_custom_fields_repository.dart';
import 'package:prism_plurality/data/repositories/drift_notes_repository.dart';
import 'package:prism_plurality/data/repositories/drift_front_session_comments_repository.dart';
import 'package:prism_plurality/data/repositories/drift_conversation_categories_repository.dart';
import 'package:prism_plurality/data/repositories/drift_reminders_repository.dart';
import 'package:prism_plurality/data/repositories/drift_friends_repository.dart';
import 'package:prism_plurality/domain/repositories/custom_fields_repository.dart';
import 'package:prism_plurality/domain/repositories/notes_repository.dart';
import 'package:prism_plurality/domain/repositories/front_session_comments_repository.dart';
import 'package:prism_plurality/domain/repositories/conversation_categories_repository.dart';
import 'package:prism_plurality/domain/repositories/reminders_repository.dart';
import 'package:prism_plurality/domain/repositories/friends_repository.dart';
import 'package:prism_plurality/core/database/daos/media_attachments_dao.dart';
import 'package:prism_plurality/data/repositories/drift_media_attachment_repository.dart';
import 'package:prism_plurality/domain/repositories/media_attachment_repository.dart';

// DAO providers
final membersDaoProvider = Provider<MembersDao>(
  (ref) => ref.watch(databaseProvider).membersDao,
);

final frontingSessionsDaoProvider = Provider<FrontingSessionsDao>(
  (ref) => ref.watch(databaseProvider).frontingSessionsDao,
);

final conversationsDaoProvider = Provider<ConversationsDao>(
  (ref) => ref.watch(databaseProvider).conversationsDao,
);

final chatMessagesDaoProvider = Provider<ChatMessagesDao>(
  (ref) => ref.watch(databaseProvider).chatMessagesDao,
);

final systemSettingsDaoProvider = Provider<SystemSettingsDao>(
  (ref) => ref.watch(databaseProvider).systemSettingsDao,
);

final pollsDaoProvider = Provider<PollsDao>(
  (ref) => ref.watch(databaseProvider).pollsDao,
);

final pollOptionsDaoProvider = Provider<PollOptionsDao>(
  (ref) => ref.watch(databaseProvider).pollOptionsDao,
);

final pollVotesDaoProvider = Provider<PollVotesDao>(
  (ref) => ref.watch(databaseProvider).pollVotesDao,
);

final pluralKitSyncDaoProvider = Provider<PluralKitSyncDao>(
  (ref) => ref.watch(databaseProvider).pluralKitSyncDao,
);

// Helper: resolve the currently configured sync handle synchronously.
ffi.PrismSyncHandle? _resolveSyncHandle(Ref ref) {
  return ref.watch(prismSyncHandleProvider).value;
}

// Repository providers
final memberRepositoryProvider = Provider<MemberRepository>(
  (ref) => DriftMemberRepository(
    ref.watch(membersDaoProvider),
    _resolveSyncHandle(ref),
    pkSyncDao: ref.watch(pluralKitSyncDaoProvider),
  ),
);

final frontingSessionRepositoryProvider = Provider<FrontingSessionRepository>(
  (ref) => DriftFrontingSessionRepository(
    ref.watch(frontingSessionsDaoProvider),
    _resolveSyncHandle(ref),
    pkSyncDao: ref.watch(pluralKitSyncDaoProvider),
  ),
);

final conversationRepositoryProvider = Provider<ConversationRepository>(
  (ref) => DriftConversationRepository(
    ref.watch(conversationsDaoProvider),
    _resolveSyncHandle(ref),
  ),
);

final chatMessageRepositoryProvider = Provider<ChatMessageRepository>(
  (ref) => DriftChatMessageRepository(
    ref.watch(chatMessagesDaoProvider),
    _resolveSyncHandle(ref),
  ),
);

final systemSettingsRepositoryProvider = Provider<SystemSettingsRepository>(
  (ref) => DriftSystemSettingsRepository(
    ref.watch(systemSettingsDaoProvider),
    _resolveSyncHandle(ref),
  ),
);

final pollRepositoryProvider = Provider<PollRepository>(
  (ref) => DriftPollRepository(
    ref.watch(pollsDaoProvider),
    ref.watch(pollOptionsDaoProvider),
    ref.watch(pollVotesDaoProvider),
    _resolveSyncHandle(ref),
  ),
);

final habitsDaoProvider = Provider<HabitsDao>(
  (ref) => ref.watch(databaseProvider).habitsDao,
);

final habitRepositoryProvider = Provider<HabitRepository>(
  (ref) => DriftHabitRepository(
    ref.watch(habitsDaoProvider),
    _resolveSyncHandle(ref),
  ),
);

final memberGroupsDaoProvider = Provider<MemberGroupsDao>(
  (ref) => ref.watch(databaseProvider).memberGroupsDao,
);

final memberGroupsRepositoryProvider = Provider<MemberGroupsRepository>(
  (ref) => DriftMemberGroupsRepository(
    ref.watch(memberGroupsDaoProvider),
    _resolveSyncHandle(ref),
    memberRepository: ref.watch(memberRepositoryProvider),
  ),
);

final customFieldsDaoProvider = Provider<CustomFieldsDao>(
  (ref) => ref.watch(databaseProvider).customFieldsDao,
);

final customFieldsRepositoryProvider = Provider<CustomFieldsRepository>(
  (ref) => DriftCustomFieldsRepository(
    ref.watch(customFieldsDaoProvider),
    _resolveSyncHandle(ref),
  ),
);

final notesDaoProvider = Provider<NotesDao>(
  (ref) => ref.watch(databaseProvider).notesDao,
);

final notesRepositoryProvider = Provider<NotesRepository>(
  (ref) => DriftNotesRepository(
    ref.watch(notesDaoProvider),
    _resolveSyncHandle(ref),
  ),
);

final frontSessionCommentsDaoProvider = Provider<FrontSessionCommentsDao>(
  (ref) => ref.watch(databaseProvider).frontSessionCommentsDao,
);

final frontSessionCommentsRepositoryProvider =
    Provider<FrontSessionCommentsRepository>(
      (ref) => DriftFrontSessionCommentsRepository(
        ref.watch(frontSessionCommentsDaoProvider),
        _resolveSyncHandle(ref),
      ),
    );

final conversationCategoriesDaoProvider = Provider<ConversationCategoriesDao>(
  (ref) => ref.watch(databaseProvider).conversationCategoriesDao,
);

final conversationCategoriesRepositoryProvider =
    Provider<ConversationCategoriesRepository>(
      (ref) => DriftConversationCategoriesRepository(
        ref.watch(conversationCategoriesDaoProvider),
        _resolveSyncHandle(ref),
      ),
    );

final remindersDaoProvider = Provider<RemindersDao>(
  (ref) => ref.watch(databaseProvider).remindersDao,
);

final remindersRepositoryProvider = Provider<RemindersRepository>(
  (ref) => DriftRemindersRepository(
    ref.watch(remindersDaoProvider),
    _resolveSyncHandle(ref),
  ),
);

final friendsDaoProvider = Provider<FriendsDao>(
  (ref) => ref.watch(databaseProvider).friendsDao,
);

final sharingRequestsDaoProvider = Provider<SharingRequestsDao>(
  (ref) => ref.watch(databaseProvider).sharingRequestsDao,
);

final friendsRepositoryProvider = Provider<FriendsRepository>(
  (ref) => DriftFriendsRepository(
    ref.watch(friendsDaoProvider),
    _resolveSyncHandle(ref),
  ),
);

final mediaAttachmentsDaoProvider = Provider<MediaAttachmentsDao>(
  (ref) => ref.watch(databaseProvider).mediaAttachmentsDao,
);

final mediaAttachmentRepositoryProvider = Provider<MediaAttachmentRepository>(
  (ref) => DriftMediaAttachmentRepository(
    ref.watch(mediaAttachmentsDaoProvider),
    _resolveSyncHandle(ref),
  ),
);
