import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/views/accent_color_picker.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/features/settings/views/terminology_picker.dart';
import 'package:prism_plurality/features/settings/widgets/font_settings_section.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_pill.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

/// Screen for customising appearance: accent color, per-member colors,
/// terminology, and a live preview card.
class AppearanceSettingsScreen extends ConsumerWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(systemSettingsProvider);

    return PrismPageScaffold(
      topBar: PrismTopBar(title: context.l10n.appearanceTitle, showBackButton: true),
      bodyPadding: EdgeInsets.zero,
      body: settingsAsync.when(
        loading: () => const PrismLoadingState(),
        error: (e, _) => Center(child: Text(context.l10n.errorWithDetail(e))),
        data: (settings) => ListView(
          padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
          children: [
            PrismSection(
              title: context.l10n.appearanceBrightness,
              child: PrismSegmentedControl<ThemeBrightness>(
                segments: ThemeBrightness.values
                    .map(
                      (b) => PrismSegment(
                        value: b,
                        label: b.displayName,
                      ),
                    )
                    .toList(),
                selected: settings.themeBrightness,
                onChanged: (value) {
                  ref
                      .read(settingsNotifierProvider.notifier)
                      .updateThemeBrightness(value);
                },
              ),
            ),
            PrismSection(
              title: context.l10n.appearanceStyle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PrismSegmentedControl<ThemeStyle>(
                    segments: ThemeStyle.values
                        .where((s) {
                          if (s == ThemeStyle.materialYou) {
                            return defaultTargetPlatform ==
                                TargetPlatform.android;
                          }
                          return true;
                        })
                        .map(
                          (s) => PrismSegment(
                            value: s,
                            label: s.displayName,
                          ),
                        )
                        .toList(),
                    selected: settings.themeStyle,
                    onChanged: (value) {
                      ref
                          .read(settingsNotifierProvider.notifier)
                          .handleThemeStyleChange(value);
                    },
                  ),
                  if (settings.themeStyle == ThemeStyle.materialYou) ...[
                    const SizedBox(height: 12),
                    Text(
                      context.l10n.appearanceUsesSystemPalette,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                    ),
                  ],
                ],
              ),
            ),
            PrismSection(
              title: context.l10n.appearanceAccentColor,
              child: PrismSectionCard(
                child: AccentColorPicker(
                  currentHex: settings.accentColorHex,
                  materialYouActive:
                      settings.themeStyle == ThemeStyle.materialYou,
                ),
              ),
            ),
            FontSettingsSection(settings: settings),
            PrismSection(
              title: context.l10n.appearancePerMemberColors(watchTerminology(context, ref).singular),
              child: PrismSectionCard(
                child: PrismSwitchRow(
                  title:
                    'Per-${watchTerminology(context, ref).singularLower} accent colors',
                  subtitle:
                    'Allow each ${watchTerminology(context, ref).singularLower} to have their own color',
                  value: settings.perMemberAccentColors,
                  onChanged: (value) {
                    ref
                        .read(settingsNotifierProvider.notifier)
                        .updatePerMemberAccentColors(value);
                  },
                ),
              ),
            ),
            PrismSection(
              title: context.l10n.appearanceSyncSection,
              child: PrismSectionCard(
                child: PrismSwitchRow(
                  title: context.l10n.appearanceSyncThemeTitle,
                  subtitle: context.l10n.appearanceSyncThemeSubtitle,
                  value: settings.syncThemeEnabled,
                  onChanged: (value) {
                    ref
                        .read(settingsNotifierProvider.notifier)
                        .updateSyncThemeEnabled(value);
                  },
                ),
              ),
            ),
            PrismSection(
              title: context.l10n.appearanceTerminology,
              child: PrismSectionCard(
                child: TerminologyPicker(
                  current: settings.terminology,
                  customTerminology: settings.customTerminology,
                  customPluralTerminology: settings.customPluralTerminology,
                ),
              ),
            ),
            PrismSection(
              title: context.l10n.appearancePreview,
              child: _PreviewCard(settings: settings),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live preview showing a sample member card using current theme settings.
class _PreviewCard extends ConsumerWidget {
  const _PreviewCard({required this.settings});

  final SystemSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final terms = watchTerminology(context, ref);

    return PrismSectionCard(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            const MemberAvatar(emoji: '\u{1F338}', size: 48),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sample ${terms.singular}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.appearanceSamplePronouns,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            PrismPill(label: context.l10n.appearanceFronting),
          ],
        ),
      ),
    );
  }
}
