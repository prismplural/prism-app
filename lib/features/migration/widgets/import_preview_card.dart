import 'package:flutter/material.dart';

import 'package:prism_plurality/features/migration/services/sp_parser.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// Card displaying a summary of what will be imported.
class ImportPreviewCard extends StatelessWidget {
  const ImportPreviewCard({
    super.key,
    required this.data,
    this.warnings = const [],
  });

  final SpExportData data;
  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (data.systemName != null) ...[
              Text(
                context.l10n.migrationPreviewSystem(data.systemName!),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              context.l10n.migrationPreviewDataFound,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            _CountRow(
              icon: AppIcons.person,
              label: context.l10n.migrationSupportedMembers,
              count: data.members.length,
            ),
            if (data.customFronts.isNotEmpty)
              _CountRow(
                icon: AppIcons.labelOutlined,
                label: context.l10n.migrationPreviewCustomFronts,
                count: data.customFronts.length,
              ),
            _CountRow(
              icon: AppIcons.flashOn,
              label: context.l10n.migrationPreviewFrontHistoryEntries,
              count: data.frontHistory.length,
            ),
            if (data.groups.isNotEmpty)
              _CountRow(
                icon: AppIcons.group,
                label: context.l10n.migrationPreviewGroups,
                count: data.groups.length,
              ),
            if (data.channels.isNotEmpty)
              _CountRow(
                icon: AppIcons.chatBubbleOutline,
                label: context.l10n.migrationPreviewChatChannels,
                count: data.channels.length,
              ),
            if (data.messages.isNotEmpty)
              _CountRow(
                icon: AppIcons.messageOutlined,
                label: context.l10n.migrationPreviewMessages,
                count: data.messages.length,
              ),
            if (data.polls.isNotEmpty)
              _CountRow(
                icon: AppIcons.pollOutlined,
                label: context.l10n.migrationPreviewPolls,
                count: data.polls.length,
              ),
            const SizedBox(height: 8),
            Divider(color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 4),
            _CountRow(
              icon: AppIcons.summarizeOutlined,
              label: context.l10n.migrationPreviewTotalEntities,
              count: data.totalEntities,
              bold: true,
            ),
            if (warnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                context.l10n.migrationPreviewWarnings,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 4),
              ...warnings.map((w) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          AppIcons.warningAmberRounded,
                          size: 16,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            w,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow({
    required this.icon,
    required this.label,
    required this.count,
    this.bold = false,
  });

  final IconData icon;
  final String label;
  final int count;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = bold
        ? theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)
        : theme.textTheme.bodySmall;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: style)),
          Text(
            count.toString(),
            style: style?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
