/// Block-level markdown extension for Discord-style `-# small text`.
///
/// A line starting with `-# ` parses to a `subtext` element rendered at
/// 85% of the surrounding font size with a muted color. Pairs with
/// [SubtextBuilder] for `flutter_markdown_plus`.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

/// Matches `-#\s+<content>` at line start and emits a `subtext` element.
/// Inline content is deferred via [md.UnparsedContent] so nested
/// bold/italic/code/links/mentions still parse.
class SubtextBlockSyntax extends md.BlockSyntax {
  const SubtextBlockSyntax();

  @override
  RegExp get pattern => RegExp(r'^-#\s+(.+)$');

  @override
  md.Node? parse(md.BlockParser parser) {
    final lines = <String>[];

    while (!parser.isDone) {
      final match = pattern.firstMatch(parser.current.content);
      if (match == null) break;
      lines.add(match.group(1)!);
      parser.advance();
    }

    return md.Element('subtext', [md.UnparsedContent(lines.join('\n'))]);
  }
}

typedef SubtextLinkTap = void Function(String href);

/// Renders a `subtext` element at 85% scale with an optional muted color.
/// Walks the parsed inline children and emits a single [Text.rich] with
/// cascading style; links stay tappable when [onTapLink] is provided.
class SubtextBuilder extends MarkdownElementBuilder {
  SubtextBuilder({
    required this.baseStyle,
    this.mutedColor,
    this.codeBackground,
    this.linkColor,
    this.textAlign,
    this.scale = 0.85,
    this.onTapLink,
  });

  final TextStyle baseStyle;
  final Color? mutedColor;
  final Color? codeBackground;
  final Color? linkColor;
  final TextAlign? textAlign;
  final double scale;
  final SubtextLinkTap? onTapLink;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final base = preferredStyle ?? parentStyle ?? baseStyle;
    final small = base.copyWith(
      fontSize: (base.fontSize ?? baseStyle.fontSize ?? 14) * scale,
      color: mutedColor ?? base.color,
    );
    return _SubtextSpan(
      nodes: List<md.Node>.unmodifiable(element.children ?? const <md.Node>[]),
      style: small,
      codeBackground: codeBackground,
      linkColor: linkColor,
      textAlign: textAlign,
      onTapLink: onTapLink,
    );
  }
}

/// Owns the [TapGestureRecognizer]s created for any nested links so they
/// can be disposed on rebuild and on unmount.
class _SubtextSpan extends StatefulWidget {
  const _SubtextSpan({
    required this.nodes,
    required this.style,
    this.codeBackground,
    this.linkColor,
    this.textAlign,
    this.onTapLink,
  });

  final List<md.Node> nodes;
  final TextStyle style;
  final Color? codeBackground;
  final Color? linkColor;
  final TextAlign? textAlign;
  final SubtextLinkTap? onTapLink;

  @override
  State<_SubtextSpan> createState() => _SubtextSpanState();
}

class _SubtextSpanState extends State<_SubtextSpan> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    super.dispose();
  }

  @override
  void didUpdateWidget(_SubtextSpan oldWidget) {
    super.didUpdateWidget(oldWidget);
    // `build` reconstructs recognizers; dispose the stale ones first.
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    final spans = _buildSpans(widget.nodes, widget.style);
    return Text.rich(
      TextSpan(children: spans, style: widget.style),
      textAlign: widget.textAlign,
    );
  }

  List<InlineSpan> _buildSpans(
    List<md.Node> nodes,
    TextStyle style, {
    GestureRecognizer? recognizer,
  }) {
    final spans = <InlineSpan>[];
    for (final node in nodes) {
      if (node is md.Text) {
        spans.add(
          TextSpan(text: node.text, style: style, recognizer: recognizer),
        );
      } else if (node is md.Element) {
        spans.add(_spanForElement(node, style, recognizer: recognizer));
      }
    }
    return spans;
  }

  InlineSpan _spanForElement(
    md.Element element,
    TextStyle style, {
    GestureRecognizer? recognizer,
  }) {
    final tag = element.tag;
    final children = element.children ?? const <md.Node>[];

    switch (tag) {
      case 'strong':
        return TextSpan(
          children: _buildSpans(
            children,
            style.copyWith(fontWeight: FontWeight.bold),
            recognizer: recognizer,
          ),
        );
      case 'em':
        return TextSpan(
          children: _buildSpans(
            children,
            style.copyWith(fontStyle: FontStyle.italic),
            recognizer: recognizer,
          ),
        );
      case 'del':
        return TextSpan(
          children: _buildSpans(
            children,
            style.copyWith(decoration: TextDecoration.lineThrough),
            recognizer: recognizer,
          ),
        );
      case 'code':
        return TextSpan(
          text: element.textContent,
          style: style.copyWith(
            fontFamily: 'monospace',
            backgroundColor: widget.codeBackground,
          ),
          recognizer: recognizer,
        );
      case 'a':
        final href = element.attributes['href'];
        final linkStyle = style.copyWith(
          color: widget.linkColor ?? style.color,
          decoration: TextDecoration.underline,
        );
        final tap = widget.onTapLink;
        if (href == null || tap == null) {
          return TextSpan(
            children: _buildSpans(children, linkStyle, recognizer: recognizer),
          );
        }
        // Recognizer must live on leaf spans — Flutter's hit test
        // resolves taps to the leaf, not the wrapper.
        final linkRecognizer = TapGestureRecognizer()..onTap = () => tap(href);
        _recognizers.add(linkRecognizer);
        return TextSpan(
          children: _buildSpans(
            children,
            linkStyle,
            recognizer: linkRecognizer,
          ),
        );
      case 'spoiler':
        // Subtext renders inline text spans, which can't host the interactive
        // reveal pill. Redact to ▮ blocks (matching `redactSpoilers`) so a
        // spoiler inside a `-#` line never leaks its plaintext — the default
        // branch below would otherwise print `element.textContent` verbatim.
        return TextSpan(
          text: '▮' * element.textContent.length.clamp(1, 8),
          style: style.copyWith(backgroundColor: widget.codeBackground),
          recognizer: recognizer,
        );
      default:
        return TextSpan(
          text: element.textContent,
          style: style,
          recognizer: recognizer,
        );
    }
  }
}
