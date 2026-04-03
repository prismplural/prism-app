import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_settings_row.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// Settings subview for the Sleep feature.
class SleepFeatureSettingsScreen extends ConsumerStatefulWidget {
  const SleepFeatureSettingsScreen({super.key});

  @override
  ConsumerState<SleepFeatureSettingsScreen> createState() =>
      _SleepFeatureSettingsScreenState();
}

class _SleepFeatureSettingsScreenState
    extends ConsumerState<SleepFeatureSettingsScreen> {
  // TODO: persist defaultSleepQuality to system_settings (requires DB migration)
  SleepQuality _defaultQuality = SleepQuality.unknown;

  void _showDefaultQualityPicker(BuildContext context) {
    PrismDialog.show<void>(
      context: context,
      title: 'Default Quality',
      message: 'Choose the default quality rating for new sleep sessions.',
      builder: (ctx) {
        return RadioGroup<SleepQuality>(
          groupValue: _defaultQuality,
          onChanged: (value) {
            if (value == null) return;
            setState(() => _defaultQuality = value);
            Navigator.of(ctx).pop();
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: SleepQuality.values
                .map(
                  (q) => RadioListTile<SleepQuality>(
                    contentPadding: EdgeInsets.zero,
                    value: q,
                    title: Text(q.label),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final sleepEnabled = ref.watch(sleepTrackingEnabledProvider);
    final theme = Theme.of(context);

    return PrismPageScaffold(
      topBar: const PrismTopBar(title: 'Sleep', showBackButton: true),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Text(
              'Sleep sessions help you track rest patterns alongside '
              'fronting sessions. You can start a sleep session from the '
              'moon icon on the fronting screen.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          PrismSection(
            title: 'General',
            child: PrismSectionCard(
              padding: EdgeInsets.zero,
              child: PrismSwitchRow(
                icon: AppIcons.bedtimeOutlined,
                iconColor: Colors.indigo,
                title: 'Enable Sleep',
                subtitle: 'Log and monitor sleep sessions',
                value: sleepEnabled,
                onChanged: (value) => ref
                    .read(settingsNotifierProvider.notifier)
                    .updateFeatureToggle(sleepTrackingEnabled: value),
              ),
            ),
          ),
          if (sleepEnabled)
            PrismSection(
              title: 'Options',
              child: PrismSectionCard(
                padding: EdgeInsets.zero,
                child: PrismSettingsRow(
                  icon: AppIcons.starOutline,
                  iconColor: Colors.indigo,
                  title: 'Default Quality',
                  subtitle: _defaultQuality.label,
                  onTap: () => _showDefaultQualityPicker(context),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
