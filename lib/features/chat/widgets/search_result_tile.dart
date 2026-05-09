import 'package:flutter/material.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/models/search_result.dart';
import 'package:prism_plurality/features/chat/utils/chat_markdown_syntax.dart';
import 'package:prism_plurality/features/chat/utils/mention_utils.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';

class SearchResultTile extends StatelessWidget {
  const SearchResultTile({
    super.key,
    required this.result,
    required this.onTap,
    this.authorMap = const <String, Member>{},
  });

  final MessageSearchResult result;
  final VoidCallback onTap;

  /// Members keyed by ID, used to resolve `@[uuid]` mention tokens in the
  /// snippet to colored `@MemberName` chips. Defaults to an empty map so
  /// tests and embeds without a member context render mentions as `@Unknown`
  /// rather than the raw token.
  final Map<String, Member> authorMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // The snippet is already redacted upstream (SearchMessagesDao builds it
    // from the redacted content), but we belt-and-suspenders it here in case
    // the snippet arrives unredacted via another path. Then strip the `[…]`
    // highlight markers and swap runs of `▮` for the word "spoiler" so
    // screen readers say "spoiler" rather than reading block glyphs.
    final a11ySnippet = redactSpoilers(result.snippet)
        .replaceAll('[', '')
        .replaceAll(']', '')
        .replaceAll(RegExp(r'▮+'), 'spoiler');

    return Semantics(
      button: true,
      label: '${result.authorName ?? 'Unknown'}: $a11ySnippet '
          'in ${result.conversationTitle ?? 'conversation'}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MemberAvatar(
                avatarImageData: result.authorAvatarData,
                memberName: result.authorName,
                emoji: result.authorEmoji ?? '❔',
                customColorEnabled: result.authorCustomColorEnabled ?? false,
                customColorHex: result.authorCustomColorHex,
                size: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            result.authorName ?? 'Unknown',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '  ·  ',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (result.conversationEmoji != null) ...[
                          Text(
                            result.conversationEmoji!,
                            style: const TextStyle(fontSize: 11),
                          ),
                          const SizedBox(width: 3),
                        ],
                        Flexible(
                          child: Text(
                            result.conversationTitle ?? 'Conversation',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _relativeTimestamp(result.timestamp),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Snippet with highlighted matches
                    _buildSnippet(context, result.snippet),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSnippet(BuildContext context, String snippet) {
    final theme = Theme.of(context);
    // Redact spoilers before bracket-tokenization: if a match landed inside
    // a spoiler, its ``[hit]`` markers get swallowed too — we'd rather lose
    // the highlight than leak the hidden text.
    final redacted = redactSpoilers(snippet);
    final baseStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final highlightStyle = baseStyle?.copyWith(
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurface,
    );

    // Mentions are detected first so the highlight scanner can ignore the
    // `[uuid]` substring inside `@[uuid]` — otherwise a mention's UUID would
    // get bolded as if it were a search hit.
    final mentions = mentionRegex.allMatches(redacted).toList();
    bool insideMention(int pos) {
      for (final m in mentions) {
        if (pos >= m.start && pos < m.end) return true;
      }
      return false;
    }

    final highlights = RegExp(r'\[([^\]]*)\]')
        .allMatches(redacted)
        .where((m) => !insideMention(m.start))
        .toList();

    final regions = <_SnippetRegion>[
      for (final m in mentions)
        _SnippetRegion.mention(m.start, m.end, m.group(1)!),
      for (final h in highlights)
        _SnippetRegion.highlight(h.start, h.end, h.group(1) ?? ''),
    ]..sort((a, b) => a.start.compareTo(b.start));

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final region in regions) {
      if (region.start > cursor) {
        spans.add(TextSpan(
          text: redacted.substring(cursor, region.start),
          style: baseStyle,
        ));
      }
      if (region.isMention) {
        final member = authorMap[region.payload];
        final name = member?.name ?? 'Unknown';
        final mentionColor = (member != null &&
                member.customColorEnabled &&
                member.customColorHex != null)
            ? AppColors.fromHex(member.customColorHex!)
            : theme.colorScheme.primary;
        spans.add(TextSpan(
          text: '@$name',
          style: baseStyle?.copyWith(
            color: mentionColor,
            fontWeight: FontWeight.w600,
          ),
          semanticsLabel: '@$name',
        ));
      } else {
        spans.add(TextSpan(text: region.payload, style: highlightStyle));
      }
      cursor = region.end;
    }
    if (cursor < redacted.length) {
      spans.add(TextSpan(
        text: redacted.substring(cursor),
        style: baseStyle,
      ));
    }

    return RichText(
      text: TextSpan(children: spans),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _relativeTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    if (diff.inDays < 365) return '${(diff.inDays / 7).floor()}w';
    return '${(diff.inDays / 365).floor()}y';
  }
}

class _SnippetRegion {
  const _SnippetRegion._(this.start, this.end, this.payload, this.isMention);

  factory _SnippetRegion.mention(int start, int end, String memberId) =>
      _SnippetRegion._(start, end, memberId, true);

  factory _SnippetRegion.highlight(int start, int end, String text) =>
      _SnippetRegion._(start, end, text, false);

  final int start;
  final int end;
  final String payload;
  final bool isMention;
}
