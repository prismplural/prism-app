import 'package:flutter/material.dart';

import 'package:prism_plurality/features/migration/services/sp_parser.dart';

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
                'System: ${data.systemName}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              'Data found',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            _CountRow(
              icon: Icons.person,
              label: 'Members',
              count: data.members.length,
            ),
            if (data.customFronts.isNotEmpty)
              _CountRow(
                icon: Icons.label_outlined,
                label: 'Custom fronts',
                count: data.customFronts.length,
              ),
            _CountRow(
              icon: Icons.flash_on,
              label: 'Front history entries',
              count: data.frontHistory.length,
            ),
            if (data.groups.isNotEmpty)
              _CountRow(
                icon: Icons.group,
                label: 'Groups',
                count: data.groups.length,
              ),
            if (data.channels.isNotEmpty)
              _CountRow(
                icon: Icons.chat_bubble_outline,
                label: 'Chat channels',
                count: data.channels.length,
              ),
            if (data.messages.isNotEmpty)
              _CountRow(
                icon: Icons.message_outlined,
                label: 'Messages',
                count: data.messages.length,
              ),
            if (data.polls.isNotEmpty)
              _CountRow(
                icon: Icons.poll_outlined,
                label: 'Polls',
                count: data.polls.length,
              ),
            const SizedBox(height: 8),
            Divider(color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 4),
            _CountRow(
              icon: Icons.summarize_outlined,
              label: 'Total entities',
              count: data.totalEntities,
              bold: true,
            ),
            if (warnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Warnings',
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
                          Icons.warning_amber_rounded,
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
