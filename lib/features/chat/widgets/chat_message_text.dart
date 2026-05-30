import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/utils/chat_markdown_syntax.dart';
import 'package:prism_plurality/features/chat/utils/mention_utils.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/utils/safe_link.dart';

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
    this.imgElementBuilder,
    this.imageLibraryVersion = 0,
  });

  final String content;
  final Map<String, Member>? authorMap;
  final TextStyle baseStyle;
  final Color defaultColor;

  /// Optional `img` element builder. When supplied (by the message bubble,
  /// which has Riverpod access), `![](tag)` resolves to library images.
  /// Null in tests / isolated use → images stay suppressed.
  final MarkdownElementBuilder? imgElementBuilder;

  /// Changes when the image library loads/changes. Folded into the render key
  /// so the cached MarkdownBody re-parses once the (async) library is ready —
  /// otherwise a library image in a freshly-opened chat stays unresolved until
  /// the row is scrolled out of view and back.
  final int imageLibraryVersion;

  @override
  State<ChatMessageText> createState() => _ChatMessageTextState();
}

class _ChatMessageTextState extends State<ChatMessageText> {
  static const int _fastPathThreshold = 2000;

  final _revealController = SpoilerRevealController();
  final _segmentRevealControllers = <int, SpoilerRevealController>{};

  @override
  void dispose() {
    _revealController.dispose();
    _disposeSegmentRevealControllers();
    super.dispose();
  }

  @override
  void didUpdateWidget(ChatMessageText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content) {
      _revealController.clear();
      _clearSegmentRevealControllers();
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildContent(
      context,
      content: widget.content,
      baseStyle: widget.baseStyle,
      defaultColor: widget.defaultColor,
    );
  }

  Widget _buildContent(
    BuildContext context, {
    required String content,
    required TextStyle baseStyle,
    required Color defaultColor,
    bool allowSmallText = true,
    bool allowEmojiSticker = true,
    Object? keySalt,
    SpoilerRevealController? revealController,
  }) {
    if (content.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final renderKey = ValueKey(
      Object.hash(
        _mentionRenderSignature(content, widget.authorMap),
        keySalt,
        widget.imageLibraryVersion,
      ),
    );

    final smallTextSegments = allowSmallText
        ? _smallTextSegments(content)
        : null;
    if (smallTextSegments != null) {
      return KeyedSubtree(
        key: renderKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (index, segment) in smallTextSegments.indexed)
              _buildContent(
                context,
                content: segment.content,
                baseStyle: segment.isSmall
                    ? _smallTextStyle(baseStyle)
                    : baseStyle,
                defaultColor: segment.isSmall
                    ? theme.colorScheme.onSurfaceVariant
                    : defaultColor,
                allowSmallText: false,
                allowEmojiSticker: !segment.isSmall,
                keySalt: index,
                revealController: _revealControllerForSegment(index),
              ),
          ],
        ),
      );
    }

    final stickerFontSize = allowEmojiSticker
        ? emojiStickerFontSize(content, baseStyle)
        : null;

    if (stickerFontSize != null) {
      return KeyedSubtree(
        key: renderKey,
        child: Text(
          content.trim(),
          style: baseStyle.copyWith(
            color: defaultColor,
            fontSize: stickerFontSize,
            height: 1.0,
          ),
        ),
      );
    }

    // Fast path: skips the markdown parser. `redactSpoilers` runs before
    // rendering so a >2000-char message with `||secret||` can't leak the
    // plaintext — we trade tap-to-reveal for a no-plaintext guarantee on
    // oversize messages.
    if (content.length > _fastPathThreshold || !hasMarkdownChars(content)) {
      return KeyedSubtree(
        key: renderKey,
        child: Text.rich(
          buildMentionSpan(
            content: redactSpoilers(content),
            authorMap: widget.authorMap,
            theme: theme,
            defaultColor: defaultColor,
            baseStyle: baseStyle,
          ),
        ),
      );
    }

    final preprocessed = escapeLeadingHeadings(content);

    return SpoilerRevealScope(
      notifier: revealController ?? _revealController,
      child: MergeSemantics(
        child: MarkdownBody(
          key: renderKey,
          data: preprocessed,
          styleSheet: chatStylesheet(context, baseStyle),
          extensionSet: chatExtensionSet,
          selectable: false,
          softLineBreak: true,
          imageBuilder: (uri, title, alt) => const SizedBox.shrink(),
          builders: {
            'mention': MentionBuilder(
              authorMap: widget.authorMap,
              theme: theme,
            ),
            'a': SafeLinkBuilder(theme: theme, onTap: _openExternal),
            'spoiler': SpoilerBuilder(theme: theme),
            // Resolve ![](tag) against the shared encrypted image library
            // when the bubble supplied a builder.
            if (widget.imgElementBuilder != null)
              'img': widget.imgElementBuilder!,
          },
        ),
      ),
    );
  }

  SpoilerRevealController _revealControllerForSegment(int index) {
    return _segmentRevealControllers.putIfAbsent(
      index,
      SpoilerRevealController.new,
    );
  }

  void _disposeSegmentRevealControllers() {
    for (final controller in _segmentRevealControllers.values) {
      controller.dispose();
    }
    _segmentRevealControllers.clear();
  }

  void _clearSegmentRevealControllers() {
    for (final controller in _segmentRevealControllers.values) {
      controller.clear();
    }
  }

  Future<void> _openExternal(String href) async {
    // Chat hrefs are peer-supplied; the helper enforces a scheme allowlist.
    await launchSafeExternalUri(href);
  }

  Object _mentionRenderSignature(
    String content,
    Map<String, Member>? authorMap,
  ) {
    final values = <Object?>[content];
    for (final match in mentionRegex.allMatches(content)) {
      final memberId = match.group(1)!;
      final member = authorMap?[memberId];
      values.addAll([
        memberId,
        member?.name,
        member?.customColorEnabled,
        member?.customColorHex,
      ]);
    }
    return Object.hashAll(values);
  }
}

class _SmallTextSegment {
  const _SmallTextSegment(this.content, this.isSmall);

  final String content;
  final bool isSmall;
}

List<_SmallTextSegment>? _smallTextSegments(String content) {
  if (!chatSmallTextLineRegex.hasMatch(content)) return null;

  final segments = <_SmallTextSegment>[];
  final normalLines = <String>[];

  void flushNormalLines() {
    if (normalLines.isEmpty) return;
    segments.add(_SmallTextSegment(normalLines.join('\n'), false));
    normalLines.clear();
  }

  for (final line in content.split('\n')) {
    final match = chatSmallTextLineRegex.firstMatch(line);
    if (match == null) {
      normalLines.add(line);
      continue;
    }
    flushNormalLines();
    segments.add(_SmallTextSegment(match.group(1)!, true));
  }

  flushNormalLines();
  return segments;
}

TextStyle _smallTextStyle(TextStyle baseStyle) {
  return baseStyle.copyWith(fontSize: (baseStyle.fontSize ?? 14) * 0.85);
}

/// Returns a sticker font size for emoji-only chat messages.
double? emojiStickerFontSize(String content, TextStyle baseStyle) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) return null;

  final count = _emojiGraphemeCount(trimmed);
  if (count == null || count > _emojiStickerMaxGraphemes) return null;

  final normalSize = baseStyle.fontSize ?? 14;
  return math.max(normalSize, switch (count) {
    1 => 48.0,
    <= 3 => 40.0,
    _ => 32.0,
  });
}

int? _emojiGraphemeCount(String content) {
  var count = 0;
  for (final cluster in content.characters) {
    if (cluster.trim().isEmpty) continue;
    if (!_isEmojiCluster(cluster)) return null;
    count++;
    if (count > _emojiStickerMaxGraphemes) return count;
  }
  return count == 0 ? null : count;
}

bool _isEmojiCluster(String cluster) {
  if (_keycapEmojiRegex.hasMatch(cluster) ||
      _flagEmojiRegex.hasMatch(cluster)) {
    return true;
  }

  final segments = cluster.split('\u200D');
  if (segments.isEmpty) return false;
  return segments.every(_isEmojiSegment);
}

bool _isEmojiSegment(String segment) {
  final hasEmojiVariation = segment.contains('\uFE0F');
  final normalized = segment
      .replaceAll(RegExp('[\uFE0E\uFE0F]'), '')
      .replaceAll(_emojiModifierRegex, '');

  if (normalized.isEmpty) return false;
  if (_emojiPresentationRegex.hasMatch(normalized) ||
      _extendedPictographicRegex.hasMatch(normalized)) {
    return true;
  }

  return hasEmojiVariation &&
      _emojiRegex.hasMatch(normalized) &&
      !_emojiKeycapBaseRegex.hasMatch(normalized);
}

final _emojiRegex = RegExp(r'^\p{Emoji}$', unicode: true);
const _emojiStickerMaxGraphemes = 6;
final _emojiPresentationRegex = RegExp(
  r'^\p{Emoji_Presentation}$',
  unicode: true,
);
final _extendedPictographicRegex = RegExp(
  r'^\p{Extended_Pictographic}$',
  unicode: true,
);
final _emojiModifierRegex = RegExp(r'[\u{1F3FB}-\u{1F3FF}]', unicode: true);
final _keycapEmojiRegex = RegExp(r'^[0-9#*]\uFE0F?\u20E3$', unicode: true);
final _emojiKeycapBaseRegex = RegExp(r'^[0-9#*]$', unicode: true);
final _flagEmojiRegex = RegExp(r'^[\u{1F1E6}-\u{1F1FF}]{2}$', unicode: true);

/// Build a [TextSpan] for plain-text messages with colored mentions.
///
/// Extracted from `message_bubble`'s `_buildContentSpan` so the fast path and
/// Task 6 can share the same logic without depending on `message_bubble`
/// internals.
///
/// - Walks [chatMentionRegex] matches across [content].
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
  final matches = chatMentionRegex.allMatches(content).toList();

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

    final memberId = mentionIdFromMatch(match);
    final alias = broadcastAliasFromMatch(match);
    final member = memberId == null ? null : authorMap?[memberId];
    final name = alias ?? member?.name ?? 'Unknown';
    final mentionColor = alias == null
        ? _memberColor(member, theme)
        : theme.colorScheme.primary;
    final display = '@$name';

    spans.add(
      TextSpan(
        text: display,
        style: defaultStyle.copyWith(
          color: mentionColor,
          fontWeight: FontWeight.w600,
        ),
        semanticsLabel: display,
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
