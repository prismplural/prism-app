import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
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
      onTapLink: (text, href, title) => _onTapLink(href),
      imageBuilder: (uri, title, alt) => const SizedBox.shrink(),
    );
  }

  MarkdownStyleSheet _buildStyleSheet(BuildContext context, ThemeData theme) {
    final base = MarkdownStyleSheet.fromTheme(theme);

    // Strip letter spacing from all text styles and apply reasonable heading caps.
    TextStyle strip(TextStyle? style) =>
        (style ?? const TextStyle()).copyWith(letterSpacing: 0);

    return base.copyWith(
      p: strip(baseStyle ?? base.p),
      h1: strip(base.h1)
          .copyWith(fontSize: 24, fontWeight: FontWeight.bold),
      h2: strip(base.h2)
          .copyWith(fontSize: 21, fontWeight: FontWeight.bold),
      h3: strip(base.h3)
          .copyWith(fontSize: 18, fontWeight: FontWeight.w600),
      h4: strip(base.h4)
          .copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      h5: strip(base.h5).copyWith(fontSize: 15),
      h6: strip(base.h6).copyWith(fontSize: 14),
      em: strip(base.em),
      strong: strip(base.strong),
      blockquote: strip(base.blockquote),
      listBullet: strip(base.listBullet),
      code: strip(base.code).copyWith(
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
      ),
      codeblockDecoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(8)),
      ),
    );
  }

  Future<void> _onTapLink(String? href) async {
    if (href == null) return;
    final uri = Uri.tryParse(href);
    if (uri == null) return;
    if (uri.scheme != 'http' && uri.scheme != 'https') return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
