/// Helpers for rendering markdown content in plain-text preview contexts
/// (note list cards, fallback titles, etc.) where the markdown isn't rendered.
library;

import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/theme/app_icons.dart';

final _imageMarkdown = RegExp(r'!\[([^\]]*)\]\(([^)]+)\)');

/// Replace markdown image syntax (`![alt](ref)`) with a readable stand-in so
/// previews don't show raw `![](nbflag)` code. Uses the alt text when present,
/// otherwise a generic `[image]` marker. For plain-`String` contexts (titles,
/// accessibility labels, anywhere a widget can't be embedded).
String stripImageMarkdown(String input) {
  if (!input.contains('![')) return input;
  return input.replaceAllMapped(_imageMarkdown, (m) {
    final alt = (m.group(1) ?? '').trim();
    return alt.isNotEmpty ? alt : '[image]';
  });
}

/// Build inline spans for a rich-text preview, replacing each markdown image
/// (`![alt](ref)`) with a small inline image icon (plus the alt text, if any).
/// Use with `Text.rich`. For contexts that can host a `WidgetSpan`.
///
/// Used by note list cards (`notes_list_screen.dart`). Chat previews (the
/// conversation tile and search results) deliberately do NOT use this yet —
/// they render the `[image]` text from `stripMarkdownMarkers`
/// (`lib/features/chat/utils/markdown_utils.dart`) instead. That asymmetry is
/// documented in detail on `stripMarkdownMarkers`: the chat preview String is
/// built upstream (in `buildTilePreviewContent` / `_buildSafeSnippet`) where
/// image refs are already collapsed, so adopting an inline icon there is a
/// provider/DAO-layer change, not a widget-layer one.
///
/// IMPORTANT: this image rule must run before any link-stripping rule — the
/// link pattern would otherwise match the `[alt](ref)` portion of an image and
/// leave a stray `!` (see the `_image`-before-`_link` ordering note in
/// `markdown_utils.dart`).
List<InlineSpan> imagePreviewSpans(
  String input, {
  required TextStyle? style,
  required Color iconColor,
}) {
  if (!input.contains('![')) {
    return [TextSpan(text: input, style: style)];
  }

  final spans = <InlineSpan>[];
  final iconSize = (style?.fontSize ?? 14) + 1;
  var last = 0;

  void addText(String s) {
    if (s.isNotEmpty) spans.add(TextSpan(text: s, style: style));
  }

  for (final m in _imageMarkdown.allMatches(input)) {
    addText(input.substring(last, m.start));
    spans.add(WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Icon(AppIcons.imageOutlined, size: iconSize, color: iconColor),
      ),
    ));
    final alt = (m.group(1) ?? '').trim();
    if (alt.isNotEmpty) addText(' $alt');
    last = m.end;
  }
  addText(input.substring(last));

  return spans.isEmpty ? [TextSpan(text: '', style: style)] : spans;
}
