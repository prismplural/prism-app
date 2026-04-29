import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';

/// Card displaying the results of the last PluralKit sync.
class PkSyncSummaryCard extends ConsumerWidget {
  final PkSyncSummary summary;

  const PkSyncSummaryCard({super.key, required this.summary});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final terms = watchTerminology(context, ref);
    String termFor(int count) =>
        count == 1 ? terms.singularLower : terms.pluralLower;

    return PrismSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.pluralkitLastSyncSummary,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          if (summary.totalChanges == 0)
            Text(
              context.l10n.pluralkitUpToDate,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else ...[
            if (summary.membersPulled > 0)
              _SummaryRow(
                icon: AppIcons.download,
                label: context.l10n.pluralkitMembersPulled(
                  summary.membersPulled,
                  termFor(summary.membersPulled),
                ),
                color: theme.colorScheme.primary,
              ),
            if (summary.membersPushed > 0)
              _SummaryRow(
                icon: AppIcons.upload,
                label: context.l10n.pluralkitMembersPushed(
                  summary.membersPushed,
                  termFor(summary.membersPushed),
                ),
                color: theme.colorScheme.tertiary,
              ),
            if (summary.switchesPulled > 0)
              _SummaryRow(
                icon: AppIcons.download,
                label: context.l10n.pluralkitSwitchesPulled(
                  summary.switchesPulled,
                ),
                color: theme.colorScheme.primary,
              ),
            if (summary.switchesPushed > 0)
              _SummaryRow(
                icon: AppIcons.upload,
                label: context.l10n.pluralkitSwitchesPushed(
                  summary.switchesPushed,
                ),
                color: theme.colorScheme.tertiary,
              ),
            if (summary.membersSkipped > 0)
              _SummaryRow(
                icon: AppIcons.skipNext,
                label: context.l10n.pluralkitMembersUnchanged(
                  summary.membersSkipped,
                  termFor(summary.membersSkipped),
                ),
                color: theme.colorScheme.onSurfaceVariant,
              ),
          ],
        ],
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
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
