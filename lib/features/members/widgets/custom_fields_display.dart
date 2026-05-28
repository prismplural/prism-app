import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:prism_plurality/domain/custom_fields/registry.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/widgets/custom_field_display_scope.dart';
import 'package:prism_plurality/features/members/widgets/custom_field_renderers.dart';
import 'package:prism_plurality/features/members/widgets/group_field_widgets.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';

/// Displays custom field values on a member detail screen.
class CustomFieldsDisplay extends ConsumerWidget {
  const CustomFieldsDisplay({super.key, required this.memberId});

  static const _compactNameLimit = 24;
  static const _compactValueLimit = 48;
  static const _compactCombinedLimit = 64;

  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fieldsAsync = ref.watch(topLevelCustomFieldsProvider);
    final valuesAsync = ref.watch(memberCustomFieldValuesProvider(memberId));

    return fieldsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (fields) => valuesAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (_, _) => const SizedBox.shrink(),
        data: (values) => _buildContent(context, fields, values),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    List<CustomField> fields,
    List<CustomFieldValue> values,
  ) {
    final valueMap = <String, CustomFieldValue>{
      for (final v in values) v.customFieldId: v,
    };

    // Iterate top-level fields (parentFieldId == null) in displayOrder.
    // Group-type fields have no per-member value and are routed directly to
    // _GroupDisplayWidget (which watches providers itself). Non-group fields
    // take the value-driven _FieldValueEntry path as before.
    //
    // Children of groups are intentionally excluded here — they render inside
    // their parent's _GroupDisplayWidget instead.
    final topLevelFields =
        fields.where((f) => f.parentFieldId == null).toList();

    final items = <_TopLevelItem>[];
    for (final field in topLevelFields) {
      if (field.fieldTypeId == 'group') {
        items.add(_TopLevelItem.group(field));
      } else {
        final value = valueMap[field.id];
        if (value != null && value.value.isNotEmpty) {
          items.add(
            _TopLevelItem.entry(
              _FieldValueEntry(
                field: field,
                value: value,
                displayValue: _formatValueForField(context, field, value.value),
              ),
            ),
          );
        }
      }
    }

    if (items.isEmpty) return const SizedBox.shrink();

    // Build the widget list respecting compact-run grouping for entry items.
    // Group widgets are rendered individually (no compact-run membership).
    final widgets = _buildItemWidgets(items);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: widgets,
      ),
    );
  }

  List<Widget> _buildItemWidgets(List<_TopLevelItem> items) {
    final widgets = <Widget>[];
    var compactRun = <_FieldValueEntry>[];

    void flushCompactRun() {
      if (compactRun.isEmpty) return;
      if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 8));
      widgets.add(_CompactFieldGroup(entries: compactRun));
      compactRun = [];
    }

    for (final item in items) {
      if (item.isGroup) {
        flushCompactRun();
        if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 8));
        widgets.add(buildGroupDisplayForMember(item.groupField!, memberId));
        continue;
      }

      final entry = item.entry!;
      // Stacked layout: explicit per-field choice (scale config), or
      // type-default (slider). See `effectiveDisplayLayout`.
      final layout = effectiveDisplayLayout(
        fieldTypeId: entry.field.fieldTypeId,
        typeConfig: entry.field.typeConfig,
      );
      final hideTitle = effectiveHideTitleOnProfile(entry.field.typeConfig);
      if (layout == DisplayLayout.stacked) {
        flushCompactRun();
        if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 8));
        widgets.add(_FieldValueStacked(entry: entry, hideTitle: hideTitle));
        continue;
      }
      if (hideTitle) {
        flushCompactRun();
        if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 8));
        widgets.add(_FieldValueCard(entry: entry, hideTitle: true));
        continue;
      }
      if (entry.isCompact) {
        compactRun.add(entry);
        continue;
      }

      flushCompactRun();
      if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 8));
      widgets.add(_FieldValueCard(entry: entry));
    }

    flushCompactRun();
    return widgets;
  }


  /// Format the raw stored value into a human-readable string for display.
  ///
  /// For date fields, this formats per the field's precision. For all other
  /// legacy types, the raw value is used as-is. Keyed on [field.fieldTypeId]
  /// (the stable string ID) rather than the legacy enum.
  static String _formatValueForField(
    BuildContext context,
    CustomField field,
    String raw,
  ) {
    if (field.fieldTypeId == 'date') {
      return _formatDateValue(context, raw, field.datePrecision);
    }
    return raw;
  }

  static bool _shouldUseCard(_FieldValueEntry entry) {
    if (entry.field.fieldTypeId == 'long_text') return true;
    if (entry.field.fieldTypeId == 'text') return false;
    if (entry.value.value.contains('\n')) return true;
    if (entry.field.name.length > _compactNameLimit) return true;
    if (entry.displayValue.length > _compactValueLimit) return true;
    return entry.field.name.length + entry.displayValue.length >
        _compactCombinedLimit;
  }

  static String _formatDateValue(
    BuildContext context,
    String raw,
    DatePrecision? precision,
  ) {
    final locale = context.dateLocale;
    try {
      final dt = DateTime.parse(raw);
      return switch (precision ?? DatePrecision.full) {
        DatePrecision.full => DateFormat.yMMMd(locale).format(dt),
        DatePrecision.monthYear => DateFormat.yMMM(locale).format(dt),
        DatePrecision.monthDay => DateFormat.MMMd(locale).format(dt),
        DatePrecision.month => DateFormat.MMMM(locale).format(dt),
        DatePrecision.year => DateFormat.y(locale).format(dt),
        DatePrecision.timestamp =>
          '${DateFormat.yMMMd(locale).format(dt)} ${context.formatTime(dt)}',
      };
    } catch (_) {
      return raw;
    }
  }
}

class _FieldValueEntry {
  const _FieldValueEntry({
    required this.field,
    required this.value,
    required this.displayValue,
  });

  final CustomField field;
  final CustomFieldValue value;
  final String displayValue;

  bool get isCompact => !CustomFieldsDisplay._shouldUseCard(this);
}

/// Discriminated union of top-level display items: either a group widget
/// (rendered directly by [_GroupDisplayWidget]) or a value-driven entry
/// (rendered via the compact/card path).
class _TopLevelItem {
  const _TopLevelItem._({this.groupField, this.entry});

  factory _TopLevelItem.group(CustomField field) =>
      _TopLevelItem._(groupField: field);

  factory _TopLevelItem.entry(_FieldValueEntry entry) =>
      _TopLevelItem._(entry: entry);

  final CustomField? groupField;
  final _FieldValueEntry? entry;

  bool get isGroup => groupField != null;
}

class _CompactFieldGroup extends StatelessWidget {
  const _CompactFieldGroup({required this.entries});

  final List<_FieldValueEntry> entries;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: PrismSectionCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              _FieldValueRow(entry: entries[i]),
            ],
          ],
        ),
      ),
    );
  }
}

class _FieldValueRow extends StatelessWidget {
  const _FieldValueRow({required this.entry});

  final _FieldValueEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            flex: 2,
            fit: FlexFit.tight,
            child: Text(
              entry.field.name,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            flex: 3,
            fit: FlexFit.tight,
            child: _FieldValueBody(
              entry: entry,
              textStyle: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
              textAlign: TextAlign.start,
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldValueCard extends StatelessWidget {
  const _FieldValueCard({required this.entry, this.hideTitle = false});

  final _FieldValueEntry entry;
  final bool hideTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headerBgColor = theme.colorScheme.onSurface.withValues(alpha: 0.04);
    final dividerColor = theme.colorScheme.onSurface.withValues(alpha: 0.07);

    final surface = PrismSurface(
      tone: PrismSurfaceTone.subtle,
      padding: EdgeInsets.zero,
      borderRadius: 8,
      child: hideTitle
          ? Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
              child: _FieldValueBody(
                entry: entry,
                textStyle: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                  height: 1.45,
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: headerBgColor,
                    border: Border(
                      bottom: BorderSide(color: dividerColor, width: 1),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _iconForField(entry.field),
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            entry.field.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                  child: _FieldValueBody(
                    entry: entry,
                    textStyle: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurface,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
    );

    final sized = SizedBox(width: double.infinity, child: surface);
    if (hideTitle) {
      return Semantics(
        container: true,
        label: entry.field.name,
        child: sized,
      );
    }
    return sized;
  }

  IconData _iconForField(CustomField field) {
    return customFieldTypeRegistry.lookupById(field.fieldTypeId)?.icon ??
        AppIcons.textFields;
  }
}

/// Stacked layout: field name as a small bold header above the renderer's
/// body. Used for types whose display widgets are inherently wide and need
/// the full row to themselves — sliders especially, where the value column
/// of the compact 2-column layout is too narrow for the track + label row.
/// Matches the visual treatment used by group children of the same types.
class _FieldValueStacked extends StatelessWidget {
  const _FieldValueStacked({required this.entry, this.hideTitle = false});

  final _FieldValueEntry entry;
  final bool hideTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card = SizedBox(
      width: double.infinity,
      child: PrismSectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!hideTitle) ...[
              Text(
                entry.field.name,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 8),
            ],
            _FieldValueBody(entry: entry),
          ],
        ),
      ),
    );

    if (hideTitle) {
      return Semantics(
        container: true,
        label: entry.field.name,
        child: card,
      );
    }
    return card;
  }
}

/// Renders the value body for a custom field entry. Dispatches THROUGH the
/// renderer registry — no hardcoded type switches.
///
/// [textStyle] and [textAlign] are applied via [DefaultTextStyle] and [Align]
/// at the call site when the renderer returns a widget that benefits from them.
/// Each renderer is self-contained; callers style the container, not internals.
class _FieldValueBody extends StatelessWidget {
  const _FieldValueBody({
    required this.entry,
    this.textStyle,
    this.textAlign = TextAlign.start,
  });

  final _FieldValueEntry entry;
  final TextStyle? textStyle;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final def = customFieldTypeRegistry.lookupById(entry.field.fieldTypeId);
    final renderer = rendererFor(def);

    if (renderer == null) {
      // Unknown type — forward-compat: render as plain text with caller style.
      return Text(entry.value.value, style: textStyle, textAlign: textAlign);
    }

    // Wrap in DefaultTextStyle so renderers that produce Text widgets inherit
    // the caller's desired style without each renderer needing to accept it.
    //
    // CustomFieldDisplayScope tells renderers like slider/scale that the
    // surrounding row/card already shows the field name, so they should skip
    // their own internal label.
    final child = CustomFieldDisplayScope(
      labelHandled: true,
      child: renderer.displayBuilder(context, entry.field, entry.value),
    );

    if (textStyle == null && textAlign == TextAlign.start) return child;

    return DefaultTextStyle.merge(
      style: textStyle ?? const TextStyle(),
      textAlign: textAlign,
      child: child,
    );
  }
}
