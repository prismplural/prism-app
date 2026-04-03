import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
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
      PrismToast.show(context, message: 'Sync event log copied');
    }

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: 'Sync Event Log',
        subtitle: '${events.length} events',
        showBackButton: true,
        actions: [
          PrismTopBarAction(
            icon: AppIcons.copyAll,
            tooltip: 'Copy log',
            onPressed: events.isEmpty ? null : copyLog,
          ),
          PrismTopBarAction(
            icon: AppIcons.deleteOutline,
            tooltip: 'Clear log',
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
              padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
              itemCount: events.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
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
              AppIcons.duotoneReceipt,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No sync events recorded',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Sync events will appear here as they happen.',
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

    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
              borderRadius: BorderRadius.circular(12),
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
