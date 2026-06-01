/// Decides whether a markdown image renders inline (within a text run) or as a
/// block (its own line, text above/below), and rewrites markdown to promote
/// block-eligible images into their own paragraph.
///
/// Flutter's text engine has no float/wrap-around, so a large inline image (a
/// single tall `WidgetSpan`) leaves awkward gaps in the line. Instead we keep
/// small images inline (emoji / flag-in-a-sentence) and put larger ones on
/// their own line — the convention most chat/markdown apps (Discord, GitHub,
/// Slack) use.
library;

import 'package:prism_plurality/features/members/services/bio_image_size.dart';

/// At or above this logical-pixel size (in either dimension) an explicitly
/// sized image is promoted to a block; below it, it stays inline.
const double blockImageMinPx = 48.0;

// Matches an image token plus any surrounding spaces/tabs (group 1 = the
// token, group 2 = its src) so a promoted image doesn't leave stray spaces
// hugging the inserted blank lines.
final _imageToken = RegExp(r'[ \t]*(!\[[^\]]*\]\(([^)]*)\))[ \t]*');

/// Whether an image with [size] should render as a block (its own line).
///
/// Percent-sized and unsized images are blocks (typically banners / dividers /
/// decoration that want the full width). Explicitly small images stay inline.
bool isBlockImageSize(BioImageSize size) {
  if (size.widthFraction != null) return true; // percent → block
  if (size.width == null && size.height == null) return true; // unsized → block
  final w = size.width ?? 0;
  final h = size.height ?? 0;
  return w >= blockImageMinPx || h >= blockImageMinPx;
}

/// Rewrites [markdown] so every block-eligible image sits in its own paragraph
/// (blank line before and after), making it render on its own line with text
/// above/below instead of disrupting an inline text run. Small, explicitly
/// sized images are left inline. Non-image markdown is untouched.
///
/// Operates on the author's raw markdown (the size fragment here is the literal
/// `#50%`, not the URL-encoded form the parser later produces).
String blockifyImageMarkdown(String markdown) {
  if (!markdown.contains('![')) return markdown;

  final lines = markdown.split('\n');
  final out = <String>[];
  var pendingBlankAfterImage = false;

  void addLine(String line) {
    final isBlank = line.trim().isEmpty;
    if (!isBlank && pendingBlankAfterImage) {
      if (out.isNotEmpty && out.last.trim().isNotEmpty) out.add('');
      pendingBlankAfterImage = false;
    } else if (isBlank) {
      pendingBlankAfterImage = false;
    }
    out.add(line);
  }

  void addBlockImage(String imageToken) {
    if (out.isNotEmpty && out.last.trim().isNotEmpty) out.add('');
    out.add(imageToken);
    pendingBlankAfterImage = true;
  }

  void addTextSegment(String text) {
    if (text.isEmpty) return;
    addLine(text);
  }

  for (final line in lines) {
    // Pipe layouts stay inline; the image builder supplies the gutter.
    if (line.contains('|')) {
      addLine(line);
      continue;
    }

    final matches = _imageToken.allMatches(line).toList();
    if (matches.isEmpty) {
      addLine(line);
      continue;
    }

    var cursor = 0;
    var sawBlockImage = false;
    final textBuffer = StringBuffer();

    for (final match in matches) {
      final src = match.group(2) ?? '';
      final hashIdx = src.indexOf('#');
      final fragment = hashIdx >= 0 ? src.substring(hashIdx + 1) : null;
      final size = BioImageSize.parse(fragment);
      final imageToken = match.group(1)!;

      if (isBlockImageSize(size)) {
        sawBlockImage = true;
        textBuffer.write(line.substring(cursor, match.start));
        addTextSegment(textBuffer.toString());
        textBuffer.clear();
        addBlockImage(imageToken);
      } else {
        textBuffer
          ..write(line.substring(cursor, match.start))
          ..write(match.group(0)!);
      }
      cursor = match.end;
    }

    textBuffer.write(line.substring(cursor));
    if (sawBlockImage) {
      addTextSegment(textBuffer.toString());
    } else {
      addLine(line);
    }
  }

  return out.join('\n');
}
