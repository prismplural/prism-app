import 'package:flutter/material.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/utils/mention_utils.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';

/// A [TextEditingController] that highlights inline markdown syntax for chat.
///
/// Differences from [MarkdownEditingController] (used in notes):
/// - `__foo__` renders as **bold** (not underline), matching CommonMark.
/// - `_foo_` renders as *italic* (negative lookahead against `__`).
/// - No heading (`# `, `## `) or horizontal rule (`---`) highlighting.
/// - Marker dim alpha is 180 (softer than notes' 102).
class ChatMarkdownEditingController extends TextEditingController {
  static final _spoiler = RegExp(r'\|\|(.+?)\|\|');
  static final _boldStar = RegExp(r'\*\*(.+?)\*\*');
  static final _boldUnderscore = RegExp(r'__(.+?)__');
  static final _italicStar = RegExp(r'(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)');
  static final _italicUnderscore = RegExp(r'(?<!_)_(?!_)(.+?)(?<!_)_(?!_)');

  Color _onSurface = AppColors.warmBlack;
  Color _markerColor = Colors.grey;
  Color _mentionFallbackColor = AppColors.prismPurple;
  TextStyle _baseStyle = const TextStyle();
  bool _themeReady = false;
  Map<String, Member> _mentionMembers = const {};

  // Cache: parsed spans are expensive to build on every keystroke.
  // Invalidated when text changes or when updateTheme() is called.
  String? _cachedText;
  List<InlineSpan>? _cachedChildren;

  ChatMarkdownEditingController({super.text});

  void updateTheme(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    _onSurface = colorScheme.onSurface;
    _markerColor = colorScheme.onSurfaceVariant.withAlpha(180);
    _mentionFallbackColor = colorScheme.primary;
    _baseStyle = TextStyle(color: _onSurface);
    _themeReady = true;
    _cachedText = null;
    _cachedChildren = null;
  }

  void updateMentionMembers(Map<String, Member> members) {
    if (_sameMentionMembers(_mentionMembers, members)) return;
    _mentionMembers = Map<String, Member>.unmodifiable(members);
    _cachedText = null;
    _cachedChildren = null;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (!_themeReady || text.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    // Return cached result if text hasn't changed since last parse.
    if (_cachedText == text && _cachedChildren != null) {
      return TextSpan(style: style, children: _cachedChildren);
    }

    final mergedStyle = style?.merge(_baseStyle) ?? _baseStyle;
    final lines = text.split('\n');
    final spans = <TextSpan>[];
    var isFirstLine = true;

    for (final line in lines) {
      if (!isFirstLine) {
        spans.add(TextSpan(text: '\n', style: mergedStyle));
      }
      isFirstLine = false;

      // No heading or horizontal rule handling — render all lines as inline.
      _parseInlineMarkdown(line, mergedStyle, spans);
    }

    _cachedText = text;
    _cachedChildren = List<InlineSpan>.unmodifiable(spans);
    return TextSpan(style: style, children: _cachedChildren);
  }

  void _parseInlineMarkdown(
    String line,
    TextStyle baseStyle,
    List<InlineSpan> spans,
  ) {
    final mentions = chatMentionRegex.allMatches(line).toList();
    if (mentions.isEmpty) {
      _parseInlineMarkdownWithoutMentions(line, baseStyle, spans);
      return;
    }

    var cursor = 0;
    for (final mention in mentions) {
      if (mention.start > cursor) {
        _parseInlineMarkdownWithoutMentions(
          line.substring(cursor, mention.start),
          baseStyle,
          spans,
        );
      }
      final memberId = mentionIdFromMatch(mention);
      final alias = broadcastAliasFromMatch(mention);
      if (memberId != null) {
        spans.add(_buildMentionSpan(memberId, baseStyle));
      } else if (alias != null) {
        spans.add(_buildBroadcastMentionSpan(alias, baseStyle));
      }
      cursor = mention.end;
    }

    if (cursor < line.length) {
      _parseInlineMarkdownWithoutMentions(
        line.substring(cursor),
        baseStyle,
        spans,
      );
    }
  }

  void _parseInlineMarkdownWithoutMentions(
    String line,
    TextStyle baseStyle,
    List<InlineSpan> spans,
  ) {
    final segments = <_Segment>[];
    final matched = List.filled(line.length, false);

    // 1. Spoilers — highest precedence. The `||` delimiter is unambiguous
    // (two chars), so spoilers run first and everything inside them is
    // locked out of later passes. Consequence: `**||hidden||**` renders as
    // two dimmed `**` markers wrapping a spoiler-tinted interior, not as
    // bold. This matches Discord's behavior.
    for (final match in _spoiler.allMatches(line)) {
      if (_overlaps(matched, match.start, match.end)) continue;
      for (var i = match.start; i < match.end; i++) {
        matched[i] = true;
      }
      segments.add(
        _Segment(
          start: match.start,
          end: match.end,
          markerBefore: '||',
          markerAfter: '||',
          content: match.group(1)!,
          contentStyle: baseStyle.copyWith(
            backgroundColor: _onSurface.withAlpha(40),
          ),
        ),
      );
    }

    // 2. Bold stars — skip if overlapping spoiler.
    for (final match in _boldStar.allMatches(line)) {
      if (_overlaps(matched, match.start, match.end)) continue;
      for (var i = match.start; i < match.end; i++) {
        matched[i] = true;
      }
      segments.add(
        _Segment(
          start: match.start,
          end: match.end,
          markerBefore: '**',
          markerAfter: '**',
          content: match.group(1)!,
          contentStyle: baseStyle.copyWith(fontWeight: FontWeight.bold),
        ),
      );
    }

    // 3. Bold underscores — only non-overlapping.
    for (final match in _boldUnderscore.allMatches(line)) {
      if (_overlaps(matched, match.start, match.end)) continue;
      for (var i = match.start; i < match.end; i++) {
        matched[i] = true;
      }
      segments.add(
        _Segment(
          start: match.start,
          end: match.end,
          markerBefore: '__',
          markerAfter: '__',
          content: match.group(1)!,
          contentStyle: baseStyle.copyWith(fontWeight: FontWeight.bold),
        ),
      );
    }

    // 4. Italic star — only non-overlapping.
    for (final match in _italicStar.allMatches(line)) {
      if (_overlaps(matched, match.start, match.end)) continue;
      for (var i = match.start; i < match.end; i++) {
        matched[i] = true;
      }
      segments.add(
        _Segment(
          start: match.start,
          end: match.end,
          markerBefore: '*',
          markerAfter: '*',
          content: match.group(1)!,
          contentStyle: baseStyle.copyWith(fontStyle: FontStyle.italic),
        ),
      );
    }

    // 5. Italic underscore — only non-overlapping.
    for (final match in _italicUnderscore.allMatches(line)) {
      if (_overlaps(matched, match.start, match.end)) continue;
      for (var i = match.start; i < match.end; i++) {
        matched[i] = true;
      }
      segments.add(
        _Segment(
          start: match.start,
          end: match.end,
          markerBefore: '_',
          markerAfter: '_',
          content: match.group(1)!,
          contentStyle: baseStyle.copyWith(fontStyle: FontStyle.italic),
        ),
      );
    }

    segments.sort((a, b) => a.start.compareTo(b.start));

    final markerStyle = baseStyle.copyWith(color: _markerColor);
    var cursor = 0;

    for (final segment in segments) {
      if (cursor < segment.start) {
        spans.add(
          TextSpan(
            text: line.substring(cursor, segment.start),
            style: baseStyle,
          ),
        );
      }
      spans.add(TextSpan(text: segment.markerBefore, style: markerStyle));
      spans.add(TextSpan(text: segment.content, style: segment.contentStyle));
      spans.add(TextSpan(text: segment.markerAfter, style: markerStyle));
      cursor = segment.end;
    }

    if (cursor < line.length) {
      spans.add(TextSpan(text: line.substring(cursor), style: baseStyle));
    }

    if (segments.isEmpty && line.isEmpty) {
      spans.add(TextSpan(text: '', style: baseStyle));
    }
  }

  TextSpan _buildMentionSpan(String memberId, TextStyle baseStyle) {
    final member = _mentionMembers[memberId];
    final name = member?.name ?? 'Unknown';
    final mentionColor =
        member != null &&
            member.customColorEnabled &&
            member.customColorHex != null
        ? AppColors.fromHex(member.customColorHex!)
        : _mentionFallbackColor;
    return TextSpan(
      text: '@$name',
      style: baseStyle.copyWith(
        color: mentionColor,
        fontWeight: FontWeight.w600,
        backgroundColor: mentionColor.withValues(alpha: 0.16),
      ),
      semanticsLabel: '@$name',
    );
  }

  TextSpan _buildBroadcastMentionSpan(String alias, TextStyle baseStyle) {
    final text = '@$alias';
    return TextSpan(
      text: text,
      style: baseStyle.copyWith(
        color: _mentionFallbackColor,
        fontWeight: FontWeight.w600,
        backgroundColor: _mentionFallbackColor.withValues(alpha: 0.16),
      ),
      semanticsLabel: text,
    );
  }

  bool _sameMentionMembers(Map<String, Member> a, Map<String, Member> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null) return false;
      if (other.name != entry.value.name ||
          other.customColorEnabled != entry.value.customColorEnabled ||
          other.customColorHex != entry.value.customColorHex) {
        return false;
      }
    }
    return true;
  }

  bool _overlaps(List<bool> matched, int start, int end) {
    for (var i = start; i < end; i++) {
      if (matched[i]) return true;
    }
    return false;
  }
}

class _Segment {
  final int start;
  final int end;
  final String markerBefore;
  final String markerAfter;
  final String content;
  final TextStyle contentStyle;

  _Segment({
    required this.start,
    required this.end,
    required this.markerBefore,
    required this.markerAfter,
    required this.content,
    required this.contentStyle,
  });
}
