import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';

/// A [TextEditingController] that highlights inline markdown syntax for chat.
///
/// Differences from [MarkdownEditingController] (used in notes):
/// - `__foo__` renders as **bold** (not underline), matching CommonMark.
/// - `_foo_` renders as *italic* (negative lookahead against `__`).
/// - No heading (`# `, `## `) or horizontal rule (`---`) highlighting.
/// - Marker dim alpha is 180 (softer than notes' 102).
class ChatMarkdownEditingController extends TextEditingController {
  static final _boldStar = RegExp(r'\*\*(.+?)\*\*');
  static final _boldUnderscore = RegExp(r'__(.+?)__');
  static final _italicStar =
      RegExp(r'(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)');
  static final _italicUnderscore =
      RegExp(r'(?<!_)_(?!_)(.+?)(?<!_)_(?!_)');

  Color _onSurface = AppColors.warmBlack;
  Color _markerColor = Colors.grey;
  TextStyle _baseStyle = const TextStyle();
  bool _themeReady = false;

  // Cache: parsed spans are expensive to build on every keystroke.
  // Invalidated when text changes or when updateTheme() is called.
  String? _cachedText;
  List<InlineSpan>? _cachedChildren;

  ChatMarkdownEditingController({super.text});

  void updateTheme(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    _onSurface = colorScheme.onSurface;
    _markerColor = colorScheme.onSurfaceVariant.withAlpha(180);
    _baseStyle = TextStyle(color: _onSurface);
    _themeReady = true;
    _cachedText = null;
    _cachedChildren = null;
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
    List<TextSpan> spans,
  ) {
    final segments = <_Segment>[];
    final matched = List.filled(line.length, false);

    // 1. Bold stars — highest precedence.
    for (final match in _boldStar.allMatches(line)) {
      for (var i = match.start; i < match.end; i++) {
        matched[i] = true;
      }
      segments.add(_Segment(
        start: match.start,
        end: match.end,
        markerBefore: '**',
        markerAfter: '**',
        content: match.group(1)!,
        contentStyle: baseStyle.copyWith(fontWeight: FontWeight.bold),
      ));
    }

    // 2. Bold underscores — only non-overlapping with #1.
    for (final match in _boldUnderscore.allMatches(line)) {
      if (_overlaps(matched, match.start, match.end)) continue;
      for (var i = match.start; i < match.end; i++) {
        matched[i] = true;
      }
      segments.add(_Segment(
        start: match.start,
        end: match.end,
        markerBefore: '__',
        markerAfter: '__',
        content: match.group(1)!,
        contentStyle: baseStyle.copyWith(fontWeight: FontWeight.bold),
      ));
    }

    // 3. Italic star — only non-overlapping.
    for (final match in _italicStar.allMatches(line)) {
      if (_overlaps(matched, match.start, match.end)) continue;
      for (var i = match.start; i < match.end; i++) {
        matched[i] = true;
      }
      segments.add(_Segment(
        start: match.start,
        end: match.end,
        markerBefore: '*',
        markerAfter: '*',
        content: match.group(1)!,
        contentStyle: baseStyle.copyWith(fontStyle: FontStyle.italic),
      ));
    }

    // 4. Italic underscore — only non-overlapping.
    for (final match in _italicUnderscore.allMatches(line)) {
      if (_overlaps(matched, match.start, match.end)) continue;
      for (var i = match.start; i < match.end; i++) {
        matched[i] = true;
      }
      segments.add(_Segment(
        start: match.start,
        end: match.end,
        markerBefore: '_',
        markerAfter: '_',
        content: match.group(1)!,
        contentStyle: baseStyle.copyWith(fontStyle: FontStyle.italic),
      ));
    }

    segments.sort((a, b) => a.start.compareTo(b.start));

    final markerStyle = baseStyle.copyWith(color: _markerColor);
    var cursor = 0;

    for (final segment in segments) {
      if (cursor < segment.start) {
        spans.add(TextSpan(
          text: line.substring(cursor, segment.start),
          style: baseStyle,
        ));
      }
      spans.add(TextSpan(text: segment.markerBefore, style: markerStyle));
      spans.add(TextSpan(text: segment.content, style: segment.contentStyle));
      spans.add(TextSpan(text: segment.markerAfter, style: markerStyle));
      cursor = segment.end;
    }

    if (cursor < line.length) {
      spans.add(TextSpan(
        text: line.substring(cursor),
        style: baseStyle,
      ));
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
