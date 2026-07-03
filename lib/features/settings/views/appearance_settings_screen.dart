import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/models.dart' hide CornerStyle;
import 'package:prism_plurality/domain/models/system_settings.dart'
    hide CornerStyle;
import 'package:prism_plurality/domain/preferences/member_name_presentation.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/views/accent_color_picker.dart';
import 'package:prism_plurality/features/settings/views/palette_settings_screen.dart';
import 'package:prism_plurality/shared/widgets/adaptive_detail_surface.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_pill.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

/// Screen for customising appearance: accent color, per-member colors, and a
/// live preview card.
class AppearanceSettingsScreen extends ConsumerWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(systemSettingsProvider);

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: context.l10n.appearanceTitle,
        showBackButton: true,
      ),
      bodyPadding: EdgeInsets.zero,
      body: settingsAsync.when(
        loading: () => const PrismLoadingState(),
        error: (e, _) => Center(child: Text(context.l10n.errorWithDetail(e))),
        data: (settings) {
          final selectedBrightness = ref.watch(themeBrightnessProvider);
          final selectedThemeStyle = ref.watch(themeStyleProvider);
          final namePresentation = ref.watch(memberNamePresentationProvider);
          final effectiveSettings = settings.copyWith(
            themeBrightness: selectedBrightness,
            themeStyle: selectedThemeStyle,
            paletteSource: ref.watch(paletteSourceProvider),
            paletteSeedColorHex: ref.watch(paletteSeedColorHexProvider),
            paletteMood: ref.watch(paletteMoodProvider),
            paletteContrast: ref.watch(paletteContrastProvider),
          );

          return ListView(
            padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
            children: [
              PrismSection(
                title: context.l10n.appearanceBrightness,
                child: PrismSegmentedControl<ThemeBrightness>(
                  segments: ThemeBrightness.values
                      .map((b) => PrismSegment(value: b, label: b.displayName))
                      .toList(),
                  selected: selectedBrightness,
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
                          .map(
                            (s) => PrismSegment(
                              value: s,
                              label: appearanceThemeStyleLabel(context, s),
                            ),
                          )
                          .toList(),
                      selected: selectedThemeStyle,
                      onChanged: (value) {
                        ref
                            .read(settingsNotifierProvider.notifier)
                            .handleThemeStyleChange(value);
                      },
                    ),
                    if (selectedThemeStyle == ThemeStyle.materialYou) ...[
                      const SizedBox(height: 12),
                      _PaletteSummaryCard(settings: effectiveSettings),
                    ],
                  ],
                ),
              ),
              PrismSection(
                title: context.l10n.appearanceCornerStyleTitle,
                description: context.l10n.appearanceCornerStyleDescription,
                child: PrismSegmentedControl<CornerStyle>(
                  segments: [
                    PrismSegment(
                      value: CornerStyle.rounded,
                      label: context.l10n.appearanceCornerStyleRounded,
                    ),
                    PrismSegment(
                      value: CornerStyle.angular,
                      label: context.l10n.appearanceCornerStyleAngular,
                    ),
                  ],
                  selected: ref.watch(cornerStyleProvider),
                  onChanged: (value) {
                    ref
                        .read(settingsNotifierProvider.notifier)
                        .updateCornerStyle(value);
                  },
                ),
              ),
              PrismSection(
                title: context.l10n.appearanceMemberNamesTitle,
                description: context.l10n.appearanceMemberNamesDescription,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PrismSegmentedControl<MemberNamePrimary>(
                      segments: [
                        PrismSegment(
                          value: MemberNamePrimary.fullName,
                          label: context.l10n.appearanceMemberNamesDisplay,
                        ),
                        PrismSegment(
                          value: MemberNamePrimary.canonicalName,
                          label: context.l10n.appearanceMemberNamesLegacy,
                        ),
                      ],
                      selected: namePresentation.primary,
                      onChanged: (value) {
                        ref
                            .read(settingsNotifierProvider.notifier)
                            .updateMemberNamePresentationPrimary(value);
                      },
                    ),
                    const SizedBox(height: 12),
                    PrismSectionCard(
                      child: PrismSwitchRow(
                        title: context
                            .l10n
                            .appearanceMemberNamesShowAlternateTitle,
                        subtitle: context
                            .l10n
                            .appearanceMemberNamesShowAlternateDescription,
                        value: namePresentation.showAlternateName,
                        onChanged: (value) {
                          ref
                              .read(settingsNotifierProvider.notifier)
                              .updateMemberNamePresentationShowAlternate(value);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              if (selectedThemeStyle != ThemeStyle.materialYou)
                PrismSection(
                  title: context.l10n.appearanceAccentColor,
                  child: PrismSectionCard(
                    child: AccentColorPicker(
                      currentHex: settings.accentColorHex,
                      onChanged: (hex) => ref
                          .read(settingsNotifierProvider.notifier)
                          .updateAccentColor(hex),
                    ),
                  ),
                ),
              PrismSection(
                title: context.l10n.appearancePerMemberColors(
                  watchTerminology(context, ref).singular,
                ),
                child: PrismSectionCard(
                  child: PrismSwitchRow(
                    title: context.l10n.appearancePerMemberColorsSwitchTitle,
                    subtitle: context.l10n
                        .appearancePerMemberColorsSwitchSubtitle(
                          watchTerminology(context, ref).singularLower,
                        ),
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
                title: context.l10n.appearanceBioMarkdownSection,
                child: PrismSectionCard(
                  child: PrismSwitchRow(
                    title: context.l10n.appearanceBioMarkdownTitle,
                    subtitle: context.l10n.appearanceBioMarkdownSubtitle,
                    value: settings.bioMarkdownEnabled,
                    onChanged: (value) {
                      ref
                          .read(settingsNotifierProvider.notifier)
                          .updateBioMarkdownEnabled(value);
                    },
                  ),
                ),
              ),
              PrismSection(
                title: context.l10n.appearanceLanguage,
                child: PrismSectionCard(
                  child: _LanguagePicker(
                    current: settings.localeOverride,
                    onChanged: (code) => ref
                        .read(settingsNotifierProvider.notifier)
                        .updateLocaleOverride(code),
                  ),
                ),
              ),
              PrismSection(
                title: context.l10n.appearancePreview,
                child: _PreviewCard(settings: settings),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PaletteSummaryCard extends ConsumerWidget {
  const _PaletteSummaryCard({required this.settings});

  final SystemSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final paletteSource = ref.watch(paletteSourceProvider);
    final preview = palettePreviewForSettings(
      context,
      settings,
      source: paletteSource,
    );

    return PrismSectionCard(
      onTap: () {
        showAdaptiveDetailSurface<void>(
          context: context,
          builder: (_) => const PaletteSettingsScreen(),
          route: (context) => context.push(AppRoutePaths.settingsPalette),
        );
      },
      accentColor: preview.primary,
      child: Row(
        children: [
          PaletteDots(colors: preview.dots, size: 16),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.paletteTitle,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  paletteSettingsSummary(
                    context,
                    settings,
                    source: paletteSource,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(
            AppIcons.chevronRightRounded,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
          ),
        ],
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
                    context.l10n.appearanceSampleMember(terms.singular),
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

class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker({required this.current, required this.onChanged});

  final String? current;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LanguageRow(
          title: context.l10n.appearanceLanguageSystem,
          isSelected: current == null || current!.isEmpty,
          onTap: () => onChanged(null),
          theme: theme,
        ),
        _LanguageRow(
          title: 'English',
          isSelected: current == 'en',
          onTap: () => onChanged('en'),
          theme: theme,
        ),
        _LanguageRow(
          title: 'Español',
          isSelected: current == 'es',
          onTap: () => onChanged('es'),
          theme: theme,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            context.l10n.appearanceLanguageFooter,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.title,
    required this.isSelected,
    required this.onTap,
    required this.theme,
  });

  final String title;
  final bool isSelected;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(child: Text(title, style: theme.textTheme.bodyLarge)),
            if (isSelected)
              Icon(AppIcons.check, color: theme.colorScheme.primary, size: 20),
          ],
        ),
      ),
    );
  }
}
