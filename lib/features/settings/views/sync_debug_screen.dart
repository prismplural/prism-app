import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_expandable_section.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

class SyncDebugScreen extends ConsumerWidget {
  const SyncDebugScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(syncEventLogProvider);

    Future<void> copyLog() async {
      final lines = events.reversed
          .map((e) => '[${e.timeLabel}] ${e.summary}')
          .join('\n');
      await Clipboard.setData(ClipboardData(text: lines));
      if (!context.mounted) return;
      PrismToast.show(context, message: context.l10n.settingsSyncDebugCopiedToast);
    }

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: context.l10n.settingsSyncDebugTitle,
        subtitle: context.l10n.settingsSyncDebugEventCount(events.length),
        showBackButton: true,
        actions: [
          PrismTopBarAction(
            icon: AppIcons.copyAll,
            tooltip: context.l10n.settingsSyncDebugCopyLogTooltip,
            onPressed: events.isEmpty ? null : copyLog,
          ),
          PrismTopBarAction(
            icon: AppIcons.deleteOutline,
            tooltip: context.l10n.settingsSyncDebugClearLogTooltip,
            onPressed: events.isEmpty
                ? null
                : () => ref.read(syncEventLogProvider.notifier).clear(),
          ),
        ],
      ),
      bodyPadding: EdgeInsets.zero,
      body: events.isEmpty
          ? const _EmptyState()
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                NavBarInset.of(context) + 16,
              ),
              itemCount: events.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final entry = events[events.length - 1 - index];
                return _EventTile(entry: entry);
              },
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
              borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(12)),
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
