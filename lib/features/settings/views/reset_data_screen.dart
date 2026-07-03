import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/reset/reset_recovery_app.dart';
import 'package:prism_plurality/domain/preferences/fronting_terms.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/settings/providers/reset_data_provider.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_grouped_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_settings_row.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

class ResetDataScreen extends ConsumerWidget {
  const ResetDataScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fieldsAsync = ref.watch(topLevelCustomFieldsProvider);
    // while loading/error, disable optimistically — better than a stale-enabled tap target
    final customFieldsEmpty = fieldsAsync.maybeWhen(
      data: (fields) => fields.isEmpty,
      orElse: () => true,
    );

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: context.l10n.resetDataTitle,
        showBackButton: true,
      ),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
        children: [
          PrismSection(
            title: context.l10n.resetDataCategoriesSection,
            description: context.l10n.resetDataCategoriesDescription,
            child: PrismGroupedSectionCard(
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
                      enabled:
                          _granularCategories[i].category ==
                              ResetCategory.customFields
                          ? !customFieldsEmpty
                          : true,
                    ),
                  ],
                ],
              ),
            ),
          ),
          PrismSection(
            title: context.l10n.resetDataDangerZone,
            child: PrismGroupedSectionCard(
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
    bool enabled = true,
  }) {
    final terms = readTerminology(context, ref);
    final frontingTerms = watchFrontingTerms(ref);
    return PrismSettingsRow(
      icon: icon,
      iconColor: iconColor,
      title: _categoryLabel(category, terms, frontingTerms),
      subtitle: _categoryDescription(category, terms, frontingTerms),
      destructive: destructive,
      enabled: enabled,
      onTap: enabled ? () => _showConfirmation(context, ref, category) : null,
    );
  }

  Future<void> _showConfirmation(
    BuildContext context,
    WidgetRef ref,
    ResetCategory category,
  ) async {
    final isAll = category == ResetCategory.all;
    final isSync = category == ResetCategory.sync;
    final isCustomFields = category == ResetCategory.customFields;
    final terms = readTerminology(context, ref);
    final frontingTerms = readFrontingTerms(ref);
    final label = _categoryLabel(category, terms, frontingTerms);
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: isSync
          ? 'Disconnect sync from this device?'
          : isCustomFields
          ? context.l10n.resetDataConfirmCustomFieldsTitle
          : context.l10n.resetDataConfirmTitle(label),
      message: isAll
          ? context.l10n.resetDataConfirmAll(terms.pluralLower)
          : isSync
          ? 'Prism will keep all local data on this device and stop syncing it. '
                'This also makes a best-effort attempt to remove this device '
                'from the relay, or delete the relay group only when the relay '
                'says this was the last device.'
          : isCustomFields
          ? context.l10n.resetDataConfirmCustomFieldsBody
          : context.l10n.resetDataConfirmCategory(label.toLowerCase()),
      confirmLabel: isAll
          ? context.l10n.resetDataConfirmEverything
          : isSync
          ? 'Disconnect Sync, Keep Data'
          : context.l10n.delete,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    try {
      final isAndroid = ref.read(resetIsAndroidProvider);
      await ref.read(resetDataNotifierProvider.notifier).reset(category);
      if (!context.mounted) return;
      if (isAll) {
        final restartRequired = await ref
            .read(fullResetServiceProvider)
            .isRestartRequired();
        if (!context.mounted) return;
        if (isAndroid && !restartRequired) {
          await Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
            MaterialPageRoute<void>(
              builder: (_) => const ResetRecoveryScreen(
                mode: ResetRecoveryScreenMode.androidClearing,
              ),
            ),
            (_) => false,
          );
          return;
        }
        if (!shouldShowResetRestartScreenAfterSuccess(
          category,
          isAndroid: isAndroid,
          restartRequired: restartRequired,
        )) {
          PrismToast.show(
            context,
            message: context.l10n.resetDataSuccess(label),
          );
          return;
        }
        await Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute<void>(
            builder: (_) => const ResetRecoveryScreen(
              mode: ResetRecoveryScreenMode.restartRequired,
            ),
          ),
          (_) => false,
        );
        return;
      }
      PrismToast.show(
        context,
        message: isSync
            ? 'Sync disconnected. This device is staying local.'
            : context.l10n.resetDataSuccess(label),
      );
    } catch (e) {
      if (!context.mounted) return;
      PrismToast.error(context, message: context.l10n.resetDataFailed(e));
    }
  }

  String _categoryLabel(
    ResetCategory category,
    Terminology terms,
    FrontingTermBundle frontingTerms,
  ) => switch (category) {
    ResetCategory.members => terms.plural,
    ResetCategory.fronting => frontingTerms.sessionPlural,
    _ => category.label,
  };

  String _categoryDescription(
    ResetCategory category,
    Terminology terms,
    FrontingTermBundle frontingTerms,
  ) => switch (category) {
    ResetCategory.members =>
      'Removes all ${terms.pluralLower}. '
          '${frontingTerms.sessionPlural} will show as unknown.',
    ResetCategory.fronting =>
      'Deletes all ${frontingTerms.historyLabel.toLowerCase()}.',
    _ => category.description,
  };
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
  _CategoryEntry(
    ResetCategory.customFields,
    AppIcons.tuneOutlined,
    Colors.pink,
  ),
];

@visibleForTesting
bool shouldShowResetRestartScreenAfterSuccess(
  ResetCategory category, {
  required bool isAndroid,
  bool restartRequired = false,
}) {
  return category == ResetCategory.all && (!isAndroid || restartRequired);
}
