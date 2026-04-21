import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/utils/chat_markdown_syntax.dart';
import 'package:prism_plurality/features/chat/utils/mention_utils.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:url_launcher/url_launcher.dart';

/// Renders chat message content with a narrow markdown subset + colored
/// mentions.
///
/// Fast path: plain text or oversized content skips the parser entirely and
/// uses a [Text.rich] with inline mention coloring (see [buildMentionSpan]).
///
/// Slow path: content that contains markdown chars and is under 2 000
/// characters is parsed via [MarkdownBody] using [chatExtensionSet] and
/// [chatStylesheet].
class ChatMessageText extends StatefulWidget {
  const ChatMessageText({
    super.key,
    required this.content,
    required this.authorMap,
    required this.baseStyle,
    required this.defaultColor,
  });

  final String content;
  final Map<String, Member>? authorMap;
  final TextStyle baseStyle;
  final Color defaultColor;

  @override
  State<ChatMessageText> createState() => _ChatMessageTextState();
}

class _ChatMessageTextState extends State<ChatMessageText> {
  static const int _fastPathThreshold = 2000;

  final Map<int, bool> _reveals = {};

  @override
  void didUpdateWidget(ChatMessageText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content) {
      _reveals.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.content.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    // Fast path: skips the markdown parser, so `||spoiler||` in >2000-char
    // messages renders literally. Same fallback other markdown sees in giant
    // messages — acceptable for v1.
    if (widget.content.length > _fastPathThreshold ||
        !hasMarkdownChars(widget.content)) {
      return Text.rich(
        buildMentionSpan(
          content: widget.content,
          authorMap: widget.authorMap,
          theme: theme,
          defaultColor: widget.defaultColor,
          baseStyle: widget.baseStyle,
        ),
      );
    }

    final preprocessed = escapeLeadingHeadings(widget.content);

    // Encode current reveal state into the key so MarkdownBody recreates its
    // widget tree (and re-runs element builders) whenever a spoiler is toggled.
    // MarkdownBody only re-parses when `data` or `styleSheet` changes; keying
    // off reveal state is the lightest-weight way to keep the pill in sync.
    final revealsKey = _reveals.isEmpty
        ? ''
        : _reveals.entries
            .where((e) => e.value)
            .map((e) => e.key)
            .join(',');

    return MergeSemantics(
      child: MarkdownBody(
        key: ValueKey(revealsKey),
        data: preprocessed,
        styleSheet: chatStylesheet(context, widget.baseStyle),
        extensionSet: chatExtensionSet,
        selectable: false,
        softLineBreak: true,
        builders: {
          'mention': MentionBuilder(authorMap: widget.authorMap, theme: theme),
          'a': SafeLinkBuilder(
            theme: theme,
            onTap: _openExternal,
          ),
          'spoiler': SpoilerBuilder(
            reveals: _reveals,
            onToggle: (start) => setState(() {
              _reveals[start] = !(_reveals[start] ?? false);
            }),
            theme: theme,
          ),
        },
      ),
    );
  }

  Future<void> _openExternal(String href) async {
    final uri = Uri.tryParse(href);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Build a [TextSpan] for plain-text messages with colored mentions.
///
/// Extracted from `message_bubble`'s `_buildContentSpan` so the fast path and
/// Task 6 can share the same logic without depending on `message_bubble`
/// internals.
///
/// - Walks [mentionRegex] matches across [content].
/// - Emits a plain-text span for each segment before a mention, then a mention
///   span with the member's color (or [theme.colorScheme.primary] as fallback).
/// - Uses [baseStyle] as the base, overriding `color` and `fontWeight` for
///   mention spans.
/// - Missing members fall back to the display name `@Unknown`.
TextSpan buildMentionSpan({
  required String content,
  required Map<String, Member>? authorMap,
  required ThemeData theme,
  required Color defaultColor,
  required TextStyle baseStyle,
}) {
  final defaultStyle = baseStyle.copyWith(color: defaultColor);
  final matches = mentionRegex.allMatches(content).toList();

  if (matches.isEmpty) {
    return TextSpan(text: content, style: defaultStyle);
  }

  final spans = <InlineSpan>[];
  var lastEnd = 0;

  for (final match in matches) {
    // Plain text before this mention.
    if (match.start > lastEnd) {
      spans.add(
        TextSpan(
          text: content.substring(lastEnd, match.start),
          style: defaultStyle,
        ),
      );
    }

    final memberId = match.group(1)!;
    final member = authorMap?[memberId];
    final name = member?.name ?? 'Unknown';
    final mentionColor = _memberColor(member, theme);

    spans.add(
      TextSpan(
        text: '@$name',
        style: defaultStyle.copyWith(
          color: mentionColor,
          fontWeight: FontWeight.w600,
        ),
        semanticsLabel: '@$name',
      ),
    );

    lastEnd = match.end;
  }

  // Trailing plain text.
  if (lastEnd < content.length) {
    spans.add(TextSpan(text: content.substring(lastEnd), style: defaultStyle));
  }

  return TextSpan(children: spans);
}

/// Resolve a member's display color.
///
/// Mirrors the logic in `MentionBuilder` and `message_bubble._buildContentSpan`:
/// use the member's custom color when it is enabled and a hex value is present,
/// otherwise fall back to the theme's primary color.
Color _memberColor(Member? member, ThemeData theme) {
  if (member != null &&
      member.customColorEnabled &&
      member.customColorHex != null) {
    return AppColors.fromHex(member.customColorHex!);
  }
  return theme.colorScheme.primary;
}
