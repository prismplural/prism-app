import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/settings/providers/reset_data_provider.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_settings_row.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

class ResetDataScreen extends ConsumerWidget {
  const ResetDataScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PrismPageScaffold(
      topBar: const PrismTopBar(title: 'Reset Data', showBackButton: true),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
        children: [
          PrismSection(
            title: 'Categories',
            description:
                'Reset specific categories of data on this device. '
                'Sync System reset wipes sync setup without deleting your app data.',
            child: PrismSectionCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < _granularCategories.length; i++) ...[
                    if (i > 0)
                      const Divider(height: 1, indent: 60, endIndent: 12),
                    _buildResetRow(
                      context,
                      ref,
                      icon: _granularCategories[i].icon,
                      iconColor: _granularCategories[i].color,
                      category: _granularCategories[i].category,
                    ),
                  ],
                ],
              ),
            ),
          ),
          PrismSection(
            title: 'Danger Zone',
            child: PrismSectionCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _buildResetRow(
                    context,
                    ref,
                    icon: AppIcons.syncDisabled,
                    iconColor: Colors.deepOrange,
                    category: ResetCategory.sync,
                    destructive: true,
                  ),
                  const Divider(height: 1, indent: 60, endIndent: 12),
                  _buildResetRow(
                    context,
                    ref,
                    icon: AppIcons.deleteForever,
                    iconColor: Colors.red,
                    category: ResetCategory.all,
                    destructive: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResetRow(
    BuildContext context,
    WidgetRef ref, {
    required IconData icon,
    required Color iconColor,
    required ResetCategory category,
    bool destructive = false,
  }) {
    return PrismSettingsRow(
      icon: icon,
      iconColor: iconColor,
      title: category.label,
      subtitle: category.description,
      destructive: destructive,
      onTap: () => _showConfirmation(context, ref, category),
    );
  }

  Future<void> _showConfirmation(
    BuildContext context,
    WidgetRef ref,
    ResetCategory category,
  ) async {
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

class _CategoryEntry {
  const _CategoryEntry(this.category, this.icon, this.color);
  final ResetCategory category;
  final IconData icon;
  final Color color;
}

final _granularCategories = [
  _CategoryEntry(ResetCategory.members, AppIcons.peopleOutline, Colors.blue),
  _CategoryEntry(ResetCategory.fronting, AppIcons.swapHoriz, Colors.purple),
  _CategoryEntry(ResetCategory.chat, AppIcons.chatBubbleOutline, Colors.teal),
  _CategoryEntry(ResetCategory.polls, AppIcons.pollOutlined, Colors.orange),
  _CategoryEntry(
    ResetCategory.habits,
    AppIcons.checkCircleOutline,
    Colors.green,
  ),
  _CategoryEntry(ResetCategory.sleep, AppIcons.bedtimeOutlined, Colors.indigo),
];
