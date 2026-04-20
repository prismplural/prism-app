import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';

/// Matches `||spoiler text||` spans — non-greedy, no nesting, inner ≥ 1 char.
final spoilerRegex = RegExp(r'\|\|(.+?)\|\|');

/// Replace each `||text||` span with ▮ block characters (clamped 1–8)
/// so spoilers don't leak through previews, reply quotes, or search snippets.
String redactSpoilers(String input) {
  return input.replaceAllMapped(
    spoilerRegex,
    (m) => '▮' * m.group(1)!.length.clamp(1, 8),
  );
}

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

/// Escape leading `#` markers so they render as literal text.
/// Chat does not support headings; the block parser is otherwise CommonMark.
String escapeLeadingHeadings(String input) {
  return input.split('\n').map((line) {
    final m = RegExp(r'^(#{1,6})\s').firstMatch(line);
    return m != null ? '\\${m.group(0)}${line.substring(m.end)}' : line;
  }).join('\n');
}

/// Fast check: does the string contain any char that could trigger markdown
/// or a mention? Used by the widget's fast path to skip parsing entirely.
bool hasMarkdownChars(String input) {
  for (var i = 0; i < input.length; i++) {
    switch (input[i]) {
      case '*':
      case '_':
      case '`':
      case '[':
      case '@':
      case '|':
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
    final member = id == null ? null : authorMap?[id];
    final name = member?.name ?? 'Unknown';
    final mentionColor = (member != null &&
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

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final href = element.attributes['href'];
    final uri = href != null ? Uri.tryParse(href) : null;
    final text = element.textContent;
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

// ---------------------------------------------------------------------------
// Memoized chat stylesheet
// ---------------------------------------------------------------------------

MarkdownStyleSheet? _cachedSheet;
_CacheKey? _cachedKey;

class _CacheKey {
  const _CacheKey(this.brightness, this.primary, this.codeBg);
  final Brightness brightness;
  final Color primary;
  final Color codeBg;

  @override
  bool operator ==(Object other) =>
      other is _CacheKey &&
      other.brightness == brightness &&
      other.primary == primary &&
      other.codeBg == codeBg;

  @override
  int get hashCode => Object.hash(brightness, primary, codeBg);
}

/// Returns a [MarkdownStyleSheet] suited for chat bubbles.
///
/// The sheet is memoized by theme brightness, primary color, and code
/// background color so repeated builds within the same theme cost nothing.
/// Headings are flattened to body style (chat doesn't support heading hierarchy).
MarkdownStyleSheet chatStylesheet(BuildContext context, TextStyle bodyStyle) {
  final theme = Theme.of(context);
  final codeBg = theme.colorScheme.onSurface.withAlpha(26);
  final key = _CacheKey(theme.brightness, theme.colorScheme.primary, codeBg);
  if (_cachedKey == key && _cachedSheet != null) return _cachedSheet!;
  final base = MarkdownStyleSheet.fromTheme(theme);
  TextStyle strip(TextStyle? s) =>
      (s ?? const TextStyle()).copyWith(letterSpacing: 0);
  final flat = strip(bodyStyle);
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

/// CommonMark block syntaxes + [MentionSyntax] inline, for chat rendering.
final md.ExtensionSet chatExtensionSet = md.ExtensionSet(
  md.ExtensionSet.commonMark.blockSyntaxes,
  [MentionSyntax(), ...md.ExtensionSet.commonMark.inlineSyntaxes],
);
