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
class ChatMessageText extends StatelessWidget {
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

  static const int _fastPathThreshold = 2000;

  @override
  Widget build(BuildContext context) {
    if (content.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    if (content.length > _fastPathThreshold || !hasMarkdownChars(content)) {
      return Text.rich(
        buildMentionSpan(
          content: content,
          authorMap: authorMap,
          theme: theme,
          defaultColor: defaultColor,
          baseStyle: baseStyle,
        ),
      );
    }

    final preprocessed = escapeLeadingHeadings(content);

    return MergeSemantics(
      child: MarkdownBody(
        data: preprocessed,
        styleSheet: chatStylesheet(context, baseStyle),
        extensionSet: chatExtensionSet,
        selectable: false,
        softLineBreak: true,
        builders: {
          'mention': MentionBuilder(authorMap: authorMap, theme: theme),
          'a': SafeLinkBuilder(
            theme: theme,
            onTap: _openExternal,
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
