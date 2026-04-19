import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';

/// Read-only display of PluralKit proxy tags.
///
/// Proxy tags are pulled from PK but never pushed by Prism. This widget
/// renders them as chips with a deeplink to edit on the PK dashboard. For
/// unlinked members the whole section collapses.
class ProxyTagsSection extends StatelessWidget {
  const ProxyTagsSection({
    super.key,
    required this.member,
    Future<bool> Function(Uri)? launcher,
  }) : _launcher = launcher;

  final Member member;
  final Future<bool> Function(Uri)? _launcher;

  @override
  Widget build(BuildContext context) {
    if (member.pluralkitId == null && member.pluralkitUuid == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final l10n = context.l10n;
    final tags = _parseProxyTags(member.proxyTagsJson);
    final deeplinkId = member.pluralkitId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.notesOutlined,
                  size: 18, color: theme.colorScheme.primary),
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
                    l10n.memberProxyTagsManagedOnPk,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
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
    final launcher = _launcher ??
        (Uri u) => launchUrl(u, mode: LaunchMode.externalApplication);
    await launcher(uri);
  }

  static List<ProxyTag> _parseProxyTags(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => ProxyTag(
                prefix: e['prefix'] as String?,
                suffix: e['suffix'] as String?,
              ))
          .where((t) => t.prefix != null || t.suffix != null)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

class ProxyTag {
  const ProxyTag({this.prefix, this.suffix});
  final String? prefix;
  final String? suffix;
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
