import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/pluralkit/providers/pk_sync_event_log_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_expandable_section.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';

/// Session-scoped debug surface for the PluralKit sync log. Mirrors the
/// Prism Sync Debug Screen in shape; diverges in two places:
///   - No fronting-migration breadcrumbs section.
///   - Error-bearing event tiles render a leading icon in the
///     theme's `colorScheme.error` so users can scan the log for the
///     actionable rows.
class PkSyncDebugScreen extends ConsumerWidget {
  const PkSyncDebugScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(pkSyncEventLogProvider);
    final hasEntries = events.isNotEmpty;

    Future<void> copyLog() async {
      const encoder = JsonEncoder.withIndent('  ');
      final buffer = StringBuffer()
        ..writeln('PluralKit sync log (${events.length} events)')
        ..writeln();
      for (final entry in events.reversed) {
        buffer.writeln('[${entry.timeLabel}] ${entry.summary}');
        buffer
          ..writeln(encoder.convert(entry.data))
          ..writeln();
      }
      await Clipboard.setData(ClipboardData(text: buffer.toString()));
      if (!context.mounted) return;
      PrismToast.show(
        context,
        message: context.l10n.settingsPkSyncDebugCopiedToast,
      );
    }

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: context.l10n.settingsPkSyncDebugTitle,
        subtitle: context.l10n.settingsPkSyncDebugEventCount(events.length),
        showBackButton: true,
        actions: [
          PrismTopBarAction(
            icon: AppIcons.copyAll,
            tooltip: context.l10n.settingsPkSyncDebugCopyTooltip,
            onPressed: hasEntries ? copyLog : null,
          ),
          PrismTopBarAction(
            icon: AppIcons.deleteOutline,
            tooltip: context.l10n.settingsPkSyncDebugClearTooltip,
            onPressed: hasEntries
                ? () => ref.read(pkSyncEventLogProvider.notifier).clear()
                : null,
          ),
        ],
      ),
      bodyPadding: EdgeInsets.zero,
      body: !hasEntries
          ? const _EmptyState()
          : ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                NavBarInset.of(context) + 16,
              ),
              children: [
                for (final entry in events.reversed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _EventTile(entry: entry),
                  ),
              ],
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              AppIcons.duotoneData,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.settingsPkSyncDebugEmptyTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.settingsPkSyncDebugEmptyBody,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.entry});

  final PkSyncEventLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final titleText = Text(
      entry.summary,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );

    // Per spec: error-bearing events get a leading icon inside the title slot
    // so users can scan the log for actionable rows. We use a Row in the
    // title slot (rather than the section's optional `leading` slot) so the
    // icon sits flush with the summary text instead of in a separate column.
    final Widget title = entry.isError
        ? Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                AppIcons.errorOutline,
                color: theme.colorScheme.error,
                size: 18,
              ),
              const SizedBox(width: 8),
              Flexible(child: titleText),
            ],
          )
        : titleText;

    return PrismExpandableSection(
      title: title,
      subtitle: Text(
        entry.timeLabel,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(
              PrismShapes.of(context).radius(12),
            ),
          ),
          child: SelectableText(
            const JsonEncoder.withIndent('  ').convert(entry.data),
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }
}
