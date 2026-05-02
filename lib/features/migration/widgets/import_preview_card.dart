import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/migration/providers/migration_providers.dart';
import 'package:prism_plurality/features/migration/services/sp_custom_front_disposition.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';

/// Card displaying a summary of what will be imported.
class ImportPreviewCard extends ConsumerWidget {
  const ImportPreviewCard({
    super.key,
    required this.data,
    this.warnings = const [],
  });

  final SpExportData data;
  final List<String> warnings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dispositions = ref.watch(cfDispositionProvider);
    final terms = watchTerminology(context, ref);

    // Only show the breakdown line if every CF has a disposition chosen.
    String? cfBreakdown;
    if (data.customFronts.isNotEmpty &&
        data.customFronts.every((cf) => dispositions.containsKey(cf.id))) {
      var asMember = 0;
      var asSleep = 0;
      var asNote = 0;
      var asSkip = 0;
      for (final cf in data.customFronts) {
        switch (dispositions[cf.id]!) {
          case CfDisposition.importAsMember:
            asMember++;
          case CfDisposition.convertToSleep:
            asSleep++;
          case CfDisposition.mergeAsNote:
            asNote++;
          case CfDisposition.skip:
            asSkip++;
        }
      }
      cfBreakdown = context.l10n.migrationCfPreviewBreakdown(
        asMember,
        asSleep,
        asNote,
        asSkip,
      );
    }

    return PrismSurface(
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
            label: context.l10n.migrationSupportedMembers(terms.plural),
            count: data.members.length,
          ),
          if (data.customFronts.isNotEmpty)
            _CountRow(
              icon: AppIcons.labelOutlined,
              label: context.l10n.migrationPreviewCustomFronts,
              count: data.customFronts.length,
            ),
          if (cfBreakdown != null)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 2, bottom: 2),
              child: Text(
                cfBreakdown,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
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
          if (data.notes.isNotEmpty)
            _CountRow(
              icon: AppIcons.noteOutlined,
              label: context.l10n.migrationResultNotes,
              count: data.notes.length,
            ),
          if (data.comments.isNotEmpty)
            _CountRow(
              icon: AppIcons.commentOutlined,
              label: context.l10n.migrationResultComments,
              count: data.comments.length,
            ),
          if (data.customFields.isNotEmpty)
            _CountRow(
              icon: AppIcons.textFields,
              label: context.l10n.migrationResultCustomFields,
              count: data.customFields.length,
            ),
          if (data.automatedTimers.isNotEmpty || data.repeatedTimers.isNotEmpty)
            _CountRow(
              icon: AppIcons.alarm,
              label: context.l10n.migrationResultReminders,
              count: data.automatedTimers.length + data.repeatedTimers.length,
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
            ...warnings.map(
              (w) => Padding(
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
              ),
            ),
          ],
        ],
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
          Icon(icon, size: 16, color: theme.colorScheme.primary),
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
