import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/widgets/font_settings_section.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/providers/accessibility_preferences_provider.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

class AccessibilitySettingsScreen extends ConsumerWidget {
  const AccessibilitySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dimBackgroundBehindSheetsAsync = ref.watch(
      dimBackgroundBehindSheetsProvider,
    );
    final forceCenteredSheetsAsync = ref.watch(forceCenteredSheetsProvider);
    final settingsAsync = ref.watch(systemSettingsProvider);

    final dimBackgroundBehindSheets = dimBackgroundBehindSheetsAsync.hasValue
        ? dimBackgroundBehindSheetsAsync.value ?? false
        : false;
    final forceCenteredSheets = forceCenteredSheetsAsync.hasValue
        ? forceCenteredSheetsAsync.value ?? false
        : false;
    final dimBackgroundBehindSheetsEnabled =
        dimBackgroundBehindSheetsAsync.hasValue &&
        !dimBackgroundBehindSheetsAsync.hasError;
    final forceCenteredSheetsEnabled =
        forceCenteredSheetsAsync.hasValue && !forceCenteredSheetsAsync.hasError;

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: context.l10n.accessibilityTitle,
        showBackButton: true,
      ),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.only(top: 8, bottom: NavBarInset.of(context)),
        children: [
          settingsAsync.when(
            loading: () => PrismSection(
              title: context.l10n.accessibilityTypographySection,
              child: const PrismSectionCard(
                child: SizedBox(height: 64, child: PrismLoadingState(size: 28)),
              ),
            ),
            error: (e, _) => PrismSection(
              title: context.l10n.accessibilityTypographySection,
              child: PrismSectionCard(
                child: Text(context.l10n.errorWithDetail(e)),
              ),
            ),
            data: (settings) => FontSettingsSection(settings: settings),
          ),
          PrismSection(
            title: context.l10n.accessibilityVisualSection,
            child: PrismSectionCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  PrismSwitchRow(
                    title: context.l10n.accessibilityDimSheetsTitle,
                    subtitle: context.l10n.accessibilityDimSheetsSubtitle,
                    icon: Icons.contrast_rounded,
                    value: dimBackgroundBehindSheets,
                    enabled: dimBackgroundBehindSheetsEnabled,
                    onChanged: (value) => ref
                        .read(dimBackgroundBehindSheetsProvider.notifier)
                        .set(value),
                  ),
                  if (dimBackgroundBehindSheetsAsync.hasError)
                    const _PreferenceLoadError(),
                ],
              ),
            ),
          ),
          PrismSection(
            title: context.l10n.accessibilitySheetsSection,
            child: PrismSectionCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  PrismSwitchRow(
                    title: context.l10n.accessibilityForceCenteredSheetsTitle,
                    subtitle:
                        context.l10n.accessibilityForceCenteredSheetsSubtitle,
                    icon: Icons.center_focus_strong_rounded,
                    value: forceCenteredSheets,
                    enabled: forceCenteredSheetsEnabled,
                    onChanged: (value) => ref
                        .read(forceCenteredSheetsProvider.notifier)
                        .set(value),
                  ),
                  if (forceCenteredSheetsAsync.hasError)
                    const _PreferenceLoadError(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreferenceLoadError extends StatelessWidget {
  const _PreferenceLoadError();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          context.l10n.accessibilityPreferencesLoadError,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ),
    );
  }
}
