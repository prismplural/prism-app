import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
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
    this.builders,
    this.inlineSyntaxes,
    this.extensionSet,
  });

  /// The text content (plain or Markdown).
  final String data;

  /// Whether to render as Markdown. When false, displays as plain [Text].
  final bool enabled;

  /// Optional base text style applied to the body text.
  final TextStyle? baseStyle;

  /// Whether the rendered text is selectable.
  final bool selectable;

  final Map<String, MarkdownElementBuilder>? builders;

  final List<md.InlineSyntax>? inlineSyntaxes;

  final md.ExtensionSet? extensionSet;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return Text(data, style: baseStyle);
    }

    final theme = Theme.of(context);
    final sheet = _buildStyleSheet(context, theme);

    return MarkdownBody(
      data: _normalizeDiscordLikeIndentation(data),
      selectable: selectable,
      styleSheet: sheet,
      softLineBreak: true,
      builders: builders ?? const <String, MarkdownElementBuilder>{},
      inlineSyntaxes: inlineSyntaxes,
      extensionSet: extensionSet,
      onTapLink: (_, href, _) => _launchSafeLink(href),
      imageBuilder: (uri, title, alt) => const SizedBox.shrink(),
      checkboxBuilder: (checked) => _buildTaskListCheckbox(
        theme: theme,
        style: sheet.checkbox,
        padding: sheet.listBulletPadding,
        checked: checked,
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

    return base.copyWith(
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

final _blockquoteMarker = RegExp(r'^(?:>{1,3})(?:[ \t]|$)');
final _headingMarker = RegExp(r'^#{1,6}(?:[ \t]|$)');
final _listMarker = RegExp(r'^(?:[*+-]|\d{1,9}[.)])(?:[ \t]|$)');
final _thematicBreakMarker = RegExp(r'^(?:[-*_][ \t]*){3,}$');
