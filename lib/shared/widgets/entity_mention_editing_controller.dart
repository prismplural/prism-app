import 'package:flutter/material.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/providers/profile_entity_mentions_provider.dart';
import 'package:prism_plurality/shared/mentions/entity_mention.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';

class EntityMentionEditingController extends TextEditingController {
  EntityMentionEditingController({super.text});

  static final _boldStar = RegExp(r'\*\*(.+?)\*\*');
  static final _boldUnderscore = RegExp(r'__(.+?)__');
  static final _italicStar = RegExp(r'(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)');
  static final _italicUnderscore = RegExp(r'(?<!_)_(?!_)(.+?)(?<!_)_(?!_)');
  static final _code = RegExp(r'`(.+?)`');

  Color _onSurface = AppColors.warmBlack;
  Color _markerColor = Colors.grey;
  Color _mentionFallbackColor = AppColors.prismPurple;
  TextStyle _baseStyle = const TextStyle();
  bool _themeReady = false;
  bool _markdownEnabled = true;
  Map<EntityMentionTarget, ProfileEntityMentionResolution> _resolutions =
      const {};
  String _hiddenLabel = 'Private';

  String? _cachedText;
  List<InlineSpan>? _cachedChildren;

  void updateTheme(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    _onSurface = colorScheme.onSurface;
    _markerColor = colorScheme.onSurfaceVariant.withAlpha(130);
    _mentionFallbackColor = colorScheme.primary;
    _baseStyle = TextStyle(color: _onSurface);
    _themeReady = true;
    _cachedText = null;
    _cachedChildren = null;
  }

  bool updateMarkdownEnabled(bool enabled, {bool notify = true}) {
    if (_markdownEnabled == enabled) return false;
    _markdownEnabled = enabled;
    _cachedText = null;
    _cachedChildren = null;
    if (notify) notifyListeners();
    return true;
  }

  bool updateMentionResolutions({
    required Map<EntityMentionTarget, ProfileEntityMentionResolution>
    resolutions,
    required String hiddenLabel,
    bool notify = true,
  }) {
    if (_sameResolutions(_resolutions, resolutions) &&
        _hiddenLabel == hiddenLabel) {
      return false;
    }
    _resolutions =
        Map<EntityMentionTarget, ProfileEntityMentionResolution>.unmodifiable(
          resolutions,
        );
    _hiddenLabel = hiddenLabel;
    _cachedText = null;
    _cachedChildren = null;
    if (notify) notifyListeners();
    return true;
  }

  void notifyPresentationChanged() => notifyListeners();

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

    if (_cachedText == text && _cachedChildren != null) {
      return TextSpan(style: style, children: _cachedChildren);
    }

    final mergedStyle = style?.merge(_baseStyle) ?? _baseStyle;
    final lines = text.split('\n');
    final spans = <InlineSpan>[];
    var isFirstLine = true;

    for (final line in lines) {
      if (!isFirstLine) {
        spans.add(TextSpan(text: '\n', style: mergedStyle));
      }
      isFirstLine = false;

      if (!_markdownEnabled) {
        _parseMentionTokensOnly(line, mergedStyle, spans);
        continue;
      }

      if (line == '---') {
        spans.add(
          TextSpan(
            text: line,
            style: mergedStyle.copyWith(
              color: _markerColor,
              fontSize: (mergedStyle.fontSize ?? 14) * 0.85,
            ),
          ),
        );
        continue;
      }

      if (line.startsWith('## ')) {
        spans.add(TextSpan(text: '## ', style: _markerStyle(mergedStyle)));
        _parseInlineMarkdown(
          line.substring(3),
          mergedStyle.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
          spans,
        );
        continue;
      }

      if (line.startsWith('# ')) {
        spans.add(TextSpan(text: '# ', style: _markerStyle(mergedStyle)));
        _parseInlineMarkdown(
          line.substring(2),
          mergedStyle.copyWith(fontSize: 20, fontWeight: FontWeight.bold),
          spans,
        );
        continue;
      }

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
    final mentions = extractEntityMentions(line);
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
      spans.add(_buildMentionSpan(mention.target, baseStyle));
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

  void _parseMentionTokensOnly(
    String line,
    TextStyle baseStyle,
    List<InlineSpan> spans,
  ) {
    final mentions = extractEntityMentions(line);
    if (mentions.isEmpty) {
      spans.add(TextSpan(text: line, style: baseStyle));
      return;
    }

    var cursor = 0;
    for (final mention in mentions) {
      if (mention.start > cursor) {
        spans.add(
          TextSpan(
            text: line.substring(cursor, mention.start),
            style: baseStyle,
          ),
        );
      }
      spans.add(_buildMentionSpan(mention.target, baseStyle));
      cursor = mention.end;
    }
    if (cursor < line.length) {
      spans.add(TextSpan(text: line.substring(cursor), style: baseStyle));
    }
  }

  void _parseInlineMarkdownWithoutMentions(
    String line,
    TextStyle baseStyle,
    List<InlineSpan> spans,
  ) {
    final segments = <_Segment>[];
    final matched = List.filled(line.length, false);

    void addMatches(
      RegExp pattern,
      String markerBefore,
      String markerAfter,
      TextStyle Function(TextStyle base) styleForMatch,
    ) {
      for (final match in pattern.allMatches(line)) {
        if (_overlaps(matched, match.start, match.end)) continue;
        for (var i = match.start; i < match.end; i++) {
          matched[i] = true;
        }
        segments.add(
          _Segment(
            start: match.start,
            end: match.end,
            markerBefore: markerBefore,
            markerAfter: markerAfter,
            content: match.group(1)!,
            contentStyle: styleForMatch(baseStyle),
          ),
        );
      }
    }

    addMatches(
      _code,
      '`',
      '`',
      (base) => base.copyWith(
        fontFamily: 'monospace',
        backgroundColor: _onSurface.withAlpha(18),
      ),
    );
    addMatches(
      _boldStar,
      '**',
      '**',
      (base) => base.copyWith(fontWeight: FontWeight.bold),
    );
    addMatches(
      _boldUnderscore,
      '__',
      '__',
      (base) => base.copyWith(fontWeight: FontWeight.bold),
    );
    addMatches(
      _italicStar,
      '*',
      '*',
      (base) => base.copyWith(fontStyle: FontStyle.italic),
    );
    addMatches(
      _italicUnderscore,
      '_',
      '_',
      (base) => base.copyWith(fontStyle: FontStyle.italic),
    );

    segments.sort((a, b) => a.start.compareTo(b.start));
    final markerStyle = _markerStyle(baseStyle);
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

  TextSpan _buildMentionSpan(EntityMentionTarget target, TextStyle baseStyle) {
    final resolution =
        _resolutions[target] ??
        ProfileEntityMentionResolution(target: target, visible: false);
    final text = target.token;
    final member = resolution.entity is Member
        ? resolution.entity as Member
        : null;
    final color =
        member != null &&
            member.customColorEnabled &&
            member.customColorHex != null
        ? AppColors.fromHex(member.customColorHex!)
        : resolution.visible
        ? _mentionFallbackColor
        : _markerColor;

    return TextSpan(
      text: text,
      style: baseStyle.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
        backgroundColor: color.withValues(
          alpha: resolution.visible ? 0.16 : 0.1,
        ),
      ),
      semanticsLabel: text,
    );
  }

  TextStyle _markerStyle(TextStyle baseStyle) =>
      baseStyle.copyWith(color: _markerColor);

  bool _overlaps(List<bool> matched, int start, int end) {
    for (var i = start; i < end; i++) {
      if (matched[i]) return true;
    }
    return false;
  }

  bool _sameResolutions(
    Map<EntityMentionTarget, ProfileEntityMentionResolution> a,
    Map<EntityMentionTarget, ProfileEntityMentionResolution> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null) return false;
      if (other.visible != entry.value.visible ||
          other.label != entry.value.label ||
          other.entity != entry.value.entity) {
        return false;
      }
    }
    return true;
  }
}

class _Segment {
  _Segment({
    required this.start,
    required this.end,
    required this.markerBefore,
    required this.markerAfter,
    required this.content,
    required this.contentStyle,
  });

  final int start;
  final int end;
  final String markerBefore;
  final String markerAfter;
  final String content;
  final TextStyle contentStyle;
}
