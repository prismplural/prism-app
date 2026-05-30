import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

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

/// Matches `||text||` inline spans.
///
/// Reveal-state identity is assigned later, by [SpoilerBuilder] in document
/// order — not here. The inline parser only sees offsets relative to the
/// current block, so two spoilers in different blocks would share an offset and
/// collide under one reveal controller.
class SpoilerSyntax extends md.InlineSyntax {
  SpoilerSyntax() : super(r'\|\|(.+?)\|\|');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('spoiler', match.group(1)!));
    return true;
  }
}

/// Publishes spoiler reveal state to every `SpoilerPill` beneath a
/// [SpoilerRevealScope]. Using an `InheritedNotifier` lets only the affected
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
/// toggling a spoiler only rebuilds the affected `SpoilerPill` leaf — the
/// enclosing `MarkdownBody` tree stays mounted and `AnimatedOpacity` animates.
class SpoilerBuilder extends MarkdownElementBuilder {
  SpoilerBuilder({required this.theme});

  final ThemeData theme;

  // Reveal state is keyed by each spoiler's position in document order within a
  // single rendered body, assigned here as the builder walks elements. Using a
  // per-build sequential id (not the inline parser's block-local offset) keeps
  // every spoiler's identity unique across paragraphs, list items, and small
  // text — so revealing one never reveals another. Deterministic across
  // rebuilds: same content → same traversal order → same ids. A fresh builder
  // is created per `build()`, so the counter resets each render.
  int _nextId = 0;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final id = _nextId++;
    final text = element.textContent;
    final base = parentStyle ?? const TextStyle();
    return SpoilerPill(
      id: id,
      text: text,
      textStyle: base,
      theme: theme,
    );
  }
}

/// Tappable spoiler pill: hidden scrim over transparent text, revealing the
/// plaintext on tap. Reveal state is read from the nearest [SpoilerRevealScope]
/// ancestor and keyed by [id].
///
/// Used by [SpoilerBuilder] for `flutter_markdown` surfaces, and embeddable via
/// `WidgetSpan` in hand-rolled inline renderers that build their own spans —
/// both must sit under a [SpoilerRevealScope] and assign each pill a body-unique
/// [id] in document order.
class SpoilerPill extends StatelessWidget {
  const SpoilerPill({
    super.key,
    required this.id,
    required this.text,
    required this.textStyle,
    required this.theme,
  });

  final int id;
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
    final revealed = controller.isRevealed(id);
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
        onTap: () => controller.toggle(id),
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
