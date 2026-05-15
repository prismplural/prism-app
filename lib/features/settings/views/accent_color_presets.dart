import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

const prismDefaultAccentColorHex = '#9070A0';

class AccentColorPreset {
  const AccentColorPreset(this.hex, this.label);

  final String hex;
  final AccentColorPresetLabel label;
}

enum AccentColorPresetLabel {
  prismPurple,
  prismIris,
  heather,
  periwinkle,
  dustyRose,
  softCoral,
  sage,
  seafoam,
  azure,
  violet,
  orchid,
  raspberry,
  emerald,
  cyan,
  ember,
}

/// Current polished accent swatches.
///
/// These intentionally do not include the legacy preset hex values. Existing
/// users keep their saved colors, but those colors now render as custom choices
/// instead of being silently mapped onto a different preset.
const accentColorPresets = [
  AccentColorPreset(
    prismDefaultAccentColorHex,
    AccentColorPresetLabel.prismPurple,
  ),
  AccentColorPreset('#8474B7', AccentColorPresetLabel.prismIris),
  AccentColorPreset('#8B6FA8', AccentColorPresetLabel.heather),
  AccentColorPreset('#667DB6', AccentColorPresetLabel.periwinkle),
  AccentColorPreset('#AC6983', AccentColorPresetLabel.dustyRose),
  AccentColorPreset('#B86457', AccentColorPresetLabel.softCoral),
  AccentColorPreset('#6F8458', AccentColorPresetLabel.sage),
  AccentColorPreset('#4F8A83', AccentColorPresetLabel.seafoam),
  AccentColorPreset('#3476F2', AccentColorPresetLabel.azure),
  AccentColorPreset('#9160F2', AccentColorPresetLabel.violet),
  AccentColorPreset('#BB4CCB', AccentColorPresetLabel.orchid),
  AccentColorPreset('#C75286', AccentColorPresetLabel.raspberry),
  AccentColorPreset('#0B8F6A', AccentColorPresetLabel.emerald),
  AccentColorPreset('#0284A8', AccentColorPresetLabel.cyan),
  AccentColorPreset('#D05820', AccentColorPresetLabel.ember),
];

bool isAccentColorPresetHex(String hex) {
  final normalized = hex.toUpperCase();
  return accentColorPresets.any((preset) => preset.hex == normalized);
}

String accentColorPresetName(BuildContext context, String hex) {
  final normalized = hex.toUpperCase();
  for (final preset in accentColorPresets) {
    if (preset.hex == normalized) {
      return accentColorPresetLabel(context, preset.label);
    }
  }
  return normalized;
}

String accentColorPresetLabel(
  BuildContext context,
  AccentColorPresetLabel label,
) {
  return switch (label) {
    AccentColorPresetLabel.prismPurple =>
      context.l10n.settingsAccentColorPrismPurple,
    AccentColorPresetLabel.prismIris =>
      context.l10n.settingsAccentColorPrismIris,
    AccentColorPresetLabel.heather => context.l10n.settingsAccentColorHeather,
    AccentColorPresetLabel.periwinkle =>
      context.l10n.settingsAccentColorPeriwinkle,
    AccentColorPresetLabel.dustyRose =>
      context.l10n.settingsAccentColorDustyRose,
    AccentColorPresetLabel.softCoral =>
      context.l10n.settingsAccentColorSoftCoral,
    AccentColorPresetLabel.sage => context.l10n.settingsAccentColorSage,
    AccentColorPresetLabel.seafoam => context.l10n.settingsAccentColorSeafoam,
    AccentColorPresetLabel.azure => context.l10n.settingsAccentColorAzure,
    AccentColorPresetLabel.violet => context.l10n.settingsAccentColorViolet,
    AccentColorPresetLabel.orchid => context.l10n.settingsAccentColorOrchid,
    AccentColorPresetLabel.raspberry =>
      context.l10n.settingsAccentColorRaspberry,
    AccentColorPresetLabel.emerald => context.l10n.settingsAccentColorEmerald,
    AccentColorPresetLabel.cyan => context.l10n.settingsAccentColorCyan,
    AccentColorPresetLabel.ember => context.l10n.settingsAccentColorEmber,
  };
}
