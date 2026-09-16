/// Decides whether a markdown image renders inline (within a text run) or as a
/// block (its own line, text above/below), and rewrites markdown to promote
/// block-eligible images into their own paragraph.
///
/// Flutter's text engine has no float/wrap-around, so a large inline image (a
/// single tall `WidgetSpan`) leaves awkward gaps in the line. Explicit sizing
/// therefore controls whether an image is promoted. Unsized images preserve
/// the author's line-level intent: standalone images are blocks, while images
/// beside meaningful text remain inline.
library;

import 'package:prism_plurality/features/members/services/bio_image_size.dart';

/// At or above this logical-pixel size (in either dimension) an explicitly
/// sized image is promoted to a block; below it, it stays inline.
const double blockImageMinPx = 48.0;

const _brailleBlank = '\u2800';

/// Fallback `1em` in logical px for the block/inline decision when the caller
/// supplies no basis. Callers with layout context (e.g. [PrismMarkdownText])
/// pass the real font size \u00d7 text scaler via `emBasisPx`, so the inline/block
/// split matches what [BioImageWidget] actually renders \u2014 important under
/// accessibility text scaling, where a `#2em` image can cross the block
/// threshold. This default (a typical body size) is used by tests and any
/// context-free caller. `3em` \u2248 the [blockImageMinPx] threshold.
const double _nominalEmPx = 16.0;

// Matches an image token plus any surrounding layout spaces (group 1 = the
// token, group 2 = its src) so a promoted image doesn't leave stray spaces
// hugging the inserted blank lines.
final _imageToken = RegExp(
  '[$_horizontalLayoutSpace]*'
  r'(!\[[^\]]*\]\(([^)]*)\))'
  '[$_horizontalLayoutSpace]*',
);

const _horizontalLayoutSpace = ' \t$_brailleBlank';

bool _isBlankLine(String line) =>
    line.replaceAll(RegExp('[$_horizontalLayoutSpace]'), '').trim().isEmpty;

bool _hasMeaningfulText(String text) => !_isBlankLine(text);

String _trimRightLayoutSpace(String text) =>
    text.replaceFirst(RegExp('[$_horizontalLayoutSpace]+\$'), '');

/// Whether an image with [size] should render as a block (its own line).
///
/// Percent-sized and unsized images return true. Explicit pixel/em sizes below
/// [blockImageMinPx] return false. Contextual exceptions for authored inline
/// layout are applied separately by [blockifyImageMarkdown].
bool isBlockImageSize(BioImageSize size, {double emBasisPx = _nominalEmPx}) {
  if (size.widthFraction != null) return true; // percent → block
  if (size.widthEm != null) {
    return size.widthEm! * emBasisPx >= blockImageMinPx; // small em → inline
  }
  if (size.width == null && size.height == null) return true; // unsized → block
  final w = size.width ?? 0;
  final h = size.height ?? 0;
  return w >= blockImageMinPx || h >= blockImageMinPx;
}

/// Rewrites [markdown] so block-eligible images sit in their own paragraphs.
/// Explicitly small images remain inline. A truly unsized image also remains
/// inline when the author placed meaningful content beside it; standalone
/// unsized images are blocks. Non-image markdown is untouched.
///
/// Operates on the author's raw markdown (the size fragment here is the literal
/// `#50%`, not the URL-encoded form the parser later produces).
String blockifyImageMarkdown(
  String markdown, {
  double emBasisPx = _nominalEmPx,
}) {
  if (!markdown.contains('![')) return markdown;

  final lines = markdown.split('\n');
  final out = <String>[];
  var pendingBlankAfterImage = false;

  void addLine(String line) {
    final isBlank = _isBlankLine(line);
    if (!isBlank && pendingBlankAfterImage) {
      if (out.isNotEmpty && !_isBlankLine(out.last)) out.add('');
      pendingBlankAfterImage = false;
    } else if (isBlank) {
      pendingBlankAfterImage = false;
    }
    out.add(isBlank ? '' : line);
  }

  void addBlockImage(String imageToken) {
    if (out.isNotEmpty && !_isBlankLine(out.last)) out.add('');
    out.add(imageToken);
    pendingBlankAfterImage = true;
  }

  void addTextSegment(String text) {
    if (text.isEmpty) return;
    addLine(text);
  }

  for (final line in lines) {
    final blockquote = _parseBlockquoteMarker(line);
    if (blockquote != null && blockquote.content.contains('![')) {
      final rewritten = blockifyImageMarkdown(
        blockquote.content,
        emBasisPx: emBasisPx,
      );
      for (final quotedLine in rewritten.split('\n')) {
        addLine(_quoteLine(blockquote.marker, quotedLine));
      }
      continue;
    }

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
      var fragment = hashIdx >= 0 ? src.substring(hashIdx + 1) : null;
      final rawFragment = fragment;
      if (rawFragment != null) {
        // Match the element builder's normalized fragment semantics.
        try {
          fragment = Uri.decodeComponent(rawFragment).trim();
        } catch (_) {
          fragment = rawFragment.trim();
        }
      }
      final isTrulyUnsized = fragment == null || fragment.isEmpty;
      final size = BioImageSize.parse(fragment);
      final imageToken = match.group(1)!;
      final matchText = match.group(0)!;
      final hasBrailleSpacer = matchText.contains(_brailleBlank);
      final sameLineText =
          line.substring(0, match.start) + line.substring(match.end);
      final hasSameLineText = _hasMeaningfulText(sameLineText);
      // Invalid explicit sizes retain the block fallback. U+2800 remains an
      // explicit legacy gutter.
      final keepInlineLayout =
          hasSameLineText && (isTrulyUnsized || hasBrailleSpacer);

      if (isBlockImageSize(size, emBasisPx: emBasisPx) && !keepInlineLayout) {
        sawBlockImage = true;
        textBuffer.write(line.substring(cursor, match.start));
        addTextSegment(_trimRightLayoutSpace(textBuffer.toString()));
        textBuffer.clear();
        addBlockImage(imageToken);
      } else {
        textBuffer
          ..write(line.substring(cursor, match.start))
          ..write(matchText);
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

_BlockquoteLine? _parseBlockquoteMarker(String line) {
  final match = _blockquoteLinePattern.firstMatch(line);
  if (match == null) return null;
  return _BlockquoteLine(
    line.substring(0, match.end),
    line.substring(match.end),
  );
}

String _quoteLine(String marker, String content) {
  if (content.isEmpty) return marker.trimRight();
  return '$marker$content';
}

class _BlockquoteLine {
  const _BlockquoteLine(this.marker, this.content);

  final String marker;
  final String content;
}

final _blockquoteLinePattern = RegExp(r'^[ \t]{0,3}>[ \t]?');
