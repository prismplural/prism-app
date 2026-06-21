/// Splits bio markdown into styled segments based on `:::` fenced directives,
/// so individual tables can opt into a border treatment that plain markdown
/// can't express per-table.
///
/// Syntax (each on its own line):
///   :::plain        → tables in this block render with NO borders
///   :::#RRGGBB       → tables in this block render with that border color
///                      (also accepts #RGB and #AARRGGBB)
///   :::left          → text in this block renders left-aligned
///   :::center        → text in this block renders centered
///   :::right         → text in this block renders right-aligned
///   :::justify       → text in this block renders justified
///   :::center plain  → compose text alignment with table styling
///   :::              → closes the current block
///
/// Anything outside a fence renders with the app's default table styling, so
/// existing bios are unaffected. Fences can nest; inner fences inherit outer
/// settings unless they override the same setting. An unclosed fence runs to
/// the end of the text.
///
/// Only a recognized directive opens a fence: `:::plain`, a valid hex color,
/// or one of the supported text alignment names. Any other `:::` line — an
/// unknown spec, an invalid hex color, or a stray bare `:::` outside an open
/// fence — is preserved verbatim as literal content and passed through to the
/// markdown renderer rather than being dropped.
library;

import 'dart:ui' show Color, TextAlign;

/// A contiguous run of markdown plus optional Prism-specific presentation.
class MarkdownSegment {
  const MarkdownSegment({
    required this.content,
    this.borderless = false,
    this.borderColor,
    this.textAlign,
  });

  final String content;

  /// Render tables in this segment with no borders (and a neutral header row).
  final bool borderless;

  /// Render table borders in this color (ignored when [borderless] is true).
  /// Null → app default border.
  final Color? borderColor;

  /// Text alignment for prose in this segment. Null → app default alignment.
  final TextAlign? textAlign;

  /// Whether this segment uses the default presentation.
  bool get isDefault => !borderless && borderColor == null && textAlign == null;
}

// A `:::` directive line (optionally indented). Group 1 is the spec (`plain`,
// `#FF8800`, `center`, or empty for a closing fence). `\r?` before `$` is
// necessary because Dart's `.` doesn't match `\r`, so a CRLF line would fail
// entirely.
final _fenceLine = RegExp(r'^\s*:::[ \t]*(.*?)[ \t]*\r?$');

/// Parse [markdown] into ordered [MarkdownSegment]s split on `:::` fences.
/// Returns a single default segment when there are no fences.
List<MarkdownSegment> parseStyledSegments(String markdown) {
  if (!markdown.contains(':::')) {
    return [MarkdownSegment(content: markdown)];
  }

  final segments = <MarkdownSegment>[];
  final buf = <String>[];
  final styleStack = <_FenceStyle>[];
  _MarkdownCodeFence? codeFence;

  void flush() {
    if (buf.isEmpty) return;
    final content = buf.join('\n');
    buf.clear();
    if (content.trim().isEmpty) return; // skip whitespace-only runs
    final style = _effectiveStyle(styleStack);
    segments.add(
      MarkdownSegment(
        content: content,
        borderless: style.borderless,
        borderColor: style.borderColor,
        textAlign: style.textAlign,
      ),
    );
  }

  for (final line in markdown.split('\n')) {
    if (codeFence != null) {
      buf.add(line);
      if (_closesMarkdownCodeFence(line, codeFence)) codeFence = null;
      continue;
    }

    final openedCodeFence = _opensMarkdownCodeFence(line);
    if (openedCodeFence != null) {
      buf.add(line);
      codeFence = openedCodeFence;
      continue;
    }

    final m = _fenceLine.firstMatch(line);
    if (m != null) {
      final spec = (m.group(1) ?? '').trimRight();
      if (spec.isEmpty && styleStack.isNotEmpty) {
        flush();
        styleStack.removeLast();
        continue;
      }

      final style = _parseFenceStyle(spec);
      if (style != null) {
        flush();
        styleStack.add(style);
        continue;
      }
    }
    buf.add(line);
  }
  flush(); // unclosed fences run to EOF with their stacked style

  return segments.isEmpty ? [MarkdownSegment(content: markdown)] : segments;
}

/// Parse `#RGB`, `#RRGGBB`, or `#AARRGGBB` into a [Color]. Returns null for
/// anything else (caller treats null as "default border").
Color? parseHexColor(String spec) {
  var hex = spec.trim();
  if (!hex.startsWith('#')) return null;
  hex = hex.substring(1);
  if (hex.length == 3) {
    hex = hex.split('').map((c) => '$c$c').join();
  }
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;
  final value = int.tryParse(hex, radix: 16);
  return value == null ? null : Color(value);
}

TextAlign? _parseTextAlign(String spec) {
  switch (spec.trim().toLowerCase()) {
    case 'left':
      return TextAlign.left;
    case 'center':
      return TextAlign.center;
    case 'right':
      return TextAlign.right;
    case 'justify':
      return TextAlign.justify;
    default:
      return null;
  }
}

class _FenceStyle {
  const _FenceStyle({this.borderless, this.borderColor, this.textAlign});

  /// Null means this fence does not change table styling.
  final bool? borderless;
  final Color? borderColor;
  final TextAlign? textAlign;
}

class _ResolvedFenceStyle {
  const _ResolvedFenceStyle({
    required this.borderless,
    this.borderColor,
    this.textAlign,
  });

  final bool borderless;
  final Color? borderColor;
  final TextAlign? textAlign;
}

_FenceStyle? _parseFenceStyle(String spec) {
  final tokens = spec
      .trim()
      .split(RegExp(r'[ \t]+'))
      .where((token) => token.isNotEmpty);
  bool? borderless;
  Color? borderColor;
  TextAlign? textAlign;
  var recognized = false;

  for (final token in tokens) {
    final lower = token.toLowerCase();
    final color = parseHexColor(token);
    final align = _parseTextAlign(token);
    if (lower == 'plain') {
      recognized = true;
      borderless = true;
      borderColor = null;
    } else if (color != null) {
      recognized = true;
      borderless = false;
      borderColor = color;
    } else if (align != null) {
      recognized = true;
      textAlign = align;
    } else {
      return null;
    }
  }

  return recognized
      ? _FenceStyle(
          borderless: borderless,
          borderColor: borderColor,
          textAlign: textAlign,
        )
      : null;
}

_ResolvedFenceStyle _effectiveStyle(List<_FenceStyle> stack) {
  var borderless = false;
  Color? borderColor;
  TextAlign? textAlign;

  for (final style in stack) {
    if (style.borderless != null) {
      borderless = style.borderless!;
      borderColor = style.borderColor;
    }
    if (style.textAlign != null) {
      textAlign = style.textAlign;
    }
  }

  return _ResolvedFenceStyle(
    borderless: borderless,
    borderColor: borderColor,
    textAlign: textAlign,
  );
}

class _MarkdownCodeFence {
  const _MarkdownCodeFence(this.character, this.length);

  final String character;
  final int length;
}

_MarkdownCodeFence? _opensMarkdownCodeFence(String line) {
  final marker = _markdownCodeFenceMarker(line);
  return marker == null ? null : _MarkdownCodeFence(marker[0], marker.length);
}

bool _closesMarkdownCodeFence(String line, _MarkdownCodeFence fence) {
  final marker = _markdownCodeFenceMarker(line);
  if (marker == null ||
      marker[0] != fence.character ||
      marker.length < fence.length) {
    return false;
  }

  final markerStart = line.indexOf(marker);
  final rest = line.substring(markerStart + marker.length);
  return rest.trim().isEmpty;
}

String? _markdownCodeFenceMarker(String line) {
  var index = 0;
  while (index < line.length && index < 3 && line.codeUnitAt(index) == _space) {
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

const _space = 0x20;
const _backtick = 0x60;
const _tilde = 0x7e;
