import 'dart:convert';
import 'dart:typed_data';

const String v1ConversationTypeGroup = 'group';
const String v1ConversationTypeDirectMessage = 'directmessage';

bool isV1ConversationDirectMessage({
  String? type,
  bool isDirectMessage = false,
  String? title,
  String? emoji,
  String? categoryId,
  required List<String> participantIds,
}) {
  final normalizedType = type?.trim().toLowerCase();
  if (normalizedType == v1ConversationTypeDirectMessage) return true;
  if (normalizedType == v1ConversationTypeGroup) return false;
  if (isDirectMessage) return true;

  final hasBlankTitle = title == null || title.trim().isEmpty;
  return hasBlankTitle &&
      emoji == null &&
      categoryId == null &&
      participantIds.length == 2;
}

String v1ConversationTypeForData({
  String? type,
  bool isDirectMessage = false,
  String? title,
  String? emoji,
  String? categoryId,
  required List<String> participantIds,
}) =>
    isV1ConversationDirectMessage(
      type: type,
      isDirectMessage: isDirectMessage,
      title: title,
      emoji: emoji,
      categoryId: categoryId,
      participantIds: participantIds,
    )
    ? v1ConversationTypeDirectMessage
    : v1ConversationTypeGroup;

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
    this.memberBoardPosts = const [],
    this.appPreferences = const [],
    this.rescueLegacyFields = false,
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
  final List<V1MemberBoardPost> memberBoardPosts;

  /// Synced app key-value preferences (`app_preference_values` rows) — the
  /// registry-backed prefs that don't have dedicated `system_settings` columns,
  /// e.g. accessibility toggles and the nav-bar expanded-label style.
  final List<V1AppPreference> appPreferences;

  /// Envelope-level marker for the PRISM1 rescue importer (§4.7).
  ///
  /// Set to `true` by `DataExportService.buildExport` when its
  /// `includeLegacyFields == true` (i.e., the migration-time export that
  /// is meant to be self-sufficient as a rescue input). When the flag is
  /// present in a parsed envelope, `DataImportService` routes EVERY
  /// session and comment row through the legacy/rescue path regardless
  /// of the per-row legacy-key sniff.
  ///
  /// Why an envelope flag instead of relying on per-row keys: the real
  /// exporter omits empty / null legacy keys (`coFronterIds: []`,
  /// `pkMemberIdsJson: null`), so a backup row with nothing fronting
  /// alongside it carried no per-row marker at all. Empty native
  /// single-member rows and orphan rows (member_id null) both bypassed
  /// the rescue path entirely; orphans then imported with `memberId =
  /// null` instead of being assigned to the Unknown sentinel — and the
  /// schema cleanup CHECK constraint rejects those rows.
  ///
  /// Per-row sniff stays as a fallback for genuinely-old PRISM1 files
  /// that pre-date this marker.
  final bool rescueLegacyFields;

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
    if (memberBoardPosts.isNotEmpty)
      'memberBoardPosts': memberBoardPosts.map((e) => e.toJson()).toList(),
    if (appPreferences.isNotEmpty)
      'appPreferences': appPreferences.map((e) => e.toJson()).toList(),
    // Envelope-level rescue marker (§4.7). Only emitted when true so
    // post-migration exports stay byte-identical to pre-marker files.
    if (rescueLegacyFields) 'rescueLegacyFields': true,
  };

  /// Format versions this codebase knows how to parse.
  ///
  /// Mirrors `DataImportService.supportedVersions` — the import service
  /// also rejects unsupported versions before invoking parsing — but the
  /// envelope-level reject here gives a tighter contract: any caller
  /// touching `V1Export.fromJson` (preview parsers, tests, future
  /// tools) gets the same gate. Review finding #39 + remediation plan
  /// WS4 step 7 explicitly require envelope-level rejection so an
  /// unknown future formatVersion can't accidentally route through the
  /// per-row legacy sniff and produce mis-rescued rows.
  static const _supportedFormatVersions = {'1.0', '2025.1'};

  factory V1Export.fromJson(Map<String, dynamic> json) {
    // Envelope `formatVersion` is the primary shape gate (review
    // finding #39 + remediation plan WS4 step 7). Reject unknown
    // versions explicitly before any per-row parsing runs so a future
    // PRISM1 v3+ shape with renamed fields can't be silently
    // misclassified as legacy and routed through the rescue path with
    // every field null. Per-row shape inference stays as a fallback
    // for legitimately-old files that pre-date the
    // `rescueLegacyFields` envelope marker (introduced alongside the
    // 0.7.0 migration-time exporter).
    final rawFormatVersion = json['formatVersion'] as String?;
    final formatVersion = rawFormatVersion ?? '1.0';
    if (rawFormatVersion != null &&
        !_supportedFormatVersions.contains(rawFormatVersion)) {
      throw FormatException(
        'Unsupported export formatVersion: $rawFormatVersion. '
        'Supported versions: ${_supportedFormatVersions.join(', ')}',
      );
    }
    // Read the envelope marker first so it can be threaded into the
    // session / comment fromJson factories. When set, every session /
    // comment row is forced through the legacy/rescue path regardless
    // of the per-row sniff.
    final rescueLegacy = json['rescueLegacyFields'] as bool? ?? false;
    return V1Export(
      formatVersion: formatVersion,
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
              ?.map(
                (e) => V1FrontSession.fromJson(
                  e as Map<String, dynamic>,
                  forceLegacyShape: rescueLegacy,
                ),
              )
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
              ?.map(
                (e) => V1HabitCompletion.fromJson(e as Map<String, dynamic>),
              )
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
              ?.map(
                (e) => V1MemberGroupEntry.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
      customFields:
          (json['customFields'] as List<dynamic>?)
              ?.map((e) => V1CustomField.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      customFieldValues:
          (json['customFieldValues'] as List<dynamic>?)
              ?.map(
                (e) => V1CustomFieldValue.fromJson(e as Map<String, dynamic>),
              )
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
                (e) => V1FrontSessionComment.fromJson(
                  e as Map<String, dynamic>,
                  forceLegacyShape: rescueLegacy,
                ),
              )
              .toList() ??
          [],
      conversationCategories:
          (json['conversationCategories'] as List<dynamic>?)
              ?.map(
                (e) =>
                    V1ConversationCategory.fromJson(e as Map<String, dynamic>),
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
      memberBoardPosts:
          (json['memberBoardPosts'] as List<dynamic>?)
              ?.map(
                (e) => V1MemberBoardPost.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
      appPreferences:
          (json['appPreferences'] as List<dynamic>?)
              ?.map((e) => V1AppPreference.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      rescueLegacyFields: rescueLegacy,
    );
  }
}

// ---------------------------------------------------------------------------
// V1AppPreference — one `app_preference_values` row (key + codec-encoded value)
// ---------------------------------------------------------------------------

class V1AppPreference {
  V1AppPreference({
    required this.key,
    required this.valueType,
    this.valueJson,
  });

  final String key;
  final String valueType;
  final String? valueJson;

  Map<String, dynamic> toJson() => {
    'key': key,
    'valueType': valueType,
    if (valueJson != null) 'valueJson': valueJson,
  };

  factory V1AppPreference.fromJson(Map<String, dynamic> json) =>
      V1AppPreference(
        key: json['key'] as String,
        valueType: json['valueType'] as String,
        valueJson: json['valueJson'] as String?,
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
    this.pkAvatarCachedUrl,
    this.isActive = true,
    required this.createdAt,
    this.displayOrder = 0,
    this.isAdmin = false,
    this.customColorEnabled = false,
    this.customColorHex,
    this.parentSystemId,
    this.pluralkitUuid,
    this.pluralkitId,
    this.pluralkitDisplayName,
    this.markdownEnabled = true,
    this.displayName,
    this.birthday,
    this.proxyTagsJson,
    this.pkBannerUrl,
    this.profileHeaderSource,
    this.profileHeaderLayout,
    this.profileHeaderVisible,
    this.nameStyleFont,
    this.nameStyleBold,
    this.nameStyleItalic,
    this.nameStyleColorMode,
    this.nameStyleColorHex,
    this.profileHeaderImageData,
    this.pkBannerImageData,
    this.pkBannerCachedUrl,
    this.pluralkitSyncIgnored = false,
    this.isAlwaysFronting = false,
    this.boardLastReadAt,
  });

  final String id;
  final String name;
  final String? pronouns;
  final String? emoji;
  final String? age;
  final String? notes;
  final String? profilePhotoData; // base64
  final String? pkAvatarCachedUrl;
  final bool isActive;
  final String createdAt;
  final int displayOrder;
  final bool isAdmin;
  final bool customColorEnabled;
  final String? customColorHex;
  final String? parentSystemId;
  final String? pluralkitUuid;
  final String? pluralkitId;
  final String? pluralkitDisplayName;
  final bool markdownEnabled;
  // Additive member metadata; older exports default to null/false.
  final String? displayName;
  final String? birthday;
  final String? proxyTagsJson;
  final String? pkBannerUrl;
  final int? profileHeaderSource;
  final int? profileHeaderLayout;
  final bool? profileHeaderVisible;
  final int? nameStyleFont;
  final bool? nameStyleBold;
  final bool? nameStyleItalic;
  final int? nameStyleColorMode;
  final String? nameStyleColorHex;
  final String? profileHeaderImageData; // base64
  final String? pkBannerImageData; // base64
  final String? pkBannerCachedUrl;
  final bool pluralkitSyncIgnored;
  final bool isAlwaysFronting;
  final String? boardLastReadAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (pronouns != null) 'pronouns': pronouns,
    if (emoji != null) 'emoji': emoji,
    if (age != null) 'age': age,
    if (notes != null) 'notes': notes,
    if (profilePhotoData != null) 'profilePhotoData': profilePhotoData,
    if (pkAvatarCachedUrl != null) 'pkAvatarCachedUrl': pkAvatarCachedUrl,
    'isActive': isActive,
    'createdAt': createdAt,
    'displayOrder': displayOrder,
    'isAdmin': isAdmin,
    'customColorEnabled': customColorEnabled,
    if (customColorHex != null) 'customColorHex': customColorHex,
    if (parentSystemId != null) 'parentSystemId': parentSystemId,
    if (pluralkitUuid != null) 'pluralkitUuid': pluralkitUuid,
    if (pluralkitId != null) 'pluralkitId': pluralkitId,
    if (pluralkitDisplayName != null)
      'pluralkitDisplayName': pluralkitDisplayName,
    'markdownEnabled': markdownEnabled,
    if (displayName != null) 'displayName': displayName,
    if (birthday != null) 'birthday': birthday,
    if (proxyTagsJson != null) 'proxyTagsJson': proxyTagsJson,
    if (pkBannerUrl != null) 'pkBannerUrl': pkBannerUrl,
    if (profileHeaderSource != null) 'profileHeaderSource': profileHeaderSource,
    if (profileHeaderLayout != null) 'profileHeaderLayout': profileHeaderLayout,
    if (profileHeaderVisible != null)
      'profileHeaderVisible': profileHeaderVisible,
    if (nameStyleFont != null) 'nameStyleFont': nameStyleFont,
    if (nameStyleBold != null) 'nameStyleBold': nameStyleBold,
    if (nameStyleItalic != null) 'nameStyleItalic': nameStyleItalic,
    if (nameStyleColorMode != null) 'nameStyleColorMode': nameStyleColorMode,
    if (nameStyleColorHex != null) 'nameStyleColorHex': nameStyleColorHex,
    if (profileHeaderImageData != null)
      'profileHeaderImageData': profileHeaderImageData,
    if (pkBannerImageData != null) 'pkBannerImageData': pkBannerImageData,
    if (pkBannerCachedUrl != null) 'pkBannerCachedUrl': pkBannerCachedUrl,
    'pluralkitSyncIgnored': pluralkitSyncIgnored,
    if (isAlwaysFronting) 'isAlwaysFronting': isAlwaysFronting,
    if (boardLastReadAt != null) 'boardLastReadAt': boardLastReadAt,
  };

  factory V1Headmate.fromJson(Map<String, dynamic> json) => V1Headmate(
    id: json['id'] as String,
    name: json['name'] as String,
    pronouns: json['pronouns'] as String?,
    emoji: json['emoji'] as String?,
    age: (json['age'])?.toString(),
    notes: json['notes'] as String?,
    profilePhotoData: json['profilePhotoData'] as String?,
    pkAvatarCachedUrl: json['pkAvatarCachedUrl'] as String?,
    isActive: json['isActive'] as bool? ?? true,
    createdAt: json['createdAt'] as String,
    displayOrder: json['displayOrder'] as int? ?? 0,
    isAdmin: json['isAdmin'] as bool? ?? false,
    customColorEnabled: json['customColorEnabled'] as bool? ?? false,
    customColorHex: json['customColorHex'] as String?,
    parentSystemId: json['parentSystemId'] as String?,
    pluralkitUuid: json['pluralkitUuid'] as String?,
    pluralkitId: json['pluralkitId'] as String?,
    pluralkitDisplayName: json['pluralkitDisplayName'] as String?,
    markdownEnabled: json['markdownEnabled'] as bool? ?? true,
    displayName: json['displayName'] as String?,
    birthday: json['birthday'] as String?,
    proxyTagsJson: json['proxyTagsJson'] as String?,
    pkBannerUrl: json['pkBannerUrl'] as String?,
    profileHeaderSource: json['profileHeaderSource'] as int?,
    profileHeaderLayout: json['profileHeaderLayout'] as int?,
    profileHeaderVisible: json['profileHeaderVisible'] as bool?,
    nameStyleFont: json['nameStyleFont'] as int?,
    nameStyleBold: json['nameStyleBold'] as bool?,
    nameStyleItalic: json['nameStyleItalic'] as bool?,
    nameStyleColorMode: json['nameStyleColorMode'] as int?,
    nameStyleColorHex: json['nameStyleColorHex'] as String?,
    profileHeaderImageData: json['profileHeaderImageData'] as String?,
    pkBannerImageData: json['pkBannerImageData'] as String?,
    pkBannerCachedUrl: json['pkBannerCachedUrl'] as String?,
    pluralkitSyncIgnored: json['pluralkitSyncIgnored'] as bool? ?? false,
    isAlwaysFronting: json['isAlwaysFronting'] as bool? ?? false,
    boardLastReadAt: json['boardLastReadAt'] as String?,
  );

  /// Convert base64 profilePhotoData to Uint8List.
  Uint8List? get avatarImageData =>
      profilePhotoData != null ? base64Decode(profilePhotoData!) : null;

  /// Convert base64 profileHeaderImageData to Uint8List.
  Uint8List? get profileHeaderImageBytes => profileHeaderImageData != null
      ? base64Decode(profileHeaderImageData!)
      : null;

  /// Convert base64 pkBannerImageData to Uint8List.
  Uint8List? get pkBannerImageBytes =>
      pkBannerImageData != null ? base64Decode(pkBannerImageData!) : null;
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
    this.pkImportSource,
    this.pkFileSwitchId,
    this.pkMemberIdsJson,
    this.sessionType,
    this.quality,
    this.isHealthKitImport,
    this.coFronterIdsRawJson,
    this.isLegacyShape = false,
  });

  /// Process-wide counter for the per-row legacy-shape fallback.
  ///
  /// Incremented whenever `V1FrontSession.fromJson` flips a row to
  /// legacy via row-shape sniff WITHOUT the envelope-level
  /// `rescueLegacyFields` flag being set. The envelope flag is the
  /// primary classifier (review finding #39 + remediation plan WS4
  /// step 7); the per-row sniff is the back-compat fallback for
  /// pre-marker (pre-0.7.0) files. A non-zero count after a successful
  /// import indicates the fallback was actually exercised — surface it
  /// in tests and (eventually) in import-result diagnostics so the
  /// fallback's removal can be justified once it stops firing in the
  /// wild. Tests should reset via [resetRowShapeLegacyFallbackCount]
  /// in setUp/tearDown to avoid cross-test bleed.
  static int _rowShapeLegacyFallbackCount = 0;
  static int get rowShapeLegacyFallbackCount => _rowShapeLegacyFallbackCount;
  static void resetRowShapeLegacyFallbackCount() {
    _rowShapeLegacyFallbackCount = 0;
  }

  final String id;
  final String startTime;
  final String? endTime;
  // Legacy-shape primary fronter id. Equivalent to memberId in new-shape
  // exports; preserved as `headmateId` in legacy exports for backward
  // compatibility with PRISM1 v6/v7 files. New-shape exports populate this
  // via the same field name (memberId) — both `memberId` and `headmateId`
  // keys are accepted on read.
  final String? headmateId;
  // Legacy-shape co-fronter list (always empty for SP/HealthKit/single-member
  // native rows; populated for multi-member native rows). Retained on the
  // model for the PRISM1 rescue importer (§4.7).
  final List<String> coFronterIds;
  final String? notes;
  final int? confidence;
  final String? pluralkitUuid;
  final String? pkImportSource;
  final String? pkFileSwitchId;
  // Legacy-shape: JSON-encoded list of PK member UUIDs for this switch.
  // Retained in v7-era PRISM1 exports for the rescue importer (§4.7); the
  // runtime column is unread from 0.7.0 onwards.
  final String? pkMemberIdsJson;

  // -- New-shape fields (per-member fronting refactor §4.1) ------------
  //
  // `sessionType`: 0 = normal fronting, 1 = sleep / HealthKit. Only present
  // in post-0.7.0 exports; legacy exports infer normal-vs-sleep from being
  // in the `frontSessions` vs `sleepSessions` array.
  final int? sessionType;
  // `quality`: SleepQuality enum index for sleep rows. New-shape only;
  // legacy sleep rows live in `sleepSessions` and use that schema.
  final int? quality;
  // `isHealthKitImport`: marker for HealthKit-imported sleep rows. New-shape
  // only; legacy sleep rows use the same field on V1SleepSession.
  final bool? isHealthKitImport;

  // -- Rescue-importer support fields (not serialized) ----------------
  //
  // The raw JSON of `coFronterIds` as it appeared in the source file, kept
  // verbatim so the rescue importer can detect corrupt JSON (per §6 edge
  // cases). When the source value parses cleanly to a list of strings, this
  // mirrors `coFronterIds`; when it's malformed the `coFronterIds` field
  // falls back to empty and this carries the original raw value for logging.
  final String? coFronterIdsRawJson;

  // Per-row sniff result from `fromJson`: true when this row carries any
  // legacy-shape marker (`coFronterIds`, `pkMemberIdsJson`, `headmateId`)
  // and not the new-shape `memberId` / `sessionType` keys. The rescue
  // importer routes legacy-shape rows through the §4.7 conversion logic;
  // new-shape rows go through the standard import path.
  final bool isLegacyShape;

  Map<String, dynamic> toJson() => {
    'id': id,
    'startTime': startTime,
    if (endTime != null) 'endTime': endTime,
    if (headmateId != null) 'headmateId': headmateId,
    if (coFronterIds.isNotEmpty) 'coFronterIds': coFronterIds,
    if (notes != null) 'notes': notes,
    if (confidence != null) 'confidence': confidence,
    if (pluralkitUuid != null) 'pluralkitUuid': pluralkitUuid,
    if (pkImportSource != null) 'pkImportSource': pkImportSource,
    if (pkFileSwitchId != null) 'pkFileSwitchId': pkFileSwitchId,
    if (pkMemberIdsJson != null) 'pkMemberIdsJson': pkMemberIdsJson,
    if (sessionType != null) 'sessionType': sessionType,
    if (quality != null) 'quality': quality,
    if (isHealthKitImport != null) 'isHealthKitImport': isHealthKitImport,
  };

  factory V1FrontSession.fromJson(
    Map<String, dynamic> json, {
    bool forceLegacyShape = false,
  }) {
    // Envelope-level marker takes precedence: when the parent V1Export
    // carries `rescueLegacyFields: true` (set by the migration-time
    // exporter), every row routes through the rescue path regardless
    // of which legacy keys this particular row happens to carry. This
    // is load-bearing: the real exporter omits empty / null legacy
    // keys, so a backup row with `co_fronter_ids = []` and
    // `pk_member_ids_json = NULL` (i.e., every native single-member
    // row, plus orphan rows) carries no per-row marker at all and
    // would otherwise bypass the rescue importer entirely.
    //
    // Per-row legacy-shape sniff: any legacy-only key present routes
    // the row through the rescue path regardless of new-shape markers.
    // The migration-time PRISM1 export emits BOTH legacy fields AND
    // `sessionType` for the same row (it's a self-sufficient rescue
    // bundle), so an AND-NOT detection would silently route those
    // rows through the new-shape importer and drop the PK / native
    // fan-out.
    //
    // The two unambiguously legacy-only keys are `coFronterIds` and
    // `pkMemberIdsJson`. `headmateId` does NOT count: the new-shape
    // exporter still emits it as the canonical member-id key in the
    // V1 envelope (the freezed model field is named `headmateId` for
    // historical reasons), and the new-shape importer accepts either
    // `memberId` or `headmateId` as the local member id. Treating
    // `headmateId` as a legacy marker would force every new-shape PK
    // row through the rescue path on re-import.
    //
    // Real pre-0.7 PRISM1 exports omit empty / null legacy keys exactly
    // like new-shape exports do, so the explicit-key sniff ALONE leaks
    // two row shapes through to the new-shape path:
    //   1. Solo PK rows (pluralkitUuid set, headmateId set, no
    //      coFronterIds, no pkMemberIdsJson) — would skip the PK
    //      deterministic-id derivation and land at the legacy random
    //      v4 id, breaking the (switch, member) collision contract on
    //      future API re-import.
    //   2. Orphan native rows (no headmateId, no coFronterIds) —
    //      would land with member_id NULL, which v8's CHECK constraint
    //      rejects.
    //
    // Broaden detection so any row that could plausibly be from a
    // pre-0.7 file routes to legacy. The new-shape carve-out is the
    // presence of `sessionType` (or `memberId`): pre-0.7 exports never
    // emit either key. Sleep rows in pre-0.7 files lived in
    // `sleepSessions`, never in `frontSessions`, so the legacy
    // importer's normal-only assumption is safe.
    final hasLegacyKeys =
        json.containsKey('coFronterIds') || json.containsKey('pkMemberIdsJson');
    final hasNewShapeMarker =
        json.containsKey('sessionType') || json.containsKey('memberId');
    final hasHeadmateId = json.containsKey('headmateId');
    final hasPluralkitUuid = json.containsKey('pluralkitUuid');
    final rowShapeLegacy =
        hasLegacyKeys ||
        (hasPluralkitUuid && !hasNewShapeMarker) ||
        (!hasHeadmateId &&
            !json.containsKey('coFronterIds') &&
            !hasNewShapeMarker);
    final isLegacy = forceLegacyShape || rowShapeLegacy;
    // Diagnostic counter for review finding #39 + remediation plan WS4
    // step 7: log every time the per-row sniff (rather than the
    // envelope `rescueLegacyFields` flag) is what flipped a row to
    // legacy. Production migration-time exports always set the
    // envelope flag, so a non-zero count here means we hit a real
    // pre-marker file in the wild — useful evidence for keeping (or
    // eventually removing) the row-shape fallback.
    if (!forceLegacyShape && rowShapeLegacy) {
      _rowShapeLegacyFallbackCount++;
    }

    // Tolerate a malformed `coFronterIds` value (per §6 edge cases — if
    // expansion fails to parse, fall back to single-member migration).
    // The raw value is preserved for logging by the rescue importer.
    final rawCo = json['coFronterIds'];
    String? rawCoJson;
    List<String> coIds;
    if (rawCo == null) {
      coIds = const [];
    } else if (rawCo is List) {
      try {
        coIds = rawCo.cast<String>();
      } catch (_) {
        coIds = const [];
        rawCoJson = jsonEncode(rawCo);
      }
    } else if (rawCo is String) {
      // Some exports may have stringified the array — try to parse, fall
      // back to empty.
      rawCoJson = rawCo;
      try {
        final parsed = jsonDecode(rawCo);
        coIds = parsed is List ? parsed.cast<String>() : const <String>[];
      } catch (_) {
        coIds = const [];
      }
    } else {
      coIds = const [];
      rawCoJson = rawCo.toString();
    }

    return V1FrontSession(
      id: json['id'] as String,
      startTime: json['startTime'] as String,
      endTime: json['endTime'] as String?,
      // Accept either key — new-shape exports use `memberId`, legacy use
      // `headmateId`. Stored on the same field.
      headmateId: json['memberId'] as String? ?? json['headmateId'] as String?,
      coFronterIds: coIds,
      coFronterIdsRawJson: rawCoJson,
      notes: json['notes'] as String?,
      confidence: json['confidence'] as int?,
      pluralkitUuid: json['pluralkitUuid'] as String?,
      pkImportSource: json['pkImportSource'] as String?,
      pkFileSwitchId: json['pkFileSwitchId'] as String?,
      pkMemberIdsJson: json['pkMemberIdsJson'] as String?,
      sessionType: json['sessionType'] as int?,
      quality: json['quality'] as int?,
      isHealthKitImport: json['isHealthKitImport'] as bool?,
      isLegacyShape: isLegacy,
    );
  }
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
    this.includesAllMembers = false,
    this.archivedForEveryone = false,
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
  final bool includesAllMembers;
  final bool archivedForEveryone;
  final Map<String, String> lastReadTimestamps;
  final String? archivedByMemberIds; // JSON-encoded string list
  final String? mutedByMemberIds; // JSON-encoded string list
  final String? description;
  final String? categoryId;
  final int displayOrder;
  String get type => v1ConversationTypeForData(
    isDirectMessage: isDirectMessage,
    title: title,
    emoji: emoji,
    categoryId: categoryId,
    participantIds: participantIds,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt,
    'lastActivityAt': lastActivityAt,
    if (title != null) 'title': title,
    if (emoji != null) 'emoji': emoji,
    'type': type,
    'isDirectMessage': isV1ConversationDirectMessage(
      isDirectMessage: isDirectMessage,
      title: title,
      emoji: emoji,
      categoryId: categoryId,
      participantIds: participantIds,
    ),
    if (creatorId != null) 'creatorId': creatorId,
    'participantIds': participantIds,
    'includesAllMembers': includesAllMembers,
    'archivedForEveryone': archivedForEveryone,
    'lastReadTimestamps': lastReadTimestamps,
    if (archivedByMemberIds != null) 'archivedByMemberIds': archivedByMemberIds,
    if (mutedByMemberIds != null) 'mutedByMemberIds': mutedByMemberIds,
    if (description != null) 'description': description,
    if (categoryId != null) 'categoryId': categoryId,
    'displayOrder': displayOrder,
  };

  factory V1Conversation.fromJson(Map<String, dynamic> json) {
    final title = json['title'] as String?;
    final emoji = json['emoji'] as String?;
    final categoryId = json['categoryId'] as String?;
    final participantIds =
        (json['participantIds'] as List<dynamic>?)?.cast<String>() ?? [];

    return V1Conversation(
      id: json['id'] as String,
      createdAt: json['createdAt'] as String,
      lastActivityAt: json['lastActivityAt'] as String,
      title: title,
      emoji: emoji,
      isDirectMessage: isV1ConversationDirectMessage(
        type: json['type'] as String?,
        isDirectMessage: json['isDirectMessage'] as bool? ?? false,
        title: title,
        emoji: emoji,
        categoryId: categoryId,
        participantIds: participantIds,
      ),
      creatorId: json['creatorId'] as String?,
      participantIds: participantIds,
      includesAllMembers: json['includesAllMembers'] as bool? ?? false,
      archivedForEveryone: json['archivedForEveryone'] as bool? ?? false,
      lastReadTimestamps:
          (json['lastReadTimestamps'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, v.toString()),
          ) ??
          {},
      archivedByMemberIds: json['archivedByMemberIds'] as String?,
      mutedByMemberIds: json['mutedByMemberIds'] as String?,
      description: json['description'] as String?,
      categoryId: categoryId,
      displayOrder: json['displayOrder'] as int? ?? 0,
    );
  }
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
    this.accentColorHex = '#9070A0',
    this.perMemberAccentColors = true,
    this.terminology = 0,
    this.memberNameDisplay = 0,
    this.customTerminology,
    this.customPluralTerminology,
    this.terminologyUseEnglish = false,
    this.frontingRemindersEnabled = false,
    this.frontingReminderIntervalMinutes = 60,
    this.themeMode = 0,
    this.themeBrightness = 0,
    this.themeStyle = 0,
    this.themeCornerStyle = 0,
    this.paletteSource = 1,
    this.paletteSeedColorHex = '#9070A0',
    this.paletteMood = 0,
    this.paletteContrast = 1,
    this.chatEnabled = true,
    this.pollsEnabled = true,
    this.habitsEnabled = true,
    this.sleepTrackingEnabled = true,
    this.gifSearchEnabled = true,
    this.voiceNotesEnabled = true,
    this.sleepSuggestionEnabled = false,
    this.sleepSuggestionHour = 22,
    this.sleepSuggestionMinute = 0,
    this.wakeSuggestionEnabled = false,
    this.wakeSuggestionAfterHours = 8.0,
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
    this.systemColor,
    this.pkGroupSyncV2Enabled = false,
    this.systemTag,
    this.systemAvatarData, // base64
    this.remindersEnabled = true,
    this.localeOverride,
    this.gifConsentState = 0,
    this.fontScale = 1.0,
    this.fontFamily = 0,
    this.pinLockEnabled = false,
    this.biometricLockEnabled = false,
    this.autoLockDelaySeconds = 0,
    this.displayFontInAppBar = true,
    this.navBarItems = const [],
    this.navBarOverflowItems = const [],
    this.navBarLabelDisplayMode = 0,
    this.navBarRevealLabelsWhenExpanded = true,
    this.syncNavigationEnabled = true,
    this.chatBadgePreferences = const {},
    this.defaultSleepQuality,
    this.frontingListViewMode = 0,
    this.addFrontDefaultBehavior = 0,
    this.quickFrontDefaultBehavior = 0,
    this.autoPromoteLongFrontingSessions = true,
    this.boardsEnabled = false,
    this.spBoardsBackfilledAt,
    this.membersListViewMode = 0,
    this.membersGroupedDefaultState = 0,
    this.membersFolderMemberVisibility = 0,
    this.membersShowPronouns = true,
    this.membersShowFrontButtons = false,
    this.membersShowGroups = true,
    this.membersFrontButtonBehavior = 0,
    this.bioMarkdownEnabled = true,
    this.hasPaletteSource = true,
    this.hasPaletteSeedColorHex = true,
    this.hasPaletteMood = true,
    this.hasPaletteContrast = true,
    this.hasBioMarkdownEnabled = true,
  });

  final String? systemName;
  final String? sharingId;
  final bool showQuickFront;
  final String accentColorHex;
  final bool perMemberAccentColors;
  final int terminology;
  final int memberNameDisplay; // MemberNameDisplay enum index
  final String? customTerminology;
  final String? customPluralTerminology;
  final bool terminologyUseEnglish;
  final bool frontingRemindersEnabled;
  final int frontingReminderIntervalMinutes;
  final int themeMode;
  final int themeBrightness; // ThemeBrightness enum index
  final int themeStyle; // ThemeStyle enum index
  final int themeCornerStyle; // CornerStyle enum index
  final int paletteSource; // PaletteSource enum index
  final String paletteSeedColorHex;
  final int paletteMood; // PaletteMood enum index
  final int paletteContrast; // PaletteContrast enum index
  final bool chatEnabled;
  final bool pollsEnabled;
  final bool habitsEnabled;
  final bool sleepTrackingEnabled;
  final bool gifSearchEnabled;
  final bool voiceNotesEnabled;
  final bool sleepSuggestionEnabled;
  final int sleepSuggestionHour;
  final int sleepSuggestionMinute;
  final bool wakeSuggestionEnabled;
  final double wakeSuggestionAfterHours;
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
  final String? systemColor;
  final bool pkGroupSyncV2Enabled;
  final String? systemTag;
  final String? systemAvatarData; // base64
  final bool remindersEnabled;
  final String? localeOverride;
  final int gifConsentState; // GifConsentState enum index
  final double fontScale;
  final int fontFamily; // FontFamily enum index
  final bool pinLockEnabled;
  final bool biometricLockEnabled;
  final int autoLockDelaySeconds;
  final bool displayFontInAppBar;
  final List<String> navBarItems;
  final List<String> navBarOverflowItems;
  final int navBarLabelDisplayMode; // NavBarLabelDisplayMode enum index
  final bool navBarRevealLabelsWhenExpanded;
  final bool syncNavigationEnabled;
  final Map<String, String> chatBadgePreferences;
  final int? defaultSleepQuality; // SleepQuality enum index
  final int frontingListViewMode; // FrontingListViewMode enum index
  final int addFrontDefaultBehavior; // FrontStartBehavior enum index
  final int quickFrontDefaultBehavior; // FrontStartBehavior enum index
  final bool autoPromoteLongFrontingSessions;
  final bool boardsEnabled;
  final String? spBoardsBackfilledAt;
  final int membersListViewMode; // MembersListViewMode enum index
  final int membersGroupedDefaultState; // MembersGroupedDefaultState enum index
  final int
  membersFolderMemberVisibility; // MembersFolderMemberVisibility index
  final bool membersShowPronouns;
  final bool membersShowFrontButtons;
  final bool membersShowGroups;
  final int membersFrontButtonBehavior; // FrontStartBehavior enum index
  final bool bioMarkdownEnabled;
  final bool hasPaletteSource;
  final bool hasPaletteSeedColorHex;
  final bool hasPaletteMood;
  final bool hasPaletteContrast;
  final bool hasBioMarkdownEnabled;

  Map<String, dynamic> toJson() => {
    if (systemName != null) 'systemName': systemName,
    if (sharingId != null) 'sharingId': sharingId,
    'showQuickFront': showQuickFront,
    'accentColorHex': accentColorHex,
    'perMemberAccentColors': perMemberAccentColors,
    'terminology': terminology,
    'memberNameDisplay': memberNameDisplay,
    if (customTerminology != null) 'customTerminology': customTerminology,
    if (customPluralTerminology != null)
      'customPluralTerminology': customPluralTerminology,
    'terminologyUseEnglish': terminologyUseEnglish,
    'frontingRemindersEnabled': frontingRemindersEnabled,
    'frontingReminderIntervalMinutes': frontingReminderIntervalMinutes,
    'themeMode': themeMode,
    'themeBrightness': themeBrightness,
    'themeStyle': themeStyle,
    'themeCornerStyle': themeCornerStyle,
    'paletteSource': paletteSource,
    'paletteSeedColorHex': paletteSeedColorHex,
    'paletteMood': paletteMood,
    'paletteContrast': paletteContrast,
    'chatEnabled': chatEnabled,
    'pollsEnabled': pollsEnabled,
    'habitsEnabled': habitsEnabled,
    'sleepTrackingEnabled': sleepTrackingEnabled,
    'gifSearchEnabled': gifSearchEnabled,
    'voiceNotesEnabled': voiceNotesEnabled,
    'sleepSuggestionEnabled': sleepSuggestionEnabled,
    'sleepSuggestionHour': sleepSuggestionHour,
    'sleepSuggestionMinute': sleepSuggestionMinute,
    'wakeSuggestionEnabled': wakeSuggestionEnabled,
    'wakeSuggestionAfterHours': wakeSuggestionAfterHours,
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
    if (systemColor != null) 'systemColor': systemColor,
    'pkGroupSyncV2Enabled': pkGroupSyncV2Enabled,
    if (systemTag != null) 'systemTag': systemTag,
    if (systemAvatarData != null) 'systemAvatarData': systemAvatarData,
    'remindersEnabled': remindersEnabled,
    if (localeOverride != null) 'localeOverride': localeOverride,
    'gifConsentState': gifConsentState,
    'fontScale': fontScale,
    'fontFamily': fontFamily,
    'pinLockEnabled': pinLockEnabled,
    'biometricLockEnabled': biometricLockEnabled,
    'autoLockDelaySeconds': autoLockDelaySeconds,
    'displayFontInAppBar': displayFontInAppBar,
    if (navBarItems.isNotEmpty) 'navBarItems': navBarItems,
    if (navBarOverflowItems.isNotEmpty)
      'navBarOverflowItems': navBarOverflowItems,
    'navBarLabelDisplayMode': navBarLabelDisplayMode,
    'navBarRevealLabelsWhenExpanded': navBarRevealLabelsWhenExpanded,
    'syncNavigationEnabled': syncNavigationEnabled,
    if (chatBadgePreferences.isNotEmpty)
      'chatBadgePreferences': chatBadgePreferences,
    if (defaultSleepQuality != null) 'defaultSleepQuality': defaultSleepQuality,
    'frontingListViewMode': frontingListViewMode,
    'addFrontDefaultBehavior': addFrontDefaultBehavior,
    'quickFrontDefaultBehavior': quickFrontDefaultBehavior,
    'autoPromoteLongFrontingSessions': autoPromoteLongFrontingSessions,
    'boardsEnabled': boardsEnabled,
    if (spBoardsBackfilledAt != null)
      'spBoardsBackfilledAt': spBoardsBackfilledAt,
    'membersListViewMode': membersListViewMode,
    'membersGroupedDefaultState': membersGroupedDefaultState,
    'membersFolderMemberVisibility': membersFolderMemberVisibility,
    'membersShowPronouns': membersShowPronouns,
    'membersShowFrontButtons': membersShowFrontButtons,
    'membersShowGroups': membersShowGroups,
    'membersFrontButtonBehavior': membersFrontButtonBehavior,
    'bioMarkdownEnabled': bioMarkdownEnabled,
  };

  factory V1SystemSettings.fromJson(
    Map<String, dynamic> json,
  ) => V1SystemSettings(
    systemName: json['systemName'] as String?,
    sharingId: json['sharingId'] as String?,
    showQuickFront: json['showQuickFront'] as bool? ?? true,
    accentColorHex: json['accentColorHex'] as String? ?? '#9070A0',
    perMemberAccentColors: json['perMemberAccentColors'] as bool? ?? true,
    terminology: json['terminology'] as int? ?? 0,
    memberNameDisplay: json['memberNameDisplay'] as int? ?? 0,
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
    themeCornerStyle: json['themeCornerStyle'] as int? ?? 0,
    paletteSource: json['paletteSource'] as int? ?? 1,
    hasPaletteSource: json.containsKey('paletteSource'),
    paletteSeedColorHex: json['paletteSeedColorHex'] as String? ?? '#9070A0',
    hasPaletteSeedColorHex: json.containsKey('paletteSeedColorHex'),
    paletteMood: json['paletteMood'] as int? ?? 0,
    hasPaletteMood: json.containsKey('paletteMood'),
    paletteContrast: json['paletteContrast'] as int? ?? 1,
    hasPaletteContrast: json.containsKey('paletteContrast'),
    chatEnabled: json['chatEnabled'] as bool? ?? true,
    pollsEnabled: json['pollsEnabled'] as bool? ?? true,
    habitsEnabled: json['habitsEnabled'] as bool? ?? true,
    sleepTrackingEnabled: json['sleepTrackingEnabled'] as bool? ?? true,
    gifSearchEnabled: json['gifSearchEnabled'] as bool? ?? true,
    voiceNotesEnabled: json['voiceNotesEnabled'] as bool? ?? true,
    sleepSuggestionEnabled: json['sleepSuggestionEnabled'] as bool? ?? false,
    sleepSuggestionHour: json['sleepSuggestionHour'] as int? ?? 22,
    sleepSuggestionMinute: json['sleepSuggestionMinute'] as int? ?? 0,
    wakeSuggestionEnabled: json['wakeSuggestionEnabled'] as bool? ?? false,
    wakeSuggestionAfterHours:
        (json['wakeSuggestionAfterHours'] as num?)?.toDouble() ?? 8.0,
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
    systemColor: json['systemColor'] as String?,
    pkGroupSyncV2Enabled: json['pkGroupSyncV2Enabled'] as bool? ?? false,
    systemTag: json['systemTag'] as String?,
    systemAvatarData: json['systemAvatarData'] as String?,
    remindersEnabled: json['remindersEnabled'] as bool? ?? true,
    localeOverride: json['localeOverride'] as String?,
    gifConsentState: json['gifConsentState'] as int? ?? 0,
    fontScale: (json['fontScale'] as num?)?.toDouble() ?? 1.0,
    fontFamily: json['fontFamily'] as int? ?? 0,
    pinLockEnabled: json['pinLockEnabled'] as bool? ?? false,
    biometricLockEnabled: json['biometricLockEnabled'] as bool? ?? false,
    autoLockDelaySeconds: json['autoLockDelaySeconds'] as int? ?? 0,
    displayFontInAppBar: json['displayFontInAppBar'] as bool? ?? true,
    navBarItems: (json['navBarItems'] as List<dynamic>?)?.cast<String>() ?? [],
    navBarOverflowItems:
        (json['navBarOverflowItems'] as List<dynamic>?)?.cast<String>() ?? [],
    navBarLabelDisplayMode: json['navBarLabelDisplayMode'] as int? ?? 0,
    navBarRevealLabelsWhenExpanded:
        json['navBarRevealLabelsWhenExpanded'] as bool? ?? true,
    syncNavigationEnabled: json['syncNavigationEnabled'] as bool? ?? true,
    chatBadgePreferences:
        (json['chatBadgePreferences'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, v.toString()),
        ) ??
        {},
    defaultSleepQuality: json['defaultSleepQuality'] as int?,
    frontingListViewMode: json['frontingListViewMode'] as int? ?? 0,
    addFrontDefaultBehavior: json['addFrontDefaultBehavior'] as int? ?? 0,
    quickFrontDefaultBehavior: json['quickFrontDefaultBehavior'] as int? ?? 0,
    autoPromoteLongFrontingSessions:
        json['autoPromoteLongFrontingSessions'] as bool? ?? true,
    boardsEnabled: json['boardsEnabled'] as bool? ?? false,
    spBoardsBackfilledAt: json['spBoardsBackfilledAt'] as String?,
    membersListViewMode: json['membersListViewMode'] as int? ?? 0,
    membersGroupedDefaultState: json['membersGroupedDefaultState'] as int? ?? 0,
    membersFolderMemberVisibility:
        json['membersFolderMemberVisibility'] as int? ?? 0,
    membersShowPronouns: json['membersShowPronouns'] as bool? ?? true,
    membersShowFrontButtons: json['membersShowFrontButtons'] as bool? ?? false,
    membersShowGroups: json['membersShowGroups'] as bool? ?? true,
    membersFrontButtonBehavior: json['membersFrontButtonBehavior'] as int? ?? 0,
    bioMarkdownEnabled: json['bioMarkdownEnabled'] as bool? ?? true,
    hasBioMarkdownEnabled: json.containsKey('bioMarkdownEnabled'),
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
    this.avatarImageData,
    this.displayOrder = 0,
    this.parentGroupId,
    this.groupType = 0,
    this.filterRules,
    required this.createdAt,
    this.sortState,
  });

  final String id;
  final String name;
  final String? description;
  final String? colorHex;
  final String? emoji;
  final String? avatarImageData; // base64
  final int displayOrder;
  final String? parentGroupId;
  final int groupType;
  final String? filterRules;
  final String createdAt;
  final Map<String, dynamic>? sortState;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (description != null) 'description': description,
    if (colorHex != null) 'colorHex': colorHex,
    if (emoji != null) 'emoji': emoji,
    if (avatarImageData != null) 'avatarImageData': avatarImageData,
    'displayOrder': displayOrder,
    if (parentGroupId != null) 'parentGroupId': parentGroupId,
    if (groupType != 0) 'groupType': groupType,
    if (filterRules != null) 'filterRules': filterRules,
    'createdAt': createdAt,
    if (sortState != null) 'sortState': sortState,
  };

  factory V1MemberGroup.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? sortState;
    final rawSortState = json['sortState'];
    if (rawSortState is Map<String, dynamic>) {
      sortState = rawSortState;
    } else if (rawSortState is Map) {
      sortState = rawSortState.map((k, v) => MapEntry(k.toString(), v));
    } else if (rawSortState is String) {
      try {
        final decoded = jsonDecode(rawSortState);
        if (decoded is Map<String, dynamic>) {
          sortState = decoded;
        } else if (decoded is Map) {
          sortState = decoded.map((k, v) => MapEntry(k.toString(), v));
        }
      } catch (_) {
        sortState = null;
      }
    }

    return V1MemberGroup(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      colorHex: json['colorHex'] as String?,
      emoji: json['emoji'] as String?,
      avatarImageData: json['avatarImageData'] as String?,
      displayOrder: json['displayOrder'] as int? ?? 0,
      parentGroupId: json['parentGroupId'] as String?,
      groupType: json['groupType'] as int? ?? 0,
      filterRules: json['filterRules'] as String?,
      createdAt: json['createdAt'] as String,
      sortState: sortState,
    );
  }

  Uint8List? get avatarImageBytes {
    if (avatarImageData == null) return null;
    try {
      return base64Decode(avatarImageData!);
    } on FormatException {
      return null;
    }
  }
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
    this.fieldTypeId,
    this.parentFieldId,
    this.typeConfigJson,
  });

  final String id;
  final String name;
  final int fieldType; // CustomFieldType enum index
  final int? datePrecision; // DatePrecision enum index
  final int displayOrder;
  final String createdAt;

  // v28 fields — optional so older backup files (without these keys) still
  // parse correctly via fromJson. Stored as raw JSON strings so future field
  // types survive a round-trip through a build that doesn't understand them.
  final String? fieldTypeId;
  final String? parentFieldId;
  final String? typeConfigJson;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'fieldType': fieldType,
    if (datePrecision != null) 'datePrecision': datePrecision,
    'displayOrder': displayOrder,
    'createdAt': createdAt,
    if (fieldTypeId != null) 'fieldTypeId': fieldTypeId,
    if (parentFieldId != null) 'parentFieldId': parentFieldId,
    if (typeConfigJson != null) 'typeConfigJson': typeConfigJson,
  };

  factory V1CustomField.fromJson(Map<String, dynamic> json) => V1CustomField(
    id: json['id'] as String,
    name: json['name'] as String,
    fieldType: json['fieldType'] as int,
    datePrecision: json['datePrecision'] as int?,
    displayOrder: json['displayOrder'] as int? ?? 0,
    createdAt: json['createdAt'] as String,
    fieldTypeId: json['fieldTypeId'] as String?,
    parentFieldId: json['parentFieldId'] as String?,
    typeConfigJson: json['typeConfigJson'] as String?,
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
    this.sessionId,
    required this.body,
    required this.timestamp,
    required this.createdAt,
    this.targetTime,
    this.authorMemberId,
    this.isLegacyShape = false,
    this.isTimestampOnlyShape = false,
  });

  /// Process-wide counter for the per-row legacy-shape fallback.
  /// Mirrors [V1FrontSession.rowShapeLegacyFallbackCount] for comments.
  /// See review finding #39 + remediation plan WS4 step 7.
  static int _rowShapeLegacyFallbackCount = 0;
  static int get rowShapeLegacyFallbackCount => _rowShapeLegacyFallbackCount;
  static void resetRowShapeLegacyFallbackCount() {
    _rowShapeLegacyFallbackCount = 0;
  }

  final String id;
  // FK to fronting_sessions. Current exports always emit this. It stays
  // nullable on the import model so abandoned timestamp-only beta exports can
  // be parsed and then dropped with a user-visible diagnostic.
  final String? sessionId;
  final String body;
  final String timestamp;
  final String createdAt;

  // Abandoned timestamp-only beta fields. They are accepted for import
  // compatibility but current exports do not emit them and current imports
  // drop rows that have only these fields without a usable sessionId.
  final String? targetTime;
  final String? authorMemberId;

  // Retained for old tests/callers. Restored session-attached imports do not
  // need a separate legacy branch for comments; any non-empty sessionId is
  // resolved directly or through the session rescue map.
  final bool isLegacyShape;

  // True when a row carries only the abandoned timestamp-only beta anchor.
  // DataImportService drops these rows because there is no durable physical
  // fronting session parent to attach them to.
  final bool isTimestampOnlyShape;

  Map<String, dynamic> toJson() => {
    'id': id,
    if (sessionId != null) 'sessionId': sessionId,
    'body': body,
    'timestamp': timestamp,
    'createdAt': createdAt,
    if (targetTime != null) 'targetTime': targetTime,
    if (authorMemberId != null) 'authorMemberId': authorMemberId,
  };

  factory V1FrontSessionComment.fromJson(
    Map<String, dynamic> json, {
    bool forceLegacyShape = false,
  }) {
    final hasSessionId =
        json.containsKey('sessionId') &&
        (json['sessionId'] as String?)?.isNotEmpty == true;
    final hasNewShapeMarker =
        json.containsKey('targetTime') || json.containsKey('authorMemberId');
    final rowShapeLegacy = hasSessionId && !hasNewShapeMarker;
    final timestampOnlyShape = !hasSessionId && hasNewShapeMarker;
    final isLegacy = forceLegacyShape || rowShapeLegacy;
    if (!forceLegacyShape && rowShapeLegacy) {
      _rowShapeLegacyFallbackCount++;
    }
    return V1FrontSessionComment(
      id: json['id'] as String,
      sessionId: json['sessionId'] as String?,
      body: json['body'] as String,
      timestamp: json['timestamp'] as String,
      createdAt: json['createdAt'] as String,
      targetTime: json['targetTime'] as String?,
      authorMemberId: json['authorMemberId'] as String?,
      isLegacyShape: isLegacy,
      isTimestampOnlyShape: timestampOnlyShape,
    );
  }
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
    this.frequency,
    this.intervalDays,
    this.weeklyDays,
    this.timeOfDay,
    this.delayHours,
    this.targetMemberId,
    this.isActive = true,
    required this.createdAt,
    required this.modifiedAt,
  });

  final String id;
  final String name;
  final String message;
  final int trigger; // ReminderTrigger enum index
  final String? frequency;
  final int? intervalDays;
  final String? weeklyDays; // JSON-encoded int list
  final String? timeOfDay;
  final int? delayHours;
  final String? targetMemberId;
  final bool isActive;
  final String createdAt;
  final String modifiedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'message': message,
    'trigger': trigger,
    if (frequency != null) 'frequency': frequency,
    if (intervalDays != null) 'intervalDays': intervalDays,
    if (weeklyDays != null) 'weeklyDays': weeklyDays,
    if (timeOfDay != null) 'timeOfDay': timeOfDay,
    if (delayHours != null) 'delayHours': delayHours,
    if (targetMemberId != null) 'targetMemberId': targetMemberId,
    'isActive': isActive,
    'createdAt': createdAt,
    'modifiedAt': modifiedAt,
  };

  factory V1Reminder.fromJson(Map<String, dynamic> json) => V1Reminder(
    id: json['id'] as String,
    name: json['name'] as String,
    message: json['message'] as String,
    trigger: json['trigger'] as int? ?? 0,
    frequency: json['frequency'] as String?,
    intervalDays: json['intervalDays'] as int?,
    weeklyDays: json['weeklyDays'] as String?,
    timeOfDay: json['timeOfDay'] as String?,
    delayHours: json['delayHours'] as int?,
    targetMemberId: json['targetMemberId'] as String?,
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
    this.memberId = '',
    this.tag = '',
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
    this.thumbnailContentHash = '',
    this.thumbnailPlaintextHash = '',
    this.sourceUrl = '',
    this.previewUrl = '',
    this.isDeleted = false,
  });

  final String id;
  final String messageId;
  final String memberId;
  final String tag;
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
  final String thumbnailContentHash;
  final String thumbnailPlaintextHash;
  final String sourceUrl;
  final String previewUrl;
  final bool isDeleted;

  Map<String, dynamic> toJson() => {
    'id': id,
    'messageId': messageId,
    if (memberId.isNotEmpty) 'memberId': memberId,
    if (tag.isNotEmpty) 'tag': tag,
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
    if (thumbnailContentHash.isNotEmpty)
      'thumbnailContentHash': thumbnailContentHash,
    if (thumbnailPlaintextHash.isNotEmpty)
      'thumbnailPlaintextHash': thumbnailPlaintextHash,
    if (sourceUrl.isNotEmpty) 'sourceUrl': sourceUrl,
    if (previewUrl.isNotEmpty) 'previewUrl': previewUrl,
    'isDeleted': isDeleted,
  };

  factory V1MediaAttachment.fromJson(Map<String, dynamic> json) =>
      V1MediaAttachment(
        id: json['id'] as String,
        messageId: json['messageId'] as String,
        memberId: json['memberId'] as String? ?? '',
        tag: json['tag'] as String? ?? '',
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
        thumbnailContentHash: json['thumbnailContentHash'] as String? ?? '',
        thumbnailPlaintextHash: json['thumbnailPlaintextHash'] as String? ?? '',
        sourceUrl: json['sourceUrl'] as String? ?? '',
        previewUrl: json['previewUrl'] as String? ?? '',
        isDeleted: json['isDeleted'] as bool? ?? false,
      );
}

// ---------------------------------------------------------------------------
// V1MemberBoardPost
// ---------------------------------------------------------------------------

class V1MemberBoardPost {
  V1MemberBoardPost({
    required this.id,
    this.targetMemberId,
    this.authorId,
    required this.audience,
    this.title,
    required this.body,
    required this.createdAt,
    required this.writtenAt,
    this.editedAt,
    this.isDeleted = false,
  });

  final String id;
  final String? targetMemberId;
  final String? authorId;
  final String audience;
  final String? title;
  final String body;
  final String createdAt;
  final String writtenAt;
  final String? editedAt;
  final bool isDeleted;

  Map<String, dynamic> toJson() => {
    'id': id,
    if (targetMemberId != null) 'targetMemberId': targetMemberId,
    if (authorId != null) 'authorId': authorId,
    'audience': audience,
    if (title != null) 'title': title,
    'body': body,
    'createdAt': createdAt,
    'writtenAt': writtenAt,
    if (editedAt != null) 'editedAt': editedAt,
    'isDeleted': isDeleted,
  };

  factory V1MemberBoardPost.fromJson(Map<String, dynamic> json) =>
      V1MemberBoardPost(
        id: json['id'] as String,
        targetMemberId: json['targetMemberId'] as String?,
        authorId: json['authorId'] as String?,
        audience: json['audience'] as String? ?? 'public',
        title: json['title'] as String?,
        body: json['body'] as String? ?? '',
        createdAt: json['createdAt'] as String,
        writtenAt: json['writtenAt'] as String,
        editedAt: json['editedAt'] as String?,
        isDeleted: json['isDeleted'] as bool? ?? false,
      );
}
