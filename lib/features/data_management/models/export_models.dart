import 'dart:convert';
import 'dart:typed_data';

/// V3 export format envelope.
class V1Export {
  V1Export({
    required this.formatVersion,
    required this.version,
    required this.appName,
    required this.exportDate,
    required this.totalRecords,
    required this.headmates,
    required this.frontSessions,
    required this.sleepSessions,
    required this.conversations,
    required this.messages,
    required this.polls,
    required this.pollOptions,
    required this.systemSettings,
    required this.habits,
    required this.habitCompletions,
    this.pluralKitSyncState,
    this.memberGroups = const [],
    this.memberGroupEntries = const [],
    this.customFields = const [],
    this.customFieldValues = const [],
    this.notes = const [],
    this.frontSessionComments = const [],
    this.conversationCategories = const [],
    this.reminders = const [],
    this.friends = const [],
    this.mediaAttachments = const [],
  });

  final String formatVersion;
  final String version;
  final String appName;
  final String exportDate;
  final int totalRecords;
  final List<V1Headmate> headmates;
  final List<V1FrontSession> frontSessions;
  final List<V1SleepSession> sleepSessions;
  final List<V1Conversation> conversations;
  final List<V1Message> messages;
  final List<V1Poll> polls;
  final List<V1PollOption> pollOptions;
  final List<V1SystemSettings> systemSettings;
  final List<V1Habit> habits;
  final List<V1HabitCompletion> habitCompletions;
  final V1PluralKitSyncState? pluralKitSyncState;
  final List<V1MemberGroup> memberGroups;
  final List<V1MemberGroupEntry> memberGroupEntries;
  final List<V1CustomField> customFields;
  final List<V1CustomFieldValue> customFieldValues;
  final List<V1Note> notes;
  final List<V1FrontSessionComment> frontSessionComments;
  final List<V1ConversationCategory> conversationCategories;
  final List<V1Reminder> reminders;
  final List<V1Friend> friends;
  final List<V1MediaAttachment> mediaAttachments;

  Map<String, dynamic> toJson() => {
    'formatVersion': formatVersion,
    'version': version,
    'appName': appName,
    'exportDate': exportDate,
    'totalRecords': totalRecords,
    'headmates': headmates.map((e) => e.toJson()).toList(),
    'frontSessions': frontSessions.map((e) => e.toJson()).toList(),
    'sleepSessions': sleepSessions.map((e) => e.toJson()).toList(),
    'conversations': conversations.map((e) => e.toJson()).toList(),
    'messages': messages.map((e) => e.toJson()).toList(),
    'polls': polls.map((e) => e.toJson()).toList(),
    'pollOptions': pollOptions.map((e) => e.toJson()).toList(),
    'systemSettings': systemSettings.map((e) => e.toJson()).toList(),
    'habits': habits.map((e) => e.toJson()).toList(),
    'habitCompletions': habitCompletions.map((e) => e.toJson()).toList(),
    if (pluralKitSyncState != null)
      'pluralKitSyncState': pluralKitSyncState!.toJson(),
    if (memberGroups.isNotEmpty)
      'memberGroups': memberGroups.map((e) => e.toJson()).toList(),
    if (memberGroupEntries.isNotEmpty)
      'memberGroupEntries': memberGroupEntries.map((e) => e.toJson()).toList(),
    if (customFields.isNotEmpty)
      'customFields': customFields.map((e) => e.toJson()).toList(),
    if (customFieldValues.isNotEmpty)
      'customFieldValues': customFieldValues.map((e) => e.toJson()).toList(),
    if (notes.isNotEmpty) 'notes': notes.map((e) => e.toJson()).toList(),
    if (frontSessionComments.isNotEmpty)
      'frontSessionComments': frontSessionComments
          .map((e) => e.toJson())
          .toList(),
    if (conversationCategories.isNotEmpty)
      'conversationCategories': conversationCategories
          .map((e) => e.toJson())
          .toList(),
    if (reminders.isNotEmpty)
      'reminders': reminders.map((e) => e.toJson()).toList(),
    if (friends.isNotEmpty) 'friends': friends.map((e) => e.toJson()).toList(),
    if (mediaAttachments.isNotEmpty)
      'mediaAttachments': mediaAttachments.map((e) => e.toJson()).toList(),
  };

  factory V1Export.fromJson(Map<String, dynamic> json) => V1Export(
    formatVersion: json['formatVersion'] as String? ?? '1.0',
    version: json['version'] as String? ?? '1.0',
    appName: json['appName'] as String? ?? 'Prism Plurality',
    exportDate: json['exportDate'] as String? ?? '',
    totalRecords: json['totalRecords'] as int? ?? 0,
    headmates:
        (json['headmates'] as List<dynamic>?)
            ?.map((e) => V1Headmate.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    frontSessions:
        (json['frontSessions'] as List<dynamic>?)
            ?.map((e) => V1FrontSession.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    sleepSessions:
        (json['sleepSessions'] as List<dynamic>?)
            ?.map((e) => V1SleepSession.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    conversations:
        (json['conversations'] as List<dynamic>?)
            ?.map((e) => V1Conversation.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    messages:
        (json['messages'] as List<dynamic>?)
            ?.map((e) => V1Message.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    polls:
        (json['polls'] as List<dynamic>?)
            ?.map((e) => V1Poll.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    pollOptions:
        (json['pollOptions'] as List<dynamic>?)
            ?.map((e) => V1PollOption.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    systemSettings:
        (json['systemSettings'] as List<dynamic>?)
            ?.map((e) => V1SystemSettings.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    habits:
        (json['habits'] as List<dynamic>?)
            ?.map((e) => V1Habit.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    habitCompletions:
        (json['habitCompletions'] as List<dynamic>?)
            ?.map((e) => V1HabitCompletion.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    pluralKitSyncState: json['pluralKitSyncState'] != null
        ? V1PluralKitSyncState.fromJson(
            json['pluralKitSyncState'] as Map<String, dynamic>,
          )
        : null,
    memberGroups:
        (json['memberGroups'] as List<dynamic>?)
            ?.map((e) => V1MemberGroup.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    memberGroupEntries:
        (json['memberGroupEntries'] as List<dynamic>?)
            ?.map((e) => V1MemberGroupEntry.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    customFields:
        (json['customFields'] as List<dynamic>?)
            ?.map((e) => V1CustomField.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    customFieldValues:
        (json['customFieldValues'] as List<dynamic>?)
            ?.map((e) => V1CustomFieldValue.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    notes:
        (json['notes'] as List<dynamic>?)
            ?.map((e) => V1Note.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    frontSessionComments:
        (json['frontSessionComments'] as List<dynamic>?)
            ?.map(
              (e) => V1FrontSessionComment.fromJson(e as Map<String, dynamic>),
            )
            .toList() ??
        [],
    conversationCategories:
        (json['conversationCategories'] as List<dynamic>?)
            ?.map(
              (e) => V1ConversationCategory.fromJson(e as Map<String, dynamic>),
            )
            .toList() ??
        [],
    reminders:
        (json['reminders'] as List<dynamic>?)
            ?.map((e) => V1Reminder.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    friends:
        (json['friends'] as List<dynamic>?)
            ?.map((e) => V1Friend.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    mediaAttachments:
        (json['mediaAttachments'] as List<dynamic>?)
            ?.map(
              (e) => V1MediaAttachment.fromJson(e as Map<String, dynamic>),
            )
            .toList() ??
        [],
  );
}

// ---------------------------------------------------------------------------
// V1Headmate
// ---------------------------------------------------------------------------

class V1Headmate {
  V1Headmate({
    required this.id,
    required this.name,
    this.pronouns,
    this.emoji,
    this.age,
    this.notes,
    this.profilePhotoData,
    this.isActive = true,
    required this.createdAt,
    this.displayOrder = 0,
    this.isAdmin = false,
    this.customColorEnabled = false,
    this.customColorHex,
    this.parentSystemId,
    this.pluralkitUuid,
    this.pluralkitId,
    this.markdownEnabled = false,
    this.displayName,
    this.birthday,
    this.proxyTagsJson,
    this.pluralkitSyncIgnored = false,
  });

  final String id;
  final String name;
  final String? pronouns;
  final String? emoji;
  final int? age;
  final String? notes;
  final String? profilePhotoData; // base64
  final bool isActive;
  final String createdAt;
  final int displayOrder;
  final bool isAdmin;
  final bool customColorEnabled;
  final String? customColorHex;
  final String? parentSystemId;
  final String? pluralkitUuid;
  final String? pluralkitId;
  final bool markdownEnabled;
  // PluralKit Phase 2 fields (additive; older exports default to null/false)
  final String? displayName;
  final String? birthday;
  final String? proxyTagsJson;
  final bool pluralkitSyncIgnored;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (pronouns != null) 'pronouns': pronouns,
    if (emoji != null) 'emoji': emoji,
    if (age != null) 'age': age,
    if (notes != null) 'notes': notes,
    if (profilePhotoData != null) 'profilePhotoData': profilePhotoData,
    'isActive': isActive,
    'createdAt': createdAt,
    'displayOrder': displayOrder,
    'isAdmin': isAdmin,
    'customColorEnabled': customColorEnabled,
    if (customColorHex != null) 'customColorHex': customColorHex,
    if (parentSystemId != null) 'parentSystemId': parentSystemId,
    if (pluralkitUuid != null) 'pluralkitUuid': pluralkitUuid,
    if (pluralkitId != null) 'pluralkitId': pluralkitId,
    'markdownEnabled': markdownEnabled,
    if (displayName != null) 'displayName': displayName,
    if (birthday != null) 'birthday': birthday,
    if (proxyTagsJson != null) 'proxyTagsJson': proxyTagsJson,
    'pluralkitSyncIgnored': pluralkitSyncIgnored,
  };

  factory V1Headmate.fromJson(Map<String, dynamic> json) => V1Headmate(
    id: json['id'] as String,
    name: json['name'] as String,
    pronouns: json['pronouns'] as String?,
    emoji: json['emoji'] as String?,
    age: json['age'] as int?,
    notes: json['notes'] as String?,
    profilePhotoData: json['profilePhotoData'] as String?,
    isActive: json['isActive'] as bool? ?? true,
    createdAt: json['createdAt'] as String,
    displayOrder: json['displayOrder'] as int? ?? 0,
    isAdmin: json['isAdmin'] as bool? ?? false,
    customColorEnabled: json['customColorEnabled'] as bool? ?? false,
    customColorHex: json['customColorHex'] as String?,
    parentSystemId: json['parentSystemId'] as String?,
    pluralkitUuid: json['pluralkitUuid'] as String?,
    pluralkitId: json['pluralkitId'] as String?,
    markdownEnabled: json['markdownEnabled'] as bool? ?? false,
    displayName: json['displayName'] as String?,
    birthday: json['birthday'] as String?,
    proxyTagsJson: json['proxyTagsJson'] as String?,
    pluralkitSyncIgnored: json['pluralkitSyncIgnored'] as bool? ?? false,
  );

  /// Convert base64 profilePhotoData to Uint8List.
  Uint8List? get avatarImageData =>
      profilePhotoData != null ? base64Decode(profilePhotoData!) : null;
}

// ---------------------------------------------------------------------------
// V1FrontSession
// ---------------------------------------------------------------------------

class V1FrontSession {
  V1FrontSession({
    required this.id,
    required this.startTime,
    this.endTime,
    this.headmateId,
    this.coFronterIds = const [],
    this.notes,
    this.confidence,
    this.pluralkitUuid,
    this.pkMemberIdsJson,
  });

  final String id;
  final String startTime;
  final String? endTime;
  final String? headmateId;
  final List<String> coFronterIds;
  final String? notes;
  final int? confidence;
  final String? pluralkitUuid;
  // PluralKit Phase 2: JSON-encoded list of PK member UUIDs for this switch
  // (additive; older exports default to null).
  final String? pkMemberIdsJson;

  Map<String, dynamic> toJson() => {
    'id': id,
    'startTime': startTime,
    if (endTime != null) 'endTime': endTime,
    if (headmateId != null) 'headmateId': headmateId,
    if (coFronterIds.isNotEmpty) 'coFronterIds': coFronterIds,
    if (notes != null) 'notes': notes,
    if (confidence != null) 'confidence': confidence,
    if (pluralkitUuid != null) 'pluralkitUuid': pluralkitUuid,
    if (pkMemberIdsJson != null) 'pkMemberIdsJson': pkMemberIdsJson,
  };

  factory V1FrontSession.fromJson(Map<String, dynamic> json) => V1FrontSession(
    id: json['id'] as String,
    startTime: json['startTime'] as String,
    endTime: json['endTime'] as String?,
    headmateId: json['headmateId'] as String?,
    coFronterIds:
        (json['coFronterIds'] as List<dynamic>?)?.cast<String>() ?? [],
    notes: json['notes'] as String?,
    confidence: json['confidence'] as int?,
    pluralkitUuid: json['pluralkitUuid'] as String?,
    pkMemberIdsJson: json['pkMemberIdsJson'] as String?,
  );
}

// ---------------------------------------------------------------------------
// V1SleepSession
// ---------------------------------------------------------------------------

class V1SleepSession {
  V1SleepSession({
    required this.id,
    required this.startTime,
    this.endTime,
    this.quality = 0,
    this.notes,
    this.isHealthKitImport = false,
  });

  final String id;
  final String startTime;
  final String? endTime;
  final int quality;
  final String? notes;
  final bool isHealthKitImport;

  Map<String, dynamic> toJson() => {
    'id': id,
    'startTime': startTime,
    if (endTime != null) 'endTime': endTime,
    'quality': quality,
    if (notes != null) 'notes': notes,
    'isHealthKitImport': isHealthKitImport,
  };

  factory V1SleepSession.fromJson(Map<String, dynamic> json) => V1SleepSession(
    id: json['id'] as String,
    startTime: json['startTime'] as String,
    endTime: json['endTime'] as String?,
    quality: json['quality'] as int? ?? 0,
    notes: json['notes'] as String?,
    isHealthKitImport: json['isHealthKitImport'] as bool? ?? false,
  );
}

// ---------------------------------------------------------------------------
// V1Conversation
// ---------------------------------------------------------------------------

class V1Conversation {
  V1Conversation({
    required this.id,
    required this.createdAt,
    required this.lastActivityAt,
    this.title,
    this.emoji,
    this.isDirectMessage = false,
    this.creatorId,
    this.participantIds = const [],
    this.lastReadTimestamps = const {},
    this.archivedByMemberIds,
    this.mutedByMemberIds,
    this.description,
    this.categoryId,
    this.displayOrder = 0,
  });

  final String id;
  final String createdAt;
  final String lastActivityAt;
  final String? title;
  final String? emoji;
  final bool isDirectMessage;
  final String? creatorId;
  final List<String> participantIds;
  final Map<String, String> lastReadTimestamps;
  final String? archivedByMemberIds; // JSON-encoded string list
  final String? mutedByMemberIds; // JSON-encoded string list
  final String? description;
  final String? categoryId;
  final int displayOrder;

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt,
    'lastActivityAt': lastActivityAt,
    if (title != null) 'title': title,
    if (emoji != null) 'emoji': emoji,
    'isDirectMessage': isDirectMessage,
    if (creatorId != null) 'creatorId': creatorId,
    'participantIds': participantIds,
    'lastReadTimestamps': lastReadTimestamps,
    if (archivedByMemberIds != null) 'archivedByMemberIds': archivedByMemberIds,
    if (mutedByMemberIds != null) 'mutedByMemberIds': mutedByMemberIds,
    if (description != null) 'description': description,
    if (categoryId != null) 'categoryId': categoryId,
    'displayOrder': displayOrder,
  };

  factory V1Conversation.fromJson(Map<String, dynamic> json) => V1Conversation(
    id: json['id'] as String,
    createdAt: json['createdAt'] as String,
    lastActivityAt: json['lastActivityAt'] as String,
    title: json['title'] as String?,
    emoji: json['emoji'] as String?,
    isDirectMessage: json['isDirectMessage'] as bool? ?? false,
    creatorId: json['creatorId'] as String?,
    participantIds:
        (json['participantIds'] as List<dynamic>?)?.cast<String>() ?? [],
    lastReadTimestamps:
        (json['lastReadTimestamps'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, v.toString()),
        ) ??
        {},
    archivedByMemberIds: json['archivedByMemberIds'] as String?,
    mutedByMemberIds: json['mutedByMemberIds'] as String?,
    description: json['description'] as String?,
    categoryId: json['categoryId'] as String?,
    displayOrder: json['displayOrder'] as int? ?? 0,
  );
}

// ---------------------------------------------------------------------------
// V1Message
// ---------------------------------------------------------------------------

class V1Message {
  V1Message({
    required this.id,
    required this.content,
    required this.timestamp,
    this.isSystemMessage = false,
    this.editedAt,
    this.authorId,
    required this.conversationId,
    this.reactions = const [],
    this.replyToId,
    this.replyToAuthorId,
    this.replyToContent,
  });

  final String id;
  final String content;
  final String timestamp;
  final bool isSystemMessage;
  final String? editedAt;
  final String? authorId;
  final String conversationId;
  final List<V1MessageReaction> reactions;
  final String? replyToId;
  final String? replyToAuthorId;
  final String? replyToContent;

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'timestamp': timestamp,
    'isSystemMessage': isSystemMessage,
    if (editedAt != null) 'editedAt': editedAt,
    if (authorId != null) 'authorId': authorId,
    'conversationId': conversationId,
    if (reactions.isNotEmpty)
      'reactions': reactions.map((r) => r.toJson()).toList(),
    if (replyToId != null) 'replyToId': replyToId,
    if (replyToAuthorId != null) 'replyToAuthorId': replyToAuthorId,
    if (replyToContent != null) 'replyToContent': replyToContent,
  };

  factory V1Message.fromJson(Map<String, dynamic> json) => V1Message(
    id: json['id'] as String,
    content: json['content'] as String,
    timestamp: json['timestamp'] as String,
    isSystemMessage: json['isSystemMessage'] as bool? ?? false,
    editedAt: json['editedAt'] as String?,
    authorId: json['authorId'] as String?,
    conversationId: json['conversationId'] as String,
    reactions:
        (json['reactions'] as List<dynamic>?)
            ?.map((e) => V1MessageReaction.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    replyToId: json['replyToId'] as String?,
    replyToAuthorId: json['replyToAuthorId'] as String?,
    replyToContent: json['replyToContent'] as String?,
  );
}

class V1MessageReaction {
  V1MessageReaction({
    required this.id,
    required this.emoji,
    required this.memberId,
    required this.timestamp,
  });

  final String id;
  final String emoji;
  final String memberId;
  final String timestamp;

  Map<String, dynamic> toJson() => {
    'id': id,
    'emoji': emoji,
    'memberId': memberId,
    'timestamp': timestamp,
  };

  factory V1MessageReaction.fromJson(Map<String, dynamic> json) =>
      V1MessageReaction(
        id: json['id'] as String,
        emoji: json['emoji'] as String,
        memberId: json['memberId'] as String,
        timestamp: json['timestamp'] as String,
      );
}

// ---------------------------------------------------------------------------
// V1Poll
// ---------------------------------------------------------------------------

class V1Poll {
  V1Poll({
    required this.id,
    required this.question,
    this.isAnonymous = false,
    this.allowsMultipleVotes = false,
    this.description,
    this.isClosed = false,
    this.expiresAt,
    required this.createdAt,
  });

  final String id;
  final String question;
  final String? description;
  final bool isAnonymous;
  final bool allowsMultipleVotes;
  final bool isClosed;
  final String? expiresAt;
  final String createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'question': question,
    if (description != null) 'description': description,
    'isAnonymous': isAnonymous,
    'allowsMultipleVotes': allowsMultipleVotes,
    'isClosed': isClosed,
    if (expiresAt != null) 'expiresAt': expiresAt,
    'createdAt': createdAt,
  };

  factory V1Poll.fromJson(Map<String, dynamic> json) => V1Poll(
    id: json['id'] as String,
    question: json['question'] as String,
    description: json['description'] as String?,
    isAnonymous: json['isAnonymous'] as bool? ?? false,
    allowsMultipleVotes: json['allowsMultipleVotes'] as bool? ?? false,
    isClosed: json['isClosed'] as bool? ?? false,
    expiresAt: json['expiresAt'] as String?,
    createdAt: json['createdAt'] as String,
  );
}

// ---------------------------------------------------------------------------
// V1PollOption
// ---------------------------------------------------------------------------

class V1PollOption {
  V1PollOption({
    required this.id,
    required this.pollId,
    required this.text,
    this.sortOrder = 0,
    this.isOtherOption = false,
    this.colorHex,
    this.votes = const [],
  });

  final String id;
  final String pollId;
  final String text;
  final int sortOrder;
  final bool isOtherOption;
  final String? colorHex;
  final List<V1PollVote> votes;

  Map<String, dynamic> toJson() => {
    'id': id,
    'pollId': pollId,
    'text': text,
    'sortOrder': sortOrder,
    'isOtherOption': isOtherOption,
    if (colorHex != null) 'colorHex': colorHex,
    if (votes.isNotEmpty) 'votes': votes.map((v) => v.toJson()).toList(),
  };

  factory V1PollOption.fromJson(Map<String, dynamic> json) => V1PollOption(
    id: json['id'] as String,
    pollId: json['pollId'] as String,
    text: json['text'] as String,
    sortOrder: json['sortOrder'] as int? ?? 0,
    isOtherOption: json['isOtherOption'] as bool? ?? false,
    colorHex: json['colorHex'] as String?,
    votes:
        (json['votes'] as List<dynamic>?)
            ?.map((e) => V1PollVote.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
  );
}

class V1PollVote {
  V1PollVote({
    required this.id,
    required this.memberId,
    required this.votedAt,
    this.responseText,
  });

  final String id;
  final String memberId;
  final String votedAt;
  final String? responseText;

  Map<String, dynamic> toJson() => {
    'id': id,
    'memberId': memberId,
    'votedAt': votedAt,
    if (responseText != null) 'responseText': responseText,
  };

  factory V1PollVote.fromJson(Map<String, dynamic> json) => V1PollVote(
    id: json['id'] as String,
    memberId: json['memberId'] as String,
    votedAt: json['votedAt'] as String,
    responseText: json['responseText'] as String?,
  );
}

// ---------------------------------------------------------------------------
// V1SystemSettings
// ---------------------------------------------------------------------------

class V1SystemSettings {
  V1SystemSettings({
    this.systemName,
    this.sharingId,
    this.showQuickFront = true,
    this.accentColorHex = '#AF8EE9',
    this.perMemberAccentColors = true,
    this.terminology = 0,
    this.customTerminology,
    this.customPluralTerminology,
    this.terminologyUseEnglish = false,
    this.frontingRemindersEnabled = false,
    this.frontingReminderIntervalMinutes = 60,
    this.themeMode = 0,
    this.themeBrightness = 0,
    this.themeStyle = 0,
    this.chatEnabled = true,
    this.pollsEnabled = true,
    this.habitsEnabled = true,
    this.sleepTrackingEnabled = true,
    this.quickSwitchThresholdSeconds = 30,
    this.identityGeneration = 0,
    this.chatLogsFront = false,
    this.hasCompletedOnboarding = false,
    this.syncThemeEnabled = false,
    this.timingMode,
    this.habitsBadgeEnabled = true,
    this.notesEnabled = true,
    this.previousAccentColorHex = '',
    this.systemDescription,
    this.systemAvatarData, // base64
    this.remindersEnabled = true,
    this.fontScale = 1.0,
    this.fontFamily = 0,
    this.pinLockEnabled = false,
    this.biometricLockEnabled = false,
    this.autoLockDelaySeconds = 0,
    this.navBarItems = const [],
    this.navBarOverflowItems = const [],
    this.syncNavigationEnabled = true,
    this.chatBadgePreferences = const {},
  });

  final String? systemName;
  final String? sharingId;
  final bool showQuickFront;
  final String accentColorHex;
  final bool perMemberAccentColors;
  final int terminology;
  final String? customTerminology;
  final String? customPluralTerminology;
  final bool terminologyUseEnglish;
  final bool frontingRemindersEnabled;
  final int frontingReminderIntervalMinutes;
  final int themeMode;
  final int themeBrightness; // ThemeBrightness enum index
  final int themeStyle; // ThemeStyle enum index
  final bool chatEnabled;
  final bool pollsEnabled;
  final bool habitsEnabled;
  final bool sleepTrackingEnabled;
  final int quickSwitchThresholdSeconds;
  final int identityGeneration;
  final bool chatLogsFront;
  final bool hasCompletedOnboarding;
  final bool syncThemeEnabled;
  final int? timingMode; // FrontingTimingMode enum index
  final bool habitsBadgeEnabled;
  final bool notesEnabled;
  final String previousAccentColorHex;
  final String? systemDescription;
  final String? systemAvatarData; // base64
  final bool remindersEnabled;
  final double fontScale;
  final int fontFamily; // FontFamily enum index
  final bool pinLockEnabled;
  final bool biometricLockEnabled;
  final int autoLockDelaySeconds;
  final List<String> navBarItems;
  final List<String> navBarOverflowItems;
  final bool syncNavigationEnabled;
  final Map<String, String> chatBadgePreferences;

  Map<String, dynamic> toJson() => {
    if (systemName != null) 'systemName': systemName,
    if (sharingId != null) 'sharingId': sharingId,
    'showQuickFront': showQuickFront,
    'accentColorHex': accentColorHex,
    'perMemberAccentColors': perMemberAccentColors,
    'terminology': terminology,
    if (customTerminology != null) 'customTerminology': customTerminology,
    if (customPluralTerminology != null)
      'customPluralTerminology': customPluralTerminology,
    'terminologyUseEnglish': terminologyUseEnglish,
    'frontingRemindersEnabled': frontingRemindersEnabled,
    'frontingReminderIntervalMinutes': frontingReminderIntervalMinutes,
    'themeMode': themeMode,
    'themeBrightness': themeBrightness,
    'themeStyle': themeStyle,
    'chatEnabled': chatEnabled,
    'pollsEnabled': pollsEnabled,
    'habitsEnabled': habitsEnabled,
    'sleepTrackingEnabled': sleepTrackingEnabled,
    'quickSwitchThresholdSeconds': quickSwitchThresholdSeconds,
    'identityGeneration': identityGeneration,
    'chatLogsFront': chatLogsFront,
    'hasCompletedOnboarding': hasCompletedOnboarding,
    'syncThemeEnabled': syncThemeEnabled,
    if (timingMode != null) 'timingMode': timingMode,
    'habitsBadgeEnabled': habitsBadgeEnabled,
    'notesEnabled': notesEnabled,
    'previousAccentColorHex': previousAccentColorHex,
    if (systemDescription != null) 'systemDescription': systemDescription,
    if (systemAvatarData != null) 'systemAvatarData': systemAvatarData,
    'remindersEnabled': remindersEnabled,
    'fontScale': fontScale,
    'fontFamily': fontFamily,
    'pinLockEnabled': pinLockEnabled,
    'biometricLockEnabled': biometricLockEnabled,
    'autoLockDelaySeconds': autoLockDelaySeconds,
    if (navBarItems.isNotEmpty) 'navBarItems': navBarItems,
    if (navBarOverflowItems.isNotEmpty)
      'navBarOverflowItems': navBarOverflowItems,
    'syncNavigationEnabled': syncNavigationEnabled,
    if (chatBadgePreferences.isNotEmpty)
      'chatBadgePreferences': chatBadgePreferences,
  };

  factory V1SystemSettings.fromJson(
    Map<String, dynamic> json,
  ) => V1SystemSettings(
    systemName: json['systemName'] as String?,
    sharingId: json['sharingId'] as String?,
    showQuickFront: json['showQuickFront'] as bool? ?? true,
    accentColorHex: json['accentColorHex'] as String? ?? '#AF8EE9',
    perMemberAccentColors: json['perMemberAccentColors'] as bool? ?? true,
    terminology: json['terminology'] as int? ?? 0,
    customTerminology: json['customTerminology'] as String?,
    customPluralTerminology: json['customPluralTerminology'] as String?,
    terminologyUseEnglish: json['terminologyUseEnglish'] as bool? ?? false,
    frontingRemindersEnabled:
        json['frontingRemindersEnabled'] as bool? ?? false,
    frontingReminderIntervalMinutes:
        json['frontingReminderIntervalMinutes'] as int? ?? 60,
    themeMode: json['themeMode'] as int? ?? 0,
    themeBrightness: json['themeBrightness'] as int? ?? 0,
    themeStyle: json['themeStyle'] as int? ?? 0,
    chatEnabled: json['chatEnabled'] as bool? ?? true,
    pollsEnabled: json['pollsEnabled'] as bool? ?? true,
    habitsEnabled: json['habitsEnabled'] as bool? ?? true,
    sleepTrackingEnabled: json['sleepTrackingEnabled'] as bool? ?? true,
    quickSwitchThresholdSeconds:
        json['quickSwitchThresholdSeconds'] as int? ?? 30,
    identityGeneration: json['identityGeneration'] as int? ?? 0,
    chatLogsFront: json['chatLogsFront'] as bool? ?? false,
    hasCompletedOnboarding: json['hasCompletedOnboarding'] as bool? ?? false,
    syncThemeEnabled: json['syncThemeEnabled'] as bool? ?? false,
    timingMode: json['timingMode'] as int?,
    habitsBadgeEnabled: json['habitsBadgeEnabled'] as bool? ?? true,
    notesEnabled: json['notesEnabled'] as bool? ?? true,
    previousAccentColorHex: json['previousAccentColorHex'] as String? ?? '',
    systemDescription: json['systemDescription'] as String?,
    systemAvatarData: json['systemAvatarData'] as String?,
    remindersEnabled: json['remindersEnabled'] as bool? ?? true,
    fontScale: (json['fontScale'] as num?)?.toDouble() ?? 1.0,
    fontFamily: json['fontFamily'] as int? ?? 0,
    pinLockEnabled: json['pinLockEnabled'] as bool? ?? false,
    biometricLockEnabled: json['biometricLockEnabled'] as bool? ?? false,
    autoLockDelaySeconds: json['autoLockDelaySeconds'] as int? ?? 0,
    navBarItems: (json['navBarItems'] as List<dynamic>?)?.cast<String>() ?? [],
    navBarOverflowItems:
        (json['navBarOverflowItems'] as List<dynamic>?)?.cast<String>() ?? [],
    syncNavigationEnabled: json['syncNavigationEnabled'] as bool? ?? true,
    chatBadgePreferences:
        (json['chatBadgePreferences'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, v.toString()),
        ) ??
        {},
  );
}

// ---------------------------------------------------------------------------
// V1Habit
// ---------------------------------------------------------------------------

class V1Habit {
  V1Habit({
    required this.id,
    required this.name,
    this.description,
    this.icon,
    this.colorHex,
    this.isActive = true,
    required this.createdAt,
    required this.modifiedAt,
    this.frequency = 'daily',
    this.weeklyDays,
    this.intervalDays,
    this.reminderTime,
    this.notificationsEnabled = false,
    this.notificationMessage,
    this.assignedMemberId,
    this.onlyNotifyWhenFronting = false,
    this.isPrivate = false,
    this.currentStreak = 0,
    this.bestStreak = 0,
    this.totalCompletions = 0,
  });

  final String id;
  final String name;
  final String? description;
  final String? icon;
  final String? colorHex;
  final bool isActive;
  final String createdAt;
  final String modifiedAt;
  final String frequency;
  final String? weeklyDays;
  final int? intervalDays;
  final String? reminderTime;
  final bool notificationsEnabled;
  final String? notificationMessage;
  final String? assignedMemberId;
  final bool onlyNotifyWhenFronting;
  final bool isPrivate;
  final int currentStreak;
  final int bestStreak;
  final int totalCompletions;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (description != null) 'description': description,
    if (icon != null) 'icon': icon,
    if (colorHex != null) 'colorHex': colorHex,
    'isActive': isActive,
    'createdAt': createdAt,
    'modifiedAt': modifiedAt,
    'frequency': frequency,
    if (weeklyDays != null) 'weeklyDays': weeklyDays,
    if (intervalDays != null) 'intervalDays': intervalDays,
    if (reminderTime != null) 'reminderTime': reminderTime,
    'notificationsEnabled': notificationsEnabled,
    if (notificationMessage != null) 'notificationMessage': notificationMessage,
    if (assignedMemberId != null) 'assignedMemberId': assignedMemberId,
    'onlyNotifyWhenFronting': onlyNotifyWhenFronting,
    'isPrivate': isPrivate,
    'currentStreak': currentStreak,
    'bestStreak': bestStreak,
    'totalCompletions': totalCompletions,
  };

  factory V1Habit.fromJson(Map<String, dynamic> json) => V1Habit(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    icon: json['icon'] as String?,
    colorHex: json['colorHex'] as String?,
    isActive: json['isActive'] as bool? ?? true,
    createdAt: json['createdAt'] as String,
    modifiedAt: json['modifiedAt'] as String,
    frequency: json['frequency'] as String? ?? 'daily',
    weeklyDays: json['weeklyDays'] as String?,
    intervalDays: json['intervalDays'] as int?,
    reminderTime: json['reminderTime'] as String?,
    notificationsEnabled: json['notificationsEnabled'] as bool? ?? false,
    notificationMessage: json['notificationMessage'] as String?,
    assignedMemberId: json['assignedMemberId'] as String?,
    onlyNotifyWhenFronting: json['onlyNotifyWhenFronting'] as bool? ?? false,
    isPrivate: json['isPrivate'] as bool? ?? false,
    currentStreak: json['currentStreak'] as int? ?? 0,
    bestStreak: json['bestStreak'] as int? ?? 0,
    totalCompletions: json['totalCompletions'] as int? ?? 0,
  );
}

// ---------------------------------------------------------------------------
// V1HabitCompletion
// ---------------------------------------------------------------------------

class V1HabitCompletion {
  V1HabitCompletion({
    required this.id,
    required this.habitId,
    required this.completedAt,
    this.completedByMemberId,
    this.notes,
    this.wasFronting = false,
    this.rating,
    required this.createdAt,
    required this.modifiedAt,
  });

  final String id;
  final String habitId;
  final String completedAt;
  final String? completedByMemberId;
  final String? notes;
  final bool wasFronting;
  final int? rating;
  final String createdAt;
  final String modifiedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'habitId': habitId,
    'completedAt': completedAt,
    if (completedByMemberId != null) 'completedByMemberId': completedByMemberId,
    if (notes != null) 'notes': notes,
    'wasFronting': wasFronting,
    if (rating != null) 'rating': rating,
    'createdAt': createdAt,
    'modifiedAt': modifiedAt,
  };

  factory V1HabitCompletion.fromJson(Map<String, dynamic> json) =>
      V1HabitCompletion(
        id: json['id'] as String,
        habitId: json['habitId'] as String,
        completedAt: json['completedAt'] as String,
        completedByMemberId: json['completedByMemberId'] as String?,
        notes: json['notes'] as String?,
        wasFronting: json['wasFronting'] as bool? ?? false,
        rating: json['rating'] as int?,
        createdAt: json['createdAt'] as String,
        modifiedAt: json['modifiedAt'] as String,
      );
}

// ---------------------------------------------------------------------------
// V1PluralKitSyncState
// ---------------------------------------------------------------------------

class V1PluralKitSyncState {
  V1PluralKitSyncState({
    this.systemId,
    this.isConnected = false,
    this.lastSyncDate,
    this.lastManualSyncDate,
  });

  final String? systemId;
  final bool isConnected;
  final String? lastSyncDate;
  final String? lastManualSyncDate;

  Map<String, dynamic> toJson() => {
    if (systemId != null) 'systemId': systemId,
    'isConnected': isConnected,
    if (lastSyncDate != null) 'lastSyncDate': lastSyncDate,
    if (lastManualSyncDate != null) 'lastManualSyncDate': lastManualSyncDate,
  };

  factory V1PluralKitSyncState.fromJson(Map<String, dynamic> json) =>
      V1PluralKitSyncState(
        systemId: json['systemId'] as String?,
        isConnected: json['isConnected'] as bool? ?? false,
        lastSyncDate: json['lastSyncDate'] as String?,
        lastManualSyncDate: json['lastManualSyncDate'] as String?,
      );
}

// ---------------------------------------------------------------------------
// V1MemberGroup
// ---------------------------------------------------------------------------

class V1MemberGroup {
  V1MemberGroup({
    required this.id,
    required this.name,
    this.description,
    this.colorHex,
    this.emoji,
    this.displayOrder = 0,
    this.parentGroupId,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String? description;
  final String? colorHex;
  final String? emoji;
  final int displayOrder;
  final String? parentGroupId;
  final String createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (description != null) 'description': description,
    if (colorHex != null) 'colorHex': colorHex,
    if (emoji != null) 'emoji': emoji,
    'displayOrder': displayOrder,
    if (parentGroupId != null) 'parentGroupId': parentGroupId,
    'createdAt': createdAt,
  };

  factory V1MemberGroup.fromJson(Map<String, dynamic> json) => V1MemberGroup(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    colorHex: json['colorHex'] as String?,
    emoji: json['emoji'] as String?,
    displayOrder: json['displayOrder'] as int? ?? 0,
    parentGroupId: json['parentGroupId'] as String?,
    createdAt: json['createdAt'] as String,
  );
}

// ---------------------------------------------------------------------------
// V1MemberGroupEntry
// ---------------------------------------------------------------------------

class V1MemberGroupEntry {
  V1MemberGroupEntry({
    required this.id,
    required this.groupId,
    required this.memberId,
  });

  final String id;
  final String groupId;
  final String memberId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'groupId': groupId,
    'memberId': memberId,
  };

  factory V1MemberGroupEntry.fromJson(Map<String, dynamic> json) =>
      V1MemberGroupEntry(
        id: json['id'] as String,
        groupId: json['groupId'] as String,
        memberId: json['memberId'] as String,
      );
}

// ---------------------------------------------------------------------------
// V1CustomField
// ---------------------------------------------------------------------------

class V1CustomField {
  V1CustomField({
    required this.id,
    required this.name,
    required this.fieldType,
    this.datePrecision,
    this.displayOrder = 0,
    required this.createdAt,
  });

  final String id;
  final String name;
  final int fieldType; // CustomFieldType enum index
  final int? datePrecision; // DatePrecision enum index
  final int displayOrder;
  final String createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'fieldType': fieldType,
    if (datePrecision != null) 'datePrecision': datePrecision,
    'displayOrder': displayOrder,
    'createdAt': createdAt,
  };

  factory V1CustomField.fromJson(Map<String, dynamic> json) => V1CustomField(
    id: json['id'] as String,
    name: json['name'] as String,
    fieldType: json['fieldType'] as int,
    datePrecision: json['datePrecision'] as int?,
    displayOrder: json['displayOrder'] as int? ?? 0,
    createdAt: json['createdAt'] as String,
  );
}

// ---------------------------------------------------------------------------
// V1CustomFieldValue
// ---------------------------------------------------------------------------

class V1CustomFieldValue {
  V1CustomFieldValue({
    required this.id,
    required this.customFieldId,
    required this.memberId,
    required this.value,
  });

  final String id;
  final String customFieldId;
  final String memberId;
  final String value;

  Map<String, dynamic> toJson() => {
    'id': id,
    'customFieldId': customFieldId,
    'memberId': memberId,
    'value': value,
  };

  factory V1CustomFieldValue.fromJson(Map<String, dynamic> json) =>
      V1CustomFieldValue(
        id: json['id'] as String,
        customFieldId: json['customFieldId'] as String,
        memberId: json['memberId'] as String,
        value: json['value'] as String,
      );
}

// ---------------------------------------------------------------------------
// V1Note
// ---------------------------------------------------------------------------

class V1Note {
  V1Note({
    required this.id,
    required this.title,
    required this.body,
    this.colorHex,
    this.memberId,
    required this.date,
    required this.createdAt,
    required this.modifiedAt,
  });

  final String id;
  final String title;
  final String body;
  final String? colorHex;
  final String? memberId;
  final String date;
  final String createdAt;
  final String modifiedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    if (colorHex != null) 'colorHex': colorHex,
    if (memberId != null) 'memberId': memberId,
    'date': date,
    'createdAt': createdAt,
    'modifiedAt': modifiedAt,
  };

  factory V1Note.fromJson(Map<String, dynamic> json) => V1Note(
    id: json['id'] as String,
    title: json['title'] as String,
    body: json['body'] as String,
    colorHex: json['colorHex'] as String?,
    memberId: json['memberId'] as String?,
    date: json['date'] as String,
    createdAt: json['createdAt'] as String,
    modifiedAt: json['modifiedAt'] as String,
  );
}

// ---------------------------------------------------------------------------
// V1FrontSessionComment
// ---------------------------------------------------------------------------

class V1FrontSessionComment {
  V1FrontSessionComment({
    required this.id,
    required this.sessionId,
    required this.body,
    required this.timestamp,
    required this.createdAt,
  });

  final String id;
  final String sessionId;
  final String body;
  final String timestamp;
  final String createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'body': body,
    'timestamp': timestamp,
    'createdAt': createdAt,
  };

  factory V1FrontSessionComment.fromJson(Map<String, dynamic> json) =>
      V1FrontSessionComment(
        id: json['id'] as String,
        sessionId: json['sessionId'] as String,
        body: json['body'] as String,
        timestamp: json['timestamp'] as String,
        createdAt: json['createdAt'] as String,
      );
}

// ---------------------------------------------------------------------------
// V1ConversationCategory
// ---------------------------------------------------------------------------

class V1ConversationCategory {
  V1ConversationCategory({
    required this.id,
    required this.name,
    this.displayOrder = 0,
    required this.createdAt,
    required this.modifiedAt,
  });

  final String id;
  final String name;
  final int displayOrder;
  final String createdAt;
  final String modifiedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'displayOrder': displayOrder,
    'createdAt': createdAt,
    'modifiedAt': modifiedAt,
  };

  factory V1ConversationCategory.fromJson(Map<String, dynamic> json) =>
      V1ConversationCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        displayOrder: json['displayOrder'] as int? ?? 0,
        createdAt: json['createdAt'] as String,
        modifiedAt: json['modifiedAt'] as String,
      );
}

// ---------------------------------------------------------------------------
// V1Reminder
// ---------------------------------------------------------------------------

class V1Reminder {
  V1Reminder({
    required this.id,
    required this.name,
    required this.message,
    this.trigger = 0,
    this.intervalDays,
    this.timeOfDay,
    this.delayHours,
    this.isActive = true,
    required this.createdAt,
    required this.modifiedAt,
  });

  final String id;
  final String name;
  final String message;
  final int trigger; // ReminderTrigger enum index
  final int? intervalDays;
  final String? timeOfDay;
  final int? delayHours;
  final bool isActive;
  final String createdAt;
  final String modifiedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'message': message,
    'trigger': trigger,
    if (intervalDays != null) 'intervalDays': intervalDays,
    if (timeOfDay != null) 'timeOfDay': timeOfDay,
    if (delayHours != null) 'delayHours': delayHours,
    'isActive': isActive,
    'createdAt': createdAt,
    'modifiedAt': modifiedAt,
  };

  factory V1Reminder.fromJson(Map<String, dynamic> json) => V1Reminder(
    id: json['id'] as String,
    name: json['name'] as String,
    message: json['message'] as String,
    trigger: json['trigger'] as int? ?? 0,
    intervalDays: json['intervalDays'] as int?,
    timeOfDay: json['timeOfDay'] as String?,
    delayHours: json['delayHours'] as int?,
    isActive: json['isActive'] as bool? ?? true,
    createdAt: json['createdAt'] as String,
    modifiedAt: json['modifiedAt'] as String,
  );
}

// ---------------------------------------------------------------------------
// V1Friend
// ---------------------------------------------------------------------------

class V1Friend {
  V1Friend({
    required this.id,
    required this.displayName,
    required this.publicKeyHex,
    this.peerSharingId,
    this.sharedSecretHex,
    this.offeredScopes = const [],
    this.grantedScopes = const [],
    this.isVerified = false,
    this.initId,
    required this.createdAt,
    this.establishedAt,
    this.lastSyncAt,
  });

  final String id;
  final String displayName;
  final String publicKeyHex;
  final String? peerSharingId;
  final String? sharedSecretHex;
  final List<String> offeredScopes;
  final List<String> grantedScopes;
  final bool isVerified;
  final String? initId;
  final String createdAt;
  final String? establishedAt;
  final String? lastSyncAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'publicKeyHex': publicKeyHex,
    if (peerSharingId != null) 'peerSharingId': peerSharingId,
    if (sharedSecretHex != null) 'sharedSecretHex': sharedSecretHex,
    if (offeredScopes.isNotEmpty) 'offeredScopes': offeredScopes,
    if (grantedScopes.isNotEmpty) 'grantedScopes': grantedScopes,
    'isVerified': isVerified,
    if (initId != null) 'initId': initId,
    'createdAt': createdAt,
    if (establishedAt != null) 'establishedAt': establishedAt,
    if (lastSyncAt != null) 'lastSyncAt': lastSyncAt,
  };

  factory V1Friend.fromJson(Map<String, dynamic> json) => V1Friend(
    id: json['id'] as String,
    displayName: json['displayName'] as String,
    publicKeyHex: json['publicKeyHex'] as String,
    peerSharingId: json['peerSharingId'] as String?,
    sharedSecretHex: json['sharedSecretHex'] as String?,
    offeredScopes:
        (json['offeredScopes'] as List<dynamic>?)?.cast<String>() ?? [],
    grantedScopes:
        (json['grantedScopes'] as List<dynamic>?)?.cast<String>() ?? [],
    isVerified: json['isVerified'] as bool? ?? false,
    initId: json['initId'] as String?,
    createdAt: json['createdAt'] as String,
    establishedAt: json['establishedAt'] as String?,
    lastSyncAt: json['lastSyncAt'] as String?,
  );
}

// ---------------------------------------------------------------------------
// V1MediaAttachment
// ---------------------------------------------------------------------------

class V1MediaAttachment {
  V1MediaAttachment({
    required this.id,
    required this.messageId,
    required this.mediaId,
    required this.mediaType,
    required this.encryptionKeyB64,
    required this.contentHash,
    required this.plaintextHash,
    required this.mimeType,
    required this.sizeBytes,
    this.width = 0,
    this.height = 0,
    this.durationMs = 0,
    this.blurhash = '',
    this.waveformB64 = '',
    this.thumbnailMediaId = '',
    this.isDeleted = false,
  });

  final String id;
  final String messageId;
  final String mediaId;
  final String mediaType;
  final String encryptionKeyB64;
  final String contentHash;
  final String plaintextHash;
  final String mimeType;
  final int sizeBytes;
  final int width;
  final int height;
  final int durationMs;
  final String blurhash;
  final String waveformB64;
  final String thumbnailMediaId;
  final bool isDeleted;

  Map<String, dynamic> toJson() => {
    'id': id,
    'messageId': messageId,
    'mediaId': mediaId,
    'mediaType': mediaType,
    'encryptionKeyB64': encryptionKeyB64,
    'contentHash': contentHash,
    'plaintextHash': plaintextHash,
    'mimeType': mimeType,
    'sizeBytes': sizeBytes,
    if (width != 0) 'width': width,
    if (height != 0) 'height': height,
    if (durationMs != 0) 'durationMs': durationMs,
    if (blurhash.isNotEmpty) 'blurhash': blurhash,
    if (waveformB64.isNotEmpty) 'waveformB64': waveformB64,
    if (thumbnailMediaId.isNotEmpty) 'thumbnailMediaId': thumbnailMediaId,
    'isDeleted': isDeleted,
  };

  factory V1MediaAttachment.fromJson(Map<String, dynamic> json) =>
      V1MediaAttachment(
        id: json['id'] as String,
        messageId: json['messageId'] as String,
        mediaId: json['mediaId'] as String,
        mediaType: json['mediaType'] as String,
        encryptionKeyB64: json['encryptionKeyB64'] as String,
        contentHash: json['contentHash'] as String,
        plaintextHash: json['plaintextHash'] as String,
        mimeType: json['mimeType'] as String,
        sizeBytes: json['sizeBytes'] as int,
        width: json['width'] as int? ?? 0,
        height: json['height'] as int? ?? 0,
        durationMs: json['durationMs'] as int? ?? 0,
        blurhash: json['blurhash'] as String? ?? '',
        waveformB64: json['waveformB64'] as String? ?? '',
        thumbnailMediaId: json['thumbnailMediaId'] as String? ?? '',
        isDeleted: json['isDeleted'] as bool? ?? false,
      );
}
