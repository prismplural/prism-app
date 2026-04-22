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

/// Matches `||spoiler text||` inline spans.
///
/// The matched offset is stamped on the element as `start` — downstream
/// reveal state (held by the message bubble) keys off this offset so each
/// spoiler in a message has a stable, parse-reset-free identity.
class SpoilerSyntax extends md.InlineSyntax {
  SpoilerSyntax() : super(r'\|\|(.+?)\|\|');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final element = md.Element.text('spoiler', match.group(1)!);
    element.attributes['start'] = match.start.toString();
    parser.addNode(element);
    return true;
  }
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

/// Publishes spoiler reveal state to every `_SpoilerSpan` beneath a
/// `ChatMessageText`. Using an `InheritedNotifier` lets only the affected
/// spoiler leaves rebuild on toggle — the enclosing `MarkdownBody`'s parsed
/// widget tree stays mounted, so `AnimatedOpacity` animates instead of
/// snapping.
class SpoilerRevealController extends ChangeNotifier {
  final Map<int, bool> _reveals = {};

  bool isRevealed(int start) => _reveals[start] ?? false;

  void toggle(int start) {
    _reveals[start] = !isRevealed(start);
    notifyListeners();
  }

  void clear() {
    if (_reveals.isEmpty) return;
    _reveals.clear();
    notifyListeners();
  }
}

class SpoilerRevealScope extends InheritedNotifier<SpoilerRevealController> {
  const SpoilerRevealScope({
    super.key,
    required SpoilerRevealController super.notifier,
    required super.child,
  });

  static SpoilerRevealController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<SpoilerRevealScope>();
    assert(scope != null, 'No SpoilerRevealScope above SpoilerBuilder');
    return scope!.notifier!;
  }
}

/// Renders `||text||` spoiler elements as a tappable pill.
///
/// Reveal state is read from the nearest [SpoilerRevealScope] ancestor, so
/// toggling a spoiler only rebuilds the affected `_SpoilerSpan` leaf — the
/// enclosing `MarkdownBody` tree stays mounted and `AnimatedOpacity` animates.
class SpoilerBuilder extends MarkdownElementBuilder {
  SpoilerBuilder({required this.theme});

  final ThemeData theme;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final start = int.tryParse(element.attributes['start'] ?? '') ?? 0;
    final text = element.textContent;
    final base = parentStyle ?? const TextStyle();
    return _SpoilerSpan(
      start: start,
      text: text,
      textStyle: base,
      theme: theme,
    );
  }
}

class _SpoilerSpan extends StatelessWidget {
  const _SpoilerSpan({
    required this.start,
    required this.text,
    required this.textStyle,
    required this.theme,
  });

  final int start;
  final String text;
  final TextStyle textStyle;
  final ThemeData theme;

  // Hidden spoilers use a dark scrim instead of a bright chip. Because the
  // plaintext is only painted in the revealed layer, this fill can stay fairly
  // subtle without leaking content.
  static const double _hiddenFillAlphaDark = 0.58;
  static const double _hiddenFillAlphaLight = 0.68;
  static const double _hiddenOutlineAlpha = 0.12;
  static const Duration _fadeDuration = Duration(milliseconds: 150);

  @override
  Widget build(BuildContext context) {
    final controller = SpoilerRevealScope.of(context);
    final revealed = controller.isRevealed(start);
    final isDark = theme.brightness == Brightness.dark;
    final hiddenFill = Colors.black.withValues(
      alpha: isDark ? _hiddenFillAlphaDark : _hiddenFillAlphaLight,
    );
    final hiddenOutline = Colors.white.withValues(alpha: _hiddenOutlineAlpha);

    return Semantics(
      button: true,
      label: revealed
          ? 'Spoiler, revealed: $text'
          : 'Hidden spoiler, double tap to reveal',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => controller.toggle(start),
        behavior: HitTestBehavior.opaque,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedOpacity(
              duration: _fadeDuration,
              opacity: revealed ? 0.0 : 1.0,
              child: IgnorePointer(
                ignoring: revealed,
                child: Container(
                  decoration: BoxDecoration(
                    color: hiddenFill,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: hiddenOutline),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    text,
                    style: textStyle.copyWith(color: Colors.transparent),
                  ),
                ),
              ),
            ),
            AnimatedOpacity(
              duration: _fadeDuration,
              opacity: revealed ? 1.0 : 0.0,
              child: IgnorePointer(
                ignoring: !revealed,
                child: Text(text, style: textStyle),
              ),
            ),
          ],
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

/// CommonMark block syntaxes + [SpoilerSyntax] and [MentionSyntax] inline,
/// for chat rendering.
final md.ExtensionSet chatExtensionSet = md.ExtensionSet(
  md.ExtensionSet.commonMark.blockSyntaxes,
  [
    SpoilerSyntax(),
    MentionSyntax(),
    ...md.ExtensionSet.commonMark.inlineSyntaxes,
  ],
);
