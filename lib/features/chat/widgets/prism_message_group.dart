import 'package:flutter/material.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/chat/models/conversation_permissions.dart';
import 'package:prism_plurality/features/chat/widgets/message_bubble.dart';

// ---------------------------------------------------------------------------
// Pure-Dart grouping logic (no Flutter imports needed for testing)
// ---------------------------------------------------------------------------

/// A single item in the grouped message list — either a date separator or a
/// group of consecutive messages from the same author.
sealed class MessageGroupItem {
  const MessageGroupItem();
}

/// Marker that tells the UI to render a [DateSeparator].
class DateSeparatorItem extends MessageGroupItem {
  const DateSeparatorItem(this.date);

  final DateTime date;
}

/// A run of consecutive messages from the same author that were sent within
/// [MessageGroupBuilder.groupingThreshold] of each other.
///
/// [messages] are in display order (newest-first when the list is reversed).
class MessageGroup extends MessageGroupItem {
  const MessageGroup({required this.messages});

  /// Messages belonging to this group, in the same order as the source list.
  final List<ChatMessage> messages;

  /// The author shared by every message in this group.
  String? get authorId => messages.firstOrNull?.authorId;
}

/// Transforms a flat, **reverse-chronological** (newest-first) message list
/// into a sequence of [MessageGroupItem]s ready for rendering.
///
/// The algorithm walks the list from index 0 (newest) to the end (oldest).
/// It inserts [DateSeparatorItem]s whenever two adjacent messages fall on
/// different calendar days, and collects consecutive messages from the same
/// author within [groupingThreshold] into [MessageGroup]s.
///
/// This class is intentionally free of Flutter dependencies so it can be
/// unit-tested with plain Dart.
class MessageGroupBuilder {
  const MessageGroupBuilder({
    this.groupingThreshold = const Duration(minutes: 2),
  });

  /// Maximum gap between two consecutive messages from the same author before
  /// a new group is started.
  final Duration groupingThreshold;

  /// Produce a list of [MessageGroupItem]s from a reverse-chronological
  /// (newest-first) list of [ChatMessage]s.
  ///
  /// Date separators are placed *after* all groups of a given day in the
  /// items list so that in a `reverse: true` ListView they render *above*
  /// the day's messages (higher index = higher on screen).
  List<MessageGroupItem> build(List<ChatMessage> messages) {
    if (messages.isEmpty) return const [];

    final items = <MessageGroupItem>[];
    var currentGroupMessages = <ChatMessage>[];

    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];

      // Detect day boundary between the previous group and this message.
      final dayChanged = currentGroupMessages.isNotEmpty &&
          !_isSameDay(currentGroupMessages.last.timestamp, message.timestamp);

      // Check whether this message continues the current group.
      final continuesGroup = currentGroupMessages.isNotEmpty &&
          !dayChanged &&
          _belongsToGroup(currentGroupMessages.last, message);

      if (continuesGroup) {
        currentGroupMessages.add(message);
      } else {
        // Flush the previous group. Reverse so oldest is first — the input
        // list is DESC (newest first) but within a group we render top-to-bottom.
        if (currentGroupMessages.isNotEmpty) {
          items.add(MessageGroup(
            messages: List.unmodifiable(currentGroupMessages.reversed.toList()),
          ));
        }

        // When the day changed, emit a separator for the completed day.
        // Placing it after the day's groups means it appears above them
        // in a reversed ListView.
        if (dayChanged) {
          items.add(DateSeparatorItem(currentGroupMessages.first.timestamp));
        }

        // Start a new group.
        currentGroupMessages = [message];
      }
    }

    // Flush the last group and add its date separator.
    if (currentGroupMessages.isNotEmpty) {
      items.add(MessageGroup(
        messages: List.unmodifiable(currentGroupMessages.reversed.toList()),
      ));
      items.add(DateSeparatorItem(currentGroupMessages.first.timestamp));
    }

    return items;
  }

  /// Whether [candidate] can be appended to the group whose last message is
  /// [last].
  bool _belongsToGroup(ChatMessage last, ChatMessage candidate) {
    if (candidate.replyToId != null || last.replyToId != null) return false;
    if (last.isSystemMessage || candidate.isSystemMessage) return false;
    if (last.authorId != candidate.authorId) return false;

    final diff = last.timestamp.difference(candidate.timestamp).abs();
    return diff < groupingThreshold;
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

// ---------------------------------------------------------------------------
// Flutter widget that renders a single group
// ---------------------------------------------------------------------------

/// Renders a [MessageGroup] — a run of consecutive messages from the same
/// author.
///
/// The first message in the group shows the author's avatar and name; the
/// remaining messages are rendered without author info so they visually align
/// beneath the first.
class PrismMessageGroup extends StatelessWidget {
  const PrismMessageGroup({
    super.key,
    required this.group,
    this.permissions,
    this.participantIds,
    this.authorMap,
    this.messageKeys,
    this.onScrollToMessage,
    this.onReply,
    this.highlightedMessageId,
  });

  final MessageGroup group;

  /// Permission model for the current conversation. Forwarded to each
  /// [MessageBubble] to control edit/delete visibility.
  final ConversationPermissions? permissions;

  /// Current participant IDs. Forwarded to each [MessageBubble] for departed
  /// member avatar dimming.
  final Set<String>? participantIds;

  /// Pre-loaded author map. When provided, [MessageBubble] can look up the
  /// author from this map instead of watching an individual provider.
  final Map<String, Member>? authorMap;

  /// GlobalKey map keyed by message ID, used to locate messages for
  /// scroll-to-reply.
  final Map<String, GlobalKey>? messageKeys;

  /// Called when the user taps a quote chip to scroll to the replied-to
  /// message.
  final void Function(String messageId)? onScrollToMessage;

  /// Called when the user selects Reply from a message's context menu.
  final void Function(ChatMessage message)? onReply;

  /// The ID of the message that should display a highlight flash overlay.
  final String? highlightedMessageId;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < group.messages.length; i++) ...[
          KeyedSubtree(
            key: messageKeys?[group.messages[i].id],
            child: MessageBubble(
              message: group.messages[i],
              showAuthorInfo: i == 0,
              permissions: permissions,
              participantIds: participantIds,
              authorMap: authorMap,
              onScrollToReply: group.messages[i].replyToId != null
                  ? () => onScrollToMessage?.call(group.messages[i].replyToId!)
                  : null,
              onReply: onReply,
              isHighlighted: group.messages[i].id == highlightedMessageId,
            ),
          ),
        ],
      ],
    );
  }
}
