import 'dart:convert';
import 'dart:typed_data';

/// V3 export format envelope.
class V3Export {
  V3Export({
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
  });

  final String formatVersion;
  final String version;
  final String appName;
  final String exportDate;
  final int totalRecords;
  final List<V3Headmate> headmates;
  final List<V3FrontSession> frontSessions;
  final List<V3SleepSession> sleepSessions;
  final List<V3Conversation> conversations;
  final List<V3Message> messages;
  final List<V3Poll> polls;
  final List<V3PollOption> pollOptions;
  final List<V3SystemSettings> systemSettings;
  final List<V3Habit> habits;
  final List<V3HabitCompletion> habitCompletions;
  final V3PluralKitSyncState? pluralKitSyncState;
  final List<V3MemberGroup> memberGroups;
  final List<V3MemberGroupEntry> memberGroupEntries;
  final List<V3CustomField> customFields;
  final List<V3CustomFieldValue> customFieldValues;
  final List<V3Note> notes;
  final List<V3FrontSessionComment> frontSessionComments;
  final List<V3ConversationCategory> conversationCategories;
  final List<V3Reminder> reminders;
  final List<V3Friend> friends;

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
          'memberGroupEntries':
              memberGroupEntries.map((e) => e.toJson()).toList(),
        if (customFields.isNotEmpty)
          'customFields': customFields.map((e) => e.toJson()).toList(),
        if (customFieldValues.isNotEmpty)
          'customFieldValues':
              customFieldValues.map((e) => e.toJson()).toList(),
        if (notes.isNotEmpty)
          'notes': notes.map((e) => e.toJson()).toList(),
        if (frontSessionComments.isNotEmpty)
          'frontSessionComments':
              frontSessionComments.map((e) => e.toJson()).toList(),
        if (conversationCategories.isNotEmpty)
          'conversationCategories':
              conversationCategories.map((e) => e.toJson()).toList(),
        if (reminders.isNotEmpty)
          'reminders': reminders.map((e) => e.toJson()).toList(),
        if (friends.isNotEmpty)
          'friends': friends.map((e) => e.toJson()).toList(),
      };

  factory V3Export.fromJson(Map<String, dynamic> json) => V3Export(
        formatVersion: json['formatVersion'] as String? ?? '2025.1',
        version: json['version'] as String? ?? '3.0',
        appName: json['appName'] as String? ?? 'Prism Plurality',
        exportDate: json['exportDate'] as String? ?? '',
        totalRecords: json['totalRecords'] as int? ?? 0,
        headmates: (json['headmates'] as List<dynamic>?)
                ?.map((e) =>
                    V3Headmate.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        frontSessions: (json['frontSessions'] as List<dynamic>?)
                ?.map((e) =>
                    V3FrontSession.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        sleepSessions: (json['sleepSessions'] as List<dynamic>?)
                ?.map((e) =>
                    V3SleepSession.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        conversations: (json['conversations'] as List<dynamic>?)
                ?.map((e) =>
                    V3Conversation.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        messages: (json['messages'] as List<dynamic>?)
                ?.map(
                    (e) => V3Message.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        polls: (json['polls'] as List<dynamic>?)
                ?.map((e) => V3Poll.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        pollOptions: (json['pollOptions'] as List<dynamic>?)
                ?.map((e) =>
                    V3PollOption.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        systemSettings: (json['systemSettings'] as List<dynamic>?)
                ?.map((e) =>
                    V3SystemSettings.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        habits: (json['habits'] as List<dynamic>?)
                ?.map((e) => V3Habit.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        habitCompletions: (json['habitCompletions'] as List<dynamic>?)
                ?.map((e) =>
                    V3HabitCompletion.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        pluralKitSyncState: json['pluralKitSyncState'] != null
            ? V3PluralKitSyncState.fromJson(
                json['pluralKitSyncState'] as Map<String, dynamic>)
            : null,
        memberGroups: (json['memberGroups'] as List<dynamic>?)
                ?.map((e) =>
                    V3MemberGroup.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        memberGroupEntries: (json['memberGroupEntries'] as List<dynamic>?)
                ?.map((e) =>
                    V3MemberGroupEntry.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        customFields: (json['customFields'] as List<dynamic>?)
                ?.map((e) =>
                    V3CustomField.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        customFieldValues: (json['customFieldValues'] as List<dynamic>?)
                ?.map((e) =>
                    V3CustomFieldValue.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        notes: (json['notes'] as List<dynamic>?)
                ?.map((e) => V3Note.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        frontSessionComments:
            (json['frontSessionComments'] as List<dynamic>?)
                    ?.map((e) => V3FrontSessionComment.fromJson(
                        e as Map<String, dynamic>))
                    .toList() ??
                [],
        conversationCategories:
            (json['conversationCategories'] as List<dynamic>?)
                    ?.map((e) => V3ConversationCategory.fromJson(
                        e as Map<String, dynamic>))
                    .toList() ??
                [],
        reminders: (json['reminders'] as List<dynamic>?)
                ?.map(
                    (e) => V3Reminder.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        friends: (json['friends'] as List<dynamic>?)
                ?.map(
                    (e) => V3Friend.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

// ---------------------------------------------------------------------------
// V3Headmate
// ---------------------------------------------------------------------------

class V3Headmate {
  V3Headmate({
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
      };

  factory V3Headmate.fromJson(Map<String, dynamic> json) => V3Headmate(
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
      );

  /// Convert base64 profilePhotoData to Uint8List.
  Uint8List? get avatarImageData =>
      profilePhotoData != null ? base64Decode(profilePhotoData!) : null;
}

// ---------------------------------------------------------------------------
// V3FrontSession
// ---------------------------------------------------------------------------

class V3FrontSession {
  V3FrontSession({
    required this.id,
    required this.startTime,
    this.endTime,
    this.headmateId,
    this.coFronterIds = const [],
    this.notes,
    this.confidence,
    this.pluralkitUuid,
  });

  final String id;
  final String startTime;
  final String? endTime;
  final String? headmateId;
  final List<String> coFronterIds;
  final String? notes;
  final int? confidence;
  final String? pluralkitUuid;

  Map<String, dynamic> toJson() => {
        'id': id,
        'startTime': startTime,
        if (endTime != null) 'endTime': endTime,
        if (headmateId != null) 'headmateId': headmateId,
        if (coFronterIds.isNotEmpty) 'coFronterIds': coFronterIds,
        if (notes != null) 'notes': notes,
        if (confidence != null) 'confidence': confidence,
        if (pluralkitUuid != null) 'pluralkitUuid': pluralkitUuid,
      };

  factory V3FrontSession.fromJson(Map<String, dynamic> json) => V3FrontSession(
        id: json['id'] as String,
        startTime: json['startTime'] as String,
        endTime: json['endTime'] as String?,
        headmateId: json['headmateId'] as String?,
        coFronterIds: (json['coFronterIds'] as List<dynamic>?)
                ?.cast<String>() ??
            [],
        notes: json['notes'] as String?,
        confidence: json['confidence'] as int?,
        pluralkitUuid: json['pluralkitUuid'] as String?,
      );
}

// ---------------------------------------------------------------------------
// V3SleepSession
// ---------------------------------------------------------------------------

class V3SleepSession {
  V3SleepSession({
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

  factory V3SleepSession.fromJson(Map<String, dynamic> json) => V3SleepSession(
        id: json['id'] as String,
        startTime: json['startTime'] as String,
        endTime: json['endTime'] as String?,
        quality: json['quality'] as int? ?? 0,
        notes: json['notes'] as String?,
        isHealthKitImport: json['isHealthKitImport'] as bool? ?? false,
      );
}

// ---------------------------------------------------------------------------
// V3Conversation
// ---------------------------------------------------------------------------

class V3Conversation {
  V3Conversation({
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
        if (archivedByMemberIds != null)
          'archivedByMemberIds': archivedByMemberIds,
        if (mutedByMemberIds != null) 'mutedByMemberIds': mutedByMemberIds,
        if (description != null) 'description': description,
        if (categoryId != null) 'categoryId': categoryId,
        'displayOrder': displayOrder,
      };

  factory V3Conversation.fromJson(Map<String, dynamic> json) =>
      V3Conversation(
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
            (json['lastReadTimestamps'] as Map<String, dynamic>?)
                    ?.map((k, v) => MapEntry(k, v.toString())) ??
                {},
        archivedByMemberIds: json['archivedByMemberIds'] as String?,
        mutedByMemberIds: json['mutedByMemberIds'] as String?,
        description: json['description'] as String?,
        categoryId: json['categoryId'] as String?,
        displayOrder: json['displayOrder'] as int? ?? 0,
      );
}

// ---------------------------------------------------------------------------
// V3Message
// ---------------------------------------------------------------------------

class V3Message {
  V3Message({
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
  final List<V3MessageReaction> reactions;
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

  factory V3Message.fromJson(Map<String, dynamic> json) => V3Message(
        id: json['id'] as String,
        content: json['content'] as String,
        timestamp: json['timestamp'] as String,
        isSystemMessage: json['isSystemMessage'] as bool? ?? false,
        editedAt: json['editedAt'] as String?,
        authorId: json['authorId'] as String?,
        conversationId: json['conversationId'] as String,
        reactions: (json['reactions'] as List<dynamic>?)
                ?.map((e) =>
                    V3MessageReaction.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        replyToId: json['replyToId'] as String?,
        replyToAuthorId: json['replyToAuthorId'] as String?,
        replyToContent: json['replyToContent'] as String?,
      );
}

class V3MessageReaction {
  V3MessageReaction({
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

  factory V3MessageReaction.fromJson(Map<String, dynamic> json) =>
      V3MessageReaction(
        id: json['id'] as String,
        emoji: json['emoji'] as String,
        memberId: json['memberId'] as String,
        timestamp: json['timestamp'] as String,
      );
}

// ---------------------------------------------------------------------------
// V3Poll
// ---------------------------------------------------------------------------

class V3Poll {
  V3Poll({
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

  factory V3Poll.fromJson(Map<String, dynamic> json) => V3Poll(
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
// V3PollOption
// ---------------------------------------------------------------------------

class V3PollOption {
  V3PollOption({
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
  final List<V3PollVote> votes;

  Map<String, dynamic> toJson() => {
        'id': id,
        'pollId': pollId,
        'text': text,
        'sortOrder': sortOrder,
        'isOtherOption': isOtherOption,
        if (colorHex != null) 'colorHex': colorHex,
        if (votes.isNotEmpty) 'votes': votes.map((v) => v.toJson()).toList(),
      };

  factory V3PollOption.fromJson(Map<String, dynamic> json) => V3PollOption(
        id: json['id'] as String,
        pollId: json['pollId'] as String,
        text: json['text'] as String,
        sortOrder: json['sortOrder'] as int? ?? 0,
        isOtherOption: json['isOtherOption'] as bool? ?? false,
        colorHex: json['colorHex'] as String?,
        votes: (json['votes'] as List<dynamic>?)
                ?.map(
                    (e) => V3PollVote.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

class V3PollVote {
  V3PollVote({
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

  factory V3PollVote.fromJson(Map<String, dynamic> json) => V3PollVote(
        id: json['id'] as String,
        memberId: json['memberId'] as String,
        votedAt: json['votedAt'] as String,
        responseText: json['responseText'] as String?,
      );
}

// ---------------------------------------------------------------------------
// V3SystemSettings
// ---------------------------------------------------------------------------

class V3SystemSettings {
  V3SystemSettings({
    this.systemName,
    this.showQuickFront = true,
    this.accentColorHex = '#AF8EE9',
    this.perMemberAccentColors = true,
    this.terminology = 0,
    this.customTerminology,
    this.customPluralTerminology,
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
  final bool showQuickFront;
  final String accentColorHex;
  final bool perMemberAccentColors;
  final int terminology;
  final String? customTerminology;
  final String? customPluralTerminology;
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
        'showQuickFront': showQuickFront,
        'accentColorHex': accentColorHex,
        'perMemberAccentColors': perMemberAccentColors,
        'terminology': terminology,
        if (customTerminology != null) 'customTerminology': customTerminology,
        if (customPluralTerminology != null)
          'customPluralTerminology': customPluralTerminology,
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

  factory V3SystemSettings.fromJson(Map<String, dynamic> json) =>
      V3SystemSettings(
        systemName: json['systemName'] as String?,
        showQuickFront: json['showQuickFront'] as bool? ?? true,
        accentColorHex: json['accentColorHex'] as String? ?? '#AF8EE9',
        perMemberAccentColors:
            json['perMemberAccentColors'] as bool? ?? true,
        terminology: json['terminology'] as int? ?? 0,
        customTerminology: json['customTerminology'] as String?,
        customPluralTerminology:
            json['customPluralTerminology'] as String?,
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
        chatLogsFront: json['chatLogsFront'] as bool? ?? false,
        hasCompletedOnboarding:
            json['hasCompletedOnboarding'] as bool? ?? false,
        syncThemeEnabled: json['syncThemeEnabled'] as bool? ?? false,
        timingMode: json['timingMode'] as int?,
        habitsBadgeEnabled: json['habitsBadgeEnabled'] as bool? ?? true,
        notesEnabled: json['notesEnabled'] as bool? ?? true,
        previousAccentColorHex:
            json['previousAccentColorHex'] as String? ?? '',
        systemDescription: json['systemDescription'] as String?,
        systemAvatarData: json['systemAvatarData'] as String?,
        remindersEnabled: json['remindersEnabled'] as bool? ?? true,
        fontScale: (json['fontScale'] as num?)?.toDouble() ?? 1.0,
        fontFamily: json['fontFamily'] as int? ?? 0,
        pinLockEnabled: json['pinLockEnabled'] as bool? ?? false,
        biometricLockEnabled: json['biometricLockEnabled'] as bool? ?? false,
        autoLockDelaySeconds: json['autoLockDelaySeconds'] as int? ?? 0,
        navBarItems:
            (json['navBarItems'] as List<dynamic>?)?.cast<String>() ?? [],
        navBarOverflowItems:
            (json['navBarOverflowItems'] as List<dynamic>?)?.cast<String>() ??
                [],
        syncNavigationEnabled:
            json['syncNavigationEnabled'] as bool? ?? true,
        chatBadgePreferences:
            (json['chatBadgePreferences'] as Map<String, dynamic>?)
                    ?.map((k, v) => MapEntry(k, v.toString())) ??
                {},
      );
}

// ---------------------------------------------------------------------------
// V3Habit
// ---------------------------------------------------------------------------

class V3Habit {
  V3Habit({
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
        if (notificationMessage != null)
          'notificationMessage': notificationMessage,
        if (assignedMemberId != null) 'assignedMemberId': assignedMemberId,
        'onlyNotifyWhenFronting': onlyNotifyWhenFronting,
        'isPrivate': isPrivate,
        'currentStreak': currentStreak,
        'bestStreak': bestStreak,
        'totalCompletions': totalCompletions,
      };

  factory V3Habit.fromJson(Map<String, dynamic> json) => V3Habit(
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
        notificationsEnabled:
            json['notificationsEnabled'] as bool? ?? false,
        notificationMessage: json['notificationMessage'] as String?,
        assignedMemberId: json['assignedMemberId'] as String?,
        onlyNotifyWhenFronting:
            json['onlyNotifyWhenFronting'] as bool? ?? false,
        isPrivate: json['isPrivate'] as bool? ?? false,
        currentStreak: json['currentStreak'] as int? ?? 0,
        bestStreak: json['bestStreak'] as int? ?? 0,
        totalCompletions: json['totalCompletions'] as int? ?? 0,
      );
}

// ---------------------------------------------------------------------------
// V3HabitCompletion
// ---------------------------------------------------------------------------

class V3HabitCompletion {
  V3HabitCompletion({
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
        if (completedByMemberId != null)
          'completedByMemberId': completedByMemberId,
        if (notes != null) 'notes': notes,
        'wasFronting': wasFronting,
        if (rating != null) 'rating': rating,
        'createdAt': createdAt,
        'modifiedAt': modifiedAt,
      };

  factory V3HabitCompletion.fromJson(Map<String, dynamic> json) =>
      V3HabitCompletion(
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
// V3PluralKitSyncState
// ---------------------------------------------------------------------------

class V3PluralKitSyncState {
  V3PluralKitSyncState({
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
        if (lastManualSyncDate != null)
          'lastManualSyncDate': lastManualSyncDate,
      };

  factory V3PluralKitSyncState.fromJson(Map<String, dynamic> json) =>
      V3PluralKitSyncState(
        systemId: json['systemId'] as String?,
        isConnected: json['isConnected'] as bool? ?? false,
        lastSyncDate: json['lastSyncDate'] as String?,
        lastManualSyncDate: json['lastManualSyncDate'] as String?,
      );
}

// ---------------------------------------------------------------------------
// V3MemberGroup
// ---------------------------------------------------------------------------

class V3MemberGroup {
  V3MemberGroup({
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

  factory V3MemberGroup.fromJson(Map<String, dynamic> json) => V3MemberGroup(
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
// V3MemberGroupEntry
// ---------------------------------------------------------------------------

class V3MemberGroupEntry {
  V3MemberGroupEntry({
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

  factory V3MemberGroupEntry.fromJson(Map<String, dynamic> json) =>
      V3MemberGroupEntry(
        id: json['id'] as String,
        groupId: json['groupId'] as String,
        memberId: json['memberId'] as String,
      );
}

// ---------------------------------------------------------------------------
// V3CustomField
// ---------------------------------------------------------------------------

class V3CustomField {
  V3CustomField({
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

  factory V3CustomField.fromJson(Map<String, dynamic> json) => V3CustomField(
        id: json['id'] as String,
        name: json['name'] as String,
        fieldType: json['fieldType'] as int,
        datePrecision: json['datePrecision'] as int?,
        displayOrder: json['displayOrder'] as int? ?? 0,
        createdAt: json['createdAt'] as String,
      );
}

// ---------------------------------------------------------------------------
// V3CustomFieldValue
// ---------------------------------------------------------------------------

class V3CustomFieldValue {
  V3CustomFieldValue({
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

  factory V3CustomFieldValue.fromJson(Map<String, dynamic> json) =>
      V3CustomFieldValue(
        id: json['id'] as String,
        customFieldId: json['customFieldId'] as String,
        memberId: json['memberId'] as String,
        value: json['value'] as String,
      );
}

// ---------------------------------------------------------------------------
// V3Note
// ---------------------------------------------------------------------------

class V3Note {
  V3Note({
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

  factory V3Note.fromJson(Map<String, dynamic> json) => V3Note(
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
// V3FrontSessionComment
// ---------------------------------------------------------------------------

class V3FrontSessionComment {
  V3FrontSessionComment({
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

  factory V3FrontSessionComment.fromJson(Map<String, dynamic> json) =>
      V3FrontSessionComment(
        id: json['id'] as String,
        sessionId: json['sessionId'] as String,
        body: json['body'] as String,
        timestamp: json['timestamp'] as String,
        createdAt: json['createdAt'] as String,
      );
}

// ---------------------------------------------------------------------------
// V3ConversationCategory
// ---------------------------------------------------------------------------

class V3ConversationCategory {
  V3ConversationCategory({
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

  factory V3ConversationCategory.fromJson(Map<String, dynamic> json) =>
      V3ConversationCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        displayOrder: json['displayOrder'] as int? ?? 0,
        createdAt: json['createdAt'] as String,
        modifiedAt: json['modifiedAt'] as String,
      );
}

// ---------------------------------------------------------------------------
// V3Reminder
// ---------------------------------------------------------------------------

class V3Reminder {
  V3Reminder({
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

  factory V3Reminder.fromJson(Map<String, dynamic> json) => V3Reminder(
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
// V3Friend
// ---------------------------------------------------------------------------

class V3Friend {
  V3Friend({
    required this.id,
    required this.displayName,
    required this.publicKeyHex,
    this.sharedSecretHex,
    this.grantedScopes = const [],
    this.isVerified = false,
    required this.createdAt,
    this.lastSyncAt,
  });

  final String id;
  final String displayName;
  final String publicKeyHex;
  final String? sharedSecretHex;
  final List<String> grantedScopes;
  final bool isVerified;
  final String createdAt;
  final String? lastSyncAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'publicKeyHex': publicKeyHex,
        if (sharedSecretHex != null) 'sharedSecretHex': sharedSecretHex,
        if (grantedScopes.isNotEmpty) 'grantedScopes': grantedScopes,
        'isVerified': isVerified,
        'createdAt': createdAt,
        if (lastSyncAt != null) 'lastSyncAt': lastSyncAt,
      };

  factory V3Friend.fromJson(Map<String, dynamic> json) => V3Friend(
        id: json['id'] as String,
        displayName: json['displayName'] as String,
        publicKeyHex: json['publicKeyHex'] as String,
        sharedSecretHex: json['sharedSecretHex'] as String?,
        grantedScopes:
            (json['grantedScopes'] as List<dynamic>?)?.cast<String>() ?? [],
        isVerified: json['isVerified'] as bool? ?? false,
        createdAt: json['createdAt'] as String,
        lastSyncAt: json['lastSyncAt'] as String?,
      );
}
