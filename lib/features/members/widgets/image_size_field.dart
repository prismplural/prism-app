import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:prism_plurality/features/members/services/bio_image_insert_spec.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';

/// A form row for choosing an inserted image's width: a unit selector
/// (Default / px / % / em) plus a value field that reveals for the non-default
/// modes. Emits an [ImageSizeSpec] on every change.
///
/// Pure UI with no media/session dependencies, so it drops into any insert
/// flow — used by the staged-image and library dialogs in [MarkdownImageButton].
/// The value carries across mode switches (it's the author's number); the
/// fragment builder clamps anything out of range.
class ImageSizeField extends StatefulWidget {
  const ImageSizeField({
    super.key,
    this.initial = ImageSizeSpec.unset,
    required this.onChanged,
  });

  final ImageSizeSpec initial;
  final ValueChanged<ImageSizeSpec> onChanged;

  @override
  State<ImageSizeField> createState() => _ImageSizeFieldState();
}

class _ImageSizeFieldState extends State<ImageSizeField> {
  late ImageSizeMode _mode = widget.initial.mode;
  late final TextEditingController _valueController = TextEditingController(
    text: widget.initial.value != null
        ? _format(widget.initial.value!)
        : '',
  );

  static String _format(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(
      ImageSizeSpec(
        mode: _mode,
        value: double.tryParse(_valueController.text.trim()),
      ),
    );
  }

  void _onModeChanged(ImageSizeMode mode) {
    setState(() => _mode = mode);
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final showValue = _mode != ImageSizeMode.defaultSize;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            l10n.mediaSizeLabel,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 8),
        PrismSegmentedControl<ImageSizeMode>(
          selected: _mode,
          onChanged: _onModeChanged,
          segments: [
            PrismSegment(
              value: ImageSizeMode.defaultSize,
              label: l10n.mediaSizeModeDefault,
            ),
            PrismSegment(
              value: ImageSizeMode.widthPx,
              label: l10n.mediaSizeModePixels,
            ),
            PrismSegment(
              value: ImageSizeMode.percent,
              label: l10n.mediaSizeModePercent,
            ),
            PrismSegment(
              value: ImageSizeMode.em,
              label: l10n.mediaSizeModeEm,
            ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: showValue
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: PrismTextField(
                    controller: _valueController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: const [_DecimalTextInputFormatter()],
                    hintText: l10n.mediaSizeValueHint,
                    onChanged: (_) => _emit(),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// Restricts input to a non-negative decimal — digits with at most one dot.
/// Rejects malformed entries like `1..5` or stray characters at the keystroke,
/// so the value either parses to a number or is empty, never a silent
/// half-number that would drop sizing without the user noticing.
class _DecimalTextInputFormatter extends TextInputFormatter {
  const _DecimalTextInputFormatter();

  static final RegExp _valid = RegExp(r'^\d*\.?\d*$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => _valid.hasMatch(newValue.text) ? newValue : oldValue;
}
