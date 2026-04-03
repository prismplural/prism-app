import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';

class MarkdownEditingController extends TextEditingController {
  static final _boldRegex = RegExp(r'\*\*(.+?)\*\*');
  static final _underlineRegex = RegExp(r'__(.+?)__');
  static final _italicRegex = RegExp(r'(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)');

  Color _onSurface = AppColors.warmBlack;
  Color _markerColor = Colors.grey;
  TextStyle _baseStyle = const TextStyle();
  bool _themeReady = false;

  MarkdownEditingController({super.text});

  void updateTheme(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    _onSurface = colorScheme.onSurface;
    _markerColor = colorScheme.onSurfaceVariant.withAlpha(102);
    _baseStyle = TextStyle(color: _onSurface);
    _themeReady = true;
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

    final mergedStyle = style?.merge(_baseStyle) ?? _baseStyle;
    final lines = text.split('\n');
    final spans = <TextSpan>[];
    var isFirstLine = true;

    for (final line in lines) {
      if (!isFirstLine) {
        spans.add(TextSpan(text: '\n', style: mergedStyle));
      }
      isFirstLine = false;

      if (line == '---') {
        spans.add(TextSpan(
          text: line,
          style: mergedStyle.copyWith(
            color: _markerColor,
            fontSize: (mergedStyle.fontSize ?? 14) * 0.85,
          ),
        ));
        continue;
      }

      if (line.startsWith('## ')) {
        spans.add(TextSpan(
          text: '## ',
          style: mergedStyle.copyWith(color: _markerColor),
        ));
        spans.add(TextSpan(
          text: line.substring(3),
          style: mergedStyle.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ));
        continue;
      }

      if (line.startsWith('# ')) {
        spans.add(TextSpan(
          text: '# ',
          style: mergedStyle.copyWith(color: _markerColor),
        ));
        spans.add(TextSpan(
          text: line.substring(2),
          style: mergedStyle.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ));
        continue;
      }

      _parseInlineMarkdown(line, mergedStyle, spans);
    }

    return TextSpan(style: style, children: spans);
  }

  void _parseInlineMarkdown(
    String line,
    TextStyle baseStyle,
    List<TextSpan> spans,
  ) {
    final segments = <_Segment>[];
    final matched = List.filled(line.length, false);

    for (final match in _boldRegex.allMatches(line)) {
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

    for (final match in _underlineRegex.allMatches(line)) {
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
        contentStyle: baseStyle.copyWith(
          decoration: TextDecoration.underline,
        ),
      ));
    }

    for (final match in _italicRegex.allMatches(line)) {
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
