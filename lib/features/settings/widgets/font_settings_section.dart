import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_select.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';

/// Font family and scale controls for the appearance settings screen.
class FontSettingsSection extends ConsumerWidget {
  const FontSettingsSection({super.key, required this.settings});

  final SystemSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final fontFamily = settings.fontFamily;
    final rawFontScale = settings.fontScale;
    final minimumFontScale = fontFamily.minimumScale;
    final fontScale = rawFontScale < minimumFontScale
        ? minimumFontScale
        : rawFontScale;
    final isDefault = fontFamily == FontFamily.system && fontScale == 1.0;

    return PrismSection(
      title: 'Font',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PrismSelect<FontFamily>(
            labelText: 'Family',
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
                      Text('Size', style: theme.textTheme.bodyMedium),
                      const Spacer(),
                      Text(
                        '${(fontScale * 100).round()}%',
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
                    max: 1.5,
                    divisions: ((1.5 - minimumFontScale) * 10).round(),
                    label: '${(fontScale * 100).round()}%',
                    onChanged: (value) {
                      final rounded = (value * 10).round() / 10;
                      ref
                          .read(settingsNotifierProvider.notifier)
                          .updateFontScale(rounded);
                    },
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
                        'The quick brown fox jumps over the lazy dog.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFamily: fontFamily.assetFontFamily,
                        ),
                      ),
                    ),
                  ),
                  if (!isDefault) ...[
                    const SizedBox(height: 12),
                    Center(
                      child: PrismButton(
                        label: 'Reset to default',
                        tone: PrismButtonTone.subtle,
                        onPressed: () {
                          ref
                              .read(settingsNotifierProvider.notifier)
                              .updateFontFamily(FontFamily.system);
                          ref
                              .read(settingsNotifierProvider.notifier)
                              .updateFontScale(1.0);
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  PrismSwitchRow(
                    title: 'Use display font',
                    subtitle: 'Use Unbounded for titles and headings',
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
