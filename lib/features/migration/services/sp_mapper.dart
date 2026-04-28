import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/models/fronting_session.dart' as domain;
import 'package:prism_plurality/domain/models/conversation.dart' as domain;
import 'package:prism_plurality/domain/models/chat_message.dart' as domain;
import 'package:prism_plurality/domain/models/poll.dart' as domain;
import 'package:prism_plurality/domain/models/poll_option.dart' as domain;
import 'package:prism_plurality/domain/models/poll_vote.dart' as domain;
import 'package:prism_plurality/domain/models/note.dart' as domain;
import 'package:prism_plurality/domain/models/front_session_comment.dart'
    as domain;
import 'package:prism_plurality/domain/models/custom_field.dart' as domain;
import 'package:prism_plurality/domain/models/custom_field_value.dart'
    as domain;
import 'package:prism_plurality/domain/models/member_group.dart' as domain;
import 'package:prism_plurality/domain/models/conversation_category.dart'
    as domain;
import 'package:prism_plurality/domain/models/reminder.dart' as domain;
import 'package:prism_plurality/features/migration/services/sp_parser.dart';
import 'package:prism_plurality/features/migration/services/sp_custom_front_disposition.dart';

/// Result of mapping SP entities to Prism domain models.
class MappedData {
  final List<domain.Member> members;
  final List<domain.FrontingSession> sessions;
  final List<domain.Conversation> conversations;
  final List<domain.ChatMessage> messages;
  final List<domain.Poll> polls;
  final List<domain.Note> notes;
  final List<domain.FrontSessionComment> frontComments;
  final List<domain.CustomField> customFields;
  final List<domain.CustomFieldValue> customFieldValues;
  final List<domain.MemberGroup> groups;
  final List<MapEntry<String, String>> groupMemberships;
  final List<domain.ConversationCategory> conversationCategories;
  final List<domain.Reminder> reminders;
  final List<String> warnings;

  /// Map of SP member ID to avatar URL (for download later).
  final Map<String, String> avatarUrls;

  /// System profile info from SP export.
  final String? systemName;
  final String? systemColor;
  final String? systemDescription;
  final String? systemAvatarUrl;

  const MappedData({
    required this.members,
    required this.sessions,
    required this.conversations,
    required this.messages,
    required this.polls,
    this.notes = const [],
    this.frontComments = const [],
    this.customFields = const [],
    this.customFieldValues = const [],
    this.groups = const [],
    this.groupMemberships = const [],
    this.conversationCategories = const [],
    this.reminders = const [],
    required this.warnings,
    required this.avatarUrls,
    this.systemName,
    this.systemColor,
    this.systemDescription,
    this.systemAvatarUrl,
  });
}

/// Maps Simply Plural entities to Prism domain models.
class SpMapper {
  static const _uuid = Uuid();

  /// Map of SP member ID to Prism UUID.
  final Map<String, String> _memberIdMap;

  /// Map of SP channel ID to Prism conversation UUID.
  final Map<String, String> _channelIdMap;

  /// Map of SP front history ID to Prism session UUID.
  final Map<String, String> _sessionIdMap;

  /// Map of SP group ID to Prism group UUID.
  final Map<String, String> _groupIdMap;

  /// Map of SP custom field ID to Prism field UUID.
  final Map<String, String> _fieldIdMap;

  /// Map of SP category ID to Prism category UUID.
  final Map<String, String> _categoryIdMap;

  /// Per-CF disposition chosen by the user (or an empty map for legacy
  /// behavior — every CF is treated as importAsMember in that case, matching
  /// pre-disposition tests).
  final Map<String, CfDisposition> _customFrontDispositions;

  /// SP CF ids whose persisted member mapping was scrubbed on init because
  /// the user's new disposition is no longer importAsMember. The importer
  /// reads [pendingStaleMappingDeletes] and asks the DAO to drop these rows.
  final List<String> _pendingStaleMappingDeletes = [];

  /// Resolved per-CF state built at mapper construction. Includes every CF
  /// in the export and any synthesized CFs added during front-history mapping
  /// (via [_ensureSyntheticCf]).
  final Map<String, CfResolved> _cfResolved = {};

  /// Quick disposition lookup by SP CF id.
  final Map<String, CfDisposition> _cfDispositionById = {};

  /// Tracks whether at least one front-history entry referenced the
  /// Unknown sentinel.  Set to true on first sighting so [map] knows to
  /// append the sentinel member entity for the importer to persist.
  /// The id itself is the shared [unknownSentinelMemberId] constant —
  /// no per-instance derivation.
  bool _unknownSentinelSeen = false;

  /// Counters for warnings surfaced by the importer.
  int _cfDroppedSessions = 0;
  int _cfDroppedComments = 0;
  int _cfOpenEndedSleepClamped = 0;
  int _cfDedupedSleepStarts = 0;
  int _cfSyntheticFallbacks = 0;
  int _cfTimerTargetsDropped = 0;
  int _cfTimersRemoved = 0;
  int _cfStaleMemberMappingsScrubbed = 0;
  int _cfSleepOverlaps = 0;

  /// Pre-seed maps from prior imports so IDs are stable across runs.
  SpMapper({
    Map<String, Map<String, String>>? existingMappings,
    Map<String, CfDisposition>? customFrontDispositions,
  }) : _memberIdMap = Map.of(existingMappings?['member'] ?? {}),
       _channelIdMap = Map.of(existingMappings?['channel'] ?? {}),
       _sessionIdMap = Map.of(existingMappings?['session'] ?? {}),
       _groupIdMap = Map.of(existingMappings?['group'] ?? {}),
       _fieldIdMap = Map.of(existingMappings?['field'] ?? {}),
       _categoryIdMap = Map.of(existingMappings?['category'] ?? {}),
       _customFrontDispositions = Map.of(customFrontDispositions ?? {});

  // Expose ID maps as unmodifiable views so the importer can persist them.
  Map<String, String> get memberIdMap => Map.unmodifiable(_memberIdMap);
  Map<String, String> get channelIdMap => Map.unmodifiable(_channelIdMap);
  Map<String, String> get sessionIdMap => Map.unmodifiable(_sessionIdMap);
  Map<String, String> get groupIdMap => Map.unmodifiable(_groupIdMap);
  Map<String, String> get fieldIdMap => Map.unmodifiable(_fieldIdMap);
  Map<String, String> get categoryIdMap => Map.unmodifiable(_categoryIdMap);

  /// SP CF ids that must be removed from persisted `sp_id_map` before the
  /// importer saves new mappings. Populated by [_buildCfResolution] during
  /// [mapAll].
  List<String> get pendingStaleMappingDeletes =>
      List.unmodifiable(_pendingStaleMappingDeletes);

  /// Map of SP channel ID to (categoryId, displayOrder) within the category.
  final Map<String, ({String categoryId, int displayOrder})>
  _channelCategoryInfo = {};

  /// Resolve SP member ID to Prism UUID.
  String? resolveMemberId(String spId) => _memberIdMap[spId];

  /// Resolve SP channel ID to Prism conversation UUID.
  String? resolveChannelId(String spId) => _channelIdMap[spId];

  /// Map all SP export data to Prism domain models.
  MappedData mapAll(SpExportData data) {
    final warnings = <String>[];
    final avatarUrls = <String, String>{};

    // 0. Resolve each custom front's disposition and scrub stale persisted
    //    CF-as-member mappings before any mapping runs. This has to happen
    //    before _mapMembers so the member pass can skip CFs that the user
    //    chose NOT to import as members, and before _mapFrontHistory so the
    //    front-history pass sees the correct disposition for each id.
    _buildCfResolution(data.customFronts, data.frontHistory);

    // 1. Map members (including custom fronts as tagged members).
    final members = _mapMembers(data.members, data.customFronts, avatarUrls);

    // 2. Map front history to sessions.
    final sessions = _mapFrontHistory(data.frontHistory, warnings);

    // 2b. If the front-history pass referenced the Unknown sentinel,
    //     append the sentinel member entity so the importer persists it.
    //     Id matches `unknownSentinelMemberId` so all devices converge.
    if (_unknownSentinelSeen) {
      members.add(
        domain.Member(
          id: unknownSentinelMemberId,
          name: 'Unknown',
          emoji: '❔', // ❔
          isActive: true,
          createdAt: DateTime.now(),
          displayOrder: members.length,
        ),
      );
    }

    // 3. Map channel categories (before channels so category info is available).
    final conversationCategories = _mapChannelCategories(
      data.channelCategories,
    );

    // 3b. Map channels to conversations.
    final conversations = _mapChannels(data.channels);

    // 4. Add a board conversation if there are board messages.
    final hasBoardMessages = data.messages.any((m) => m.channelId == '_board');
    if (hasBoardMessages) {
      final boardId = _uuid.v4();
      _channelIdMap['_board'] = boardId;
      conversations.add(
        domain.Conversation(
          id: boardId,
          createdAt: DateTime.now(),
          lastActivityAt: DateTime.now(),
          title: 'Board Messages',
          emoji: '\u{1F4CB}',
          isDirectMessage: true,
          participantIds: const [],
        ),
      );
    }

    // 5. Map messages.
    final messages = _mapMessages(data.messages, warnings);

    // 6. Map polls.
    final polls = _mapPolls(data.polls);

    // 7. Map notes.
    final notes = _mapNotes(data.notes, warnings);

    // 8. Map front comments.
    final frontComments = _mapFrontComments(data.comments, warnings);

    // 9. Map custom fields + values from member info maps.
    final customFields = _mapCustomFieldDefs(data.customFields);
    final customFieldValues = _mapCustomFieldValues(data.members, warnings);

    // 10. Map groups.
    final groups = _mapGroups(data.groups);
    final groupMemberships = _mapGroupMemberships(data.groups, warnings);

    // 11. Map board messages as DM conversations + messages.
    final boardResult = _mapBoardMessages(data.boardMessages, warnings);
    conversations.addAll(boardResult.conversations);
    messages.addAll(boardResult.messages);

    // 12. Map timers to reminders.
    final reminders = _mapTimers(
      data.automatedTimers,
      data.repeatedTimers,
      warnings,
    );

    _appendCfWarnings(warnings);

    return MappedData(
      members: members,
      sessions: sessions,
      conversations: conversations,
      messages: messages,
      polls: polls,
      notes: notes,
      frontComments: frontComments,
      customFields: customFields,
      customFieldValues: customFieldValues,
      groups: groups,
      groupMemberships: groupMemberships,
      conversationCategories: conversationCategories,
      reminders: reminders,
      warnings: warnings,
      avatarUrls: avatarUrls,
      systemName: data.systemName,
      systemColor: data.systemColor,
      systemDescription: data.systemDescription,
      systemAvatarUrl: data.systemAvatarUrl,
    );
  }

  /// Map SP members to Prism members.
  List<domain.Member> _mapMembers(
    List<SpMember> spMembers,
    List<SpCustomFront> customFronts,
    Map<String, String> avatarUrls,
  ) {
    final members = <domain.Member>[];

    for (var i = 0; i < spMembers.length; i++) {
      final sp = spMembers[i];
      final prismId = _memberIdMap[sp.id] ?? _uuid.v4();
      _memberIdMap[sp.id] = prismId;

      // Track avatar URL for later download.
      // Prefer legacy avatarUrl; fall back to constructing URL from avatarUuid
      // (new-style uploads stored at serve.apparyllis.com/avatars/{uid}/{uuid}).
      if (sp.avatarUrl != null && sp.avatarUrl!.isNotEmpty) {
        avatarUrls[prismId] = sp.avatarUrl!;
      } else if (sp.avatarUuid != null &&
          sp.avatarUuid!.isNotEmpty &&
          sp.uid != null &&
          sp.uid!.isNotEmpty) {
        avatarUrls[prismId] =
            'https://serve.apparyllis.com/avatars/${sp.uid}/${sp.avatarUuid}';
      }

      // Normalize SP color to hex without '#'.
      String? colorHex = sp.color;
      if (colorHex != null) {
        colorHex = colorHex.replaceFirst('#', '');
        if (colorHex.isEmpty) colorHex = null;
      }

      members.add(
        domain.Member(
          id: prismId,
          name: sp.name,
          pronouns: sp.pronouns,
          emoji: '\u2754', // SP doesn't use emoji identifiers
          bio: sp.desc,
          isActive: !sp.archived,
          createdAt: DateTime.now(),
          displayOrder: i,
          customColorEnabled: colorHex != null,
          customColorHex: colorHex,
          pluralkitId: sp.pkId,
        ),
      );
    }

    // Map custom fronts as tagged members — only for CFs whose disposition
    // is importAsMember. Others are handled by _mapFrontHistory and never
    // get a member row.
    for (var i = 0; i < customFronts.length; i++) {
      final cf = customFronts[i];
      final disposition =
          _cfDispositionById[cf.id] ?? CfDisposition.importAsMember;
      if (disposition != CfDisposition.importAsMember) continue;
      final prismId = _memberIdMap[cf.id] ?? _uuid.v4();
      _memberIdMap[cf.id] = prismId;

      if (cf.avatarUrl != null && cf.avatarUrl!.isNotEmpty) {
        avatarUrls[prismId] = cf.avatarUrl!;
      }

      String? colorHex = cf.color;
      if (colorHex != null) {
        colorHex = colorHex.replaceFirst('#', '');
        if (colorHex.isEmpty) colorHex = null;
      }

      members.add(
        domain.Member(
          id: prismId,
          name: cf.name,
          emoji: '\u{1F3F7}\uFE0F', // tag emoji to indicate custom front
          bio: cf.desc,
          isActive: true,
          createdAt: DateTime.now(),
          displayOrder: spMembers.length + i,
          customColorEnabled: colorHex != null,
          customColorHex: colorHex,
        ),
      );
    }

    return members;
  }

  /// Map SP front history to Prism fronting sessions.
  ///
  /// Per §2.6 of the fronting-per-member-sessions plan: SP `frontHistory`
  /// rows are already one-per-member — each row maps 1:1 to one Prism row.
  /// No co-fronter expansion.  Co-fronting is an emergent property of
  /// overlapping intervals in the new model.
  ///
  /// ID derivation (§2.6 deterministic IDs):
  ///   `localId = _sessionIdMap[entry._id]?.localId`
  ///           `?? Uuid().v5(spFrontingNamespace, entry._id)`
  /// Existing SP rows already have entries in `sp_id_map` (via
  /// `_sessionIdMap` seeded from the DAO) → re-import finds them and keeps
  /// their original IDs.  New rows get deterministic v5 IDs.
  ///
  /// `live: true` → `end_time = NULL` (active session).
  /// `live: false` → `end_time = endTime`.
  ///
  /// `customStatus` is folded into `notes` with a `[bracket]` prefix per
  /// §2.6: `"[Co-fronting] (comment if any)"`.
  ///
  /// `member: "unknown"` is mapped to the Unknown sentinel member, created
  /// on-the-fly with a deterministic ID (Phase 5 will tag it
  /// `is_system_managed`; until that lands we create it here).
  ///
  /// `custom: true` rows still flow through the disposition tree — the
  /// per-member model doesn't change how CF dispositions are applied.
  List<domain.FrontingSession> _mapFrontHistory(
    List<SpFrontHistory> history,
    List<String> warnings,
  ) {
    final sessions = <domain.FrontingSession>[];
    // Track emitted sleep sessions by start-time for the 60s same-start dedup.
    final sleepStarts = <int>[];

    for (final entry in history) {
      final rawMain = entry.memberId;

      // If the entry is flagged isCustomFront but the CF id isn't in the
      // customFronts list, synthesize a mergeAsNote CF on the fly.
      if (rawMain != null &&
          rawMain.isNotEmpty &&
          rawMain != 'unknown' &&
          entry.isCustomFront &&
          !_cfResolved.containsKey(rawMain) &&
          !_memberIdMap.containsKey(rawMain)) {
        _ensureSyntheticCf(rawMain);
      }

      final mainKind = _classifyId(rawMain);

      // Resolve the primary member for this row.
      String? primaryMemberId;
      String? primaryCfNoteName;
      bool sleepPath = false;

      switch (mainKind) {
        case _IdKind.unknownSentinel:
          // Map to the Unknown sentinel member.  Id is the shared
          // [unknownSentinelMemberId] so all devices converge; the mapper
          // marks it seen so the sentinel member entity gets appended to
          // [map]'s output.
          _unknownSentinelSeen = true;
          primaryMemberId = unknownSentinelMemberId;
          break;
        case _IdKind.missing:
          primaryMemberId = null;
          if (rawMain != null && rawMain.isNotEmpty) {
            warnings.add(
              'Front entry ${entry.id}: member "$rawMain" not found, '
              'session will have no primary fronter.',
            );
          }
          break;
        case _IdKind.realMember:
        case _IdKind.cfMember:
          primaryMemberId = _memberIdMap[rawMain];
          if (primaryMemberId == null) {
            warnings.add(
              'Front entry ${entry.id}: member "$rawMain" not found, '
              'session will have no primary fronter.',
            );
          }
          break;
        case _IdKind.cfNote:
          primaryMemberId = null;
          primaryCfNoteName = _cfResolved[rawMain]?.name;
          break;
        case _IdKind.cfSleep:
          sleepPath = true;
          primaryMemberId = null;
          break;
        case _IdKind.cfSkip:
          primaryMemberId = null;
          break;
      }

      // --- Notes assembly ---
      // Per §2.6: customStatus is folded into notes with a bracket prefix.
      // Format: "[customStatus] comment" or just "[customStatus]" or
      // just "comment" depending on what's present.
      // CF-note names (for cfNote primary) are prepended the same way.
      final noteTags = <String>[];
      if (primaryCfNoteName != null) noteTags.add(primaryCfNoteName);

      // Build base note from customStatus + comment per §2.6.
      String? baseNote;
      if (entry.customStatus != null && entry.customStatus!.isNotEmpty) {
        if (entry.comment != null && entry.comment!.isNotEmpty) {
          baseNote = '[${entry.customStatus}] ${entry.comment}';
        } else {
          baseNote = '[${entry.customStatus}]';
        }
      } else {
        baseNote = entry.comment;
      }

      String? notes;
      if (noteTags.isEmpty) {
        notes = baseNote;
      } else {
        final tagStr = noteTags.map((n) => '[$n]').join(' ');
        if (baseNote == null || baseNote.isEmpty) {
          notes = tagStr;
        } else {
          notes = '$tagStr $baseNote';
        }
      }

      // --- Emit ---
      if (sleepPath) {
        // cfSleep primary: emit sleep session (1:1, no co-fronters in Prism
        // sleep sessions).

        // Open-ended sleep clamp — SP live flag doesn't apply to sleep CFs
        // (they have no "live" concept in real exports), so use endTime null
        // as the trigger.
        DateTime endTime;
        final effectiveEndTime = entry.live ? null : entry.endTime;
        if (effectiveEndTime == null) {
          endTime = entry.startTime.add(const Duration(hours: 24));
          _cfOpenEndedSleepClamped++;
        } else {
          endTime = effectiveEndTime;
        }

        // Same-start 60s defensive dedup.
        final startMs = entry.startTime.millisecondsSinceEpoch;
        final dup = sleepStarts.any((s) => (s - startMs).abs() <= 60000);
        if (dup) {
          _cfDedupedSleepStarts++;
          continue;
        }
        sleepStarts.add(startMs);

        // Deterministic ID: sp_id_map lookup first, then v5 derivation.
        final sessionId =
            _sessionIdMap[entry.id] ?? deriveSpSessionId(entry.id);
        _sessionIdMap[entry.id] = sessionId;

        sessions.add(
          domain.FrontingSession(
            id: sessionId,
            startTime: entry.startTime,
            endTime: endTime,
            memberId: null,
            notes: notes,
            sessionType: domain.SessionType.sleep,
            quality: domain.SleepQuality.unknown,
          ),
        );
        continue;
      }

      // Non-sleep path — resolve cfSkip: drop entirely if no co-fronter
      // promotion is possible (co-fronters don't exist in per-member model,
      // so cfSkip with no other member → always drop).
      if (mainKind == _IdKind.cfSkip && primaryMemberId == null) {
        _cfDroppedSessions++;
        continue;
      }

      // All other sessionless paths (missing, cfNote with no co-fronters)
      // emit a session with null primary so the timeline row + attached
      // comments survive.  cfNote primary with no real-member co-fronters
      // in the source is unusual but preserves the note text.

      // Deterministic ID: sp_id_map lookup first, then v5 derivation.
      final sessionId =
          _sessionIdMap[entry.id] ?? deriveSpSessionId(entry.id);
      _sessionIdMap[entry.id] = sessionId;

      // live: true → end_time = NULL; false → end_time = endTime.
      final sessionEndTime = entry.live ? null : entry.endTime;

      sessions.add(
        domain.FrontingSession(
          id: sessionId,
          startTime: entry.startTime,
          endTime: sessionEndTime,
          memberId: primaryMemberId,
          notes: notes,
        ),
      );
    }

    _countSleepOverlaps(sessions);

    return sessions;
  }

  /// Count sleep sessions whose time span intersects any other session in
  /// the same batch (sleep × sleep or sleep × normal). Emitted as a single
  /// aggregated warning so the user can resolve validator-flagged overlaps
  /// in the Fronting tab (plan §E5).
  void _countSleepOverlaps(List<domain.FrontingSession> sessions) {
    if (sessions.length < 2) return;
    final sorted = [...sessions]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    // Max safe DateTime (year 275760) — used for open-ended regular sessions
    // so we can still detect overlap without overflowing DateTime. Sleep
    // sessions are always clamped before reaching here (Step 4 adds +24h
    // when endTime is null), so the null path only fires for regular ones.
    final farFuture = DateTime.fromMillisecondsSinceEpoch(
      8640000000000000,
      isUtc: true,
    );
    final overlapping = <int>{};
    for (var i = 0; i < sorted.length; i++) {
      final a = sorted[i];
      final aEnd = a.endTime ?? farFuture;
      for (var j = i + 1; j < sorted.length; j++) {
        final b = sorted[j];
        // Sessions are start-sorted, so b.startTime >= a.startTime.
        if (b.startTime.isBefore(aEnd)) {
          // Only count sleep sessions that overlap something else.
          if (a.sessionType == domain.SessionType.sleep) overlapping.add(i);
          if (b.sessionType == domain.SessionType.sleep) overlapping.add(j);
        } else {
          break;
        }
      }
    }
    _cfSleepOverlaps = overlapping.length;
  }

  /// Classify an SP id (from front-history main or co-fronter slot) into
  /// the 5-way taxonomy used by [_mapFrontHistory].
  _IdKind _classifyId(String? rawId) {
    if (rawId == null || rawId.isEmpty) return _IdKind.missing;
    if (rawId == 'unknown') return _IdKind.unknownSentinel;
    final cfDisposition = _cfDispositionById[rawId];
    if (cfDisposition != null) {
      switch (cfDisposition) {
        case CfDisposition.importAsMember:
          return _IdKind.cfMember;
        case CfDisposition.mergeAsNote:
          return _IdKind.cfNote;
        case CfDisposition.convertToSleep:
          return _IdKind.cfSleep;
        case CfDisposition.skip:
          return _IdKind.cfSkip;
      }
    }
    if (_memberIdMap.containsKey(rawId)) return _IdKind.realMember;
    return _IdKind.missing;
  }

  /// Synthesize a CF entry for ids that appear in front history with
  /// `isCustomFront` set but are missing from the exported customFronts
  /// list (deleted CF / version skew). Default disposition is mergeAsNote
  /// so timelines stay intact without fabricating a member.
  void _ensureSyntheticCf(String spId) {
    if (_cfResolved.containsKey(spId)) return;
    _cfSyntheticFallbacks++;
    const name = '(deleted custom front)';
    _cfResolved[spId] = const CfResolved(
      spId: '',
      name: name,
      disposition: CfDisposition.mergeAsNote,
    );
    _cfDispositionById[spId] = CfDisposition.mergeAsNote;
  }

  /// Populate [_cfResolved], [_cfDispositionById], and scrub stale member
  /// mappings for CFs whose disposition is no longer importAsMember.
  ///
  /// Also scrubs stale mappings for SP ids that appear in front history with
  /// `isCustomFront: true` but are NOT present in the current `customFronts`
  /// list — these are CFs that were imported as members in a prior run and
  /// have since been deleted from the SP source. Without this, `_classifyId`
  /// would resolve them via `_memberIdMap` as real members instead of
  /// synthesizing them as `mergeAsNote` (plan §E15).
  void _buildCfResolution(
    List<SpCustomFront> customFronts,
    List<SpFrontHistory> frontHistory,
  ) {
    final currentCfIds = {for (final cf in customFronts) cf.id};
    final hasUserChoices = _customFrontDispositions.isNotEmpty;
    for (final cf in customFronts) {
      // Legacy behavior: empty map → every CF becomes importAsMember (so
      // pre-disposition callers and tests keep working unchanged). When the
      // caller supplies a non-empty map, each CF MUST be listed; unknowns
      // fall back to mergeAsNote (safe default).
      final disposition = hasUserChoices
          ? (_customFrontDispositions[cf.id] ?? CfDisposition.mergeAsNote)
          : CfDisposition.importAsMember;
      _cfDispositionById[cf.id] = disposition;
      _cfResolved[cf.id] = CfResolved(
        spId: cf.id,
        name: cf.name,
        disposition: disposition,
      );

      // Stale-mapping scrub. A CF imported as a member in a prior run but
      // now set to any other disposition must lose its persisted mapping,
      // otherwise front-history resolution would silently treat it as a
      // real member via _memberIdMap.
      if (disposition != CfDisposition.importAsMember &&
          _memberIdMap.containsKey(cf.id)) {
        _memberIdMap.remove(cf.id);
        _pendingStaleMappingDeletes.add(cf.id);
        _cfStaleMemberMappingsScrubbed++;
      }
    }

    // Scrub stale CF-as-member mappings for ids referenced in front history
    // with isCustomFront: true but missing from the current customFronts
    // list. Otherwise `_classifyId` would hit `_memberIdMap` first and treat
    // a deleted CF as a real member (plan §E15).
    // Note: SP front history is one-row-per-member — there are no co-fronter
    // slots in real exports.  Only the primary member id is checked here.
    final staleCfIds = <String>{};
    for (final entry in frontHistory) {
      if (!entry.isCustomFront) continue;
      final mId = entry.memberId;
      if (mId != null &&
          mId.isNotEmpty &&
          mId != 'unknown' &&
          !currentCfIds.contains(mId) &&
          _memberIdMap.containsKey(mId)) {
        staleCfIds.add(mId);
      }
    }
    for (final id in staleCfIds) {
      _memberIdMap.remove(id);
      if (!_pendingStaleMappingDeletes.contains(id)) {
        _pendingStaleMappingDeletes.add(id);
      }
      _cfStaleMemberMappingsScrubbed++;
    }
  }

  /// Emit aggregated CF-handling warnings into [warnings].
  void _appendCfWarnings(List<String> warnings) {
    if (_cfDroppedSessions > 0) {
      warnings.add(
        '$_cfDroppedSessions front-history entries dropped (primary was a '
        'skipped custom front).',
      );
    }
    if (_cfDroppedComments > 0) {
      warnings.add(
        '$_cfDroppedComments comments dropped (attached to skipped '
        'custom-front sessions).',
      );
    }
    if (_cfOpenEndedSleepClamped > 0) {
      warnings.add(
        '$_cfOpenEndedSleepClamped open-ended SP sleep entries clamped to '
        '24h duration.',
      );
    }
    if (_cfDedupedSleepStarts > 0) {
      warnings.add(
        '$_cfDedupedSleepStarts duplicate-start SP sleep entries collapsed.',
      );
    }
    if (_cfSyntheticFallbacks > 0) {
      warnings.add(
        '$_cfSyntheticFallbacks front-history references pointed to custom '
        'fronts deleted in SP — handled as notes.',
      );
    }
    if (_cfTimerTargetsDropped > 0 || _cfTimersRemoved > 0) {
      final total = _cfTimerTargetsDropped + _cfTimersRemoved;
      warnings.add(
        '$total timers targeted custom fronts that aren\'t imported as '
        'members — target dropped or timer removed.',
      );
    }
    if (_cfSleepOverlaps > 0) {
      warnings.add(
        '$_cfSleepOverlaps sleep sessions overlap with other sessions in '
        'your timeline — resolve in the Fronting tab.',
      );
    }
    if (_cfStaleMemberMappingsScrubbed > 0) {
      warnings.add(
        '$_cfStaleMemberMappingsScrubbed previously-imported custom fronts '
        'are no longer imported as members; existing member records remain '
        '— delete manually if you want them gone.',
      );
    }
  }

  /// Map SP channel categories to Prism conversation categories.
  ///
  /// Also populates [_channelCategoryInfo] so that [_mapChannels] can assign
  /// each conversation its category ID and display order.
  List<domain.ConversationCategory> _mapChannelCategories(
    List<SpChannelCategory> spCategories,
  ) {
    final categories = <domain.ConversationCategory>[];
    final now = DateTime.now();

    for (var i = 0; i < spCategories.length; i++) {
      final sp = spCategories[i];
      final prismId = _categoryIdMap[sp.id] ?? _uuid.v4();
      _categoryIdMap[sp.id] = prismId;

      categories.add(
        domain.ConversationCategory(
          id: prismId,
          name: sp.name,
          displayOrder: i,
          createdAt: now,
          modifiedAt: now,
        ),
      );

      // Record which channels belong to this category and their order.
      for (var j = 0; j < sp.channelIds.length; j++) {
        _channelCategoryInfo[sp.channelIds[j]] = (
          categoryId: prismId,
          displayOrder: j,
        );
      }
    }

    return categories;
  }

  /// Map SP channels to Prism conversations.
  List<domain.Conversation> _mapChannels(List<SpChannel> channels) {
    final conversations = <domain.Conversation>[];

    for (final ch in channels) {
      final prismId = _channelIdMap[ch.id] ?? _uuid.v4();
      _channelIdMap[ch.id] = prismId;

      // Resolve participant IDs.
      final participantIds = <String>[];
      for (final mId in ch.memberIds) {
        final resolved = _memberIdMap[mId];
        if (resolved != null) {
          participantIds.add(resolved);
        }
      }

      // Look up category info if this channel belongs to a category.
      final catInfo = _channelCategoryInfo[ch.id];

      conversations.add(
        domain.Conversation(
          id: prismId,
          createdAt: ch.createdAt ?? DateTime.now(),
          lastActivityAt: ch.createdAt ?? DateTime.now(),
          title: ch.name,
          description: ch.desc,
          isDirectMessage: participantIds.length <= 2,
          participantIds: participantIds,
          categoryId: catInfo?.categoryId,
          displayOrder: catInfo?.displayOrder ?? 0,
        ),
      );
    }

    return conversations;
  }

  /// Map SP messages to Prism chat messages.
  ///
  /// Uses a two-pass approach so that reply threading is preserved:
  ///   Pass 1 — generate stable Prism UUIDs and collect (prismId → spReplyTo).
  ///   Pass 2 — resolve spReplyTo IDs to Prism UUIDs and set replyToId.
  List<domain.ChatMessage> _mapMessages(
    List<SpMessage> spMessages,
    List<String> warnings,
  ) {
    // Pass 1: assign Prism UUIDs, build lookup maps.
    final spIdToPrismId = <String, String>{};
    final prismIdToSpReplyTo = <String, String?>{};
    final mapped = <domain.ChatMessage>[];

    for (final msg in spMessages) {
      // Resolve conversation ID.
      final conversationId = _channelIdMap[msg.channelId];
      if (conversationId == null) {
        // Skip messages for unknown channels.
        continue;
      }

      if (msg.content.isEmpty) continue;

      // Resolve sender.
      String? authorId;
      if (msg.senderId != null) {
        authorId = _memberIdMap[msg.senderId!];
      }

      // Only treat updatedAt as an edit if it differs from the original
      // timestamp by more than 1 second (avoids false positives from
      // clock skew in SP exports that set both fields to the same value).
      DateTime? editedAt;
      if (msg.updatedAt != null &&
          msg.updatedAt!.difference(msg.timestamp).abs() >
              const Duration(seconds: 1)) {
        editedAt = msg.updatedAt;
      }

      final prismId = _uuid.v4();
      spIdToPrismId[msg.id] = prismId;
      prismIdToSpReplyTo[prismId] = msg.replyTo;

      mapped.add(
        domain.ChatMessage(
          id: prismId,
          content: msg.content,
          timestamp: msg.timestamp,
          editedAt: editedAt,
          authorId: authorId,
          conversationId: conversationId,
        ),
      );
    }

    // Pass 2: set replyToId where the referenced SP message was also imported.
    final result = mapped.map((m) {
      final spReplyTo = prismIdToSpReplyTo[m.id];
      if (spReplyTo == null) return m;
      final replyPrismId = spIdToPrismId[spReplyTo];
      if (replyPrismId == null) return m;
      return m.copyWith(replyToId: replyPrismId);
    }).toList();

    // Update conversation lastActivityAt based on latest message.
    // This is handled by the importer when inserting.

    return result;
  }

  /// Map SP notes to Prism notes.
  List<domain.Note> _mapNotes(List<SpNote> spNotes, List<String> warnings) {
    final notes = <domain.Note>[];
    for (final sp in spNotes) {
      if (sp.body.isEmpty && sp.title.isEmpty) continue;

      String? prismMemberId;
      if (sp.memberId != null) {
        prismMemberId = _memberIdMap[sp.memberId!];
        if (prismMemberId == null) {
          warnings.add(
            'Note "${sp.title}": member "${sp.memberId}" not found, '
            'note will not be linked to a member.',
          );
        }
      }

      String? colorHex = sp.color;
      if (colorHex != null) {
        if (!colorHex.startsWith('#')) colorHex = '#$colorHex';
        if (colorHex == '#') colorHex = null;
      }

      notes.add(
        domain.Note(
          id: _uuid.v4(),
          title: sp.title.isEmpty ? 'Untitled' : sp.title,
          body: sp.body,
          colorHex: colorHex,
          memberId: prismMemberId,
          date: sp.date,
          createdAt: sp.date,
          modifiedAt: sp.date,
        ),
      );
    }
    return notes;
  }

  /// Map SP comments to Prism front session comments.
  List<domain.FrontSessionComment> _mapFrontComments(
    List<SpComment> spComments,
    List<String> warnings,
  ) {
    final comments = <domain.FrontSessionComment>[];
    for (final sp in spComments) {
      if (sp.text.isEmpty) continue;

      // Only map comments on frontHistory entries.
      if (sp.collection != 'frontHistory') continue;

      final sessionId = _sessionIdMap[sp.documentId];
      if (sessionId == null) {
        // Legacy warning path for orphan comments. CF-driven drops are
        // counted separately via _cfDroppedComments and aggregated at the
        // end of mapAll — but we can't distinguish here without extra
        // bookkeeping, so keep the per-comment warning (matches pre-v2
        // behavior) and also bump the dropped counter.
        _cfDroppedComments++;
        warnings.add(
          'Comment ${sp.id}: front session "${sp.documentId}" not found, '
          'comment skipped.',
        );
        continue;
      }

      comments.add(
        domain.FrontSessionComment(
          id: _uuid.v4(),
          body: sp.text,
          timestamp: sp.time,
          // targetTime anchors the comment to the moment in time it references.
          // Per §3.5, comments attach to a timestamp (not a session FK).
          // Use sp.time as the target — it's the user-meaningful "when" for
          // the comment.  The session id is tracked via _sessionIdMap for
          // comment-orphan detection above but is no longer stored on the row.
          targetTime: sp.time,
          createdAt: sp.time,
        ),
      );
    }
    return comments;
  }

  /// Map SP custom field definitions to Prism custom fields.
  List<domain.CustomField> _mapCustomFieldDefs(
    List<SpCustomFieldDef> spFields,
  ) {
    final fields = <domain.CustomField>[];
    for (var i = 0; i < spFields.length; i++) {
      final sp = spFields[i];
      final prismId = _fieldIdMap[sp.id] ?? _uuid.v4();
      _fieldIdMap[sp.id] = prismId;

      // Map SP integer type to Prism type.
      // SP types: 0=text, 1=color, 2=date, 3=month, 4=year, 5=monthYear, 6=timestamp, 7=monthDay
      final fieldType = switch (sp.type) {
        1 => domain.CustomFieldType.color,
        2 || 3 || 4 || 5 || 6 || 7 => domain.CustomFieldType.date,
        _ => domain.CustomFieldType.text,
      };

      final datePrecision = switch (sp.type) {
        2 => domain.DatePrecision.full,
        3 => domain.DatePrecision.month,
        4 => domain.DatePrecision.year,
        5 => domain.DatePrecision.monthYear,
        6 => domain.DatePrecision.timestamp,
        7 => domain.DatePrecision.monthDay,
        _ => null,
      };

      fields.add(
        domain.CustomField(
          id: prismId,
          name: sp.name,
          fieldType: fieldType,
          datePrecision: datePrecision,
          displayOrder: i,
          createdAt: DateTime.now(),
        ),
      );
    }
    return fields;
  }

  /// Extract custom field values from SP member info maps.
  List<domain.CustomFieldValue> _mapCustomFieldValues(
    List<SpMember> spMembers,
    List<String> warnings,
  ) {
    final values = <domain.CustomFieldValue>[];
    for (final sp in spMembers) {
      if (sp.info.isEmpty) continue;
      final prismMemberId = _memberIdMap[sp.id];
      if (prismMemberId == null) continue;

      for (final entry in sp.info.entries) {
        final fieldId = _fieldIdMap[entry.key];
        if (fieldId == null) continue; // Field definition not found.

        final rawValue = entry.value;
        if (rawValue == null) continue;

        final value = rawValue.toString();
        if (value.isEmpty) continue;

        values.add(
          domain.CustomFieldValue(
            id: _uuid.v4(),
            customFieldId: fieldId,
            memberId: prismMemberId,
            value: value,
          ),
        );
      }
    }
    return values;
  }

  /// Map SP groups to Prism member groups.
  List<domain.MemberGroup> _mapGroups(List<SpGroup> spGroups) {
    final groups = <domain.MemberGroup>[];

    // First pass: create all groups and build the ID map.
    for (var i = 0; i < spGroups.length; i++) {
      final sp = spGroups[i];
      final prismId = _groupIdMap[sp.id] ?? _uuid.v4();
      _groupIdMap[sp.id] = prismId;

      String? colorHex = sp.color;
      if (colorHex != null) {
        if (!colorHex.startsWith('#')) colorHex = '#$colorHex';
        if (colorHex == '#') colorHex = null;
      }

      // Resolve parent if already mapped; "root" means top-level.
      String? parentGroupId;
      if (sp.parent != null && sp.parent != 'root') {
        parentGroupId = _groupIdMap[sp.parent!];
      }

      groups.add(
        domain.MemberGroup(
          id: prismId,
          name: sp.name,
          description: sp.desc,
          colorHex: colorHex,
          emoji: sp.emoji,
          displayOrder: i,
          parentGroupId: parentGroupId,
          createdAt: DateTime.now(),
        ),
      );
    }

    // Second pass: fix up any parent references that couldn't resolve in the
    // first pass (child appeared before parent in the list).
    for (var i = 0; i < spGroups.length; i++) {
      final sp = spGroups[i];
      if (sp.parent != null &&
          sp.parent != 'root' &&
          groups[i].parentGroupId == null) {
        final resolvedParent = _groupIdMap[sp.parent!];
        if (resolvedParent != null) {
          groups[i] = groups[i].copyWith(parentGroupId: resolvedParent);
        }
      }
    }

    return groups;
  }

  /// Extract group memberships from SP group data.
  /// Returns list of (groupId, memberId) pairs.
  List<MapEntry<String, String>> _mapGroupMemberships(
    List<SpGroup> spGroups,
    List<String> warnings,
  ) {
    final memberships = <MapEntry<String, String>>[];
    for (final sp in spGroups) {
      final prismGroupId = _groupIdMap[sp.id];
      if (prismGroupId == null) continue;

      for (final spMemberId in sp.memberIds) {
        final prismMemberId = _memberIdMap[spMemberId];
        if (prismMemberId == null) {
          warnings.add(
            'Group "${sp.name}": member "$spMemberId" not found, '
            'membership skipped.',
          );
          continue;
        }
        memberships.add(MapEntry(prismGroupId, prismMemberId));
      }
    }
    return memberships;
  }

  /// Map SP board messages to DM conversations + chat messages.
  ({List<domain.Conversation> conversations, List<domain.ChatMessage> messages})
  _mapBoardMessages(List<SpBoardMessage> boardMsgs, List<String> warnings) {
    if (boardMsgs.isEmpty) {
      return (
        conversations: <domain.Conversation>[],
        messages: <domain.ChatMessage>[],
      );
    }

    // Group by (writtenBy, writtenFor) pair → DM conversation.
    final dmConvMap = <String, String>{}; // pairKey → conversationId
    final conversations = <domain.Conversation>[];
    final messages = <domain.ChatMessage>[];

    for (final bm in boardMsgs) {
      if (bm.message.isEmpty) continue;

      final byId = bm.writtenBy != null ? _memberIdMap[bm.writtenBy!] : null;
      final forId = bm.writtenFor != null ? _memberIdMap[bm.writtenFor!] : null;

      if (byId == null && forId == null) {
        warnings.add(
          'Board message ${bm.id}: both writtenBy and writtenFor unknown, '
          'message skipped.',
        );
        continue;
      }

      // Create a stable key for the DM pair (order-independent).
      final ids = [byId ?? '', forId ?? '']..sort();
      final pairKey = ids.join('_');

      if (!dmConvMap.containsKey(pairKey)) {
        final convId = _uuid.v4();
        dmConvMap[pairKey] = convId;

        final participantIds = <String>[
          ?byId,
          if (forId != null && forId != byId) forId,
        ];

        conversations.add(
          domain.Conversation(
            id: convId,
            createdAt: bm.writtenAt,
            lastActivityAt: bm.writtenAt,
            title: bm.title,
            emoji: '\u{1F4DD}',
            isDirectMessage: true,
            participantIds: participantIds,
          ),
        );
      }

      final convId = dmConvMap[pairKey]!;

      final content = bm.title != null && bm.title!.isNotEmpty
          ? '**${bm.title}**\n${bm.message}'
          : bm.message;

      messages.add(
        domain.ChatMessage(
          id: _uuid.v4(),
          content: content,
          timestamp: bm.writtenAt,
          authorId: byId,
          conversationId: convId,
        ),
      );
    }

    return (conversations: conversations, messages: messages);
  }

  /// Map SP automated and repeated timers to Prism reminders.
  List<domain.Reminder> _mapTimers(
    List<SpAutomatedTimer> automatedTimers,
    List<SpRepeatedTimer> repeatedTimers,
    List<String> warnings,
  ) {
    final reminders = <domain.Reminder>[];
    final now = DateTime.now();

    // Automated timers → onFrontChange reminders.
    //
    // SP's `type` field selects the target:
    //   0 = specific member    → resolve via _memberIdMap
    //   1 = custom front       → resolve via _memberIdMap (custom fronts are
    //                            imported as tagged members and share the
    //                            same id map)
    //   2 = any front change   → no target; fires on every switch
    //
    // If the target id doesn't resolve (archived in SP, missing from the
    // export, etc.), we drop the target (reminder becomes "any front change")
    // and count it for the import disclosure.
    var droppedTargets = 0;
    var resolvedTargets = 0;
    for (final timer in automatedTimers) {
      final name = timer.name.isNotEmpty ? timer.name : 'Imported Timer';
      final message = timer.message ?? name;

      String? targetMemberId;
      final type = timer.type;
      // type == 1 → CF target. Apply per-CF disposition.
      if (type == 1) {
        final spId = timer.targetId;
        final disposition = spId != null ? _cfDispositionById[spId] : null;
        if (disposition == CfDisposition.convertToSleep ||
            disposition == CfDisposition.skip) {
          // Drop the timer entirely (sleep/skip semantics don't translate).
          _cfTimersRemoved++;
          continue;
        }
        if (spId != null) {
          final resolved = _memberIdMap[spId];
          if (resolved != null) {
            targetMemberId = resolved;
            resolvedTargets++;
          } else {
            // CF that's no longer a member (mergeAsNote) or an unknown id.
            if (disposition == CfDisposition.mergeAsNote) {
              _cfTimerTargetsDropped++;
            } else {
              droppedTargets++;
            }
          }
        } else {
          droppedTargets++;
        }
      } else if (type == 0) {
        final spId = timer.targetId;
        if (spId != null) {
          final resolved = _memberIdMap[spId];
          if (resolved != null) {
            targetMemberId = resolved;
            resolvedTargets++;
          } else {
            droppedTargets++;
          }
        } else {
          droppedTargets++;
        }
      }

      reminders.add(
        domain.Reminder(
          id: _uuid.v4(),
          name: name,
          message: message,
          trigger: domain.ReminderTrigger.onFrontChange,
          delayHours: timer.delayHours?.toInt(),
          targetMemberId: targetMemberId,
          isActive: timer.enabled,
          createdAt: now,
          modifiedAt: now,
        ),
      );
    }

    // Surface target-resolution stats for the import disclosure screen. The
    // "fires only when Prism is running" caveat is part of the honesty copy
    // in CreateReminderSheet; we restate it here so users reviewing the
    // import preview understand the local-only nature of member-targeted
    // reminders.
    if (resolvedTargets > 0) {
      warnings.add(
        '$resolvedTargets imported timer${resolvedTargets == 1 ? '' : 's'} '
        'will fire only when Prism is running and sees the switch.',
      );
    }
    if (droppedTargets > 0) {
      warnings.add(
        '$droppedTargets imported timer${droppedTargets == 1 ? '' : 's'} '
        'had a target that could not be resolved and will fire on any front '
        'change.',
      );
    }

    // Repeated timers → scheduled reminders.
    for (final timer in repeatedTimers) {
      final name = timer.name.isNotEmpty ? timer.name : 'Imported Timer';
      final message = timer.message ?? name;

      reminders.add(
        domain.Reminder(
          id: _uuid.v4(),
          name: name,
          message: message,
          trigger: domain.ReminderTrigger.scheduled,
          intervalDays: timer.intervalDays,
          timeOfDay: timer.timeOfDay,
          isActive: timer.enabled,
          createdAt: now,
          modifiedAt: now,
        ),
      );
    }

    return reminders;
  }

  /// Map SP polls to Prism polls.
  List<domain.Poll> _mapPolls(List<SpPoll> spPolls) {
    final polls = <domain.Poll>[];

    for (final sp in spPolls) {
      if (sp.question.isEmpty) continue;

      // Build options with colors.
      final options = <domain.PollOption>[];
      for (var i = 0; i < sp.options.length; i++) {
        final spOption = sp.options[i];
        String? colorHex = spOption.color;
        if (colorHex != null) {
          colorHex = colorHex.replaceFirst('#', '');
          if (colorHex.isEmpty) colorHex = null;
        }

        options.add(
          domain.PollOption(
            id: _uuid.v4(),
            text: spOption.name,
            sortOrder: i,
            colorHex: colorHex,
          ),
        );
      }

      // Build a lookup from option name to PollOption for vote resolution.
      final optionByName = <String, domain.PollOption>{};
      for (final opt in options) {
        optionByName[opt.text] = opt;
      }

      // Collect votes grouped by option ID.
      final votesByOptionId = <String, List<domain.PollVote>>{};
      for (final vote in sp.votes) {
        final prismMemberId = _memberIdMap[vote.memberId];
        if (prismMemberId == null) continue; // Unknown member, skip.

        final matchedOption = optionByName[vote.optionName];
        if (matchedOption == null) continue; // No matching option, skip.

        votesByOptionId
            .putIfAbsent(matchedOption.id, () => [])
            .add(
              domain.PollVote(
                id: _uuid.v4(),
                memberId: prismMemberId,
                votedAt: DateTime.now(),
                responseText: vote.comment,
              ),
            );
      }

      // Attach votes to their options.
      final optionsWithVotes = options.map((opt) {
        final votes = votesByOptionId[opt.id];
        return votes != null ? opt.copyWith(votes: votes) : opt;
      }).toList();

      polls.add(
        domain.Poll(
          id: _uuid.v4(),
          question: sp.question,
          description: sp.description,
          allowsMultipleVotes: sp.allowMultiple,
          isClosed: sp.endDate != null && sp.endDate!.isBefore(DateTime.now()),
          expiresAt: sp.endDate,
          createdAt: DateTime.now(),
          options: optionsWithVotes,
        ),
      );
    }

    return polls;
  }
}

/// Internal classification of an id referenced by an SP front-history entry.
enum _IdKind {
  /// Id resolves to a real Prism member via `_memberIdMap`.
  realMember,

  /// SP CF with disposition `importAsMember` (resolved via `_memberIdMap`).
  cfMember,

  /// SP CF with disposition `mergeAsNote`.
  cfNote,

  /// SP CF with disposition `convertToSleep`.
  cfSleep,

  /// SP CF with disposition `skip`.
  cfSkip,

  /// SP's literal "unknown" primary sentinel.
  unknownSentinel,

  /// Id missing/empty or unresolvable.
  missing,
}
