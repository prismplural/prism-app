import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';
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
    // Enforce 1.0x minimum when Open Dyslexic is active.
    final fontScale =
        fontFamily == FontFamily.openDyslexic && rawFontScale < 1.0
            ? 1.0
            : rawFontScale;
    final isDefault =
        fontFamily == FontFamily.system && fontScale == 1.0;

    return PrismSection(
      title: 'Font',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Font family selector
          PrismSegmentedControl<FontFamily>(
            segments: FontFamily.values
                .map(
                  (f) => PrismSegment(
                    value: f,
                    label: f.displayName,
                  ),
                )
                .toList(),
            selected: fontFamily,
            onChanged: (newFamily) {
              ref
                  .read(settingsNotifierProvider.notifier)
                  .updateFontFamily(newFamily);
              // Clamp scale to 1.0 when switching to Open Dyslexic
              if (newFamily == FontFamily.openDyslexic &&
                  rawFontScale < 1.0) {
                ref
                    .read(settingsNotifierProvider.notifier)
                    .updateFontScale(1.0);
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
              // Font scale slider
              Row(
                children: [
                  Text(
                    'Size',
                    style: theme.textTheme.bodyMedium,
                  ),
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
                min: fontFamily == FontFamily.openDyslexic ? 1.0 : 0.8,
                max: 1.5,
                divisions: fontFamily == FontFamily.openDyslexic ? 5 : 7,
                label: '${(fontScale * 100).round()}%',
                onChanged: (value) {
                  // Round to nearest 0.1
                  final rounded =
                      (value * 10).round() / 10;
                  ref
                      .read(settingsNotifierProvider.notifier)
                      .updateFontScale(rounded);
                },
              ),
              const SizedBox(height: 12),
              // Live preview
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(12)),
                ),
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(fontScale),
                  ),
                  child: Text(
                    'The quick brown fox jumps over the lazy dog.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: fontFamily == FontFamily.openDyslexic
                          ? 'OpenDyslexic'
                          : null,
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
