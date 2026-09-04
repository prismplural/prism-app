import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/markdown/member_mention_syntax.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/utils/safe_link.dart';
import 'package:prism_plurality/shared/widgets/markdown_text.dart';
import 'package:prism_plurality/shared/widgets/prism_markdown_text.dart';

// ---------------------------------------------------------------------------
// Shared display widget helpers extracted from custom_fields_display.dart.
// These have no dependency on the registry or definitions — they are pure
// Flutter widgets used by both the display file and the definition files.
// ---------------------------------------------------------------------------

class FieldInlineMarkdownText extends ConsumerWidget {
  const FieldInlineMarkdownText(
    this.data, {
    super.key,
    this.style,
    this.textAlign = TextAlign.start,
  });

  final String data;
  final TextStyle? style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mentionMembers = containsMemberMention(data)
        ? ref.watch(activeMemberListProvider).value ?? const <Member>[]
        : const <Member>[];
    final mentionMemberMap = {
      for (final member in mentionMembers) member.id: member,
    };
    final preferDisplayName = ref.watch(memberNamePreferDisplayProvider);
    final mentionVersion = mentionMemberMap.entries
        .map(
          (entry) =>
              '${entry.key}:${entry.value.effectiveName(preferDisplayName: preferDisplayName)}',
        )
        .join(',');
    return MarkdownText(
      key: ValueKey('${data}_${preferDisplayName}_$mentionVersion'),
      data: _stripUnsafeMarkdownLinks(data),
      baseStyle: style,
      textAlign: textAlign,
      memberMap: mentionMemberMap,
      preferDisplayName: preferDisplayName,
      onTapMember: (memberId) =>
          unawaited(context.push(AppRoutePaths.member(memberId))),
    );
  }
}

String _stripUnsafeMarkdownLinks(String input) {
  final output = StringBuffer();
  var cursor = 0;

  while (cursor < input.length) {
    final labelStart = input.indexOf('[', cursor);
    if (labelStart < 0) {
      output.write(input.substring(cursor));
      break;
    }
    final labelEnd = input.indexOf('](', labelStart + 1);
    if (labelEnd < 0) {
      output.write(input.substring(cursor));
      break;
    }

    var hrefEnd = labelEnd + 2;
    var depth = 1;
    while (hrefEnd < input.length && depth > 0) {
      final char = input[hrefEnd++];
      if (char == '(') depth++;
      if (char == ')') depth--;
    }
    if (depth != 0) {
      output.write(input.substring(cursor, labelEnd + 2));
      cursor = labelEnd + 2;
      continue;
    }

    final href = input.substring(labelEnd + 2, hrefEnd - 1);
    if (safeExternalUri(href) == null) {
      output
        ..write(input.substring(cursor, labelStart))
        ..write(input.substring(labelStart + 1, labelEnd));
    } else {
      output.write(input.substring(cursor, hrefEnd));
    }
    cursor = hrefEnd;
  }

  return output.toString();
}

/// Renders a long text custom field value in full. It sits on a scrollable
/// member detail surface, so long values grow the scroll extent.
class FieldLongTextPreview extends StatelessWidget {
  const FieldLongTextPreview({super.key, required this.data, this.style});

  final String data;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PrismMarkdownText(
      data: data,
      enabled: true,
      baseStyle: style ?? theme.textTheme.bodyMedium,
    );
  }
}

/// Renders a hex color value with a circular color swatch preview.
class FieldColorDisplay extends StatelessWidget {
  const FieldColorDisplay({super.key, required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color? color;
    try {
      color = AppColors.fromHex(value);
    } catch (_) {
      color = null;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (color != null) ...[
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
          textAlign: TextAlign.end,
        ),
      ],
    );
  }
}
