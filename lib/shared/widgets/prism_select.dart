import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';

enum PrismSelectStyle { field, compact }

/// Option model for [PrismSelect].
///
/// [leading] and [fieldLeading] accept arbitrary widgets, so callers can use
/// avatars, emoji, tinted badges, or custom glyphs in either the popup rows
/// or the closed field.
class PrismSelectItem<T> {
  const PrismSelectItem({
    required this.value,
    required this.label,
    this.subtitle,
    this.leading,
    this.trailing,
    this.enabled = true,
    this.semanticLabel,
    this.fieldLabel,
    this.fieldSubtitle,
    this.fieldLeading,
  });

  final T value;
  final String label;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool enabled;
  final String? semanticLabel;

  /// Optional override for the closed field label.
  final String? fieldLabel;

  /// Optional override for the closed field subtitle.
  final String? fieldSubtitle;

  /// Optional override for the closed field leading widget.
  final Widget? fieldLeading;
}

/// A field-styled select control that opens a frosted Prism popup.
///
/// Use this for standard form-style selects. The popup adopts the same blurred
/// overlay treatment as existing app-bar and sheet menus via [BlurPopupAnchor].
class PrismSelect<T> extends StatefulWidget {
  const PrismSelect({
    super.key,
    required this.items,
    required this.onChanged,
    this.value,
    this.labelText,
    this.hintText,
    this.helperText,
    this.errorText,
    this.enabled = true,
    this.isDense = false,
    this.contentPadding,
    this.menuMaxHeight = 280,
    this.menuWidth,
    this.preferredDirection,
    this.semanticLabel,
    this.style = PrismSelectStyle.field,
  });

  const PrismSelect.compact({
    super.key,
    required this.items,
    required this.onChanged,
    this.value,
    this.hintText,
    this.enabled = true,
    this.contentPadding,
    this.menuMaxHeight = 280,
    this.menuWidth,
    this.preferredDirection,
    this.semanticLabel,
  }) : labelText = null,
       helperText = null,
       errorText = null,
       isDense = true,
       style = PrismSelectStyle.compact;

  final List<PrismSelectItem<T>> items;
  final ValueChanged<T?> onChanged;
  final T? value;
  final String? labelText;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final bool enabled;
  final bool isDense;
  final EdgeInsetsGeometry? contentPadding;
  final double menuMaxHeight;
  final double? menuWidth;
  final BlurPopupDirection? preferredDirection;
  final String? semanticLabel;
  final PrismSelectStyle style;

  @override
  State<PrismSelect<T>> createState() => _PrismSelectState<T>();
}

class _PrismSelectState<T> extends State<PrismSelect<T>> {
  final _popupKey = GlobalKey<BlurPopupAnchorState>();

  PrismSelectItem<T>? get _selectedItem {
    for (final item in widget.items) {
      if (item.value == widget.value) return item;
    }
    return null;
  }

  bool get _canOpen =>
      widget.enabled && widget.items.any((item) => item.enabled);

  void _openPopup() {
    if (!_canOpen) return;
    _popupKey.currentState?.show();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final resolvedWidth =
            widget.menuWidth ??
            (constraints.hasBoundedWidth && constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 220.0);
        final field = _SelectField(
          selectedItem: _selectedItem,
          labelText: widget.labelText,
          hintText: widget.hintText,
          helperText: widget.helperText,
          errorText: widget.errorText,
          enabled: widget.enabled,
          isDense: widget.isDense,
          contentPadding: widget.contentPadding,
          semanticLabel: widget.semanticLabel,
          onTap: _canOpen ? _openPopup : null,
          style: widget.style,
        );

        if (!_canOpen) {
          return field;
        }

        return BlurPopupAnchor(
          key: _popupKey,
          trigger: BlurPopupTrigger.manual,
          preferredDirection: widget.preferredDirection,
          width: resolvedWidth,
          maxHeight: widget.menuMaxHeight,
          itemCount: widget.items.length,
          itemBuilder: (context, index, close) {
            final item = widget.items[index];
            final isSelected = item.value == widget.value;
            return _SelectMenuItem(
              item: item,
              isSelected: isSelected,
              onTap: item.enabled
                  ? () {
                      close();
                      widget.onChanged(item.value);
                    }
                  : null,
            );
          },
          child: field,
        );
      },
    );
  }
}

class _SelectField<T> extends StatelessWidget {
  const _SelectField({
    required this.selectedItem,
    required this.labelText,
    required this.hintText,
    required this.helperText,
    required this.errorText,
    required this.enabled,
    required this.isDense,
    required this.contentPadding,
    required this.semanticLabel,
    required this.onTap,
    required this.style,
  });

  final PrismSelectItem<T>? selectedItem;
  final String? labelText;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final bool enabled;
  final bool isDense;
  final EdgeInsetsGeometry? contentPadding;
  final String? semanticLabel;
  final VoidCallback? onTap;
  final PrismSelectStyle style;

  @override
  Widget build(BuildContext context) {
    return switch (style) {
      PrismSelectStyle.field => _buildField(context),
      PrismSelectStyle.compact => _buildCompact(context),
    };
  }

  Widget _buildField(BuildContext context) {
    final theme = Theme.of(context);
    final inputTheme = theme.inputDecorationTheme;
    final border = inputTheme.border;
    final borderRadius = border is OutlineInputBorder
        ? border.borderRadius
        : BorderRadius.circular(999);
    final disabledColor = theme.disabledColor;
    final hintStyle = theme.textTheme.bodyLarge?.copyWith(
      color: enabled
          ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.72)
          : disabledColor,
    );
    final fieldLabel = selectedItem?.fieldLabel ?? selectedItem?.label;
    final fieldSubtitle = selectedItem?.fieldSubtitle ?? selectedItem?.subtitle;
    final fieldLeading = selectedItem?.fieldLeading ?? selectedItem?.leading;

    final field = Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticLabel ?? labelText ?? fieldLabel ?? hintText,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: InputDecorator(
            isEmpty: selectedItem == null,
            decoration: InputDecoration(
              hintText: hintText,
              helperText: helperText,
              errorText: errorText,
              enabled: enabled,
              isDense: isDense,
              contentPadding: contentPadding,
            ),
            child: Row(
              children: [
                Expanded(
                  child: selectedItem == null
                      ? Text(hintText ?? '', style: hintStyle)
                      : _SelectFieldContent(
                          label: fieldLabel ?? '',
                          subtitle: fieldSubtitle,
                          leading: fieldLeading,
                          enabled: enabled,
                        ),
                ),
                const SizedBox(width: 8),
                Icon(
                  AppIcons.expandMore,
                  size: 18,
                  color: enabled
                      ? theme.colorScheme.onSurfaceVariant
                      : disabledColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (labelText != null) {
      final labelStyle = theme.textTheme.labelLarge!.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Text(labelText!, style: labelStyle)),
          const SizedBox(height: 4),
          field,
        ],
      );
    }
    return field;
  }

  Widget _buildCompact(BuildContext context) {
    final theme = Theme.of(context);
    final inputTheme = theme.inputDecorationTheme;
    final border = inputTheme.border;
    final enabledBorder = inputTheme.enabledBorder;
    final borderRadius = border is OutlineInputBorder
        ? border.borderRadius
        : BorderRadius.circular(999);
    final borderColor = enabledBorder is OutlineInputBorder
        ? enabledBorder.borderSide.color
        : theme.colorScheme.outline.withValues(alpha: 0.28);
    final fillColor =
        inputTheme.fillColor ??
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6);
    final disabledColor = theme.disabledColor;
    final label =
        selectedItem?.fieldLabel ?? selectedItem?.label ?? hintText ?? '';
    final leading = selectedItem?.fieldLeading ?? selectedItem?.leading;
    final labelStyle = theme.textTheme.bodyMedium?.copyWith(
      color: selectedItem == null
          ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.78)
          : enabled
          ? theme.colorScheme.onSurface
          : disabledColor,
      fontWeight: selectedItem == null ? FontWeight.w500 : FontWeight.w600,
    );
    final resolvedPadding =
        contentPadding ??
        const EdgeInsets.symmetric(horizontal: 12, vertical: 8);

    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticLabel ?? labelText ?? label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: Ink(
            padding: resolvedPadding,
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: borderRadius,
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading != null) ...[leading, const SizedBox(width: 8)],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: labelStyle,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  AppIcons.expandMore,
                  size: 16,
                  color: enabled
                      ? theme.colorScheme.onSurfaceVariant
                      : disabledColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectFieldContent extends StatelessWidget {
  const _SelectFieldContent({
    required this.label,
    required this.subtitle,
    required this.leading,
    required this.enabled,
  });

  final String label;
  final String? subtitle;
  final Widget? leading;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = enabled
        ? theme.colorScheme.onSurface
        : theme.disabledColor;
    final subtitleColor = enabled
        ? theme.colorScheme.onSurfaceVariant
        : theme.disabledColor;

    return Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 12)],
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(color: foreground),
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: subtitleColor,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SelectMenuItem<T> extends StatelessWidget {
  const _SelectMenuItem({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final PrismSelectItem<T> item;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trailingChildren = <Widget>[
      if (item.trailing != null) item.trailing!,
      if (isSelected)
        Icon(
          AppIcons.check,
          size: 18,
          color: item.enabled ? theme.colorScheme.primary : theme.disabledColor,
        ),
    ];

    return PrismListRow(
      dense: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      leading: item.leading,
      title: Text(
        item.label,
        style: isSelected ? TextStyle(color: theme.colorScheme.primary) : null,
      ),
      subtitle: item.subtitle != null ? Text(item.subtitle!) : null,
      trailing: trailingChildren.isEmpty
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < trailingChildren.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  trailingChildren[i],
                ],
              ],
            ),
      enabled: item.enabled,
      onTap: onTap,
    );
  }
}
