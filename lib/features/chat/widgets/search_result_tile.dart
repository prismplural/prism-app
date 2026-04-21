import 'package:flutter/material.dart';

import 'package:prism_plurality/features/chat/models/search_result.dart';
import 'package:prism_plurality/features/chat/utils/chat_markdown_syntax.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

class SearchResultTile extends StatelessWidget {
  const SearchResultTile({
    super.key,
    required this.result,
    required this.onTap,
  });

  final MessageSearchResult result;
  final VoidCallback onTap;

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
                        Expanded(
                          child: Text(
                            result.authorName ?? 'Unknown',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
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
                    const SizedBox(height: 2),
                    // Conversation pill
                    TintedGlassSurface(
                      borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(8)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (result.conversationEmoji != null) ...[
                            Text(
                              result.conversationEmoji!,
                              style: const TextStyle(fontSize: 10),
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
                        ],
                      ),
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

    final spans = <InlineSpan>[];
    final regex = RegExp(r'\[([^\]]*)\]');
    var lastEnd = 0;

    for (final match in regex.allMatches(redacted)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: redacted.substring(lastEnd, match.start),
          style: baseStyle,
        ));
      }
      spans.add(TextSpan(
        text: match.group(1),
        style: highlightStyle,
      ));
      lastEnd = match.end;
    }
    if (lastEnd < redacted.length) {
      spans.add(TextSpan(
        text: redacted.substring(lastEnd),
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
