import 'package:uuid/uuid.dart';

import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/models/fronting_session.dart' as domain;
import 'package:prism_plurality/domain/models/conversation.dart' as domain;
import 'package:prism_plurality/domain/models/chat_message.dart' as domain;
import 'package:prism_plurality/domain/models/poll.dart' as domain;
import 'package:prism_plurality/domain/models/poll_option.dart' as domain;
import 'package:prism_plurality/domain/models/note.dart' as domain;
import 'package:prism_plurality/domain/models/front_session_comment.dart'
    as domain;
import 'package:prism_plurality/domain/models/custom_field.dart' as domain;
import 'package:prism_plurality/domain/models/custom_field_value.dart'
    as domain;
import 'package:prism_plurality/domain/models/member_group.dart' as domain;
import 'package:prism_plurality/domain/models/reminder.dart' as domain;
import 'package:prism_plurality/features/migration/services/sp_parser.dart';

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
  final List<domain.Reminder> reminders;
  final List<String> warnings;

  /// Map of SP member ID to avatar URL (for download later).
  final Map<String, String> avatarUrls;

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
    this.reminders = const [],
    required this.warnings,
    required this.avatarUrls,
  });
}

/// Maps Simply Plural entities to Prism domain models.
class SpMapper {
  static const _uuid = Uuid();

  /// Map of SP member ID to Prism UUID.
  final Map<String, String> _memberIdMap = {};

  /// Map of SP channel ID to Prism conversation UUID.
  final Map<String, String> _channelIdMap = {};

  /// Map of SP front history ID to Prism session UUID.
  final Map<String, String> _sessionIdMap = {};

  /// Map of SP group ID to Prism group UUID.
  final Map<String, String> _groupIdMap = {};

  /// Map of SP custom field ID to Prism field UUID.
  final Map<String, String> _fieldIdMap = {};

  /// Resolve SP member ID to Prism UUID.
  String? resolveMemberId(String spId) => _memberIdMap[spId];

  /// Resolve SP channel ID to Prism conversation UUID.
  String? resolveChannelId(String spId) => _channelIdMap[spId];

  /// Map all SP export data to Prism domain models.
  MappedData mapAll(SpExportData data) {
    final warnings = <String>[];
    final avatarUrls = <String, String>{};

    // 1. Map members (including custom fronts as tagged members).
    final members = _mapMembers(data.members, data.customFronts, avatarUrls);

    // 2. Map front history to sessions.
    final sessions = _mapFrontHistory(data.frontHistory, warnings);

    // 3. Map channels to conversations.
    final conversations = _mapChannels(data.channels);

    // 4. Add a board conversation if there are board messages.
    final hasBoardMessages = data.messages.any((m) => m.channelId == '_board');
    if (hasBoardMessages) {
      final boardId = _uuid.v4();
      _channelIdMap['_board'] = boardId;
      conversations.add(domain.Conversation(
        id: boardId,
        createdAt: DateTime.now(),
        lastActivityAt: DateTime.now(),
        title: 'Board Messages',
        emoji: '\u{1F4CB}',
        isDirectMessage: true,
        participantIds: const [],
      ));
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
    final customFieldValues =
        _mapCustomFieldValues(data.members, warnings);

    // 10. Map groups.
    final groups = _mapGroups(data.groups);
    final groupMemberships = _mapGroupMemberships(data.groups, warnings);

    // 11. Map board messages as DM conversations + messages.
    final boardResult =
        _mapBoardMessages(data.boardMessages, warnings);
    conversations.addAll(boardResult.conversations);
    messages.addAll(boardResult.messages);

    // 12. Map timers to reminders.
    final reminders = _mapTimers(
        data.automatedTimers, data.repeatedTimers, warnings);

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
      reminders: reminders,
      warnings: warnings,
      avatarUrls: avatarUrls,
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
      final prismId = _uuid.v4();
      _memberIdMap[sp.id] = prismId;

      // Track avatar URL for later download.
      if (sp.avatarUrl != null && sp.avatarUrl!.isNotEmpty) {
        avatarUrls[prismId] = sp.avatarUrl!;
      }

      // Normalize SP color to hex without '#'.
      String? colorHex = sp.color;
      if (colorHex != null) {
        colorHex = colorHex.replaceFirst('#', '');
        if (colorHex.isEmpty) colorHex = null;
      }

      members.add(domain.Member(
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
      ));
    }

    // Map custom fronts as tagged members.
    for (var i = 0; i < customFronts.length; i++) {
      final cf = customFronts[i];
      final prismId = _uuid.v4();
      _memberIdMap[cf.id] = prismId;

      if (cf.avatarUrl != null && cf.avatarUrl!.isNotEmpty) {
        avatarUrls[prismId] = cf.avatarUrl!;
      }

      String? colorHex = cf.color;
      if (colorHex != null) {
        colorHex = colorHex.replaceFirst('#', '');
        if (colorHex.isEmpty) colorHex = null;
      }

      members.add(domain.Member(
        id: prismId,
        name: cf.name,
        emoji: '\u{1F3F7}\uFE0F', // tag emoji to indicate custom front
        bio: cf.desc,
        isActive: true,
        createdAt: DateTime.now(),
        displayOrder: spMembers.length + i,
        customColorEnabled: colorHex != null,
        customColorHex: colorHex,
      ));
    }

    return members;
  }

  /// Map SP front history to Prism fronting sessions.
  List<domain.FrontingSession> _mapFrontHistory(
    List<SpFrontHistory> history,
    List<String> warnings,
  ) {
    final sessions = <domain.FrontingSession>[];

    for (final entry in history) {
      // Resolve main fronter.
      String? prismMemberId;
      if (entry.memberId != null && entry.memberId != 'unknown') {
        prismMemberId = _memberIdMap[entry.memberId!];
        if (prismMemberId == null) {
          warnings.add(
            'Front entry ${entry.id}: member "${entry.memberId}" not found, '
            'session will have no primary fronter.',
          );
        }
      }

      // Resolve co-fronters.
      final coFronterIds = <String>[];
      for (final cfId in entry.coFronters) {
        final resolved = _memberIdMap[cfId];
        if (resolved != null) {
          coFronterIds.add(resolved);
        }
      }

      final sessionId = _uuid.v4();
      _sessionIdMap[entry.id] = sessionId;

      sessions.add(domain.FrontingSession(
        id: sessionId,
        startTime: entry.startTime,
        endTime: entry.endTime,
        memberId: prismMemberId,
        coFronterIds: coFronterIds,
        notes: entry.comment ?? entry.customStatus,
      ));
    }

    return sessions;
  }

  /// Map SP channels to Prism conversations.
  List<domain.Conversation> _mapChannels(List<SpChannel> channels) {
    final conversations = <domain.Conversation>[];

    for (final ch in channels) {
      final prismId = _uuid.v4();
      _channelIdMap[ch.id] = prismId;

      // Resolve participant IDs.
      final participantIds = <String>[];
      for (final mId in ch.memberIds) {
        final resolved = _memberIdMap[mId];
        if (resolved != null) {
          participantIds.add(resolved);
        }
      }

      conversations.add(domain.Conversation(
        id: prismId,
        createdAt: ch.createdAt ?? DateTime.now(),
        lastActivityAt: ch.createdAt ?? DateTime.now(),
        title: ch.name,
        isDirectMessage: participantIds.length <= 2,
        participantIds: participantIds,
      ));
    }

    return conversations;
  }

  /// Map SP messages to Prism chat messages.
  List<domain.ChatMessage> _mapMessages(
    List<SpMessage> spMessages,
    List<String> warnings,
  ) {
    final messages = <domain.ChatMessage>[];

    for (final msg in spMessages) {
      // Resolve conversation ID.
      final conversationId = _channelIdMap[msg.channelId];
      if (conversationId == null) {
        // Skip messages for unknown channels.
        continue;
      }

      // Resolve sender.
      String? authorId;
      if (msg.senderId != null) {
        authorId = _memberIdMap[msg.senderId!];
      }

      if (msg.content.isEmpty) continue;

      messages.add(domain.ChatMessage(
        id: _uuid.v4(),
        content: msg.content,
        timestamp: msg.timestamp,
        authorId: authorId,
        conversationId: conversationId,
      ));
    }

    // Update conversation lastActivityAt based on latest message.
    // This is handled by the importer when inserting.

    return messages;
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

      notes.add(domain.Note(
        id: _uuid.v4(),
        title: sp.title.isEmpty ? 'Untitled' : sp.title,
        body: sp.body,
        colorHex: colorHex,
        memberId: prismMemberId,
        date: sp.date,
        createdAt: sp.date,
        modifiedAt: sp.date,
      ));
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
        warnings.add(
          'Comment ${sp.id}: front session "${sp.documentId}" not found, '
          'comment skipped.',
        );
        continue;
      }

      comments.add(domain.FrontSessionComment(
        id: _uuid.v4(),
        sessionId: sessionId,
        body: sp.text,
        timestamp: sp.time,
        createdAt: sp.time,
      ));
    }
    return comments;
  }

  /// Map SP custom field definitions to Prism custom fields.
  List<domain.CustomField> _mapCustomFieldDefs(
      List<SpCustomFieldDef> spFields) {
    final fields = <domain.CustomField>[];
    for (var i = 0; i < spFields.length; i++) {
      final sp = spFields[i];
      final prismId = _uuid.v4();
      _fieldIdMap[sp.id] = prismId;

      // Map SP type to Prism type.
      final fieldType = switch (sp.type.toLowerCase()) {
        'color' => domain.CustomFieldType.color,
        'date' => domain.CustomFieldType.date,
        _ => domain.CustomFieldType.text,
      };

      fields.add(domain.CustomField(
        id: prismId,
        name: sp.name,
        fieldType: fieldType,
        displayOrder: i,
        createdAt: DateTime.now(),
      ));
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

        values.add(domain.CustomFieldValue(
          id: _uuid.v4(),
          customFieldId: fieldId,
          memberId: prismMemberId,
          value: value,
        ));
      }
    }
    return values;
  }

  /// Map SP groups to Prism member groups.
  List<domain.MemberGroup> _mapGroups(List<SpGroup> spGroups) {
    final groups = <domain.MemberGroup>[];
    for (var i = 0; i < spGroups.length; i++) {
      final sp = spGroups[i];
      final prismId = _uuid.v4();
      _groupIdMap[sp.id] = prismId;

      String? colorHex = sp.color;
      if (colorHex != null) {
        if (!colorHex.startsWith('#')) colorHex = '#$colorHex';
        if (colorHex == '#') colorHex = null;
      }

      groups.add(domain.MemberGroup(
        id: prismId,
        name: sp.name,
        description: sp.desc,
        colorHex: colorHex,
        displayOrder: i,
        createdAt: DateTime.now(),
      ));
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
  ({
    List<domain.Conversation> conversations,
    List<domain.ChatMessage> messages,
  }) _mapBoardMessages(
    List<SpBoardMessage> boardMsgs,
    List<String> warnings,
  ) {
    if (boardMsgs.isEmpty) {
      return (conversations: <domain.Conversation>[], messages: <domain.ChatMessage>[]);
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
          if (byId != null) byId,
          if (forId != null && forId != byId) forId,
        ];

        conversations.add(domain.Conversation(
          id: convId,
          createdAt: bm.writtenAt,
          lastActivityAt: bm.writtenAt,
          title: bm.title,
          emoji: '\u{1F4DD}',
          isDirectMessage: true,
          participantIds: participantIds,
        ));
      }

      final convId = dmConvMap[pairKey]!;

      final content = bm.title != null && bm.title!.isNotEmpty
          ? '**${bm.title}**\n${bm.message}'
          : bm.message;

      messages.add(domain.ChatMessage(
        id: _uuid.v4(),
        content: content,
        timestamp: bm.writtenAt,
        authorId: byId,
        conversationId: convId,
      ));
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
    for (final timer in automatedTimers) {
      final name = timer.name.isNotEmpty ? timer.name : 'Imported Timer';
      final message = timer.message ?? name;

      reminders.add(domain.Reminder(
        id: _uuid.v4(),
        name: name,
        message: message,
        trigger: domain.ReminderTrigger.onFrontChange,
        delayHours: timer.delayHours?.toInt(),
        isActive: timer.enabled,
        createdAt: now,
        modifiedAt: now,
      ));
    }

    // Repeated timers → scheduled reminders.
    for (final timer in repeatedTimers) {
      final name = timer.name.isNotEmpty ? timer.name : 'Imported Timer';
      final message = timer.message ?? name;

      reminders.add(domain.Reminder(
        id: _uuid.v4(),
        name: name,
        message: message,
        trigger: domain.ReminderTrigger.scheduled,
        intervalDays: timer.intervalDays,
        timeOfDay: timer.timeOfDay,
        isActive: timer.enabled,
        createdAt: now,
        modifiedAt: now,
      ));
    }

    return reminders;
  }

  /// Map SP polls to Prism polls.
  List<domain.Poll> _mapPolls(List<SpPoll> spPolls) {
    final polls = <domain.Poll>[];

    for (final sp in spPolls) {
      if (sp.question.isEmpty) continue;

      final options = <domain.PollOption>[];
      for (var i = 0; i < sp.options.length; i++) {
        options.add(domain.PollOption(
          id: _uuid.v4(),
          text: sp.options[i],
          sortOrder: i,
        ));
      }

      polls.add(domain.Poll(
        id: _uuid.v4(),
        question: sp.question,
        allowsMultipleVotes: sp.allowMultiple,
        isClosed: sp.endDate != null && sp.endDate!.isBefore(DateTime.now()),
        expiresAt: sp.endDate,
        createdAt: DateTime.now(),
        options: options,
      ));
    }

    return polls;
  }
}
