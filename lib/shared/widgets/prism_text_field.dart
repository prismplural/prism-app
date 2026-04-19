import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';

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

    // Multi-line fields use a slightly tighter radius than single-line
    // since the taller container looks better with less rounding.
    OutlineInputBorder? multiLineBorder(InputBorder? themeBorder) {
      if (!_isMultiLine || fieldStyle != PrismTextFieldStyle.standard) {
        return null;
      }
      final radius = BorderRadius.all(
        Radius.circular(PrismShapes.of(context).radius(PrismTokens.radiusMedium)),
      );
      if (themeBorder is OutlineInputBorder) {
        return themeBorder.copyWith(borderRadius: radius);
      }
      return null;
    }

    // When a static label is rendered above the field, don't duplicate it
    // inside the InputDecoration — keep the field itself clean.
    final hasExternalLabel =
        labelText != null && fieldStyle != PrismTextFieldStyle.borderless;
    final hasError = errorText != null && errorText!.isNotEmpty;
    final isBorderless = fieldStyle == PrismTextFieldStyle.borderless;
    final errorColor = theme.colorScheme.error;

    // Build the error chip suffix when there's an error.
    Widget? effectiveSuffix = suffix;
    if (hasError && !isBorderless) {
      final chip = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: errorColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          errorText!,
          style: theme.textTheme.labelSmall!.copyWith(
            color: errorColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      // If there's already a suffix, stack them.
      effectiveSuffix = suffix != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [suffix!, const SizedBox(width: 6), chip],
            )
          : chip;
    }

    // Error border: subtle tint instead of the default bold red.
    OutlineInputBorder? errorBorder() {
      if (isBorderless || !hasError) return null;
      final radius = _isMultiLine
          ? BorderRadius.all(
              Radius.circular(
                PrismShapes.of(context).radius(PrismTokens.radiusMedium),
              ),
            )
          : BorderRadius.circular(
              PrismShapes.of(context).radius(PrismTokens.radiusLarge),
            );
      return OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: errorColor.withValues(alpha: 0.25)),
      );
    }

    final decoration = InputDecoration(
      labelText: hasExternalLabel ? null : labelText,
      floatingLabelBehavior: FloatingLabelBehavior.never,
      hintText: hintText,
      // When we have an external label, render helper text ourselves
      // so it aligns with the label at the container edge.
      helperText: hasExternalLabel ? null : helperText,
      // Suppress below-field error text — errors show as an inline chip.
      errorText: hasError ? '' : null,
      errorStyle: hasError
          ? const TextStyle(fontSize: 0, height: 0)
          : null,
      prefixIcon: prefixIcon,
      suffixIcon: effectiveSuffix != null
          ? Padding(
              padding: const EdgeInsets.only(right: 12),
              child: effectiveSuffix,
            )
          : null,
      suffixIconConstraints: effectiveSuffix != null
          ? const BoxConstraints(minHeight: 0, minWidth: 0)
          : null,
      hintStyle: hintStyle,
      contentPadding: contentPadding,
      prefixText: prefixText,
      isDense: isDense,
      // Tint the fill when errored.
      filled: isBorderless ? false : true,
      fillColor: isBorderless
          ? null
          : hasError
              ? errorColor.withValues(alpha: 0.06)
              : null,
      border: isBorderless ? InputBorder.none : multiLineBorder(inputTheme.border),
      enabledBorder: isBorderless
          ? InputBorder.none
          : multiLineBorder(inputTheme.enabledBorder),
      focusedBorder: isBorderless
          ? InputBorder.none
          : multiLineBorder(inputTheme.focusedBorder),
      disabledBorder: isBorderless ? InputBorder.none : null,
      errorBorder: isBorderless ? InputBorder.none : errorBorder(),
      focusedErrorBorder: isBorderless ? InputBorder.none : errorBorder(),
      isCollapsed: isBorderless,
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
      enableSuggestions: !obscureText,
      autocorrect: !obscureText,
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

    if (hasExternalLabel) {
      final hasHelper = helperText != null && helperText!.isNotEmpty;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLabel(context),
          const SizedBox(height: 6),
          // Semantics label so screen readers still announce the field name
          // even though the visual label lives outside the InputDecoration.
          Semantics(
            label: labelText,
            child: textFormField,
          ),
          if (hasHelper) ...[
            const SizedBox(height: 4),
            Text(
              helperText!,
              style: theme.textTheme.bodySmall!.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      );
    }
    return textFormField;
  }

  Widget _buildLabel(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.titleSmall!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    // Only treat trailing " *" or "*" as a required indicator
    final requiredPattern = RegExp(r'\s?\*$');
    if (requiredPattern.hasMatch(labelText!)) {
      final base = labelText!.replaceAll(requiredPattern, '');
      return Text.rich(
        TextSpan(children: [
          TextSpan(text: base, style: style),
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
