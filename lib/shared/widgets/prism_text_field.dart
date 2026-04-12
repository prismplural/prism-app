import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum PrismTextFieldStyle { standard, borderless }

/// A shared text-field wrapper that preserves Material text entry behavior.
class PrismTextField extends StatelessWidget {
  const PrismTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.initialValue,
    this.labelText,
    this.hintText,
    this.helperText,
    this.errorText,
    this.prefixIcon,
    this.suffix,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.validator,
    this.autovalidateMode,
    this.enabled = true,
    this.autofocus = false,
    this.obscureText = false,
    this.textCapitalization = TextCapitalization.none,
    this.minLines = 1,
    this.maxLines = 1,
    this.style,
    this.hintStyle,
    this.contentPadding,
    this.cursorColor,
    this.fieldStyle = PrismTextFieldStyle.standard,
    this.inputFormatters,
    this.maxLength,
    this.textAlign = TextAlign.start,
    this.prefixText,
    this.isDense,
  }) : assert(
         controller == null || initialValue == null,
         'Provide either a controller or an initialValue, not both.',
       );

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? initialValue;
  final String? labelText;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final Widget? prefixIcon;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;
  final AutovalidateMode? autovalidateMode;
  final bool enabled;
  final bool autofocus;
  final bool obscureText;
  final TextCapitalization textCapitalization;
  final int? minLines;
  final int? maxLines;
  final TextStyle? style;
  final TextStyle? hintStyle;
  final EdgeInsetsGeometry? contentPadding;
  final Color? cursorColor;
  final PrismTextFieldStyle fieldStyle;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final TextAlign textAlign;
  final String? prefixText;
  final bool? isDense;

  bool get _isMultiLine =>
      (maxLines != null && maxLines! > 1) ||
      (minLines != null && minLines! > 1);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inputTheme = theme.inputDecorationTheme;

    // Multi-line standard fields use a rounded rectangle instead of the
    // theme-level pill (BorderRadius.circular(999)).
    OutlineInputBorder? multiLineBorder(InputBorder? themeBorder) {
      if (!_isMultiLine || fieldStyle != PrismTextFieldStyle.standard) {
        return null;
      }
      const radius = BorderRadius.all(Radius.circular(12));
      if (themeBorder is OutlineInputBorder) {
        return themeBorder.copyWith(borderRadius: radius);
      }
      return null;
    }

    final decoration = InputDecoration(
      hintText: hintText,
      helperText: helperText,
      errorText: errorText,
      prefixIcon: prefixIcon,
      suffixIcon: suffix,
      hintStyle: hintStyle,
      contentPadding: contentPadding,
      prefixText: prefixText,
      isDense: isDense,
      border: fieldStyle == PrismTextFieldStyle.borderless
          ? InputBorder.none
          : multiLineBorder(inputTheme.border),
      enabledBorder: fieldStyle == PrismTextFieldStyle.borderless
          ? InputBorder.none
          : multiLineBorder(inputTheme.enabledBorder),
      focusedBorder: fieldStyle == PrismTextFieldStyle.borderless
          ? InputBorder.none
          : multiLineBorder(inputTheme.focusedBorder),
      disabledBorder: fieldStyle == PrismTextFieldStyle.borderless
          ? InputBorder.none
          : null,
      errorBorder: fieldStyle == PrismTextFieldStyle.borderless
          ? InputBorder.none
          : null,
      focusedErrorBorder: fieldStyle == PrismTextFieldStyle.borderless
          ? InputBorder.none
          : null,
      filled: fieldStyle == PrismTextFieldStyle.borderless ? false : null,
      isCollapsed: fieldStyle == PrismTextFieldStyle.borderless,
    );

    final textFormField = TextFormField(
      controller: controller,
      focusNode: focusNode,
      initialValue: initialValue,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      validator: validator,
      autovalidateMode: autovalidateMode,
      enabled: enabled,
      autofocus: autofocus,
      obscureText: obscureText,
      textCapitalization: textCapitalization,
      minLines: minLines,
      maxLines: maxLines,
      style: style ?? theme.textTheme.bodyLarge,
      cursorColor: cursorColor ?? theme.colorScheme.primary,
      decoration: decoration,
      inputFormatters: inputFormatters,
      maxLength: maxLength,
      textAlign: textAlign,
    );

    if (labelText != null && fieldStyle != PrismTextFieldStyle.borderless) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLabel(context),
          const SizedBox(height: 4),
          textFormField,
        ],
      );
    }
    return textFormField;
  }

  Widget _buildLabel(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelLarge!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    if (labelText!.contains('*')) {
      final idx = labelText!.indexOf('*');
      return Text.rich(
        TextSpan(children: [
          TextSpan(text: labelText!.substring(0, idx), style: style),
          TextSpan(
            text: ' *',
            style: style.copyWith(color: theme.colorScheme.primary),
          ),
        ]),
      );
    }
    return Text(labelText!, style: style);
  }
}
