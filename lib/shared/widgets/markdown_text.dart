import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:prism_plurality/shared/markdown/spoiler_syntax.dart';
import 'package:prism_plurality/shared/markdown/subtext_syntax.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:url_launcher/url_launcher.dart';

/// Renders text as Markdown when [enabled], otherwise as plain [Text].
///
/// Images are disabled (rendered as empty boxes). Links are opened externally
/// except for unsafe schemes. HTML tags are not rendered.
class MarkdownText extends StatelessWidget {
  const MarkdownText({
    super.key,
    required this.data,
    this.enabled = true,
    this.baseStyle,
    this.selectable = false,
    this.imageBuilder,
    this.imgElementBuilder,
    this.tableBorderless = false,
    this.tableBorderColor,
  });

  /// The text content (plain or Markdown).
  final String data;

  /// Whether to render as Markdown. When false, displays as plain [Text].
  final bool enabled;

  /// Optional base text style applied to the body text.
  final TextStyle? baseStyle;

  /// Whether the rendered text is selectable.
  final bool selectable;

  /// Optional image builder. When null, images are suppressed (empty box).
  final Widget Function(Uri uri, String? title, String? alt)? imageBuilder;

  /// Optional custom element builder for `img` tags. Takes precedence over
  /// [imageBuilder] and receives the raw `src` attribute (including any
  /// `#WxH` sizing fragment, which the default image path strips).
  final MarkdownElementBuilder? imgElementBuilder;

  /// Render tables with no borders and a neutral (non-bold) header row. Used
  /// for `:::plain` layout tables (image-beside-text) so they read clean.
  final bool tableBorderless;

  /// Render table borders in this color (ignored when [tableBorderless]).
  /// Null → the default theme border.
  final Color? tableBorderColor;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return Text(data, style: baseStyle);
    }

    final theme = Theme.of(context);
    final sheet = _buildStyleSheet(context, theme);
    final bodyStyle = sheet.p ?? baseStyle ?? const TextStyle();

    // `revealKey: data` resets reveal state when the rendered content changes,
    // so a reused widget slot never shows a stale spoiler as already revealed.
    return _SpoilerRevealHost(
      revealKey: data,
      child: MarkdownBody(
        data: preserveBlankLines(_normalizeDiscordLikeIndentation(data)),
        selectable: selectable,
        styleSheet: sheet,
        softLineBreak: true,
        onTapLink: (_, href, _) => _launchSafeLink(href),
        imageBuilder:
            imageBuilder ?? (uri, title, alt) => const SizedBox.shrink(),
        checkboxBuilder: (checked) => _buildTaskListCheckbox(
          theme: theme,
          style: sheet.checkbox,
          padding: sheet.listBulletPadding,
          checked: checked,
        ),
        extensionSet: md.ExtensionSet(
          [
            const SubtextBlockSyntax(),
            ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
          ],
          [SpoilerSyntax(), ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes],
        ),
        builders: {
          'subtext': SubtextBuilder(
            baseStyle: bodyStyle,
            mutedColor: theme.colorScheme.onSurfaceVariant,
            codeBackground: theme.colorScheme.surfaceContainerHighest,
            linkColor: theme.colorScheme.primary,
            // ignore: unnecessary_lambdas — adapts non-null href to nullable handler
            onTapLink: (href) => _launchSafeLink(href),
          ),
          'spoiler': SpoilerBuilder(theme: theme),
          'img': ?imgElementBuilder,
        },
      ),
    );
  }

  MarkdownStyleSheet _buildStyleSheet(BuildContext context, ThemeData theme) {
    final base = MarkdownStyleSheet.fromTheme(theme);

    // Strip letter spacing from all text styles and apply reasonable heading caps.
    TextStyle strip(TextStyle? style) =>
        (style ?? const TextStyle()).copyWith(letterSpacing: 0);

    final radius = PrismShapes.of(context).radius(8);
    final mutedSurface = theme.colorScheme.surfaceContainerHighest;
    final mutedFg = theme.colorScheme.onSurfaceVariant;

    final sheet = base.copyWith(
      p: strip(baseStyle ?? base.p),
      a: strip(base.a).copyWith(
        color: theme.colorScheme.primary,
        decoration: TextDecoration.underline,
        decorationColor: theme.colorScheme.primary.withValues(alpha: 0.5),
      ),
      h1: strip(base.h1).copyWith(fontSize: 24, fontWeight: FontWeight.bold),
      h2: strip(base.h2).copyWith(fontSize: 21, fontWeight: FontWeight.bold),
      h3: strip(base.h3).copyWith(fontSize: 18, fontWeight: FontWeight.w600),
      h4: strip(base.h4).copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      h5: strip(base.h5).copyWith(fontSize: 15),
      h6: strip(base.h6).copyWith(fontSize: 14),
      em: strip(base.em),
      strong: strip(base.strong),
      blockquote: strip(base.blockquote).copyWith(color: mutedFg),
      blockquoteDecoration: BoxDecoration(
        color: mutedSurface,
        borderRadius: BorderRadius.circular(radius),
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 3),
        ),
      ),
      listBullet: strip(base.listBullet),
      checkbox: strip(
        base.checkbox,
      ).copyWith(color: mutedFg.withValues(alpha: 0.92)),
      code: strip(base.code).copyWith(backgroundColor: mutedSurface),
      codeblockDecoration: BoxDecoration(
        color: mutedSurface,
        borderRadius: BorderRadius.circular(radius),
      ),
    );

    // Per-segment table border treatment (from `:::plain` / `:::#hex` fences).
    if (tableBorderless) {
      // No gridlines, and a neutral header row so layout tables (image-beside-
      // text) don't get the default bold/spreadsheet look.
      return sheet.copyWith(
        tableBorder: const TableBorder(),
        tableHead: sheet.tableBody ?? sheet.p,
      );
    }
    if (tableBorderColor != null) {
      return sheet.copyWith(
        tableBorder: TableBorder.all(color: tableBorderColor!),
      );
    }
    return sheet;
  }

  Widget _buildTaskListCheckbox({
    required ThemeData theme,
    required TextStyle? style,
    required EdgeInsets? padding,
    required bool checked,
  }) {
    return Padding(
      padding: padding ?? const EdgeInsets.only(right: 4),
      child: Icon(
        checked ? Icons.check_box : Icons.check_box_outline_blank,
        size: (style?.fontSize ?? baseStyle?.fontSize ?? 14) + 2,
        color: checked
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.92),
      ),
    );
  }

  Future<void> _launchSafeLink(String? href) async {
    final uri = href != null ? Uri.tryParse(href) : null;
    final scheme = uri?.scheme.toLowerCase();
    if (uri == null ||
        scheme == null ||
        scheme.isEmpty ||
        scheme == 'javascript' ||
        scheme == 'data') {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _normalizeDiscordLikeIndentation(String input) {
    // Discord-style profile text uses fenced code blocks; four leading ASCII
    // spaces are often decorative indentation, not an implicit code block.
    if (input.isEmpty) return input;

    final lines = input.split('\n');
    final out = <String>[];
    _MarkdownFence? fence;

    for (final line in lines) {
      final accidentallyIndented = _removeAccidentalCodeIndent(line);

      if (fence != null) {
        final candidate = accidentallyIndented ?? line;
        if (_isClosingFence(candidate, fence)) {
          out.add(candidate);
          fence = null;
        } else {
          out.add(line);
        }
        continue;
      }

      if (accidentallyIndented != null) {
        final openingFence = _openingFence(accidentallyIndented);
        if (openingFence != null ||
            _startsWithDiscordStyleBlockMarker(accidentallyIndented)) {
          out.add(accidentallyIndented);
          fence = openingFence;
        } else {
          out.add(_replaceLeadingAsciiWhitespaceWithNbsp(line));
        }
        continue;
      }

      out.add(line);
      fence = _openingFence(line);
    }

    return out.join('\n');
  }

  String? _removeAccidentalCodeIndent(String line) {
    var columns = 0;
    var index = 0;
    while (index < line.length) {
      final unit = line.codeUnitAt(index);
      if (unit == _space) {
        columns += 1;
      } else if (unit == _tab) {
        columns += 4 - (columns % 4);
      } else {
        break;
      }
      index += 1;
    }

    return columns >= 4 ? line.substring(index) : null;
  }

  String _replaceLeadingAsciiWhitespaceWithNbsp(String line) {
    final buffer = StringBuffer();
    var index = 0;
    while (index < line.length) {
      final unit = line.codeUnitAt(index);
      if (unit == _space) {
        buffer.write(_nbsp);
      } else if (unit == _tab) {
        buffer.write(_nbsp * 4);
      } else {
        break;
      }
      index += 1;
    }
    buffer.write(line.substring(index));
    return buffer.toString();
  }

  bool _startsWithDiscordStyleBlockMarker(String line) {
    return _blockquoteMarker.hasMatch(line) ||
        _headingMarker.hasMatch(line) ||
        _listMarker.hasMatch(line) ||
        _subtextMarker.hasMatch(line) ||
        _thematicBreakMarker.hasMatch(line);
  }

  _MarkdownFence? _openingFence(String line) {
    final marker = _fenceMarker(line);
    return marker == null ? null : _MarkdownFence(marker[0], marker.length);
  }

  bool _isClosingFence(String line, _MarkdownFence fence) {
    final marker = _fenceMarker(line);
    if (marker == null ||
        marker[0] != fence.character ||
        marker.length < fence.length) {
      return false;
    }

    final markerStart = line.indexOf(marker);
    final rest = line.substring(markerStart + marker.length);
    return rest.trim().isEmpty;
  }

  String? _fenceMarker(String line) {
    var index = 0;
    while (index < line.length &&
        index < 3 &&
        line.codeUnitAt(index) == _space) {
      index += 1;
    }
    if (index >= line.length || line.codeUnitAt(index) == _space) return null;

    final unit = line.codeUnitAt(index);
    if (unit != _backtick && unit != _tilde) return null;

    var end = index;
    while (end < line.length && line.codeUnitAt(end) == unit) {
      end += 1;
    }
    if (end - index < 3) return null;
    return line.substring(index, end);
  }
}

/// Owns the [SpoilerRevealController] for a [MarkdownText] subtree and exposes
/// it to the `||spoiler||` pills via [SpoilerRevealScope].
///
/// Held in a `StatefulWidget` so the controller is disposed with the subtree
/// and reveal state resets when [revealKey] (the rendered content) changes.
class _SpoilerRevealHost extends StatefulWidget {
  const _SpoilerRevealHost({required this.revealKey, required this.child});

  final String revealKey;
  final Widget child;

  @override
  State<_SpoilerRevealHost> createState() => _SpoilerRevealHostState();
}

class _SpoilerRevealHostState extends State<_SpoilerRevealHost> {
  final _controller = SpoilerRevealController();

  @override
  void didUpdateWidget(_SpoilerRevealHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revealKey != widget.revealKey) {
      _controller.clear();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SpoilerRevealScope(notifier: _controller, child: widget.child);
  }
}

/// Replaces blank lines with NBSP lines so Markdown keeps plain-text spacing.
/// Fenced code blocks are left untouched.
@visibleForTesting
String preserveBlankLines(String input) {
  if (input.isEmpty) return input;

  final lines = input.split('\n');
  final out = <String>[];
  String? fenceMarker;

  var i = 0;
  while (i < lines.length) {
    final line = lines[i];

    if (fenceMarker != null) {
      out.add(line);
      final match = _fenceOpenPattern.firstMatch(line);
      if (match != null) {
        final marker = match[1]!;
        if (marker[0] == fenceMarker[0] &&
            marker.length >= fenceMarker.length &&
            line.substring(match.end).trim().isEmpty) {
          fenceMarker = null;
        }
      }
      i++;
      continue;
    }

    final match = _fenceOpenPattern.firstMatch(line);
    if (match != null) {
      out.add(line);
      fenceMarker = match[1]!;
      i++;
      continue;
    }

    if (_blankLinePattern.hasMatch(line)) {
      var count = 0;
      var j = i;
      while (j < lines.length && _blankLinePattern.hasMatch(lines[j])) {
        count++;
        j++;
      }
      for (var k = 0; k < count; k++) {
        out.add(_nbsp);
      }
      i = j;
      continue;
    }

    out.add(line);
    i++;
  }

  return out.join('\n');
}

class _MarkdownFence {
  const _MarkdownFence(this.character, this.length);

  final String character;
  final int length;
}

const _space = 0x20;
const _tab = 0x09;
const _backtick = 0x60;
const _tilde = 0x7e;
const _nbsp = '\u00A0';

final _blankLinePattern = RegExp(r'^[ \t\r]*$');
final _fenceOpenPattern = RegExp(r'^ {0,3}(`{3,}|~{3,})');

final _blockquoteMarker = RegExp(r'^(?:>{1,3})(?:[ \t]|$)');
final _headingMarker = RegExp(r'^#{1,6}(?:[ \t]|$)');
final _listMarker = RegExp(r'^(?:[*+-]|\d{1,9}[.)])(?:[ \t]|$)');
final _subtextMarker = RegExp(r'^-#[ \t]');
final _thematicBreakMarker = RegExp(r'^(?:[-*_][ \t]*){3,}$');
