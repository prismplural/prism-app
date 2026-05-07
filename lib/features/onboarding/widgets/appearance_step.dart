import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/features/settings/views/accent_color_picker.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart'
    hide CornerStyle;
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';

class AppearanceStep extends ConsumerWidget {
  const AppearanceStep({super.key});

  String _brightnessLabel(ThemeBrightness value) {
    return switch (value) {
      ThemeBrightness.system => 'System',
      ThemeBrightness.light => 'Light',
      ThemeBrightness.dark => 'Dark',
    };
  }

  String _styleLabel(ThemeStyle value) {
    return switch (value) {
      ThemeStyle.standard => 'Default',
      ThemeStyle.oled => 'OLED',
      ThemeStyle.materialYou => 'Material You',
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboarding = ref.watch(onboardingProvider);
    final notifier = ref.read(onboardingProvider.notifier);
    final settings = ref
        .watch(systemSettingsProvider)
        .whenOrNull(data: (settings) => settings);
    final platform = ref.watch(targetPlatformProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    final supportsMaterialYou = platform == TargetPlatform.android;
    final terms = resolveTerminology(
      context.l10n,
      onboarding.selectedTerminology,
      customSingular: onboarding.customTermSingular,
      customPlural: onboarding.customTermPlural,
      useEnglish: onboarding.terminologyUseEnglish,
    );
    final themeBrightness =
        onboarding.themeBrightness ??
        settings?.themeBrightness ??
        ThemeBrightness.system;
    final rawThemeStyle =
        onboarding.themeStyle ?? settings?.themeStyle ?? ThemeStyle.standard;
    final themeStyle = effectiveThemeStyleForPlatform(rawThemeStyle, platform);
    final cornerStyle =
        onboarding.cornerStyle ?? settings?.cornerStyle ?? CornerStyle.rounded;

    if (rawThemeStyle != themeStyle && onboarding.themeStyle != themeStyle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        notifier.setThemeStyle(themeStyle);
      });
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(
            label: context.l10n.onboardingAppearanceTheme,
            isDark: isDark,
          ),
          const SizedBox(height: 10),
          PrismSegmentedControl<ThemeBrightness>(
            segments: ThemeBrightness.values
                .map(
                  (value) => PrismSegment(
                    value: value,
                    label: _brightnessLabel(value),
                  ),
                )
                .toList(),
            selected: themeBrightness,
            onChanged: notifier.setThemeBrightness,
          ),
          const SizedBox(height: 12),
          PrismSegmentedControl<ThemeStyle>(
            segments:
                [
                      ThemeStyle.standard,
                      ThemeStyle.oled,
                      if (supportsMaterialYou) ThemeStyle.materialYou,
                    ]
                    .map(
                      (value) =>
                          PrismSegment(value: value, label: _styleLabel(value)),
                    )
                    .toList(),
            selected: themeStyle,
            onChanged: notifier.setThemeStyle,
          ),
          const SizedBox(height: 24),
          _SectionLabel(
            label: context.l10n.appearanceCornerStyleTitle,
            isDark: isDark,
          ),
          const SizedBox(height: 10),
          PrismSegmentedControl<CornerStyle>(
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
            selected: cornerStyle,
            onChanged: notifier.setCornerStyle,
          ),
          const SizedBox(height: 24),
          _SectionLabel(
            label: context.l10n.onboardingPreferencesAccentColor,
            isDark: isDark,
          ),
          const SizedBox(height: 10),
          AccentColorPicker(
            currentHex: onboarding.accentColorHex,
            onChanged: notifier.setAccentColor,
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.warmWhite.withValues(alpha: 0.1)
                  : AppColors.parchmentElevated,
              borderRadius: BorderRadius.circular(
                PrismShapes.of(context).radius(12),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.onboardingPreferencesPerMemberColors(
                          terms.singular,
                          terms.singularLower,
                        ),
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.warmWhite
                              : AppColors.warmBlack,
                        ),
                      ),
                      Text(
                        context.l10n
                            .onboardingPreferencesPerMemberColorsSubtitle(
                              terms.singularLower,
                            ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? AppColors.mutedTextDark
                              : AppColors.mutedTextLight,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: onboarding.usePerMemberColors,
                  onChanged: notifier.setUsePerMemberColors,
                  activeTrackColor: primary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.isDark});

  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        color: isDark
            ? AppColors.warmWhite.withValues(alpha: 0.8)
            : AppColors.warmBlack.withValues(alpha: 0.8),
      ),
    );
  }
}
