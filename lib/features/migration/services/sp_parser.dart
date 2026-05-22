import 'dart:convert';

final _spBase64Pattern = RegExp(r'^[A-Za-z0-9+/]+={0,2}$');
final _shortPlainChatTokenPattern = RegExp(r'^[A-Za-z0-9]{1,16}$');

/// Parse an SP timestamp string to a UTC [DateTime].
///
/// SP exports emit ISO-8601 strings without a timezone offset (e.g.
/// `"2023-11-14T16:13:20.000"`). `DateTime.tryParse` interprets offset-less
/// strings in the runner's *local* timezone, which makes byte-stable goldens
/// impossible across machines in different zones. We instead assume UTC for
/// offset-less strings (SP server emits UTC by convention) and force any
/// already-offset string back to UTC so every parsed instant is in the same
/// frame.
DateTime? _parseUtc(String s) {
  if (s.isEmpty) return null;
  // Treat offset-less ISO-8601 strings as UTC. Detect any explicit zone
  // marker (`Z` or `±HH:MM` / `±HHMM`) so we don't double-suffix.
  final hasZone =
      s.endsWith('Z') ||
      s.endsWith('z') ||
      RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(s);
  final normalized = hasZone ? s : '${s}Z';
  return DateTime.tryParse(normalized)?.toUtc();
}

Map<String, String> extractSpCustomFieldValueKeyMap(dynamic rawFields) {
  if (rawFields is! Map) return const {};

  final valueKeyMap = <String, String>{};
  for (final entry in rawFields.entries) {
    final alias = entry.key.toString();
    final rawField = entry.value;
    if (alias.isEmpty || rawField is! Map) continue;

    final fieldId = rawField['name']?.toString();
    if (fieldId == null || fieldId.isEmpty) continue;
    valueKeyMap[alias] = fieldId;
  }

  return valueKeyMap;
}

Map<String, dynamic> normalizeSpMemberJsonInfoKeys(
  Map<String, dynamic> memberJson,
  Map<String, String> customFieldValueKeyMap,
) {
  final rawInfo = memberJson['info'];
  if (customFieldValueKeyMap.isEmpty || rawInfo is! Map) {
    return memberJson;
  }

  final normalizedInfo = <String, dynamic>{};
  for (final entry in rawInfo.entries) {
    final rawKey = entry.key.toString();
    final normalizedKey = customFieldValueKeyMap[rawKey] ?? rawKey;
    normalizedInfo[normalizedKey] = entry.value;
  }

  return {...memberJson, 'info': normalizedInfo};
}

List<int>? _decodeStrictSpBase64(String value) {
  if (value.isEmpty ||
      value.trim() != value ||
      value.length % 4 != 0 ||
      !_spBase64Pattern.hasMatch(value)) {
    return null;
  }

  final firstPadding = value.indexOf('=');
  if (firstPadding != -1 && firstPadding < value.length - 2) {
    return null;
  }

  try {
    return base64Decode(value);
  } on FormatException {
    return null;
  }
}

bool _looksLikePlainTextBytes(List<int> bytes) {
  try {
    final decoded = utf8.decode(bytes, allowMalformed: false);
    if (decoded.isEmpty) return false;
    final runes = decoded.runes.toList();
    final printable = runes.where((rune) {
      return rune == 0x09 ||
          rune == 0x0A ||
          rune == 0x0D ||
          (rune >= 0x20 && rune != 0x7F);
    }).length;
    return printable / runes.length >= 0.85;
  } on FormatException {
    return false;
  }
}

bool _looksLikeEncryptedSpMessage(String content, dynamic rawIv) {
  if (rawIv == null) return false;
  final iv = rawIv.toString();
  final ivBytes = _decodeStrictSpBase64(iv);
  if (ivBytes == null || ivBytes.length != 16) return false;

  // SP exports can leave `iv` after decrypting `message`.
  // Short plaintext like "test" is also valid base64.
  if (_shortPlainChatTokenPattern.hasMatch(content)) return false;

  final contentBytes = _decodeStrictSpBase64(content);
  if (contentBytes == null || contentBytes.isEmpty) return false;

  return !_looksLikePlainTextBytes(contentBytes);
}

/// Parsed Simply Plural export data.
class SpExportData {
  final List<SpMember> members;
  final List<SpCustomFront> customFronts;
  final List<SpFrontHistory> frontHistory;
  final List<SpGroup> groups;
  final List<SpChannel> channels;
  final List<SpChannelCategory> channelCategories;
  final List<SpMessage> messages;
  final List<SpPoll> polls;
  final List<SpNote> notes;
  final List<SpComment> comments;
  final List<SpCustomFieldDef> customFields;
  final List<SpBoardMessage> boardMessages;
  final List<SpAutomatedTimer> automatedTimers;
  final List<SpRepeatedTimer> repeatedTimers;
  final String? systemName;
  final String? systemColor;
  final String? systemDescription;
  final String? systemId;
  final String? systemAvatarUrl;

  const SpExportData({
    required this.members,
    required this.customFronts,
    required this.frontHistory,
    required this.groups,
    required this.channels,
    this.channelCategories = const [],
    required this.messages,
    required this.polls,
    this.notes = const [],
    this.comments = const [],
    this.customFields = const [],
    this.boardMessages = const [],
    this.automatedTimers = const [],
    this.repeatedTimers = const [],
    this.systemName,
    this.systemColor,
    this.systemDescription,
    this.systemId,
    this.systemAvatarUrl,
  });

  int get totalEntities =>
      members.length +
      customFronts.length +
      frontHistory.length +
      groups.length +
      channels.length +
      channelCategories.length +
      messages.length +
      polls.length +
      notes.length +
      comments.length +
      customFields.length +
      boardMessages.length +
      automatedTimers.length +
      repeatedTimers.length;

  bool get isEmpty => totalEntities == 0;

  int get encryptedChatMessageCount =>
      messages.where((message) => message.looksEncrypted).length;

  bool get hasEncryptedChatMessages => encryptedChatMessageCount > 0;

  SpExportData withoutChat() {
    return SpExportData(
      members: members,
      customFronts: customFronts,
      frontHistory: frontHistory,
      groups: groups,
      channels: const [],
      channelCategories: const [],
      messages: const [],
      polls: polls,
      notes: notes,
      comments: comments,
      customFields: customFields,
      boardMessages: boardMessages,
      automatedTimers: automatedTimers,
      repeatedTimers: repeatedTimers,
      systemName: systemName,
      systemColor: systemColor,
      systemDescription: systemDescription,
      systemId: systemId,
      systemAvatarUrl: systemAvatarUrl,
    );
  }
}

/// SP member structure.
class SpMember {
  final String id;
  final String name;
  final String? pronouns;
  final String? avatarUrl;
  final String? avatarUuid; // MinIO-hosted avatar (new-style uploads)
  final String? uid; // System owner ID — needed to construct avatarUuid URL
  final String? color;
  final String? desc;
  final bool archived;
  final String? pkId;
  final Map<String, dynamic> info;

  const SpMember({
    required this.id,
    required this.name,
    this.pronouns,
    this.avatarUrl,
    this.avatarUuid,
    this.uid,
    this.color,
    this.desc,
    this.archived = false,
    this.pkId,
    this.info = const {},
  });

  factory SpMember.fromJson(Map<String, dynamic> json) {
    return SpMember(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Unknown').toString(),
      pronouns: json['pronouns'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      avatarUuid: json['avatarUuid'] as String?,
      uid: json['uid'] as String?,
      color: json['color'] as String?,
      desc: json['desc'] as String?,
      archived: json['archived'] == true,
      pkId: json['pkId'] != null && json['pkId'].toString().isNotEmpty
          ? json['pkId'].toString()
          : null,
      info: json['info'] is Map<String, dynamic>
          ? json['info'] as Map<String, dynamic>
          : const {},
    );
  }
}

/// SP custom front entry.
class SpCustomFront {
  final String id;
  final String name;
  final String? color;
  final String? desc;
  final String? avatarUrl;

  const SpCustomFront({
    required this.id,
    required this.name,
    this.color,
    this.desc,
    this.avatarUrl,
  });

  factory SpCustomFront.fromJson(Map<String, dynamic> json) {
    return SpCustomFront(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Custom Front').toString(),
      color: json['color'] as String?,
      desc: json['desc'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
    );
  }
}

/// SP front history entry.
///
/// Each row represents one member's continuous presence — the source is
/// already one-row-per-member (§2.6).  `coFronters` is preserved as a struct
/// field so existing callers (e.g. analysis code) continue to compile, but the
/// `fromJson` factory no longer reads `coFronters`/`cofronters` keys from the
/// JSON source: those keys do not exist in any real SP export and were always
/// parsed as an empty list.  The per-member mapping model means co-fronting is
/// an emergent property of overlapping intervals, not a field on an entry.
class SpFrontHistory {
  final String id;
  final String? memberId;
  final List<String> coFronters;
  final DateTime startTime;

  /// Raw `endTime` from the SP export (always present as an int, even for
  /// active sessions).  Use [live] to determine whether the session is
  /// currently active: when [live] is `true`, treat `endTime` as `null`
  /// in the Prism row.
  final DateTime? endTime;

  /// SP `live` flag.  `true` means the session is still active; `endTime`
  /// carries a snapshot value from SP's server clock but must be ignored when
  /// deriving the Prism `end_time` field (set `end_time = NULL` instead).
  final bool live;

  final String? comment;
  final String? customStatus;
  final bool isCustomFront;

  const SpFrontHistory({
    required this.id,
    this.memberId,
    this.coFronters = const [],
    required this.startTime,
    this.endTime,
    this.live = false,
    this.comment,
    this.customStatus,
    this.isCustomFront = false,
  });

  factory SpFrontHistory.fromJson(
    Map<String, dynamic> json, {
    DateTime Function()? now,
  }) {
    final clock = now ?? DateTime.now;
    // SP stores times as epoch milliseconds.
    final startMs = json['startTime'];
    final endMs = json['endTime'];

    DateTime parseTime(dynamic value) {
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
      }
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) {
          return DateTime.fromMillisecondsSinceEpoch(parsed, isUtc: true);
        }
        return _parseUtc(value) ?? clock().toUtc();
      }
      return clock().toUtc();
    }

    // SP `live` flag: true means the session is currently active. When live,
    // endTime must be treated as NULL in the Prism row regardless of the
    // snapshot value SP stores.
    final live = json['live'] == true;

    // Note: coFronters / cofronters keys are NOT read from JSON here.
    // Those keys do not exist in real SP exports; the struct field remains
    // for compatibility with non-import callers (e.g. analysis code that
    // operates on in-memory test data).

    return SpFrontHistory(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      memberId: json['member']?.toString(),
      coFronters: const [],
      startTime: parseTime(startMs),
      endTime: endMs != null ? parseTime(endMs) : null,
      live: live,
      comment: json['comment'] as String?,
      customStatus: json['customStatus'] as String?,
      isCustomFront: json['custom'] == true || json['customFront'] == true,
    );
  }
}

/// SP group structure.
class SpGroup {
  final String id;
  final String name;
  final String? desc;
  final List<String> memberIds;
  final String? color;
  final String? emoji;
  final String? parent;

  const SpGroup({
    required this.id,
    required this.name,
    this.desc,
    this.memberIds = const [],
    this.color,
    this.emoji,
    this.parent,
  });

  factory SpGroup.fromJson(Map<String, dynamic> json) {
    final memberList = <String>[];
    final rawMembers = json['members'];
    if (rawMembers is List) {
      for (final m in rawMembers) {
        memberList.add(m.toString());
      }
    }

    return SpGroup(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Group').toString(),
      desc: json['desc'] as String?,
      memberIds: memberList,
      color: json['color'] as String?,
      emoji: json['emoji'] as String?,
      parent: json['parent'] as String?,
    );
  }
}

/// SP channel structure.
class SpChannel {
  final String id;
  final String? name;
  final String? desc;
  final List<String> memberIds;
  final DateTime? createdAt;

  const SpChannel({
    required this.id,
    this.name,
    this.desc,
    this.memberIds = const [],
    this.createdAt,
  });

  factory SpChannel.fromJson(Map<String, dynamic> json) {
    final memberList = <String>[];
    final rawMembers = json['members'];
    if (rawMembers is List) {
      for (final m in rawMembers) {
        memberList.add(m.toString());
      }
    }

    return SpChannel(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      name: json['name'] as String?,
      desc: json['desc'] as String?,
      memberIds: memberList,
      createdAt: json['createdAt'] != null
          ? _parseUtc(json['createdAt'].toString())
          : null,
    );
  }
}

/// SP message structure.
class SpMessage {
  final String id;
  final String channelId;
  final String? senderId;
  final String content;
  final DateTime timestamp;

  /// SP message _id that this message replies to (reply threading).
  final String? replyTo;

  /// Last-edit timestamp. Null if the message was never edited.
  final DateTime? updatedAt;

  /// True when an SP file export appears to still contain encrypted ciphertext.
  final bool looksEncrypted;

  const SpMessage({
    required this.id,
    required this.channelId,
    this.senderId,
    required this.content,
    required this.timestamp,
    this.replyTo,
    this.updatedAt,
    this.looksEncrypted = false,
  });

  factory SpMessage.fromJson(
    Map<String, dynamic> json,
    String channelId, {
    DateTime Function()? now,
  }) {
    final clock = now ?? DateTime.now;
    DateTime parseTime(dynamic value) {
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
      }
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) {
          return DateTime.fromMillisecondsSinceEpoch(parsed, isUtc: true);
        }
        return _parseUtc(value) ?? clock().toUtc();
      }
      return clock().toUtc();
    }

    DateTime? parseOptionalTime(dynamic value) {
      if (value == null) return null;
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
      }
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) {
          return DateTime.fromMillisecondsSinceEpoch(parsed, isUtc: true);
        }
        return _parseUtc(value);
      }
      return null;
    }

    final replyTo = json['replyTo'] as String?;
    final content = (json['message'] ?? json['content'] ?? '').toString();

    return SpMessage(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      channelId: channelId,
      senderId:
          json['sender']?.toString() ??
          json['writer']?.toString() ??
          json['member']?.toString(),
      content: content,
      timestamp: parseTime(
        json['timestamp'] ?? json['writtenAt'] ?? json['createdAt'],
      ),
      // Only store replyTo if it's a non-empty string (SP uses "" to mean no reply).
      replyTo: (replyTo != null && replyTo.isNotEmpty) ? replyTo : null,
      updatedAt: parseOptionalTime(json['updatedAt'] ?? json['lastUpdated']),
      looksEncrypted: _looksLikeEncryptedSpMessage(content, json['iv']),
    );
  }
}

/// SP poll option with name and optional color.
class SpPollOption {
  final String name;
  final String? color;

  const SpPollOption({required this.name, this.color});
}

/// SP poll vote entry.
class SpPollVote {
  final String memberId;
  final String optionName;
  final String? comment;

  const SpPollVote({
    required this.memberId,
    required this.optionName,
    this.comment,
  });
}

/// SP poll structure.
class SpPoll {
  final String id;
  final String question;
  final String? description;
  final List<SpPollOption> options;
  final List<SpPollVote> votes;
  final bool isCustom;
  final bool allowMultiple;
  final bool allowAbstain;
  final bool allowVeto;
  final DateTime? endDate;

  const SpPoll({
    required this.id,
    required this.question,
    this.description,
    this.options = const [],
    this.votes = const [],
    this.isCustom = false,
    this.allowMultiple = false,
    this.allowAbstain = false,
    this.allowVeto = false,
    this.endDate,
  });

  factory SpPoll.fromJson(
    Map<String, dynamic> json, {
    DateTime Function()? now,
  }) {
    final clock = now ?? DateTime.now;
    DateTime parseTime(dynamic value) {
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
      }
      if (value is num) {
        return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
      }
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) {
          return DateTime.fromMillisecondsSinceEpoch(parsed, isUtc: true);
        }
        return _parseUtc(value) ?? clock().toUtc();
      }
      return clock().toUtc();
    }

    final optionList = <SpPollOption>[];
    final rawOptions = json['options'];
    if (rawOptions is List) {
      for (final o in rawOptions) {
        if (o is Map) {
          optionList.add(
            SpPollOption(
              name: (o['text'] ?? o['name'] ?? o.toString()).toString(),
              color: o['color'] as String?,
            ),
          );
        } else {
          optionList.add(SpPollOption(name: o.toString()));
        }
      }
    }

    final voteList = <SpPollVote>[];
    final rawVotes = json['votes'];
    if (rawVotes is List) {
      for (final v in rawVotes) {
        if (v is Map) {
          final memberId = (v['id'] ?? '').toString();
          final optionName = (v['vote'] ?? '').toString();
          if (memberId.isNotEmpty && optionName.isNotEmpty) {
            voteList.add(
              SpPollVote(
                memberId: memberId,
                optionName: optionName,
                comment: v['comment'] as String?,
              ),
            );
          }
        }
      }
    }

    final rawEndTime = json['endTime'] ?? json['endDate'];

    return SpPoll(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      question: (json['question'] ?? json['title'] ?? json['name'] ?? '')
          .toString(),
      description: json['desc'] as String? ?? json['description'] as String?,
      options: optionList,
      votes: voteList,
      isCustom: json['custom'] == true,
      allowMultiple: json['allowMultiple'] == true,
      allowAbstain: json['allowAbstain'] == true,
      allowVeto: json['allowVeto'] == true,
      endDate: rawEndTime != null ? parseTime(rawEndTime) : null,
    );
  }
}

/// SP note structure.
class SpNote {
  final String id;
  final String title;
  final String body;
  final String? color;
  final String? memberId;
  final DateTime date;

  const SpNote({
    required this.id,
    required this.title,
    required this.body,
    this.color,
    this.memberId,
    required this.date,
  });

  factory SpNote.fromJson(
    Map<String, dynamic> json, {
    DateTime Function()? now,
  }) {
    final clock = now ?? DateTime.now;
    DateTime parseTime(dynamic value) {
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
      }
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) {
          return DateTime.fromMillisecondsSinceEpoch(parsed, isUtc: true);
        }
        return _parseUtc(value) ?? clock().toUtc();
      }
      return clock().toUtc();
    }

    return SpNote(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      title: (json['title'] ?? 'Untitled').toString(),
      body: (json['note'] ?? json['body'] ?? '').toString(),
      color: json['color'] as String?,
      memberId: json['member']?.toString(),
      date: parseTime(json['date'] ?? json['createdAt']),
    );
  }
}

/// SP comment (on front history entries).
class SpComment {
  final String id;
  final String documentId;
  final String collection;
  final String text;
  final DateTime time;

  const SpComment({
    required this.id,
    required this.documentId,
    required this.collection,
    required this.text,
    required this.time,
  });

  factory SpComment.fromJson(
    Map<String, dynamic> json, {
    DateTime Function()? now,
  }) {
    final clock = now ?? DateTime.now;
    DateTime parseTime(dynamic value) {
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
      }
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) {
          return DateTime.fromMillisecondsSinceEpoch(parsed, isUtc: true);
        }
        return _parseUtc(value) ?? clock().toUtc();
      }
      return clock().toUtc();
    }

    return SpComment(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      documentId: (json['documentId'] ?? '').toString(),
      collection: (json['collection'] ?? '').toString(),
      text: (json['text'] ?? json['comment'] ?? '').toString(),
      time: parseTime(json['time'] ?? json['createdAt']),
    );
  }
}

/// SP custom field definition.
class SpCustomFieldDef {
  final String id;
  final String name;
  final int type;
  final String? order;
  final bool supportMarkdown;

  const SpCustomFieldDef({
    required this.id,
    required this.name,
    required this.type,
    this.order,
    this.supportMarkdown = false,
  });

  factory SpCustomFieldDef.fromJson(Map<String, dynamic> json) {
    return SpCustomFieldDef(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Field').toString(),
      type: (json['type'] is int
          ? json['type'] as int
          : int.tryParse(json['type'].toString()) ?? 0),
      order: json['order']?.toString(),
      supportMarkdown: json['supportMarkdown'] == true,
    );
  }
}

/// SP board message (member-to-member messages).
class SpBoardMessage {
  final String id;
  final String? writtenBy;
  final String? writtenFor;
  final String? title;
  final String message;
  final DateTime writtenAt;

  /// Whether the recipient has read this message in Simply Plural.
  ///
  /// When true, the importer sets `members.boardLastReadAt` to at least
  /// [writtenAt] for the recipient, so the Prism inbox starts in a
  /// read state matching what the user saw in SP.
  final bool read;

  const SpBoardMessage({
    required this.id,
    this.writtenBy,
    this.writtenFor,
    this.title,
    required this.message,
    required this.writtenAt,
    this.read = false,
  });

  factory SpBoardMessage.fromJson(
    Map<String, dynamic> json, {
    DateTime Function()? now,
  }) {
    final clock = now ?? DateTime.now;
    DateTime parseTime(dynamic value) {
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
      }
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) {
          return DateTime.fromMillisecondsSinceEpoch(parsed, isUtc: true);
        }
        return _parseUtc(value) ?? clock().toUtc();
      }
      return clock().toUtc();
    }

    return SpBoardMessage(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      writtenBy: json['writtenBy']?.toString(),
      writtenFor: json['writtenFor']?.toString(),
      title: json['title'] as String?,
      message: (json['message'] ?? '').toString(),
      writtenAt: parseTime(json['writtenAt'] ?? json['createdAt']),
      read: json['read'] == true,
    );
  }
}

/// SP automated timer (fires on front change).
class SpAutomatedTimer {
  final String id;
  final String name;
  final String? message;
  final num? delayHours;
  final bool enabled;

  /// SP timer target type. 0 = specific member, 1 = custom front, 2 = any
  /// front change. null if the export omitted the field (treated as "any").
  final int? type;

  /// Target member or custom-front id when [type] is 0 or 1.
  /// Source fields vary across SP export versions; the parser tries `action`
  /// first (string id of the target), then `id` / `targetId`.
  final String? targetId;

  const SpAutomatedTimer({
    required this.id,
    required this.name,
    this.message,
    this.delayHours,
    this.enabled = true,
    this.type,
    this.targetId,
  });

  factory SpAutomatedTimer.fromJson(Map<String, dynamic> json) {
    // `type` is an int in the SP schema. Accept a string fallback defensively
    // since some export variants stringify small ints.
    int? parseType(dynamic v) {
      if (v is int) return v;
      if (v is String) return int.tryParse(v);
      return null;
    }

    // Target id: SP uses different field names across versions; be lenient.
    String? parseTargetId(Map<String, dynamic> m) {
      for (final key in const ['action', 'targetId', 'memberId', 'memberID']) {
        final v = m[key];
        if (v is String && v.isNotEmpty) return v;
      }
      return null;
    }

    return SpAutomatedTimer(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Timer').toString(),
      message: json['message'] as String?,
      delayHours: json['delayInHours'] is num
          ? json['delayInHours'] as num
          : json['delayInHours'] is String
          ? num.tryParse(json['delayInHours'] as String)
          : null,
      enabled: json['enabled'] != false,
      type: parseType(json['type']),
      targetId: parseTargetId(json),
    );
  }
}

/// SP repeated timer (fires on a schedule).
class SpRepeatedTimer {
  final String id;
  final String name;
  final String? message;
  final int? intervalDays;
  final String? timeOfDay;
  final bool enabled;

  const SpRepeatedTimer({
    required this.id,
    required this.name,
    this.message,
    this.intervalDays,
    this.timeOfDay,
    this.enabled = true,
  });

  factory SpRepeatedTimer.fromJson(Map<String, dynamic> json) {
    return SpRepeatedTimer(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Timer').toString(),
      message: json['message'] as String?,
      intervalDays: json['dayInterval'] is int
          ? json['dayInterval'] as int
          : json['intervalInDays'] is int
          ? json['intervalInDays'] as int
          : json['intervalInDays'] is String
          ? int.tryParse(json['intervalInDays'] as String)
          : json['interval'] is int
          ? json['interval'] as int
          : null,
      timeOfDay: json['time'] is Map
          ? '${json['time']['hour']}:${json['time']['minute'].toString().padLeft(2, '0')}'
          : json['time'] as String? ?? json['timeOfDay'] as String?,
      enabled: json['enabled'] != false,
    );
  }
}

/// SP channel category structure.
class SpChannelCategory {
  final String id;
  final String name;
  final List<String> channelIds;

  const SpChannelCategory({
    required this.id,
    required this.name,
    this.channelIds = const [],
  });

  factory SpChannelCategory.fromJson(Map<String, dynamic> json) {
    final channelList = <String>[];
    final rawChannels = json['channels'];
    if (rawChannels is List) {
      for (final ch in rawChannels) {
        channelList.add(ch.toString());
      }
    }

    return SpChannelCategory(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Category').toString(),
      channelIds: channelList,
    );
  }
}

/// Parser for Simply Plural JSON exports.
class SpParser {
  SpParser._();

  /// Parse a SP export JSON string into structured data.
  ///
  /// Handles both array and map formats since SP has changed formats
  /// across different versions.
  ///
  /// [now] is a determinism seam: factories that fall back to "current time"
  /// when a timestamp is unparseable route through this closure. Production
  /// callers leave it `null` (defaults to [DateTime.now]); the Phase 0 parity
  /// harness injects the same `FixedClock` it gives to `SpMapper` so goldens
  /// are byte-stable.
  static SpExportData parse(String jsonString, {DateTime Function()? now}) {
    final clock = now ?? DateTime.now;
    final dynamic decoded = jsonDecode(jsonString);

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Invalid SP export: expected a JSON object at the top level.',
      );
    }

    final json = decoded;

    // Parse system name from settings if available.
    String? systemName;
    String? systemColor;
    String? systemDescription;
    String? systemId;
    String? systemAvatarUrl;
    final settings = json['settings'];
    if (settings is Map<String, dynamic>) {
      systemName =
          settings['systemName'] as String? ?? settings['name'] as String?;
    }

    // Try to get system info from users collection.
    final users = json['users'];
    var customFieldValueKeyMap = const <String, String>{};
    if (users is List && users.isNotEmpty) {
      final user = users.first;
      if (user is Map<String, dynamic>) {
        systemName ??= user['username'] as String?;
        systemColor ??= user['color'] as String?;
        systemDescription ??= user['desc'] as String?;
        customFieldValueKeyMap = extractSpCustomFieldValueKeyMap(
          user['fields'],
        );

        // System-level avatar: prefer direct URL, else construct the
        // serve.apparyllis.com URL from (uid, avatarUuid). Mirrors the
        // per-member logic in sp_mapper.dart.
        final uid = user['uid'] as String? ?? user['_id'] as String?;
        systemId = uid;
        final avatarUrl = user['avatarUrl'] as String?;
        final avatarUuid = user['avatarUuid'] as String?;
        if (avatarUrl != null && avatarUrl.isNotEmpty) {
          systemAvatarUrl = avatarUrl;
        } else if (uid != null &&
            uid.isNotEmpty &&
            avatarUuid != null &&
            avatarUuid.isNotEmpty) {
          systemAvatarUrl =
              'https://serve.apparyllis.com/avatars/$uid/$avatarUuid';
        }
      }
    }

    return SpExportData(
      members: _parseMembers(json['members'], customFieldValueKeyMap),
      customFronts: _parseList(
        json['frontStatuses'] ?? json['customFronts'],
        SpCustomFront.fromJson,
      ),
      frontHistory: _parseList(
        json['frontHistory'],
        (m) => SpFrontHistory.fromJson(m, now: clock),
      ),
      groups: _parseList(json['groups'], SpGroup.fromJson),
      channels: _parseList(json['channels'], SpChannel.fromJson),
      channelCategories: _parseList(
        json['channelCategories'],
        SpChannelCategory.fromJson,
      ),
      messages: _parseMessages(
        json['messages'],
        json['chatMessages'],
        now: clock,
      ),
      polls: _parseList(json['polls'], (m) => SpPoll.fromJson(m, now: clock)),
      notes: _parseList(json['notes'], (m) => SpNote.fromJson(m, now: clock)),
      comments: _parseList(
        json['comments'],
        (m) => SpComment.fromJson(m, now: clock),
      ),
      customFields: _parseList(json['customFields'], SpCustomFieldDef.fromJson),
      boardMessages: _parseList(
        json['boardMessages'],
        (m) => SpBoardMessage.fromJson(m, now: clock),
      ),
      automatedTimers: _parseList(
        json['automatedReminders'] ?? json['automatedTimers'],
        SpAutomatedTimer.fromJson,
      ),
      repeatedTimers: _parseList(
        json['repeatedReminders'] ??
            json['repeatedRemidners'] ??
            json['repeatedTimers'],
        SpRepeatedTimer.fromJson,
      ),
      systemName: systemName,
      systemColor: systemColor,
      systemDescription: systemDescription,
      systemId: systemId,
      systemAvatarUrl: systemAvatarUrl,
    );
  }

  static List<SpMember> _parseMembers(
    dynamic raw,
    Map<String, String> customFieldValueKeyMap,
  ) {
    if (raw == null) return [];

    if (raw is List) {
      return raw
          .whereType<Map<String, dynamic>>()
          .map(
            (memberJson) => SpMember.fromJson(
              normalizeSpMemberJsonInfoKeys(memberJson, customFieldValueKeyMap),
            ),
          )
          .toList();
    }

    if (raw is Map<String, dynamic>) {
      return raw.values
          .whereType<Map<String, dynamic>>()
          .map(
            (memberJson) => SpMember.fromJson(
              normalizeSpMemberJsonInfoKeys(memberJson, customFieldValueKeyMap),
            ),
          )
          .toList();
    }

    return [];
  }

  /// Parse a list that might be an array or a map of keyed objects.
  static List<T> _parseList<T>(
    dynamic raw,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (raw == null) return [];

    if (raw is List) {
      return raw.whereType<Map<String, dynamic>>().map(fromJson).toList();
    }

    // SP sometimes exports collections as { "id1": { ... }, "id2": { ... } }
    if (raw is Map<String, dynamic>) {
      return raw.values
          .whereType<Map<String, dynamic>>()
          .map(fromJson)
          .toList();
    }

    return [];
  }

  /// Parse chat messages from both channel-message export formats.
  static List<SpMessage> _parseMessages(
    dynamic channelMessages,
    dynamic flatChatMessages, {
    DateTime Function()? now,
  }) {
    final messages = <SpMessage>[];

    // Channel messages: map of channel_id -> array of messages
    if (channelMessages is Map<String, dynamic>) {
      for (final entry in channelMessages.entries) {
        final channelId = entry.key;
        final rawMsgs = entry.value;
        if (rawMsgs is List) {
          for (final msg in rawMsgs) {
            if (msg is Map<String, dynamic>) {
              messages.add(SpMessage.fromJson(msg, channelId, now: now));
            }
          }
        }
      }
    }

    // Flat chatMessages list (real export format)
    if (flatChatMessages is List) {
      for (final msg in flatChatMessages) {
        if (msg is Map<String, dynamic>) {
          final channelId = (msg['channel'] ?? '').toString();
          messages.add(SpMessage.fromJson(msg, channelId, now: now));
        }
      }
    }
    return messages;
  }
}
