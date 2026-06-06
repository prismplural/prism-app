import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/preferences/preference_registry.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/providers/accessibility_preferences_provider.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_select.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';

/// Font family, scale, and spacing controls for the accessibility settings.
class FontSettingsSection extends ConsumerWidget {
  const FontSettingsSection({super.key, required this.settings});

  final SystemSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final fontFamily = settings.fontFamily;
    final rawFontScale = settings.fontScale;
    final minimumFontScale = fontFamily.minimumScale;
    final maximumFontScale = fontFamily.maximumScale;
    final fontScale = rawFontScale
        .clamp(minimumFontScale, maximumFontScale)
        .toDouble();
    final letterSpacingAsync = ref.watch(typographyLetterSpacingProvider);
    final letterSpacing =
        letterSpacingAsync.whenOrNull(data: (value) => value) ??
        typographyLetterSpacingPreference.defaultValue;
    final letterSpacingEnabled =
        letterSpacingAsync.hasValue && !letterSpacingAsync.hasError;
    final letterSpacingIsDefault =
        (letterSpacing - typographyLetterSpacingPreference.defaultValue).abs() <
        0.05;
    final isDefault =
        fontFamily == FontFamily.system &&
        fontScale == 1.0 &&
        letterSpacingIsDefault;
    final l10n = context.l10n;
    String letterSpacingLabel(double value) {
      if ((value - typographyLetterSpacingPreference.defaultValue).abs() <
          0.05) {
        return l10n.accessibilityLetterSpacingNormal;
      }
      final formatted = value.toStringAsFixed(1);
      final signed = value > 0 ? '+$formatted' : formatted;
      return l10n.accessibilityLetterSpacingOffsetValue(signed);
    }

    return PrismSection(
      title: l10n.accessibilityTypographySection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PrismSelect<FontFamily>(
            labelText: l10n.accessibilityFontFamilyLabel,
            value: fontFamily,
            items: FontFamily.values
                .map((f) => PrismSelectItem(value: f, label: f.displayName))
                .toList(),
            onChanged: (newFamily) {
              if (newFamily == null) return;
              ref
                  .read(settingsNotifierProvider.notifier)
                  .updateFontFamily(newFamily);
              if (rawFontScale < newFamily.minimumScale) {
                ref
                    .read(settingsNotifierProvider.notifier)
                    .updateFontScale(newFamily.minimumScale);
              } else if (rawFontScale > newFamily.maximumScale) {
                ref
                    .read(settingsNotifierProvider.notifier)
                    .updateFontScale(newFamily.maximumScale);
              }
            },
          ),
          const SizedBox(height: 12),
          PrismSectionCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        l10n.accessibilityFontSizeLabel,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const Spacer(),
                      Text(
                        l10n.accessibilityFontSizeValue(
                          (fontScale * 100).round(),
                        ),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: fontScale,
                    min: minimumFontScale,
                    max: maximumFontScale,
                    divisions: ((maximumFontScale - minimumFontScale) * 10)
                        .round(),
                    label: l10n.accessibilityFontSizeValue(
                      (fontScale * 100).round(),
                    ),
                    onChanged: (value) {
                      final rounded = (value * 10).round() / 10;
                      ref
                          .read(settingsNotifierProvider.notifier)
                          .updateFontScale(rounded);
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        l10n.accessibilityLetterSpacingLabel,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const Spacer(),
                      Text(
                        letterSpacingLabel(letterSpacing),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: letterSpacing,
                    min: typographyLetterSpacingMin,
                    max: typographyLetterSpacingMax,
                    divisions: typographyLetterSpacingDivisions,
                    label: letterSpacingLabel(letterSpacing),
                    onChanged: letterSpacingEnabled
                        ? (value) {
                            final rounded = (value * 10).round() / 10;
                            ref
                                .read(typographyLetterSpacingProvider.notifier)
                                .set(rounded);
                          }
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(
                        PrismShapes.of(context).radius(12),
                      ),
                    ),
                    child: MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(fontScale)),
                      child: Text(
                        l10n.accessibilityTypographyPreviewText,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFamily: fontFamily.assetFontFamily,
                          letterSpacing: letterSpacing,
                        ),
                      ),
                    ),
                  ),
                  if (letterSpacingAsync.hasError) ...[
                    const SizedBox(height: 10),
                    Text(
                      context.l10n.accessibilityPreferencesLoadError,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  if (!isDefault) ...[
                    const SizedBox(height: 12),
                    Center(
                      child: PrismButton(
                        label: l10n.accessibilityResetTypographyButton,
                        tone: PrismButtonTone.subtle,
                        onPressed: () {
                          ref
                              .read(settingsNotifierProvider.notifier)
                              .updateFontFamily(FontFamily.system);
                          ref
                              .read(settingsNotifierProvider.notifier)
                              .updateFontScale(1.0);
                          ref
                              .read(typographyLetterSpacingProvider.notifier)
                              .set(
                                typographyLetterSpacingPreference.defaultValue,
                              );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  PrismSwitchRow(
                    title: l10n.accessibilityUseDisplayFontTitle,
                    subtitle: l10n.accessibilityUseDisplayFontSubtitle,
                    value: settings.displayFontInAppBar,
                    onChanged: (value) {
                      ref
                          .read(settingsNotifierProvider.notifier)
                          .updateDisplayFontInAppBar(value);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
