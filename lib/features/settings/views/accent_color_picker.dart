import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/accent_legibility.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

class _PresetColor {
  const _PresetColor(this.hex);
  final String hex;
}

const _presetColors = [
  _PresetColor('#B498C2'),
  _PresetColor('#2563EB'),
  _PresetColor('#16A34A'),
  _PresetColor('#DC2626'),
  _PresetColor('#EA580C'),
  _PresetColor('#DB2777'),
  _PresetColor('#0D9488'),
  _PresetColor('#D97706'),
  _PresetColor('#4F46E5'),
  _PresetColor('#6B7280'),
];

Color _parseHex(String hex) {
  final cleaned = hex.replaceFirst('#', '');
  final value = int.tryParse('FF$cleaned', radix: 16) ?? 0xFFAF8EE9;
  return Color(value);
}

String _toHex(Color color) {
  final value = color.toARGB32();
  return '#${(value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// A grid of preset color circles plus a custom color picker for choosing
/// an accent color. The caller provides [currentHex] and [onChanged] so the
/// widget can be reused for both app settings and onboarding.
class AccentColorPicker extends StatelessWidget {
  const AccentColorPicker({
    required this.currentHex,
    required this.onChanged,
    this.materialYouActive = false,
    super.key,
  });

  final String currentHex;
  final ValueChanged<String> onChanged;
  final bool materialYouActive;

  bool _isPreset(String hex) {
    return _presetColors.any((c) => c.hex.toUpperCase() == hex.toUpperCase());
  }

  String _tooltipForPreset(BuildContext context, String hex) {
    return switch (hex.toUpperCase()) {
      '#B498C2' => context.l10n.settingsAccentColorPrismPurple,
      '#2563EB' => context.l10n.settingsAccentColorBlue,
      '#16A34A' => context.l10n.settingsAccentColorGreen,
      '#DC2626' => context.l10n.settingsAccentColorRed,
      '#EA580C' => context.l10n.settingsAccentColorOrange,
      '#DB2777' => context.l10n.settingsAccentColorPink,
      '#0D9488' => context.l10n.settingsAccentColorTeal,
      '#D97706' => context.l10n.settingsAccentColorAmber,
      '#4F46E5' => context.l10n.settingsAccentColorIndigo,
      '#6B7280' => context.l10n.settingsAccentColorGray,
      _ => hex,
    };
  }

  void _openColorPicker(BuildContext context) {
    var pickerColor = _parseHex(currentHex);

    PrismDialog.show(
      context: context,
      title: context.l10n.settingsAccentColorPickerTitle,
      builder: (dialogContext) {
        return SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pickerColor,
            onColorChanged: (color) {
              pickerColor = color;
            },
            enableAlpha: false,
            hexInputBar: true,
            labelTypes: const [],
            pickerAreaHeightPercent: 0.7,
          ),
        );
      },
      actions: [
        PrismButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
          label: context.l10n.cancel,
        ),
        PrismButton(
          onPressed: () {
            Navigator.of(context, rootNavigator: true).pop();
            onChanged(_toHex(pickerColor));
          },
          label: context.l10n.settingsAccentColorSelect,
          tone: PrismButtonTone.filled,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMaterialYou = materialYouActive;
    final systemAccent = Theme.of(context).colorScheme.primary;
    final legibility = classifyAccentLegibility(_parseHex(currentHex));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (isMaterialYou)
              _ColorCircle(
                color: systemAccent,
                isSelected: true,
                onTap: () {},
                tooltip: context.l10n.settingsAccentColorSystemColor,
              ),
            for (final preset in _presetColors)
              _ColorCircle(
                color: isMaterialYou
                    ? _parseHex(preset.hex).withValues(alpha: 0.35)
                    : _parseHex(preset.hex),
                isSelected: !isMaterialYou &&
                    preset.hex.toUpperCase() == currentHex.toUpperCase(),
                onTap: isMaterialYou ? () {} : () => onChanged(preset.hex),
                tooltip: _tooltipForPreset(context, preset.hex),
              ),
            if (!isMaterialYou)
              _ColorCircle(
                color: !_isPreset(currentHex) ? _parseHex(currentHex) : null,
                isSelected: !_isPreset(currentHex),
                isCustom: true,
                onTap: () => _openColorPicker(context),
                tooltip: context.l10n.settingsAccentColorCustom,
              ),
          ],
        ),
        if (isMaterialYou)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              context.l10n.settingsAccentColorSystemPaletteNote,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                  ),
            ),
          )
        else if (legibility != AccentLegibility.ok)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _LegibilityWarning(kind: legibility),
          ),
      ],
    );
  }
}

class _LegibilityWarning extends StatelessWidget {
  const _LegibilityWarning({required this.kind});

  final AccentLegibility kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = switch (kind) {
      AccentLegibility.tooDark => context.l10n.accentLegibilityTooDark,
      AccentLegibility.tooLight => context.l10n.accentLegibilityTooLight,
      AccentLegibility.tooDesaturated =>
        context.l10n.accentLegibilityTooDesaturated,
      AccentLegibility.ok => '',
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          AppIcons.warningRounded,
          size: 16,
          color: theme.colorScheme.tertiary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
      ],
    );
  }
}

class _ColorCircle extends StatelessWidget {
  const _ColorCircle({
    required this.isSelected,
    required this.onTap,
    this.color,
    this.isCustom = false,
    this.tooltip,
  });

  final Color? color;
  final bool isSelected;
  final bool isCustom;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final circle = Semantics(
      button: true,
      label: 'Select color',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isCustom && color == null
                ? theme.colorScheme.surfaceContainerHighest
                : color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline.withValues(alpha: 0.3),
              width: isSelected ? 3 : 1,
            ),
          ),
          child: isCustom && !isSelected
              ? Icon(
                  AppIcons.colorize,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                )
              : isSelected
                  ? Icon(AppIcons.check, size: 20, color: AppColors.warmWhite)
                  : null,
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: circle);
    }
    return circle;
  }
}
