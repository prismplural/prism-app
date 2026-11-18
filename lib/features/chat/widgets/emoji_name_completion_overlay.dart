import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';

/// Glassmorphism completion list for `:name` Unicode emoji tokens.
///
/// Shows the bounded matches produced by
/// `detectEmojiCompletionTrigger`/`searchEmojiNames` above the composer field.
/// Touch: tap a row. Keyboard: Up/Down move, Enter/Tab select, Escape dismisses
/// (the composer owns dismissal and the mention chooser keeps priority).
class EmojiNameCompletionOverlay extends StatefulWidget {
  const EmojiNameCompletionOverlay({
    super.key,
    required this.matches,
    required this.onSelect,
    required this.availableWidth,
    required this.availableHeight,
  });

  /// Bounded matches, best first. An empty list renders nothing at all.
  final List<Emoji> matches;

  /// Called with the chosen emoji; the composer replaces the token.
  final ValueChanged<Emoji> onSelect;

  /// Width available from the anchored composer field.
  final double availableWidth;

  /// Height available above the composer field (already excludes the keyboard
  /// and the safe area). The list shrinks to this instead of being clipped.
  final double availableHeight;

  /// Key for the popup surface, used by layout tests.
  static const Key surfaceKey = Key('emojiNameCompletionSurface');

  @override
  State<EmojiNameCompletionOverlay> createState() =>
      EmojiNameCompletionOverlayState();
}

class EmojiNameCompletionOverlayState
    extends State<EmojiNameCompletionOverlay> {
  /// Highlighted row. Reset to the best match whenever the matches change so
  /// Enter always inserts the top match for the current prefix.
  int _highlightedIndex = 0;

  /// Attached to the highlighted row so keyboard navigation scrolls it into
  /// view when the list is taller than the popup.
  final _highlightedRowKey = GlobalKey();

  /// Rows that fit in the popup before scrolling.
  static const double _maxListHeight = 240;

  @override
  void didUpdateWidget(covariant EmojiNameCompletionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameMatches(oldWidget.matches, widget.matches) ||
        _highlightedIndex >= widget.matches.length) {
      _highlightedIndex = 0;
    }
  }

  static bool _sameMatches(List<Emoji> a, List<Emoji> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].emoji != b[i].emoji) return false;
    }
    return true;
  }

  /// Size the popup would occupy, or null when the popup renders nothing.
  ///
  /// [build] and [handleKeyEvent] share this single predicate: a popup with no
  /// usable geometry paints nothing, so it must not consume navigation or
  /// selection keys either. Without that, a hidden popup would swallow Enter and
  /// insert an emoji the user never saw.
  ({double width, double height})? _surfaceGeometry() {
    if (widget.matches.isEmpty) return null;
    final width = math.min(widget.availableWidth, _maxPopupWidth);
    final height = math.min(
      math.max(widget.availableHeight, 0.0),
      _maxListHeight,
    );
    if (width < _minUsableWidth || height <= 0) return null;
    return (width: width, height: height);
  }

  /// Handle keyboard navigation. Returns true if the event was consumed.
  bool handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (_surfaceGeometry() == null) return false;
    final count = widget.matches.length;
    if (count == 0) return false;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveHighlight(_highlightedIndex + 1);
      return true;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveHighlight(_highlightedIndex - 1);
      return true;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.tab) {
      _selectAt(_highlightedIndex);
      return true;
    }
    if (key == LogicalKeyboardKey.escape) {
      return true; // Caller owns dismissal.
    }
    return false;
  }

  void _moveHighlight(int nextIndex) {
    final count = widget.matches.length;
    setState(() => _highlightedIndex = (nextIndex % count + count) % count);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final rowContext = _highlightedRowKey.currentContext;
      if (rowContext == null || !mounted) return;
      unawaited(Scrollable.ensureVisible(rowContext, alignment: 0.5));
    });
  }

  void _selectAt(int index) {
    if (index < 0 || index >= widget.matches.length) return;
    widget.onSelect(widget.matches[index]);
  }

  @override
  Widget build(BuildContext context) {
    final matches = widget.matches;
    // Same predicate as key handling: no room, or an anchored width too narrow
    // for a readable row, means no usable surface at all.
    final geometry = _surfaceGeometry();
    if (matches.isEmpty || geometry == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final width = geometry.width;
    final listHeight = geometry.height;

    return Align(
      alignment: Alignment.bottomLeft,
      child: Material(
        type: MaterialType.transparency,
        child: SizedBox(
          width: width,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(
              PrismShapes.of(context).radius(16),
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: PrismTokens.glassBlurStrong,
                sigmaY: PrismTokens.glassBlurStrong,
              ),
              child: Container(
                key: EmojiNameCompletionOverlay.surfaceKey,
                constraints: BoxConstraints(maxHeight: listHeight),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withValues(
                    alpha: isDark ? 0.92 : 0.96,
                  ),
                  borderRadius: BorderRadius.circular(
                    PrismShapes.of(context).radius(16),
                  ),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.5,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.shadow.withValues(alpha: 0.18),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                // At most eight rows, so every row is built eagerly. That
                // keeps the highlighted row's context available for
                // `Scrollable.ensureVisible` without a lazy-list estimate.
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var index = 0; index < matches.length; index++)
                        _EmojiCompletionRow(
                          key: index == _highlightedIndex
                              ? _highlightedRowKey
                              : null,
                          emoji: matches[index],
                          label: _labelFor(matches[index]),
                          isHighlighted: index == _highlightedIndex,
                          onTap: () => _selectAt(index),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The first keyword segment is the CLDR annotation; that is the name the
  /// user typed a prefix of, so it is also the accessible name.
  static String _labelFor(Emoji emoji) {
    final keywords = emoji.keywords;
    for (final keyword in keywords) {
      if (keyword.isNotEmpty) return keyword;
    }
    return emoji.emoji;
  }

  /// Narrowest popup that still shows a glyph plus a readable label.
  static const double _minUsableWidth = 140;
  static const double _maxPopupWidth = 320;
}

class _EmojiCompletionRow extends StatelessWidget {
  const _EmojiCompletionRow({
    super.key,
    required this.emoji,
    required this.label,
    required this.isHighlighted,
    required this.onTap,
  });

  final Emoji emoji;
  final String label;
  final bool isHighlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Semantics(
      // One merged node per row: screen readers announce the glyph and its
      // annotation instead of the two separate text runs.
      label: '${emoji.emoji} $label',
      button: true,
      selected: isHighlighted,
      // Child semantics are excluded so the row is announced once, so the tap
      // action for assistive technology is provided here as well.
      excludeSemantics: true,
      onTap: onTap,
      child: Container(
        color: isHighlighted
            ? primary.withValues(alpha: 0.12)
            : Colors.transparent,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            // Theme text styles plus a minimum target height: the row grows
            // with the system text scale instead of clipping (no FittedBox and
            // no fixed font size).
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Text(emoji.emoji, style: theme.textTheme.bodyLarge),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: isHighlighted
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
