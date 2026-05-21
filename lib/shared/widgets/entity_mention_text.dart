import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown/markdown.dart' as md;

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/providers/profile_entity_mentions_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/mentions/entity_mention.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/widgets/markdown_text.dart';

typedef EntityMentionTapCallback =
    Future<void> Function(
      BuildContext context,
      WidgetRef ref,
      ProfileEntityMentionResolution resolution,
    );

class EntityMentionMarkdownText extends ConsumerWidget {
  const EntityMentionMarkdownText({
    super.key,
    required this.data,
    this.enabled = true,
    this.baseStyle,
    this.selectable = false,
    this.onTapMention,
  });

  final String data;
  final bool enabled;
  final TextStyle? baseStyle;
  final bool selectable;
  final EntityMentionTapCallback? onTapMention;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolutions = ref.watch(
      profileEntityMentionResolutionsProvider(data),
    );
    if (!enabled) {
      final style =
          baseStyle ??
          Theme.of(context).textTheme.bodyMedium ??
          const TextStyle();
      final span = TextSpan(
        style: style,
        children: buildEntityMentionInlineSpans(
          context: context,
          ref: ref,
          data: data,
          baseStyle: style,
          resolutions: resolutions,
          hiddenLabel: context.l10n.profileMentionPrivate,
          onTapMention: onTapMention,
          parseInlineMarkdown: false,
        ),
      );
      if (selectable) return SelectableText.rich(span);
      return Text.rich(span);
    }

    return MarkdownText(
      data: data,
      enabled: true,
      baseStyle: baseStyle,
      selectable: selectable,
      inlineSyntaxes: [EntityMentionSyntax()],
      builders: {
        'entity-mention': EntityMentionBuilder(
          ref: ref,
          resolutions: resolutions,
          hiddenLabel: context.l10n.profileMentionPrivate,
          onTapMention: onTapMention,
        ),
      },
    );
  }
}

class EntityMentionInlineText extends ConsumerWidget {
  const EntityMentionInlineText({
    super.key,
    required this.data,
    this.style,
    this.textAlign = TextAlign.start,
    this.onTapMention,
  });

  final String data;
  final TextStyle? style;
  final TextAlign textAlign;
  final EntityMentionTapCallback? onTapMention;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final baseStyle = style ?? theme.textTheme.bodyMedium ?? const TextStyle();
    final hiddenLabel = context.l10n.profileMentionPrivate;
    final resolutions = ref.watch(
      profileEntityMentionResolutionsProvider(data),
    );
    final spans = buildEntityMentionInlineSpans(
      context: context,
      ref: ref,
      data: data,
      baseStyle: baseStyle,
      resolutions: resolutions,
      hiddenLabel: hiddenLabel,
      onTapMention: onTapMention,
    );

    return Text.rich(
      TextSpan(style: baseStyle, children: spans),
      textAlign: textAlign,
    );
  }
}

class EntityMentionSyntax extends md.InlineSyntax {
  EntityMentionSyntax()
    : super(
        r'@\[([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\]|@\[([a-z]+):([^\]\r\n]{1,128})\]',
      );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final legacyId = match.group(1);
    EntityMentionTarget? target;
    if (legacyId != null) {
      target = EntityMentionTarget(
        type: EntityMentionType.member,
        id: legacyId,
        isLegacyMember: true,
      );
    } else {
      final type = EntityMentionType.fromTokenName(match.group(2)!);
      final id = match.group(3)!;
      if (type != null && isValidEntityMentionId(id)) {
        target = EntityMentionTarget(type: type, id: id);
      }
    }
    if (target == null) return false;

    final element = md.Element.empty('entity-mention');
    element.attributes['type'] = target.type.tokenName;
    element.attributes['id'] = target.id;
    if (target.isLegacyMember) element.attributes['legacy'] = 'true';
    parser.addNode(element);
    return true;
  }
}

class EntityMentionBuilder extends MarkdownElementBuilder {
  EntityMentionBuilder({
    required this.ref,
    required this.resolutions,
    required this.hiddenLabel,
    this.onTapMention,
  });

  final WidgetRef ref;
  final Map<EntityMentionTarget, ProfileEntityMentionResolution> resolutions;
  final String hiddenLabel;
  final EntityMentionTapCallback? onTapMention;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final target = _targetFromAttributes(element.attributes);
    if (target == null) return null;

    final resolution =
        resolutions[target] ??
        ProfileEntityMentionResolution(target: target, visible: false);
    final baseStyle = parentStyle ?? preferredStyle ?? const TextStyle();
    return _EntityMentionSpanWidget(
      ref: ref,
      resolution: resolution,
      hiddenLabel: hiddenLabel,
      style: _mentionStyle(context, resolution, baseStyle),
      onTapMention: onTapMention,
    );
  }
}

List<InlineSpan> buildEntityMentionInlineSpans({
  required BuildContext context,
  required WidgetRef ref,
  required String data,
  required TextStyle baseStyle,
  required Map<EntityMentionTarget, ProfileEntityMentionResolution> resolutions,
  required String hiddenLabel,
  EntityMentionTapCallback? onTapMention,
  bool parseInlineMarkdown = true,
}) {
  final matches = extractEntityMentions(data);
  if (matches.isEmpty) {
    final spans = <InlineSpan>[];
    _appendTextBeforeMention(
      spans: spans,
      data: data,
      baseStyle: baseStyle,
      context: context,
      parseInlineMarkdown: parseInlineMarkdown,
    );
    return spans;
  }

  final spans = <InlineSpan>[];
  var cursor = 0;
  for (final match in matches) {
    if (match.start > cursor) {
      _appendTextBeforeMention(
        spans: spans,
        data: data.substring(cursor, match.start),
        baseStyle: baseStyle,
        context: context,
        parseInlineMarkdown: parseInlineMarkdown,
      );
    }
    final resolution =
        resolutions[match.target] ??
        ProfileEntityMentionResolution(target: match.target, visible: false);
    final label = resolution.displayText(hiddenLabel);
    final style = _mentionStyle(context, resolution, baseStyle);
    if (resolution.visible && onTapMention != null) {
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onTapMention(context, ref, resolution),
            child: Text(label, style: style, semanticsLabel: label),
          ),
        ),
      );
    } else {
      spans.add(TextSpan(text: label, style: style, semanticsLabel: label));
    }
    cursor = match.end;
  }
  if (cursor < data.length) {
    _appendTextBeforeMention(
      spans: spans,
      data: data.substring(cursor),
      baseStyle: baseStyle,
      context: context,
      parseInlineMarkdown: parseInlineMarkdown,
    );
  }
  return spans;
}

void _appendTextBeforeMention({
  required List<InlineSpan> spans,
  required String data,
  required TextStyle baseStyle,
  required BuildContext context,
  required bool parseInlineMarkdown,
}) {
  if (parseInlineMarkdown) {
    _appendInlineMarkdownSpans(spans, data, baseStyle, context);
    return;
  }
  if (data.isNotEmpty) spans.add(TextSpan(text: data, style: baseStyle));
}

class _EntityMentionSpanWidget extends StatelessWidget {
  const _EntityMentionSpanWidget({
    required this.ref,
    required this.resolution,
    required this.hiddenLabel,
    required this.style,
    this.onTapMention,
  });

  final WidgetRef ref;
  final ProfileEntityMentionResolution resolution;
  final String hiddenLabel;
  final TextStyle style;
  final EntityMentionTapCallback? onTapMention;

  @override
  Widget build(BuildContext context) {
    final label = resolution.displayText(hiddenLabel);
    final text = Text.rich(
      TextSpan(text: label, style: style, semanticsLabel: label),
    );
    if (!resolution.visible || onTapMention == null) return text;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTapMention!(context, ref, resolution),
      child: text,
    );
  }
}

TextStyle _mentionStyle(
  BuildContext context,
  ProfileEntityMentionResolution resolution,
  TextStyle baseStyle,
) {
  final theme = Theme.of(context);
  final member = resolution.entity is Member
      ? resolution.entity as Member
      : null;
  final color =
      member != null &&
          member.customColorEnabled &&
          member.customColorHex != null
      ? AppColors.fromHex(member.customColorHex!)
      : resolution.visible
      ? theme.colorScheme.primary
      : theme.colorScheme.onSurfaceVariant;
  return baseStyle.copyWith(
    color: color,
    fontWeight: FontWeight.w600,
    backgroundColor: color.withValues(alpha: resolution.visible ? 0.14 : 0.08),
  );
}

EntityMentionTarget? _targetFromAttributes(Map<String, String> attributes) {
  final typeName = attributes['type'];
  final id = attributes['id'];
  if (typeName == null || id == null) return null;
  final type = EntityMentionType.fromTokenName(typeName);
  if (type == null || !isValidEntityMentionId(id)) return null;
  return EntityMentionTarget(
    type: type,
    id: id,
    isLegacyMember: attributes['legacy'] == 'true',
  );
}

final _inlineBoldStar = RegExp(r'\*\*(.+?)\*\*');
final _inlineBoldUnderscore = RegExp(r'__(.+?)__');
final _inlineItalicStar = RegExp(r'(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)');
final _inlineItalicUnderscore = RegExp(r'(?<!_)_(?!_)(.+?)(?<!_)_(?!_)');
final _inlineCode = RegExp(r'`(.+?)`');

void _appendInlineMarkdownSpans(
  List<InlineSpan> spans,
  String data,
  TextStyle baseStyle,
  BuildContext context,
) {
  if (data.isEmpty) return;
  final codeColor = Theme.of(context).colorScheme.surfaceContainerHighest;
  final segments = <_InlineSegment>[];
  final matched = List.filled(data.length, false);

  void addMatches(
    RegExp pattern,
    TextStyle Function(TextStyle base) styleForMatch,
  ) {
    for (final match in pattern.allMatches(data)) {
      if (_overlaps(matched, match.start, match.end)) continue;
      for (var i = match.start; i < match.end; i++) {
        matched[i] = true;
      }
      segments.add(
        _InlineSegment(
          start: match.start,
          end: match.end,
          content: match.group(1)!,
          style: styleForMatch(baseStyle),
        ),
      );
    }
  }

  addMatches(
    _inlineCode,
    (base) =>
        base.copyWith(fontFamily: 'monospace', backgroundColor: codeColor),
  );
  addMatches(
    _inlineBoldStar,
    (base) => base.copyWith(fontWeight: FontWeight.bold),
  );
  addMatches(
    _inlineBoldUnderscore,
    (base) => base.copyWith(fontWeight: FontWeight.bold),
  );
  addMatches(
    _inlineItalicStar,
    (base) => base.copyWith(fontStyle: FontStyle.italic),
  );
  addMatches(
    _inlineItalicUnderscore,
    (base) => base.copyWith(fontStyle: FontStyle.italic),
  );

  if (segments.isEmpty) {
    spans.add(TextSpan(text: data, style: baseStyle));
    return;
  }

  segments.sort((a, b) => a.start.compareTo(b.start));
  var cursor = 0;
  for (final segment in segments) {
    if (cursor < segment.start) {
      spans.add(TextSpan(text: data.substring(cursor, segment.start)));
    }
    spans.add(TextSpan(text: segment.content, style: segment.style));
    cursor = segment.end;
  }
  if (cursor < data.length) {
    spans.add(TextSpan(text: data.substring(cursor)));
  }
}

bool _overlaps(List<bool> matched, int start, int end) {
  for (var i = start; i < end; i++) {
    if (matched[i]) return true;
  }
  return false;
}

class _InlineSegment {
  const _InlineSegment({
    required this.start,
    required this.end,
    required this.content,
    required this.style,
  });

  final int start;
  final int end;
  final String content;
  final TextStyle style;
}
