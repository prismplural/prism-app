import 'package:flutter/material.dart';

import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// Card displaying the results of the last PluralKit sync.
class PkSyncSummaryCard extends StatelessWidget {
  final PkSyncSummary summary;

  const PkSyncSummaryCard({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Last Sync Summary',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            if (summary.totalChanges == 0)
              Text(
                'Everything is up to date.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else ...[
              if (summary.membersPulled > 0)
                _SummaryRow(
                  icon: AppIcons.download,
                  label: '${summary.membersPulled} member${summary.membersPulled == 1 ? '' : 's'} pulled',
                  color: theme.colorScheme.primary,
                ),
              if (summary.membersPushed > 0)
                _SummaryRow(
                  icon: AppIcons.upload,
                  label: '${summary.membersPushed} member${summary.membersPushed == 1 ? '' : 's'} pushed',
                  color: theme.colorScheme.tertiary,
                ),
              if (summary.switchesPulled > 0)
                _SummaryRow(
                  icon: AppIcons.download,
                  label: '${summary.switchesPulled} switch${summary.switchesPulled == 1 ? '' : 'es'} pulled',
                  color: theme.colorScheme.primary,
                ),
              if (summary.switchesPushed > 0)
                _SummaryRow(
                  icon: AppIcons.upload,
                  label: '${summary.switchesPushed} switch${summary.switchesPushed == 1 ? '' : 'es'} pushed',
                  color: theme.colorScheme.tertiary,
                ),
              if (summary.membersSkipped > 0)
                _SummaryRow(
                  icon: AppIcons.skipNext,
                  label: '${summary.membersSkipped} member${summary.membersSkipped == 1 ? '' : 's'} unchanged',
                  color: theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: color,
                ),
          ),
        ],
      ),
    );
  }
}
