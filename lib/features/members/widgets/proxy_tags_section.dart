import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/utils/proxy_tag.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';

/// Display of a member's proxy tags.
///
/// Proxy tags can be set locally in Prism and may also be pulled from
/// PluralKit. This widget renders them as chips, optionally offering Prism's
/// local editor and a PK dashboard deeplink for linked members.
class ProxyTagsSection extends StatelessWidget {
  const ProxyTagsSection({
    super.key,
    required this.member,
    this.onEditInPrism,
    Future<bool> Function(Uri)? launcher,
  }) : _launcher = launcher;

  final Member member;
  final VoidCallback? onEditInPrism;
  final Future<bool> Function(Uri)? _launcher;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final tags = parseProxyTags(member.proxyTagsJson);
    final deeplinkId = member.pluralkitId;
    final editInPrism = onEditInPrism;

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (tags.isEmpty)
                    Text(
                      l10n.memberProxyTagsEmpty,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final tag in tags) _ProxyTagChip(tag: tag),
                      ],
                    ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.memberProxyTagsLocalDescription,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (editInPrism != null) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: PrismButton(
                        label: l10n.memberProxyTagsEditInPrism,
                        icon: AppIcons.editOutlined,
                        tone: PrismButtonTone.filled,
                        density: PrismControlDensity.compact,
                        onPressed: editInPrism,
                      ),
                    ),
                  ],
                  if (deeplinkId != null && deeplinkId.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: PrismButton(
                        label: l10n.memberProxyTagsEditOnPk,
                        icon: AppIcons.editOutlined,
                        tone: PrismButtonTone.subtle,
                        density: PrismControlDensity.compact,
                        onPressed: () => _openOnPluralKit(deeplinkId),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openOnPluralKit(String pluralkitId) async {
    final uri = Uri.parse('https://dash.pluralkit.me/profile/m/$pluralkitId');
    final launcher =
        _launcher ??
        (Uri u) => launchUrl(u, mode: LaunchMode.externalApplication);
    await launcher(uri);
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
