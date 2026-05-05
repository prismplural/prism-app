import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/services/fronting_migration_breadcrumb_log.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_expandable_section.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

final frontingMigrationBreadcrumbsProvider =
    FutureProvider<List<FrontingMigrationBreadcrumb>>((ref) {
      return FrontingMigrationBreadcrumbLog.instance.readAll();
    });

class SyncDebugScreen extends ConsumerWidget {
  const SyncDebugScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(syncEventLogProvider);
    final breadcrumbsAsync = ref.watch(frontingMigrationBreadcrumbsProvider);
    final breadcrumbs = breadcrumbsAsync.asData?.value ?? const [];
    final breadcrumbCount = breadcrumbs.length;
    final hasAnyEntries = events.isNotEmpty || breadcrumbCount > 0;

    Future<void> copyLog() async {
      final breadcrumbs = await ref.read(
        frontingMigrationBreadcrumbsProvider.future,
      );
      const encoder = JsonEncoder.withIndent('  ');
      final buffer = StringBuffer()
        ..writeln('Sync event log (${events.length} entries)')
        ..writeln();
      for (final entry in events.reversed) {
        buffer.writeln('[${entry.timeLabel}] ${entry.summary}');
        if (entry.data.isNotEmpty) {
          buffer
            ..writeln(encoder.convert(entry.data))
            ..writeln();
        }
      }
      if (breadcrumbs.isNotEmpty) {
        buffer
          ..writeln(
            'Fronting migration breadcrumbs (${breadcrumbs.length} entries)',
          )
          ..writeln();
        for (final breadcrumb in breadcrumbs.reversed) {
          final ts = _formatTimestamp(breadcrumb.timestamp);
          buffer.writeln('[$ts] ${breadcrumb.summary}');
          buffer
            ..writeln(encoder.convert(breadcrumb.toJson()))
            ..writeln();
        }
      }
      await Clipboard.setData(ClipboardData(text: buffer.toString()));
      if (!context.mounted) return;
      PrismToast.show(
        context,
        message: context.l10n.settingsSyncDebugCopiedToast,
      );
    }

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: context.l10n.settingsSyncDebugTitle,
        subtitle:
            '${context.l10n.settingsSyncDebugEventCount(events.length)}'
            '${breadcrumbCount > 0 ? ' • $breadcrumbCount migration breadcrumbs' : ''}',
        showBackButton: true,
        actions: [
          PrismTopBarAction(
            icon: AppIcons.copyAll,
            tooltip: context.l10n.settingsSyncDebugCopyLogTooltip,
            onPressed: hasAnyEntries ? copyLog : null,
          ),
          PrismTopBarAction(
            icon: AppIcons.deleteOutline,
            tooltip: context.l10n.settingsSyncDebugClearLogTooltip,
            onPressed: hasAnyEntries
                ? () async {
                    ref.read(syncEventLogProvider.notifier).clear();
                    await FrontingMigrationBreadcrumbLog.instance.clear();
                    ref.invalidate(frontingMigrationBreadcrumbsProvider);
                  }
                : null,
          ),
        ],
      ),
      bodyPadding: EdgeInsets.zero,
      body: !hasAnyEntries
          ? const _EmptyState()
          : ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                NavBarInset.of(context) + 16,
              ),
              children: [
                if (breadcrumbCount > 0) ...[
                  Text(
                    'Fronting migration breadcrumbs',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  ...[
                    for (final breadcrumb in breadcrumbs.reversed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _FrontingMigrationBreadcrumbTile(
                          breadcrumb: breadcrumb,
                        ),
                      ),
                  ],
                  const SizedBox(height: 8),
                ],
                if (events.isNotEmpty) ...[
                  Text(
                    'Sync events',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  ...[
                    for (final entry in events.reversed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _EventTile(entry: entry),
                      ),
                  ],
                ],
              ],
            ),
    );
  }
}

String _formatTimestamp(DateTime timestamp) {
  final local = timestamp.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}:'
      '${local.second.toString().padLeft(2, '0')}';
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
              context.l10n.settingsSyncDebugEmptyTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.settingsSyncDebugEmptyBody,
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

  final SyncEventLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PrismExpandableSection(
      title: Text(
        entry.summary,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        entry.timeLabel,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      children: [
        if (entry.data.isNotEmpty)
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

class _FrontingMigrationBreadcrumbTile extends StatelessWidget {
  const _FrontingMigrationBreadcrumbTile({required this.breadcrumb});

  final FrontingMigrationBreadcrumb breadcrumb;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PrismExpandableSection(
      title: Text(
        breadcrumb.summary,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        _formatTimestamp(breadcrumb.timestamp),
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
            const JsonEncoder.withIndent('  ').convert(breadcrumb.toJson()),
            style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }
}
