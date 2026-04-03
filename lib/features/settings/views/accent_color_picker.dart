import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';

/// Preset colors available for accent color selection.
class _PresetColor {
  const _PresetColor(this.label, this.hex);
  final String label;
  final String hex;
}

const _presetColors = [
  _PresetColor('Prism Purple', '#B498C2'),
  _PresetColor('Blue', '#2563EB'),
  _PresetColor('Green', '#16A34A'),
  _PresetColor('Red', '#DC2626'),
  _PresetColor('Orange', '#EA580C'),
  _PresetColor('Pink', '#DB2777'),
  _PresetColor('Teal', '#0D9488'),
  _PresetColor('Amber', '#D97706'),
  _PresetColor('Indigo', '#4F46E5'),
  _PresetColor('Gray', '#6B7280'),
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
      title: 'Pick a color',
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
          label: 'Cancel',
        ),
        PrismButton(
          onPressed: () {
            Navigator.of(context).pop();
            _selectColor(_toHex(pickerColor));
          },
          label: 'Select',
          tone: PrismButtonTone.filled,
        ),
      ],
    );
  }

  bool _isPreset(String hex) {
    return _presetColors
        .any((c) => c.hex.toUpperCase() == hex.toUpperCase());
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
                tooltip: 'System color',
              ),
            for (final preset in _presetColors)
              _ColorCircle(
                color: isMaterialYou
                    ? _parseHex(preset.hex).withValues(alpha: 0.35)
                    : _parseHex(preset.hex),
                isSelected: !isMaterialYou &&
                    preset.hex.toUpperCase() == _selectedHex.toUpperCase(),
                onTap: isMaterialYou ? () {} : () => _selectColor(preset.hex),
                tooltip: preset.label,
              ),
            // Custom color picker button
            if (!isMaterialYou)
              _ColorCircle(
                color: !_isPreset(_selectedHex) ? _parseHex(_selectedHex) : null,
                isSelected: !_isPreset(_selectedHex),
                isCustom: true,
                onTap: _openColorPicker,
                tooltip: 'Custom',
              ),
          ],
        ),
        if (isMaterialYou)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Using your system color palette',
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

    final circle = GestureDetector(
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
                Icons.colorize,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              )
            : isSelected
                ? const Icon(Icons.check, size: 20, color: AppColors.warmWhite)
                : null,
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: circle);
    }
    return circle;
  }
}
