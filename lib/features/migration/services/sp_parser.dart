import 'dart:convert';

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
}

/// SP member structure.
class SpMember {
  final String id;
  final String name;
  final String? pronouns;
  final String? avatarUrl;
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
class SpFrontHistory {
  final String id;
  final String? memberId;
  final List<String> coFronters;
  final DateTime startTime;
  final DateTime? endTime;
  final String? comment;
  final String? customStatus;
  final bool isCustomFront;

  const SpFrontHistory({
    required this.id,
    this.memberId,
    this.coFronters = const [],
    required this.startTime,
    this.endTime,
    this.comment,
    this.customStatus,
    this.isCustomFront = false,
  });

  factory SpFrontHistory.fromJson(Map<String, dynamic> json) {
    // SP stores times as epoch milliseconds.
    final startMs = json['startTime'];
    final endMs = json['endTime'];

    DateTime parseTime(dynamic value) {
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) {
          return DateTime.fromMillisecondsSinceEpoch(parsed);
        }
        return DateTime.tryParse(value) ?? DateTime.now();
      }
      return DateTime.now();
    }

    final coFrontersList = <String>[];
    final rawCoFronters = json['coFronters'] ?? json['cofronters'];
    if (rawCoFronters is List) {
      for (final cf in rawCoFronters) {
        coFrontersList.add(cf.toString());
      }
    }

    return SpFrontHistory(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      memberId: json['member']?.toString(),
      coFronters: coFrontersList,
      startTime: parseTime(startMs),
      endTime: endMs != null ? parseTime(endMs) : null,
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
          ? DateTime.tryParse(json['createdAt'].toString())
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

  const SpMessage({
    required this.id,
    required this.channelId,
    this.senderId,
    required this.content,
    required this.timestamp,
  });

  factory SpMessage.fromJson(Map<String, dynamic> json, String channelId) {
    DateTime parseTime(dynamic value) {
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) {
          return DateTime.fromMillisecondsSinceEpoch(parsed);
        }
        return DateTime.tryParse(value) ?? DateTime.now();
      }
      return DateTime.now();
    }

    return SpMessage(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      channelId: channelId,
      senderId: json['sender']?.toString() ?? json['writer']?.toString() ?? json['member']?.toString(),
      content: (json['message'] ?? json['content'] ?? '').toString(),
      timestamp: parseTime(json['timestamp'] ?? json['writtenAt'] ?? json['createdAt']),
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
  final bool allowMultiple;
  final DateTime? endDate;

  const SpPoll({
    required this.id,
    required this.question,
    this.description,
    this.options = const [],
    this.votes = const [],
    this.allowMultiple = false,
    this.endDate,
  });

  factory SpPoll.fromJson(Map<String, dynamic> json) {
    DateTime parseTime(dynamic value) {
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
      if (value is num) {
        return DateTime.fromMillisecondsSinceEpoch(value.toInt());
      }
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) {
          return DateTime.fromMillisecondsSinceEpoch(parsed);
        }
        return DateTime.tryParse(value) ?? DateTime.now();
      }
      return DateTime.now();
    }

    final optionList = <SpPollOption>[];
    final rawOptions = json['options'];
    if (rawOptions is List) {
      for (final o in rawOptions) {
        if (o is Map) {
          optionList.add(SpPollOption(
            name: (o['text'] ?? o['name'] ?? o.toString()).toString(),
            color: o['color'] as String?,
          ));
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
            voteList.add(SpPollVote(
              memberId: memberId,
              optionName: optionName,
              comment: v['comment'] as String?,
            ));
          }
        }
      }
    }

    final rawEndTime = json['endTime'] ?? json['endDate'];

    return SpPoll(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      question: (json['question'] ?? json['title'] ?? '').toString(),
      description: json['desc'] as String? ?? json['description'] as String?,
      options: optionList,
      votes: voteList,
      allowMultiple: json['allowMultiple'] == true,
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

  factory SpNote.fromJson(Map<String, dynamic> json) {
    DateTime parseTime(dynamic value) {
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) {
          return DateTime.fromMillisecondsSinceEpoch(parsed);
        }
        return DateTime.tryParse(value) ?? DateTime.now();
      }
      return DateTime.now();
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

  factory SpComment.fromJson(Map<String, dynamic> json) {
    DateTime parseTime(dynamic value) {
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) {
          return DateTime.fromMillisecondsSinceEpoch(parsed);
        }
        return DateTime.tryParse(value) ?? DateTime.now();
      }
      return DateTime.now();
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

  const SpBoardMessage({
    required this.id,
    this.writtenBy,
    this.writtenFor,
    this.title,
    required this.message,
    required this.writtenAt,
  });

  factory SpBoardMessage.fromJson(Map<String, dynamic> json) {
    DateTime parseTime(dynamic value) {
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) {
          return DateTime.fromMillisecondsSinceEpoch(parsed);
        }
        return DateTime.tryParse(value) ?? DateTime.now();
      }
      return DateTime.now();
    }

    return SpBoardMessage(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      writtenBy: json['writtenBy']?.toString(),
      writtenFor: json['writtenFor']?.toString(),
      title: json['title'] as String?,
      message: (json['message'] ?? '').toString(),
      writtenAt: parseTime(json['writtenAt'] ?? json['createdAt']),
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

  const SpAutomatedTimer({
    required this.id,
    required this.name,
    this.message,
    this.delayHours,
    this.enabled = true,
  });

  factory SpAutomatedTimer.fromJson(Map<String, dynamic> json) {
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
  static SpExportData parse(String jsonString) {
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
    final settings = json['settings'];
    if (settings is Map<String, dynamic>) {
      systemName =
          settings['systemName'] as String? ?? settings['name'] as String?;
    }

    // Try to get system info from users collection.
    final users = json['users'];
    if (users is List && users.isNotEmpty) {
      final user = users.first;
      if (user is Map<String, dynamic>) {
        systemName ??= user['username'] as String?;
        systemColor ??= user['color'] as String?;
        systemDescription ??= user['desc'] as String?;
      }
    }

    return SpExportData(
      members: _parseList(json['members'], SpMember.fromJson),
      customFronts:
          _parseList(json['frontStatuses'] ?? json['customFronts'], SpCustomFront.fromJson),
      frontHistory:
          _parseList(json['frontHistory'], SpFrontHistory.fromJson),
      groups: _parseList(json['groups'], SpGroup.fromJson),
      channels: _parseList(json['channels'], SpChannel.fromJson),
      channelCategories: _parseList(json['channelCategories'], SpChannelCategory.fromJson),
      messages: _parseMessages(json['messages'], json['boardMessages'], json['chatMessages']),
      polls: _parseList(json['polls'], SpPoll.fromJson),
      notes: _parseList(json['notes'], SpNote.fromJson),
      comments: _parseList(json['comments'], SpComment.fromJson),
      customFields:
          _parseList(json['customFields'], SpCustomFieldDef.fromJson),
      boardMessages:
          _parseList(json['boardMessages'], SpBoardMessage.fromJson),
      automatedTimers:
          _parseList(json['automatedReminders'] ?? json['automatedTimers'], SpAutomatedTimer.fromJson),
      repeatedTimers:
          _parseList(json['repeatedReminders'] ?? json['repeatedRemidners'] ?? json['repeatedTimers'], SpRepeatedTimer.fromJson),
      systemName: systemName,
      systemColor: systemColor,
      systemDescription: systemDescription,
    );
  }

  /// Parse a list that might be an array or a map of keyed objects.
  static List<T> _parseList<T>(
    dynamic raw,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (raw == null) return [];

    if (raw is List) {
      return raw
          .whereType<Map<String, dynamic>>()
          .map(fromJson)
          .toList();
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

  /// Parse messages from both channel messages and board messages.
  static List<SpMessage> _parseMessages(
    dynamic channelMessages,
    dynamic boardMessages,
    dynamic flatChatMessages,
  ) {
    final messages = <SpMessage>[];

    // Channel messages: map of channel_id -> array of messages
    if (channelMessages is Map<String, dynamic>) {
      for (final entry in channelMessages.entries) {
        final channelId = entry.key;
        final rawMsgs = entry.value;
        if (rawMsgs is List) {
          for (final msg in rawMsgs) {
            if (msg is Map<String, dynamic>) {
              messages.add(SpMessage.fromJson(msg, channelId));
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
          messages.add(SpMessage.fromJson(msg, channelId));
        }
      }
    }

    // Board messages go into a special DM-style conversation.
    if (boardMessages is List) {
      for (final msg in boardMessages) {
        if (msg is Map<String, dynamic>) {
          messages.add(SpMessage.fromJson(msg, '_board'));
        }
      }
    }

    return messages;
  }
}
