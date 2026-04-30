import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/utils/proxy_tag.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';

/// Read-only display of a member's proxy tags. Editing happens in the
/// member edit sheet.
class ProxyTagsSection extends StatelessWidget {
  const ProxyTagsSection({super.key, required this.member});

  final Member member;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final tags = parseProxyTags(member.proxyTagsJson);

    if (tags.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.tag, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                l10n.memberSectionProxyTags,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: PrismSurface(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final tag in tags) _ProxyTagChip(tag: tag)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProxyTagChip extends StatelessWidget {
  const _ProxyTagChip({required this.tag});

  final ProxyTag tag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prefix = tag.prefix ?? '';
    final suffix = tag.suffix ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(20)),
      ),
      child: Text(
        '${prefix}text$suffix',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
