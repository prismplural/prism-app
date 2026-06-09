import 'package:flutter/material.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/shared/markdown/member_mention_syntax.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/utils/text_presentation.dart';

class MarkdownEditingController extends TextEditingController {
  static final _spoilerRegex = RegExp(r'\|\|(.+?)\|\|');
  static final _boldRegex = RegExp(r'\*\*(.+?)\*\*');
  static final _underlineRegex = RegExp(r'__(.+?)__');
  static final _italicRegex = RegExp(r'(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)');

  Color _onSurface = AppColors.warmBlack;
  Color _markerColor = Colors.grey;
  Color _mentionFallbackColor = AppColors.prismPurple;
  TextStyle _baseStyle = const TextStyle();
  bool _themeReady = false;
  Map<String, Member> _mentionMembers = const {};

  // Cache: parsed spans are expensive to build on every keystroke.
  // Invalidated when text changes or when updateTheme() is called.
  String? _cachedText;
  List<TextSpan>? _cachedChildren;

  MarkdownEditingController({super.text});

  void updateTheme(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    _onSurface = colorScheme.onSurface;
    _markerColor = colorScheme.onSurfaceVariant.withAlpha(102);
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
    final textStyle = textStyleForTextPresentation(mergedStyle, text);
    final lines = text.split('\n');
    final spans = <TextSpan>[];
    var isFirstLine = true;

    for (final line in lines) {
      if (!isFirstLine) {
        spans.add(TextSpan(text: '\n', style: textStyle));
      }
      isFirstLine = false;

      if (line == '---') {
        spans.add(
          TextSpan(
            text: line,
            style: textStyle.copyWith(
              color: _markerColor,
              fontSize: (textStyle.fontSize ?? 14) * 0.85,
            ),
          ),
        );
        continue;
      }

      if (line.startsWith('## ')) {
        spans.add(
          TextSpan(
            text: '## ',
            style: textStyle.copyWith(color: _markerColor),
          ),
        );
        // Parse the heading body so inline markers (spoilers, bold, …) still
        // style inside a heading, matching the rendered output.
        _parseInlineMarkdown(
          line.substring(3),
          textStyle.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
          spans,
        );
        continue;
      }

      if (line.startsWith('# ')) {
        spans.add(
          TextSpan(
            text: '# ',
            style: textStyle.copyWith(color: _markerColor),
          ),
        );
        _parseInlineMarkdown(
          line.substring(2),
          textStyle.copyWith(fontSize: 20, fontWeight: FontWeight.bold),
          spans,
        );
        continue;
      }

      _parseInlineMarkdown(line, textStyle, spans);
    }

    _cachedText = text;
    _cachedChildren = List.unmodifiable(spans);
    return TextSpan(style: style, children: spans);
  }

  void _parseInlineMarkdown(
    String line,
    TextStyle baseStyle,
    List<TextSpan> spans,
  ) {
    final mentions = memberMentionRegex.allMatches(line).toList();
    if (mentions.isNotEmpty) {
      var cursor = 0;
      for (final mention in mentions) {
        if (mention.start > cursor) {
          _parseInlineMarkdownWithoutMentions(
            line.substring(cursor, mention.start),
            baseStyle,
            spans,
          );
        }
        final memberId = memberMentionIdFromMatch(mention)!;
        final member = _mentionMembers[memberId];
        final mentionColor =
            member != null &&
                member.customColorEnabled &&
                member.customColorHex != null
            ? AppColors.fromHex(member.customColorHex!)
            : _mentionFallbackColor;
        final display = '@${member?.name ?? 'Unknown'}';
        final hiddenLength = mention.end - mention.start - display.length;
        spans.add(
          TextSpan(
            children: [
              TextSpan(
                text: display,
                style: baseStyle.copyWith(
                  color: mentionColor,
                  fontWeight: FontWeight.w600,
                  backgroundColor: mentionColor.withValues(alpha: 0.16),
                ),
                semanticsLabel: display,
              ),
              if (hiddenLength > 0)
                TextSpan(
                  text: '\u200B' * hiddenLength,
                  style: baseStyle.copyWith(
                    color: Colors.transparent,
                    fontSize: 0,
                    height: 0,
                  ),
                ),
            ],
          ),
        );
        cursor = mention.end;
      }
      if (cursor < line.length) {
        _parseInlineMarkdownWithoutMentions(
          line.substring(cursor),
          baseStyle,
          spans,
        );
      }
      return;
    }

    _parseInlineMarkdownWithoutMentions(line, baseStyle, spans);
  }

  void _parseInlineMarkdownWithoutMentions(
    String line,
    TextStyle baseStyle,
    List<TextSpan> spans,
  ) {
    final segments = <_Segment>[];
    final matched = List.filled(line.length, false);

    // Spoilers run first: the `||` delimiter is unambiguous, so everything
    // inside a spoiler is locked out of later passes. `**||hidden||**` renders
    // as dimmed `**` markers wrapping a spoiler-tinted interior, not as bold —
    // matching the chat composer and the rendered output.
    for (final match in _spoilerRegex.allMatches(line)) {
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

    for (final match in _boldRegex.allMatches(line)) {
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

    for (final match in _underlineRegex.allMatches(line)) {
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
          contentStyle: baseStyle.copyWith(
            decoration: TextDecoration.underline,
          ),
        ),
      );
    }

    for (final match in _italicRegex.allMatches(line)) {
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

  bool _overlaps(List<bool> matched, int start, int end) {
    for (var i = start; i < end; i++) {
      if (matched[i]) return true;
    }
    return false;
  }

  bool _sameMentionMembers(Map<String, Member> a, Map<String, Member> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      final member = entry.value;
      if (other == null ||
          other.name != member.name ||
          other.customColorEnabled != member.customColorEnabled ||
          other.customColorHex != member.customColorHex) {
        return false;
      }
    }
    return true;
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
