import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/system_settings.dart'
    hide CornerStyle;
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/views/accent_color_picker.dart';
import 'package:prism_plurality/features/settings/views/accent_color_presets.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/app_theme.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_pill.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

String appearanceThemeStyleLabel(BuildContext context, ThemeStyle style) {
  return switch (style) {
    ThemeStyle.standard => context.l10n.appearanceStylePrism,
    ThemeStyle.oled => context.l10n.appearanceStyleOled,
    ThemeStyle.materialYou => context.l10n.appearanceStylePalette,
  };
}

String paletteSettingsSummary(
  BuildContext context,
  SystemSettings settings, {
  PaletteSource? source,
}) {
  final resolvedSource = source ?? settings.paletteSource;
  final sourceLabel = switch (resolvedSource) {
    PaletteSource.device => context.l10n.paletteSourceDeviceColors,
    PaletteSource.custom => context.l10n.paletteSummaryCustom(
      paletteSeedColorName(context, settings.paletteSeedColorHex),
    ),
  };
  return context.l10n.paletteSummary(
    sourceLabel,
    paletteMoodLabel(context, settings.paletteMood),
    paletteContrastLabel(context, settings.paletteContrast),
  );
}

PalettePreview palettePreviewForSettings(
  BuildContext context,
  SystemSettings settings, {
  PaletteSource? source,
}) {
  if ((source ?? settings.paletteSource) == PaletteSource.device) {
    return PalettePreview.fromScheme(Theme.of(context).colorScheme);
  }
  return PalettePreview.from(
    seedColor: paletteSeedColorForSettings(context, settings, source: source),
    mood: settings.paletteMood,
    contrast: settings.paletteContrast,
    brightness: Theme.of(context).brightness,
  );
}

Color paletteSeedColorForSettings(
  BuildContext context,
  SystemSettings settings, {
  PaletteSource? source,
}) {
  final resolvedSource = source ?? settings.paletteSource;
  return switch (resolvedSource) {
    PaletteSource.device => Theme.of(context).colorScheme.primary,
    PaletteSource.custom => parsePaletteHex(settings.paletteSeedColorHex),
  };
}

String paletteMoodLabel(BuildContext context, PaletteMood mood) {
  return switch (mood) {
    PaletteMood.tonal => context.l10n.paletteMoodTonal,
    PaletteMood.vibrant => context.l10n.paletteMoodVibrant,
    PaletteMood.expressive => context.l10n.paletteMoodExpressive,
    PaletteMood.fidelity => context.l10n.paletteMoodFidelity,
    PaletteMood.monochrome => context.l10n.paletteMoodMonochrome,
  };
}

String paletteContrastLabel(BuildContext context, PaletteContrast contrast) {
  return switch (contrast) {
    PaletteContrast.soft => context.l10n.paletteContrastSoft,
    PaletteContrast.standard => context.l10n.paletteContrastStandard,
    PaletteContrast.high => context.l10n.paletteContrastHigh,
  };
}

String paletteSeedColorName(BuildContext context, String hex) {
  return accentColorPresetName(context, hex);
}

Color parsePaletteHex(String hex) {
  final cleaned = hex.replaceFirst('#', '');
  final fallback = prismDefaultAccentColorHex.replaceFirst('#', '');
  final value =
      int.tryParse('FF$cleaned', radix: 16) ??
      int.parse('FF$fallback', radix: 16);
  return Color(value);
}

class PaletteSettingsScreen extends ConsumerWidget {
  const PaletteSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(systemSettingsProvider);

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: context.l10n.paletteTitle,
        showBackButton: true,
      ),
      bodyPadding: EdgeInsets.zero,
      body: settingsAsync.when(
        loading: () => const PrismLoadingState(),
        error: (e, _) => Center(child: Text(context.l10n.errorWithDetail(e))),
        data: (settings) {
          final platform = ref.watch(targetPlatformProvider);
          final deviceSourceAvailable = paletteDeviceSourceAvailableForPlatform(
            platform,
          );
          final paletteSource = ref.watch(paletteSourceProvider);
          final viewSettings = settings.copyWith(
            paletteSource: paletteSource,
            paletteSeedColorHex: ref.watch(paletteSeedColorHexProvider),
            paletteMood: ref.watch(paletteMoodProvider),
            paletteContrast: ref.watch(paletteContrastProvider),
          );
          final notifier = ref.read(settingsNotifierProvider.notifier);
          final seedColor = paletteSeedColorForSettings(
            context,
            viewSettings,
            source: paletteSource,
          );
          final moodPreviews = {
            for (final mood in PaletteMood.values)
              mood: PalettePreview.from(
                seedColor: seedColor,
                mood: mood,
                contrast: viewSettings.paletteContrast,
                brightness: Theme.of(context).brightness,
              ),
          };
          final selectedPreview = palettePreviewForSettings(
            context,
            viewSettings,
            source: paletteSource,
          );

          return ListView(
            padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
            children: [
              if (deviceSourceAvailable)
                PrismSection(
                  title: context.l10n.paletteSourceTitle,
                  child: Column(
                    children: [
                      _SourceCard(
                        title: context.l10n.paletteSourceDeviceColors,
                        subtitle: context.l10n.paletteSourceDeviceSubtitle,
                        icon: AppIcons.devicesOutlined,
                        selected: paletteSource == PaletteSource.device,
                        enabled: true,
                        onTap: () =>
                            notifier.updatePaletteSource(PaletteSource.device),
                      ),
                      const SizedBox(height: 10),
                      _SourceCard(
                        title: context.l10n.paletteSourceCustomColor,
                        subtitle: context.l10n.paletteSourceCustomSubtitle,
                        icon: AppIcons.colorize,
                        selected: paletteSource == PaletteSource.custom,
                        enabled: true,
                        onTap: () =>
                            notifier.updatePaletteSource(PaletteSource.custom),
                      ),
                    ],
                  ),
                ),
              if (paletteSource == PaletteSource.custom)
                PrismSection(
                  title: context.l10n.paletteColorTitle,
                  child: PrismSectionCard(
                    child: AccentColorPicker(
                      currentHex: viewSettings.paletteSeedColorHex,
                      onChanged: notifier.updatePaletteSeedColorHex,
                    ),
                  ),
                ),
              PrismSection(
                title: context.l10n.paletteMoodTitle,
                child: Column(
                  children: [
                    for (final mood in PaletteMood.values) ...[
                      _MoodCard(
                        mood: mood,
                        preview: moodPreviews[mood]!,
                        selected: viewSettings.paletteMood == mood,
                        onTap: () => notifier.updatePaletteMood(mood),
                      ),
                      if (mood != PaletteMood.values.last)
                        const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
              PrismSection(
                title: context.l10n.paletteContrastTitle,
                child: PrismSegmentedControl<PaletteContrast>(
                  segments: PaletteContrast.values
                      .map(
                        (contrast) => PrismSegment(
                          value: contrast,
                          label: paletteContrastLabel(context, contrast),
                        ),
                      )
                      .toList(),
                  selected: viewSettings.paletteContrast,
                  onChanged: notifier.updatePaletteContrast,
                ),
              ),
              PrismSection(
                title: context.l10n.palettePreviewTitle,
                child: PrismSectionCard(
                  padding: const EdgeInsets.all(14),
                  accentColor: selectedPreview.primary,
                  child: _PaletteLivePreview(preview: selectedPreview),
                ),
              ),
              PrismSection(
                title: context.l10n.paletteResetTitle,
                child: PrismSectionCard(
                  padding: EdgeInsets.zero,
                  child: PrismListRow(
                    title: Text(context.l10n.paletteResetAction),
                    subtitle: Text(context.l10n.paletteResetDescription),
                    leading: Icon(
                      AppIcons.restartAlt,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    onTap: () => _resetPaletteSettings(notifier),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class PalettePreview {
  const PalettePreview({
    required this.scheme,
    required this.primary,
    required this.dots,
  });

  factory PalettePreview.from({
    required Color seedColor,
    required PaletteMood mood,
    required PaletteContrast contrast,
    required Brightness brightness,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
      dynamicSchemeVariant: AppTheme.dynamicSchemeVariantForPalette(
        mood,
        seedColor: seedColor,
      ),
      contrastLevel: _contrastLevel(contrast),
    );

    return PalettePreview(
      scheme: scheme,
      primary: scheme.primary,
      dots: [
        scheme.primary,
        scheme.secondary,
        scheme.tertiary,
        scheme.primaryContainer,
      ],
    );
  }

  factory PalettePreview.fromScheme(ColorScheme scheme) {
    return PalettePreview(
      scheme: scheme,
      primary: scheme.primary,
      dots: [
        scheme.primary,
        scheme.secondary,
        scheme.tertiary,
        scheme.primaryContainer,
      ],
    );
  }

  final ColorScheme scheme;
  final Color primary;
  final List<Color> dots;
}

double _contrastLevel(PaletteContrast contrast) {
  return switch (contrast) {
    PaletteContrast.soft => -0.25,
    PaletteContrast.standard => 0.0,
    PaletteContrast.high => 0.5,
  };
}

Future<void> _resetPaletteSettings(SettingsNotifier notifier) async {
  await notifier.updatePaletteSource(PaletteSource.custom);
  await notifier.updatePaletteSeedColorHex(prismDefaultAccentColorHex);
  await notifier.updatePaletteMood(PaletteMood.tonal);
  await notifier.updatePaletteContrast(PaletteContrast.standard);
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;

    return PrismSectionCard(
      onTap: enabled ? onTap : null,
      accentColor: tint,
      tone: selected ? PrismSurfaceTone.accent : PrismSurfaceTone.subtle,
      child: Row(
        children: [
          Icon(
            icon,
            size: 24,
            color: enabled
                ? tint
                : theme.colorScheme.onSurface.withValues(alpha: 0.35),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: enabled
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurface.withValues(alpha: 0.45),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: enabled
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.55,
                          ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (selected)
            Icon(AppIcons.check, color: theme.colorScheme.primary, size: 20),
        ],
      ),
    );
  }
}

class _MoodCard extends StatelessWidget {
  const _MoodCard({
    required this.mood,
    required this.preview,
    required this.selected,
    required this.onTap,
  });

  final PaletteMood mood;
  final PalettePreview preview;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PrismSectionCard(
      onTap: onTap,
      accentColor: preview.primary,
      tone: selected ? PrismSurfaceTone.accent : PrismSurfaceTone.subtle,
      child: Row(
        children: [
          PaletteDots(colors: preview.dots),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  paletteMoodLabel(context, mood),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _moodDescription(context, mood),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (selected)
            Icon(AppIcons.check, color: theme.colorScheme.primary, size: 20),
        ],
      ),
    );
  }
}

String _moodDescription(BuildContext context, PaletteMood mood) {
  return switch (mood) {
    PaletteMood.tonal => context.l10n.paletteMoodTonalDescription,
    PaletteMood.vibrant => context.l10n.paletteMoodVibrantDescription,
    PaletteMood.expressive => context.l10n.paletteMoodExpressiveDescription,
    PaletteMood.fidelity => context.l10n.paletteMoodFidelityDescription,
    PaletteMood.monochrome => context.l10n.paletteMoodMonochromeDescription,
  };
}

class PaletteDots extends StatelessWidget {
  const PaletteDots({super.key, required this.colors, this.size = 18});

  final List<Color> colors;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * 2.8,
      height: size * 1.8,
      child: Stack(
        children: [
          for (var i = 0; i < colors.length; i++)
            Positioned(
              left: i * size * 0.62,
              top: i.isEven ? 0 : size * 0.55,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: colors[i],
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.72),
                    width: 1.2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PaletteLivePreview extends StatelessWidget {
  const _PaletteLivePreview({required this.preview});

  final PalettePreview preview;

  @override
  Widget build(BuildContext context) {
    final scheme = preview.scheme;
    final shapes = PrismShapes.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PreviewMemberRow(
          emoji: '\u{1F338}',
          title: context.l10n.palettePreviewMemberOne,
          subtitle: context.l10n.palettePreviewMemberOneDetail,
          color: scheme.primary,
          badge: context.l10n.palettePreviewChip,
        ),
        const SizedBox(height: 10),
        _PreviewMemberRow(
          emoji: '\u{2600}',
          title: context.l10n.palettePreviewMemberTwo,
          subtitle: context.l10n.palettePreviewMemberTwoDetail,
          color: scheme.tertiary,
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Theme(
              data: Theme.of(context).copyWith(colorScheme: scheme),
              child: PrismButton(
                label: context.l10n.palettePreviewButton,
                icon: AppIcons.check,
                tone: PrismButtonTone.filled,
                density: PrismControlDensity.compact,
                onPressed: () {},
              ),
            ),
            PrismPill(
              label: context.l10n.palettePreviewChip,
              tone: PrismPillTone.accent,
              color: scheme.tertiary,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(shapes.radius(14)),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Text(
            context.l10n.palettePreviewInput,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.secondaryContainer.withValues(alpha: 0.52),
            borderRadius: BorderRadius.circular(shapes.radius(999)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                AppIcons.navHome,
                size: 16,
                color: scheme.onSecondaryContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.l10n.palettePreviewNavHint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PreviewMemberRow extends StatelessWidget {
  const _PreviewMemberRow({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.color,
    this.badge,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final Color color;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shapes = PrismShapes.of(context);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.18 : 0.12,
        ),
        borderRadius: BorderRadius.circular(shapes.radius(14)),
        border: Border.all(
          color: color.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.26 : 0.20,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Text(emoji, style: const TextStyle(fontSize: 21)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (badge != null) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(shapes.radius(999)),
              ),
              child: Text(
                badge!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
