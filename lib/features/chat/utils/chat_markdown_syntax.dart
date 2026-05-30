import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/utils/mention_utils.dart';
import 'package:prism_plurality/shared/markdown/spoiler_syntax.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';

// Spoiler machinery (`SpoilerSyntax`, `SpoilerBuilder`, `SpoilerRevealScope`,
// `SpoilerRevealController`, `redactSpoilers`, `spoilerRegex`) is shared across
// every markdown surface; it lives in `shared/markdown/spoiler_syntax.dart`.
// Re-exported here so existing chat callers keep importing it from this file.
export 'package:prism_plurality/shared/markdown/spoiler_syntax.dart';

final chatSmallTextLineRegex = RegExp(r'^-#\s+(.+)$', multiLine: true);

/// Matches @[uuid] mention tokens (strict 36-char UUID).
class MentionSyntax extends md.InlineSyntax {
  MentionSyntax()
    : super(
        r'@\[([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\]',
      );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final element = md.Element.empty('mention');
    element.attributes['id'] = match.group(1)!;
    parser.addNode(element);
    return true;
  }
}

/// Matches literal broadcast mention aliases such as `@everyone` and `@all`.
class BroadcastMentionSyntax extends md.InlineSyntax {
  BroadcastMentionSyntax()
    : super(r'@(everyone|all)', caseSensitive: false, startCharacter: 64);

  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    startMatchPos ??= parser.pos;
    final match = pattern.matchAsPrefix(parser.source, startMatchPos);
    if (match == null) return false;
    if (!hasBroadcastMentionBoundaries(parser.source, match.start, match.end)) {
      return false;
    }
    parser.writeText();
    final element = md.Element.empty('mention');
    element.attributes['alias'] = match.group(1)!;
    parser.addNode(element);
    parser.consume(match.end - match.start);
    return true;
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) => false;
}

/// Escape leading `#` markers so they render as literal text.
/// Chat does not support headings; the block parser is otherwise CommonMark.
String escapeLeadingHeadings(String input) {
  return input
      .split('\n')
      .map((line) {
        final m = RegExp(r'^(#{1,6})\s').firstMatch(line);
        return m != null ? '\\${m.group(0)}${line.substring(m.end)}' : line;
      })
      .join('\n');
}

/// Fast check: does the string contain any char that could trigger markdown
/// or a mention? Used by the widget's fast path to skip parsing entirely.
bool hasMarkdownChars(String input) {
  if (chatSmallTextLineRegex.hasMatch(input)) return true;

  for (var i = 0; i < input.length; i++) {
    switch (input[i]) {
      case '*':
      case '_':
      case '`':
      case '[':
      case '@':
      case '|':
      case '>':
        return true;
    }
  }
  return false;
}

// ---------------------------------------------------------------------------
// Element builders
// ---------------------------------------------------------------------------

/// Renders `@[uuid]` mention elements as styled inline text.
///
/// Merges with [parentStyle] so bold/italic context composes correctly.
/// Color comes from the member's custom color when enabled, otherwise falls
/// back to the active theme's primary color.
class MentionBuilder extends MarkdownElementBuilder {
  MentionBuilder({required this.authorMap, required this.theme});
  final Map<String, Member>? authorMap;
  final ThemeData theme;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final id = element.attributes['id'];
    final alias = element.attributes['alias'];
    if (alias != null && isBroadcastMentionAlias(alias)) {
      final text = '@$alias';
      final merged = (parentStyle ?? const TextStyle()).copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w600,
      );
      return Text.rich(
        TextSpan(text: text, style: merged, semanticsLabel: text),
      );
    }

    final member = id == null ? null : authorMap?[id];
    final name = member?.name ?? 'Unknown';
    final mentionColor =
        (member != null &&
            member.customColorEnabled &&
            member.customColorHex != null)
        ? AppColors.fromHex(member.customColorHex!)
        : theme.colorScheme.primary;
    final merged = (parentStyle ?? const TextStyle()).copyWith(
      color: mentionColor,
      fontWeight: FontWeight.w600,
    );
    return Text.rich(
      TextSpan(text: '@$name', style: merged, semanticsLabel: '@$name'),
    );
  }
}

/// Renders links safely, allowing only http and https schemes.
///
/// Links with disallowed schemes (e.g. `javascript:`, `mailto:`) are rendered
/// as plain text with no tap target. The [onTap] callback is injected by the
/// caller so this file remains free of `url_launcher` imports.
class SafeLinkBuilder extends MarkdownElementBuilder {
  SafeLinkBuilder({required this.onTap, required this.theme});
  final void Function(String url) onTap;
  final ThemeData theme;

  // `markdown` splits 3+ word link text into multiple Text nodes; flutter_markdown_plus
  // then only swaps children[0] for the builder's widget, so trailing nodes duplicate.
  // Coalesce here so the builder owns the whole label.
  @override
  void visitElementBefore(md.Element element) {
    final children = element.children;
    if (children == null || children.length < 2) return;
    final buffer = StringBuffer();
    for (final node in children) {
      if (node is! md.Text) return;
      buffer.write(node.text);
    }
    children
      ..clear()
      ..add(md.Text(buffer.toString()));
  }

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final href = element.attributes['href'];
    final uri = href != null ? Uri.tryParse(href) : null;
    // Build the label from child nodes so a spoiler inside link text is redacted
    // to ▮ blocks. `element.textContent` would flatten the spoiler child to its
    // plaintext, leaking it (the link label has no room for an interactive pill).
    final text = _labelWithRedactedSpoilers(element);
    final base = parentStyle ?? const TextStyle();
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return Text(text, style: base);
    }
    return GestureDetector(
      onTap: () => onTap(href!),
      child: Text(
        text,
        style: base.copyWith(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}

/// Flattens an inline element to display text, replacing any `spoiler`
/// descendant with ▮ blocks (matching [redactSpoilers]) so spoiler plaintext
/// never leaks through renderers that collapse children to a plain string.
String _labelWithRedactedSpoilers(md.Node node) {
  if (node is md.Text) return node.text;
  if (node is md.Element) {
    if (node.tag == 'spoiler') {
      return '▮' * node.textContent.length.clamp(1, 8);
    }
    final children = node.children;
    if (children == null) return node.textContent;
    return children.map(_labelWithRedactedSpoilers).join();
  }
  return '';
}

// ---------------------------------------------------------------------------
// Memoized chat stylesheet
// ---------------------------------------------------------------------------

MarkdownStyleSheet? _cachedSheet;
_CacheKey? _cachedKey;

class _CacheKey {
  const _CacheKey(
    this.brightness,
    this.primary,
    this.codeBg,
    this.mutedBg,
    this.mutedFg,
    this.radius,
    this.bodyStyle,
  );
  final Brightness brightness;
  final Color primary;
  final Color codeBg;
  final Color mutedBg;
  final Color mutedFg;
  final double radius;
  final TextStyle bodyStyle;

  @override
  bool operator ==(Object other) =>
      other is _CacheKey &&
      other.brightness == brightness &&
      other.primary == primary &&
      other.codeBg == codeBg &&
      other.mutedBg == mutedBg &&
      other.mutedFg == mutedFg &&
      other.radius == radius &&
      other.bodyStyle == bodyStyle;

  @override
  int get hashCode => Object.hash(
    brightness,
    primary,
    codeBg,
    mutedBg,
    mutedFg,
    radius,
    bodyStyle,
  );
}

/// Returns a [MarkdownStyleSheet] suited for chat bubbles.
///
/// The sheet is memoized by theme brightness, primary color, and code
/// background color so repeated builds within the same theme cost nothing.
/// Headings are flattened to body style (chat doesn't support heading hierarchy).
MarkdownStyleSheet chatStylesheet(BuildContext context, TextStyle bodyStyle) {
  final theme = Theme.of(context);
  final codeBg = theme.colorScheme.onSurface.withAlpha(26);
  final mutedBg = theme.colorScheme.surfaceContainerHighest;
  final mutedFg = theme.colorScheme.onSurfaceVariant;
  final radius = PrismShapes.of(context).radius(8);
  final base = MarkdownStyleSheet.fromTheme(theme);
  TextStyle strip(TextStyle? s) =>
      (s ?? const TextStyle()).copyWith(letterSpacing: 0);
  final flat = strip(bodyStyle);
  final key = _CacheKey(
    theme.brightness,
    theme.colorScheme.primary,
    codeBg,
    mutedBg,
    mutedFg,
    radius,
    flat,
  );
  if (_cachedKey == key && _cachedSheet != null) return _cachedSheet!;
  _cachedSheet = base.copyWith(
    p: flat,
    em: flat.copyWith(fontStyle: FontStyle.italic),
    strong: flat.copyWith(fontWeight: FontWeight.bold),
    code: flat.copyWith(fontFamily: 'monospace', backgroundColor: codeBg),
    h1: flat,
    h2: flat,
    h3: flat,
    h4: flat,
    h5: flat,
    h6: flat,
    a: flat.copyWith(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
    ),
    blockquote: flat.copyWith(color: mutedFg),
    blockquoteDecoration: BoxDecoration(
      color: mutedBg,
      borderRadius: BorderRadius.circular(radius),
      border: Border(
        left: BorderSide(color: theme.colorScheme.primary, width: 3),
      ),
    ),
  );
  _cachedKey = key;
  return _cachedSheet!;
}

/// Reset the stylesheet cache — test-only helper.
@visibleForTesting
void debugResetChatStylesheetCache() {
  _cachedSheet = null;
  _cachedKey = null;
}

// ---------------------------------------------------------------------------
// Extension set
// ---------------------------------------------------------------------------

/// CommonMark block syntaxes + [SpoilerSyntax] and [MentionSyntax] inline,
/// for chat rendering.
final md.ExtensionSet chatExtensionSet =
    md.ExtensionSet(md.ExtensionSet.commonMark.blockSyntaxes, [
      SpoilerSyntax(),
      MentionSyntax(),
      BroadcastMentionSyntax(),
      ...md.ExtensionSet.commonMark.inlineSyntaxes,
    ]);
