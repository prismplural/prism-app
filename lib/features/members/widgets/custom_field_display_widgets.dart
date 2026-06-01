import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/markdown/spoiler_syntax.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/utils/safe_link.dart';
import 'package:prism_plurality/shared/utils/text_presentation.dart';
import 'package:prism_plurality/shared/widgets/prism_markdown_text.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';

// ---------------------------------------------------------------------------
// Shared display widget helpers extracted from custom_fields_display.dart.
// These have no dependency on the registry or definitions — they are pure
// Flutter widgets used by both the display file and the definition files.
// ---------------------------------------------------------------------------

/// Renders a text value with inline markdown support (bold, italic, code) plus
/// tap-to-reveal `||spoiler||` pills.
///
/// Stateful so it can own the [SpoilerRevealController] for its spoilers and
/// reset reveal state when [data] changes.
class FieldInlineMarkdownText extends StatefulWidget {
  const FieldInlineMarkdownText(
    this.data, {
    super.key,
    this.style,
    this.textAlign = TextAlign.start,
  });

  final String data;
  final TextStyle? style;
  final TextAlign textAlign;

  @override
  State<FieldInlineMarkdownText> createState() =>
      _FieldInlineMarkdownTextState();
}

class _FieldInlineMarkdownTextState extends State<FieldInlineMarkdownText> {
  static final _spoiler = RegExp(r'\|\|(.+?)\|\|');
  // Simple `[label](url)` pattern. The URL group stops at the first ')' due
  // to `[^)]+`, so a URL that itself contains ')' (e.g. some Wikipedia links
  // like https://x/Foo_(bar)) is truncated and will link to the wrong target.
  // Such values should use a long-text field, which uses the full CommonMark
  // renderer.
  static final _link = RegExp(r'(?<!@)\[([^\]]+)\]\(([^)]+)\)');
  static final _boldStar = RegExp(r'\*\*(.+?)\*\*');
  static final _boldUnderscore = RegExp(r'__(.+?)__');
  static final _italicStar = RegExp(r'(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)');
  static final _italicUnderscore = RegExp(r'(?<!_)_(?!_)(.+?)(?<!_)_(?!_)');
  static final _code = RegExp(r'`(.+?)`');

  final _revealController = SpoilerRevealController();
  final _linkRecognizers = <TapGestureRecognizer>[];

  @override
  void didUpdateWidget(FieldInlineMarkdownText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _revealController.clear();
    }
    // Recognizers are disposed at the top of build(), not here.
  }

  @override
  void dispose() {
    for (final r in _linkRecognizers) {
      r.dispose();
    }
    _linkRecognizers.clear();
    _revealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Dispose last frame's recognizers before rebuilding spans. Must be the
    // top of build() so inherited-dependency rebuilds (e.g. Theme.of) don't
    // leak them.
    for (final r in _linkRecognizers) {
      r.dispose();
    }
    _linkRecognizers.clear();

    final data = widget.data;
    final theme = Theme.of(context);
    final baseStyle = textStyleForTextPresentation(
      widget.style ?? theme.textTheme.bodyMedium ?? const TextStyle(),
      data,
    );
    final codeColor = theme.colorScheme.surfaceContainerHighest;

    final segments = <_InlineMarkdownSegment>[];
    final matched = List.filled(data.length, false);

    void addMatches(
      RegExp pattern,
      TextStyle Function(TextStyle base) styleForMatch, {
      bool isSpoiler = false,
    }) {
      for (final match in pattern.allMatches(data)) {
        if (_overlaps(matched, match.start, match.end)) continue;
        for (var i = match.start; i < match.end; i++) {
          matched[i] = true;
        }
        segments.add(
          _InlineMarkdownSegment(
            start: match.start,
            end: match.end,
            content: match.group(1)!,
            style: styleForMatch(baseStyle),
            isSpoiler: isSpoiler,
          ),
        );
      }
    }

    void addLinkMatches() {
      for (final match in _link.allMatches(data)) {
        if (_overlaps(matched, match.start, match.end)) continue;
        for (var i = match.start; i < match.end; i++) {
          matched[i] = true;
        }
        final label = match.group(1)!;
        final rawUrl = match.group(2)!;
        if (safeExternalUri(rawUrl) != null) {
          final linkStyle = baseStyle.copyWith(
            color: theme.colorScheme.primary,
            decoration: TextDecoration.underline,
            decorationColor: theme.colorScheme.primary.withValues(alpha: 0.5),
          );
          segments.add(
            _InlineMarkdownSegment(
              start: match.start,
              end: match.end,
              content: label,
              style: linkStyle,
              url: rawUrl,
            ),
          );
        } else {
          // Unsafe URL: consume the syntax, render label as plain text.
          segments.add(
            _InlineMarkdownSegment(
              start: match.start,
              end: match.end,
              content: label,
              style: baseStyle,
            ),
          );
        }
      }
    }

    // Pass order (highest precedence first): spoiler → code → link → bold →
    // italic. Code runs before link so that a backtick-quoted string like
    // `[x](https://example.com)` renders as monospace literal code rather than
    // a tappable link (matches CommonMark: code spans outrank link syntax).
    addMatches(_spoiler, (base) => base, isSpoiler: true);
    addMatches(
      _code,
      (base) =>
          base.copyWith(fontFamily: 'monospace', backgroundColor: codeColor),
    );
    addLinkMatches();
    addMatches(_boldStar, (base) => base.copyWith(fontWeight: FontWeight.bold));
    addMatches(
      _boldUnderscore,
      (base) => base.copyWith(fontWeight: FontWeight.bold),
    );
    addMatches(
      _italicStar,
      (base) => base.copyWith(fontStyle: FontStyle.italic),
    );
    addMatches(
      _italicUnderscore,
      (base) => base.copyWith(fontStyle: FontStyle.italic),
    );

    if (segments.isEmpty) {
      return Text(data, style: baseStyle, textAlign: widget.textAlign);
    }

    segments.sort((a, b) => a.start.compareTo(b.start));
    final spans = <InlineSpan>[];
    var cursor = 0;
    // Document-order id per spoiler so each reveals independently (mirrors
    // SpoilerBuilder's keying for the flutter_markdown surfaces).
    var spoilerId = 0;

    for (final segment in segments) {
      if (cursor < segment.start) {
        spans.add(TextSpan(text: data.substring(cursor, segment.start)));
      }
      if (segment.isSpoiler) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: SpoilerPill(
              id: spoilerId++,
              text: segment.content,
              textStyle: baseStyle,
              theme: theme,
            ),
          ),
        );
      } else if (segment.url != null) {
        final r = TapGestureRecognizer()
          ..onTap = () => launchSafeExternalUri(segment.url);
        _linkRecognizers.add(r);
        spans.add(
          TextSpan(
            text: segment.content,
            style: segment.style,
            recognizer: r,
            semanticsLabel: segment.content,
          ),
        );
      } else {
        spans.add(TextSpan(text: segment.content, style: segment.style));
      }
      cursor = segment.end;
    }

    if (cursor < data.length) {
      spans.add(TextSpan(text: data.substring(cursor)));
    }

    return SpoilerRevealScope(
      notifier: _revealController,
      child: Text.rich(
        TextSpan(style: baseStyle, children: spans),
        textAlign: widget.textAlign,
      ),
    );
  }

  bool _overlaps(List<bool> matched, int start, int end) {
    for (var i = start; i < end; i++) {
      if (matched[i]) return true;
    }
    return false;
  }
}

class _InlineMarkdownSegment {
  const _InlineMarkdownSegment({
    required this.start,
    required this.end,
    required this.content,
    required this.style,
    this.isSpoiler = false,
    this.url,
  });

  final int start;
  final int end;
  final String content;
  final TextStyle style;
  final bool isSpoiler;
  final String? url;
}

/// Renders a long text value with a line/character preview and a "View more"
/// sheet opener when the text is truncated.
class FieldLongTextPreview extends StatelessWidget {
  const FieldLongTextPreview({
    super.key,
    required this.title,
    required this.data,
    this.style,
  });

  static const _previewCharacterLimit = 900;
  static const _previewLineLimit = 12;

  final String title;
  final String data;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _buildPreview(data);
    final isTruncated = preview != data;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PrismMarkdownText(
          data: isTruncated ? '$preview...' : data,
          enabled: true,
          baseStyle: style ?? theme.textTheme.bodyMedium,
        ),
        if (isTruncated) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => _openDetail(context),
            child: Text(
              'View more',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _openDetail(BuildContext context) {
    PrismSheet.showFullScreen<void>(
      context: context,
      builder: (context, scrollController) => _FieldDetailSheet(
        title: title,
        data: data,
        scrollController: scrollController,
      ),
    );
  }

  String _buildPreview(String raw) {
    final lines = raw.split('\n');
    var preview = lines.length > _previewLineLimit
        ? lines.take(_previewLineLimit).join('\n')
        : raw;

    if (preview.length > _previewCharacterLimit) {
      preview = preview.substring(0, _previewCharacterLimit);
      final lastWhitespace = preview.lastIndexOf(RegExp(r'\s'));
      if (lastWhitespace > _previewCharacterLimit * 0.65) {
        preview = preview.substring(0, lastWhitespace);
      }
    }

    return preview.trimRight();
  }
}

class _FieldDetailSheet extends StatelessWidget {
  const _FieldDetailSheet({
    required this.title,
    required this.data,
    required this.scrollController,
  });

  final String title;
  final String data;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        children: [
          PrismSheetTopBar(title: title),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              children: [
                PrismMarkdownText(
                  data: data,
                  enabled: true,
                  baseStyle: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders a hex color value with a circular color swatch preview.
class FieldColorDisplay extends StatelessWidget {
  const FieldColorDisplay({super.key, required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color? color;
    try {
      color = AppColors.fromHex(value);
    } catch (_) {
      color = null;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (color != null) ...[
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
          textAlign: TextAlign.end,
        ),
      ],
    );
  }
}
