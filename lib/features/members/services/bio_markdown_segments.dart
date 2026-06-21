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
///   :::              → closes the current block
///
/// Anything outside a fence renders with the app's default table styling, so
/// existing bios are unaffected. Fences do not nest; an unclosed fence runs to
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
  var inFence = false;
  var borderless = false;
  Color? color;
  TextAlign? textAlign;

  void flush({required bool fenced}) {
    if (buf.isEmpty) return;
    final content = buf.join('\n');
    buf.clear();
    if (content.trim().isEmpty) return; // skip whitespace-only runs
    segments.add(
      MarkdownSegment(
        content: content,
        borderless: fenced && borderless,
        borderColor: fenced ? color : null,
        textAlign: fenced ? textAlign : null,
      ),
    );
  }

  void clearFenceStyle() {
    borderless = false;
    color = null;
    textAlign = null;
  }

  for (final line in markdown.split('\n')) {
    final m = _fenceLine.firstMatch(line);
    if (m != null) {
      final spec = (m.group(1) ?? '').trimRight();
      if (inFence) {
        if (spec.isEmpty) {
          // A bare `:::` closes the open fence (and is consumed).
          flush(fenced: true);
          inFence = false;
          clearFenceStyle();
          continue;
        }
        // A non-empty `:::` spec inside a fence is literal content.
      } else {
        // Only known Prism directives open a fence; any other `:::` line falls
        // through to buf.add below as literal content.
        final isPlain = spec.toLowerCase() == 'plain';
        final parsed = parseHexColor(spec);
        final parsedAlign = _parseTextAlign(spec);
        if (isPlain || parsed != null || parsedAlign != null) {
          flush(fenced: false); // emit preceding default content
          inFence = true;
          clearFenceStyle();
          if (isPlain) {
            borderless = true;
          } else if (parsed != null) {
            color = parsed;
          } else {
            textAlign = parsedAlign;
          }
          continue;
        }
      }
    }
    buf.add(line);
  }
  flush(fenced: inFence); // unclosed fence runs to EOF

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
