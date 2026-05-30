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

  String promote(String line) => line.replaceAllMapped(_imageToken, (m) {
        final src = m.group(2) ?? '';
        final hashIdx = src.indexOf('#');
        final fragment = hashIdx >= 0 ? src.substring(hashIdx + 1) : null;
        final size = BioImageSize.parse(fragment);
        if (isBlockImageSize(size)) {
          // Drop the surrounding spaces (consumed by the match) and isolate.
          return '\n\n${m.group(1)}\n\n';
        }
        return m.group(0)!; // small → leave inline, original spacing intact
      });

  // Process line by line so images inside a table row (`| ![](img) | … |`,
  // the side-by-side layout) are left untouched — promoting one would inject a
  // blank line mid-row and shatter the table.
  final lines = markdown.split('\n');
  final out = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    if (i > 0) out.write('\n');
    final line = lines[i];
    out.write(line.contains('|') ? line : promote(line));
  }

  // Collapse the blank-line runs we introduced and trim the edges.
  return out.toString().replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}
