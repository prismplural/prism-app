import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/settings/providers/reset_data_provider.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

class ResetDataScreen extends ConsumerWidget {
  const ResetDataScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return PrismPageScaffold(
      topBar: const PrismTopBar(title: 'Reset Data', showBackButton: true),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Reset specific categories of data on this device. '
              'Sync System reset wipes sync setup without deleting your app data. ',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          ..._granularCategories.map(
            (entry) => _ResetTile(
              icon: entry.icon,
              iconColor: entry.color,
              category: entry.category,
            ),
          ),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'DANGER ZONE',
              style: TextStyle(
                color: Colors.red.withValues(alpha: 0.7),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const _ResetTile(
            icon: Icons.sync_disabled,
            iconColor: Colors.deepOrange,
            category: ResetCategory.sync,
            isDanger: true,
          ),
          const _ResetTile(
            icon: Icons.delete_forever,
            iconColor: Colors.red,
            category: ResetCategory.all,
            isDanger: true,
          ),
        ],
      ),
    );
  }
}

class _CategoryEntry {
  const _CategoryEntry(this.category, this.icon, this.color);
  final ResetCategory category;
  final IconData icon;
  final Color color;
}

const _granularCategories = [
  _CategoryEntry(ResetCategory.members, Icons.people_outline, Colors.blue),
  _CategoryEntry(ResetCategory.fronting, Icons.swap_horiz, Colors.purple),
  _CategoryEntry(ResetCategory.chat, Icons.chat_bubble_outline, Colors.teal),
  _CategoryEntry(ResetCategory.polls, Icons.poll_outlined, Colors.orange),
  _CategoryEntry(
    ResetCategory.habits,
    Icons.check_circle_outline,
    Colors.green,
  ),
  _CategoryEntry(ResetCategory.sleep, Icons.bedtime_outlined, Colors.indigo),
];

class _ResetTile extends ConsumerWidget {
  const _ResetTile({
    required this.icon,
    required this.iconColor,
    required this.category,
    this.isDanger = false,
  });

  final IconData icon;
  final Color iconColor;
  final ResetCategory category;
  final bool isDanger;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return ListTile(
      leading: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(color: iconColor, shape: BoxShape.circle),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
      title: Text(
        category.label,
        style: isDanger
            ? TextStyle(color: Colors.red.withValues(alpha: 0.8))
            : null,
      ),
      subtitle: Text(
        category.description,
        style: TextStyle(color: onSurface.withValues(alpha: 0.5)),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: isDanger
            ? Colors.red.withValues(alpha: 0.5)
            : onSurface.withValues(alpha: 0.3),
      ),
      onTap: () => _showConfirmation(context, ref),
    );
  }

  Future<void> _showConfirmation(BuildContext context, WidgetRef ref) async {
    final isAll = category == ResetCategory.all;
    final isSync = category == ResetCategory.sync;
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: 'Reset ${category.label}?',
      message: isAll
          ? 'This will permanently delete all your data including members, '
                'fronting sessions, messages, polls, habits, sleep data, and settings. '
                'This action cannot be undone.'
          : isSync
          ? 'This keeps your local app data, but removes sync keys, relay '
                'configuration, device identity, and sync history from this device. '
                'You will need to set up sync again afterward.'
          : 'This will permanently delete all ${category.label.toLowerCase()} data '
                'on this device. This action cannot be undone.',
      confirmLabel: isAll
          ? 'Reset Everything'
          : isSync
          ? 'Reset Sync'
          : 'Reset',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(resetDataNotifierProvider.notifier).reset(category);
      if (!context.mounted) return;
      PrismToast.show(context, message: '${category.label} reset successfully');
    } catch (e) {
      if (!context.mounted) return;
      PrismToast.error(context, message: 'Failed to reset: $e');
    }
  }
}
