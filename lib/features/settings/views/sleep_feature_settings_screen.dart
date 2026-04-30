import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';

import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/utils/sleep_quality_l10n.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_time_picker.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_settings_row.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

/// Settings subview for the Sleep feature.
class SleepFeatureSettingsScreen extends ConsumerStatefulWidget {
  const SleepFeatureSettingsScreen({super.key});

  @override
  ConsumerState<SleepFeatureSettingsScreen> createState() =>
      _SleepFeatureSettingsScreenState();
}

class _SleepFeatureSettingsScreenState
    extends ConsumerState<SleepFeatureSettingsScreen> {
  void _showDefaultQualityPicker(
      BuildContext context, SleepQuality currentQuality) {
    PrismDialog.show<void>(
      context: context,
      title: context.l10n.featureSleepDefaultQualityTitle,
      message: context.l10n.featureSleepDefaultQualityMessage,
      builder: (ctx) {
        return RadioGroup<SleepQuality>(
          groupValue: currentQuality,
          onChanged: (value) {
            if (value == null) return;
            ref
                .read(settingsNotifierProvider.notifier)
                .updateDefaultSleepQuality(value);
            Navigator.of(ctx).pop();
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: SleepQuality.values
                .map(
                  (q) => RadioListTile<SleepQuality>(
                    contentPadding: EdgeInsets.zero,
                    value: q,
                    title: Text(q.localizedLabel(context.l10n)),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }

  Widget _buildBedtimeTimePicker(
      BuildContext context, WidgetRef ref, ThemeData theme) {
    final time = ref.watch(sleepSuggestionTimeProvider);
    final formatted =
        TimeOfDay(hour: time.hour, minute: time.minute).format(context);

    return Builder(
      builder: (anchorContext) => PrismSettingsRow(
        icon: AppIcons.schedule,
        iconColor: AppColors.sleep(theme.brightness),
        title: context.l10n.featureSleepBedtimeTime,
        subtitle: formatted,
        onTap: () async {
          final picked = await showPrismTimePicker(
            context: context,
            anchorContext: anchorContext,
            initialTime: TimeOfDay(hour: time.hour, minute: time.minute),
          );
          if (picked != null) {
            await ref
                .read(settingsNotifierProvider.notifier)
                .updateSleepSuggestionTime(picked.hour, picked.minute);
          }
        },
      ),
    );
  }

  Widget _buildWakeDurationPicker(
      BuildContext context, WidgetRef ref, ThemeData theme) {
    final hours = ref.watch(wakeSuggestionAfterHoursProvider);

    return PrismSettingsRow(
      icon: AppIcons.alarm,
      iconColor: AppColors.sleep(theme.brightness),
      title: context.l10n.featureSleepWakeAfter,
      subtitle:
          context.l10n.featureSleepWakeAfterHours(hours.toStringAsFixed(0)),
      onTap: () => _showWakeDurationPicker(context, ref, hours),
    );
  }

  void _showWakeDurationPicker(
      BuildContext context, WidgetRef ref, double currentHours) {
    const options = [6.0, 7.0, 8.0, 9.0, 10.0];

    PrismDialog.show<void>(
      context: context,
      title: context.l10n.featureSleepWakeAfter,
      builder: (ctx) => RadioGroup<double>(
        groupValue: currentHours,
        onChanged: (v) {
          if (v == null) return;
          ref
              .read(settingsNotifierProvider.notifier)
              .updateWakeSuggestionAfterHours(v);
          Navigator.of(ctx).pop();
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: options
              .map(
                (h) => RadioListTile<double>(
                  contentPadding: EdgeInsets.zero,
                  value: h,
                  title: Text(
                    context.l10n
                        .featureSleepWakeAfterHours(h.toStringAsFixed(0)),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sleepEnabled = ref.watch(sleepTrackingEnabledProvider);
    final defaultQuality =
        ref.watch(defaultSleepQualityProvider) ?? SleepQuality.unknown;
    final theme = Theme.of(context);

    return PrismPageScaffold(
      topBar: PrismTopBar(title: context.l10n.featureSleepTitle, showBackButton: true),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Text(
              context.l10n.featureSleepDescription,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (sleepEnabled)
            PrismSection(
              title: context.l10n.featureSleepGeneral,
              child: PrismSectionCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    PrismSettingsRow(
                      icon: AppIcons.bedtimeRounded,
                      iconColor: AppColors.sleep(theme.brightness),
                      title: context.l10n.sleepViewAllHistory,
                      onTap: () => context.push(AppRoutePaths.sleep),
                    ),
                    const Divider(height: 1, indent: 56),
                    PrismSwitchRow(
                      icon: AppIcons.bedtimeOutlined,
                      iconColor: AppColors.sleep(theme.brightness),
                      title: context.l10n.featureSleepEnable,
                      subtitle: context.l10n.featureSleepEnableSubtitle,
                      value: sleepEnabled,
                      onChanged: (value) => ref
                          .read(settingsNotifierProvider.notifier)
                          .updateFeatureToggle(sleepTrackingEnabled: value),
                    ),
                  ],
                ),
              ),
            )
          else
            PrismSection(
              title: context.l10n.featureSleepGeneral,
              child: PrismSectionCard(
                padding: EdgeInsets.zero,
                child: PrismSwitchRow(
                  icon: AppIcons.bedtimeOutlined,
                  iconColor: AppColors.sleep(theme.brightness),
                  title: context.l10n.featureSleepEnable,
                  subtitle: context.l10n.featureSleepEnableSubtitle,
                  value: sleepEnabled,
                  onChanged: (value) => ref
                      .read(settingsNotifierProvider.notifier)
                      .updateFeatureToggle(sleepTrackingEnabled: value),
                ),
              ),
            ),
          if (sleepEnabled)
            PrismSection(
              title: context.l10n.featureSleepOptions,
              child: PrismSectionCard(
                padding: EdgeInsets.zero,
                child: PrismSettingsRow(
                  icon: AppIcons.starOutline,
                  iconColor: AppColors.sleep(theme.brightness),
                  title: context.l10n.featureSleepDefaultQuality,
                  subtitle: defaultQuality.localizedLabel(context.l10n),
                  onTap: () =>
                      _showDefaultQualityPicker(context, defaultQuality),
                ),
              ),
            ),
          if (sleepEnabled)
            PrismSection(
              title: context.l10n.featureSleepSuggestions,
              child: PrismSectionCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    PrismSwitchRow(
                      icon: AppIcons.bedtimeOutlined,
                      iconColor: AppColors.sleep(theme.brightness),
                      title: context.l10n.featureSleepBedtimeReminder,
                      subtitle:
                          context.l10n.featureSleepBedtimeReminderSubtitle,
                      value: ref.watch(sleepSuggestionEnabledProvider),
                      onChanged: (v) => ref
                          .read(settingsNotifierProvider.notifier)
                          .updateSleepSuggestionEnabled(v),
                    ),
                    if (ref.watch(sleepSuggestionEnabledProvider))
                      _buildBedtimeTimePicker(context, ref, theme),
                    Divider(
                      height: 1,
                      indent: 56,
                      endIndent: 12,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.08),
                    ),
                    PrismSwitchRow(
                      icon: AppIcons.wbSunnyRounded,
                      iconColor: AppColors.sleep(theme.brightness),
                      title: context.l10n.featureSleepWakeReminder,
                      subtitle:
                          context.l10n.featureSleepWakeReminderSubtitle,
                      value: ref.watch(wakeSuggestionEnabledProvider),
                      onChanged: (v) => ref
                          .read(settingsNotifierProvider.notifier)
                          .updateWakeSuggestionEnabled(v),
                    ),
                    if (ref.watch(wakeSuggestionEnabledProvider))
                      _buildWakeDurationPicker(context, ref, theme),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
