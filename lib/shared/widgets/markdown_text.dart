import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

/// Renders text as Markdown when [enabled], otherwise as plain [Text].
///
/// Images are disabled (rendered as empty boxes). Only http/https links are
/// opened. HTML tags are not rendered.
class MarkdownText extends StatelessWidget {
  const MarkdownText({
    super.key,
    required this.data,
    this.enabled = true,
    this.baseStyle,
    this.selectable = false,
  });

  /// The text content (plain or Markdown).
  final String data;

  /// Whether to render as Markdown. When false, displays as plain [Text].
  final bool enabled;

  /// Optional base text style applied to the body text.
  final TextStyle? baseStyle;

  /// Whether the rendered text is selectable.
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return Text(data, style: baseStyle);
    }

    final theme = Theme.of(context);
    final sheet = _buildStyleSheet(context, theme);

    return MarkdownBody(
      data: data,
      selectable: selectable,
      styleSheet: sheet,
      imageBuilder: (uri, title, alt) => const SizedBox.shrink(),
      checkboxBuilder: (checked) => _buildTaskListCheckbox(
        theme: theme,
        style: sheet.checkbox,
        padding: sheet.listBulletPadding,
        checked: checked,
      ),
      builders: {'a': _SafeLinkBuilder(theme: theme)},
    );
  }

  MarkdownStyleSheet _buildStyleSheet(BuildContext context, ThemeData theme) {
    final base = MarkdownStyleSheet.fromTheme(theme);

    // Strip letter spacing from all text styles and apply reasonable heading caps.
    TextStyle strip(TextStyle? style) =>
        (style ?? const TextStyle()).copyWith(letterSpacing: 0);

    final radius = PrismShapes.of(context).radius(8);
    final mutedSurface = theme.colorScheme.surfaceContainerHighest;
    final mutedFg = theme.colorScheme.onSurfaceVariant;

    return base.copyWith(
      p: strip(baseStyle ?? base.p),
      a: strip(base.a).copyWith(
        color: theme.colorScheme.primary,
        decoration: TextDecoration.underline,
        decorationColor: theme.colorScheme.primary.withValues(alpha: 0.5),
      ),
      h1: strip(base.h1).copyWith(fontSize: 24, fontWeight: FontWeight.bold),
      h2: strip(base.h2).copyWith(fontSize: 21, fontWeight: FontWeight.bold),
      h3: strip(base.h3).copyWith(fontSize: 18, fontWeight: FontWeight.w600),
      h4: strip(base.h4).copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      h5: strip(base.h5).copyWith(fontSize: 15),
      h6: strip(base.h6).copyWith(fontSize: 14),
      em: strip(base.em),
      strong: strip(base.strong),
      blockquote: strip(base.blockquote).copyWith(color: mutedFg),
      blockquoteDecoration: BoxDecoration(
        color: mutedSurface,
        borderRadius: BorderRadius.circular(radius),
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 3),
        ),
      ),
      listBullet: strip(base.listBullet),
      checkbox: strip(
        base.checkbox,
      ).copyWith(color: mutedFg.withValues(alpha: 0.92)),
      code: strip(base.code).copyWith(backgroundColor: mutedSurface),
      codeblockDecoration: BoxDecoration(
        color: mutedSurface,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  Widget _buildTaskListCheckbox({
    required ThemeData theme,
    required TextStyle? style,
    required EdgeInsets? padding,
    required bool checked,
  }) {
    return Padding(
      padding: padding ?? const EdgeInsets.only(right: 4),
      child: Icon(
        checked ? Icons.check_box : Icons.check_box_outline_blank,
        size: (style?.fontSize ?? baseStyle?.fontSize ?? 14) + 2,
        color: checked
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.92),
      ),
    );
  }
}

/// Renders `<a>` elements, downgrading any non-http(s) link to plain text
/// so unsafe schemes (e.g. `javascript:`, `mailto:`) don't appear tappable.
///
/// Registering a builder for `a` bypasses flutter_markdown_plus's default
/// link path, so this builder must construct the tappable widget itself for
/// safe links.
class _SafeLinkBuilder extends MarkdownElementBuilder {
  _SafeLinkBuilder({required this.theme});

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
    final linkStyle = base.copyWith(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.primary.withValues(alpha: 0.5),
    );
    return GestureDetector(
      onTap: () => _launchExternal(uri),
      child: Text(text, style: linkStyle),
    );
  }

  Future<void> _launchExternal(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
