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
    this.alignLabelWithHint,
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
  final bool? alignLabelWithHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final decoration = InputDecoration(
      labelText: labelText,
      hintText: hintText,
      helperText: helperText,
      errorText: errorText,
      prefixIcon: prefixIcon,
      suffixIcon: suffix,
      hintStyle: hintStyle,
      contentPadding: contentPadding,
      prefixText: prefixText,
      isDense: isDense,
      alignLabelWithHint: alignLabelWithHint,
      border: fieldStyle == PrismTextFieldStyle.borderless
          ? InputBorder.none
          : null,
      enabledBorder: fieldStyle == PrismTextFieldStyle.borderless
          ? InputBorder.none
          : null,
      focusedBorder: fieldStyle == PrismTextFieldStyle.borderless
          ? InputBorder.none
          : null,
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

    return TextFormField(
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
  }
}
