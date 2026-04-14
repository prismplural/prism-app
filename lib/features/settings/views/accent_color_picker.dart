import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// Preset colors available for accent color selection.
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

/// Parses a hex color string (with or without '#') into a [Color].
Color _parseHex(String hex) {
  final cleaned = hex.replaceFirst('#', '');
  final value = int.tryParse('FF$cleaned', radix: 16) ?? 0xFFAF8EE9;
  return Color(value);
}

/// Converts a [Color] to a hex string with leading '#'.
String _toHex(Color color) {
  final value = color.toARGB32();
  return '#${(value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// A grid of preset color circles plus a custom color picker for choosing
/// the app's accent color.
///
/// When [materialYouActive] is true, the presets are shown faded out with the
/// system-derived accent displayed as a leading circle at full brightness.
class AccentColorPicker extends ConsumerStatefulWidget {
  const AccentColorPicker({
    required this.currentHex,
    this.materialYouActive = false,
    super.key,
  });

  final String currentHex;
  final bool materialYouActive;

  @override
  ConsumerState<AccentColorPicker> createState() => _AccentColorPickerState();
}

class _AccentColorPickerState extends ConsumerState<AccentColorPicker> {
  late String _selectedHex;

  @override
  void initState() {
    super.initState();
    _selectedHex = widget.currentHex;
  }

  void _selectColor(String hex) {
    setState(() {
      _selectedHex = hex;
    });
    ref.read(settingsNotifierProvider.notifier).updateAccentColor(hex);
  }

  void _openColorPicker() {
    var pickerColor = _parseHex(_selectedHex);

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
          onPressed: () => Navigator.of(context).pop(),
          label: context.l10n.cancel,
        ),
        PrismButton(
          onPressed: () {
            Navigator.of(context).pop();
            _selectColor(_toHex(pickerColor));
          },
          label: context.l10n.settingsAccentColorSelect,
          tone: PrismButtonTone.filled,
        ),
      ],
    );
  }

  bool _isPreset(String hex) {
    return _presetColors
        .any((c) => c.hex.toUpperCase() == hex.toUpperCase());
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

  @override
  Widget build(BuildContext context) {
    final isMaterialYou = widget.materialYouActive;
    final systemAccent = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            // When Material You is active, show the system accent first.
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
                    preset.hex.toUpperCase() == _selectedHex.toUpperCase(),
                onTap: isMaterialYou ? () {} : () => _selectColor(preset.hex),
                tooltip: _tooltipForPreset(context, preset.hex),
              ),
            // Custom color picker button
            if (!isMaterialYou)
              _ColorCircle(
                color: !_isPreset(_selectedHex) ? _parseHex(_selectedHex) : null,
                isSelected: !_isPreset(_selectedHex),
                isCustom: true,
                onTap: _openColorPicker,
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
