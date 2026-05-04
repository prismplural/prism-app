import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/markdown_text.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
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
    final fieldsAsync = ref.watch(customFieldsProvider);
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

    final entries = [
      for (final field in fields)
        if ((valueMap[field.id]?.value ?? '').isNotEmpty)
          _FieldValueEntry(
            field: field,
            value: valueMap[field.id]!,
            displayValue: _formatValueForField(
              context,
              field,
              valueMap[field.id]!.value,
            ),
          ),
    ];

    if (entries.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                AppIcons.tuneOutlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.memberSectionCustomFields,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._buildEntryWidgets(entries),
        ],
      ),
    );
  }

  List<Widget> _buildEntryWidgets(List<_FieldValueEntry> entries) {
    final widgets = <Widget>[];
    var compactRun = <_FieldValueEntry>[];

    void flushCompactRun() {
      if (compactRun.isEmpty) return;
      if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 8));
      widgets.add(_CompactFieldGroup(entries: compactRun));
      compactRun = [];
    }

    for (final entry in entries) {
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

  static String _formatValueForField(
    BuildContext context,
    CustomField field,
    String raw,
  ) {
    return switch (field.fieldType) {
      CustomFieldType.date => _formatDateValue(
        context,
        raw,
        field.datePrecision,
      ),
      CustomFieldType.text ||
      CustomFieldType.longText ||
      CustomFieldType.color => raw,
    };
  }

  static bool _shouldUseCard(_FieldValueEntry entry) {
    if (entry.field.fieldType == CustomFieldType.longText) return true;
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
        DatePrecision.timestamp => DateFormat.yMMMd(locale).add_jm().format(dt),
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

class _CompactFieldGroup extends StatelessWidget {
  const _CompactFieldGroup({required this.entries});

  final List<_FieldValueEntry> entries;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: PrismSectionCard(
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              entry.field.name,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: _FieldValueBody(
              entry: entry,
              textStyle: theme.textTheme.bodyMedium,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldValueCard extends StatelessWidget {
  const _FieldValueCard({required this.entry});

  final _FieldValueEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headerBgColor = theme.colorScheme.onSurface.withValues(alpha: 0.04);
    final dividerColor = theme.colorScheme.onSurface.withValues(alpha: 0.07);

    return PrismSurface(
      tone: PrismSurfaceTone.subtle,
      padding: EdgeInsets.zero,
      borderRadius: 8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: headerBgColor,
              border: Border(bottom: BorderSide(color: dividerColor, width: 1)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
  }

  IconData _iconForField(CustomField field) => switch (field.fieldType) {
    CustomFieldType.text => AppIcons.textFields,
    CustomFieldType.longText => AppIcons.notes,
    CustomFieldType.color => AppIcons.palette,
    CustomFieldType.date => AppIcons.calendarToday,
  };
}

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
    return switch (entry.field.fieldType) {
      CustomFieldType.text => _InlineMarkdownText(
        entry.value.value,
        style: textStyle,
        textAlign: textAlign,
      ),
      CustomFieldType.longText => _LongTextPreview(
        title: entry.field.name,
        data: entry.value.value,
        style: textStyle,
      ),
      CustomFieldType.color => _ColorDisplay(value: entry.value.value),
      CustomFieldType.date => Text(
        entry.displayValue,
        style: textStyle,
        textAlign: textAlign,
      ),
    };
  }
}

class _LongTextPreview extends StatelessWidget {
  const _LongTextPreview({required this.title, required this.data, this.style});

  static const _previewCharacterLimit = 900;
  static const _previewLineLimit = 12;

  final String title;
  final String data;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _buildPreview(data);
    final isTruncated = preview != data;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MarkdownText(
          data: isTruncated ? '$preview...' : data,
          enabled: true,
          baseStyle: style ?? theme.textTheme.bodyMedium,
        ),
        if (isTruncated) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => _openDetail(context),
            child: Text(
              'View more',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _openDetail(BuildContext context) {
    PrismSheet.showFullScreen<void>(
      context: context,
      builder: (context, scrollController) => _CustomFieldDetailSheet(
        title: title,
        data: data,
        scrollController: scrollController,
      ),
    );
  }

  String _buildPreview(String raw) {
    final lines = raw.split('\n');
    var preview = lines.length > _previewLineLimit
        ? lines.take(_previewLineLimit).join('\n')
        : raw;

    if (preview.length > _previewCharacterLimit) {
      preview = preview.substring(0, _previewCharacterLimit);
      final lastWhitespace = preview.lastIndexOf(RegExp(r'\s'));
      if (lastWhitespace > _previewCharacterLimit * 0.65) {
        preview = preview.substring(0, lastWhitespace);
      }
    }

    return preview.trimRight();
  }
}

class _CustomFieldDetailSheet extends StatelessWidget {
  const _CustomFieldDetailSheet({
    required this.title,
    required this.data,
    required this.scrollController,
  });

  final String title;
  final String data;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        children: [
          PrismSheetTopBar(title: title),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              children: [
                MarkdownText(
                  data: data,
                  enabled: true,
                  baseStyle: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorDisplay extends StatelessWidget {
  const _ColorDisplay({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color? color;
    try {
      color = AppColors.fromHex(value);
    } catch (_) {
      color = null;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (color != null) ...[
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
          textAlign: TextAlign.end,
        ),
      ],
    );
  }
}

class _InlineMarkdownText extends StatelessWidget {
  const _InlineMarkdownText(
    this.data, {
    this.style,
    this.textAlign = TextAlign.start,
  });

  final String data;
  final TextStyle? style;
  final TextAlign textAlign;

  static final _boldStar = RegExp(r'\*\*(.+?)\*\*');
  static final _boldUnderscore = RegExp(r'__(.+?)__');
  static final _italicStar = RegExp(r'(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)');
  static final _italicUnderscore = RegExp(r'(?<!_)_(?!_)(.+?)(?<!_)_(?!_)');
  static final _code = RegExp(r'`(.+?)`');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = style ?? theme.textTheme.bodyMedium ?? const TextStyle();
    final codeColor = theme.colorScheme.surfaceContainerHighest;

    final segments = <_InlineMarkdownSegment>[];
    final matched = List.filled(data.length, false);

    void addMatches(
      RegExp pattern,
      TextStyle Function(TextStyle base) styleForMatch,
    ) {
      for (final match in pattern.allMatches(data)) {
        if (_overlaps(matched, match.start, match.end)) continue;
        for (var i = match.start; i < match.end; i++) {
          matched[i] = true;
        }
        segments.add(
          _InlineMarkdownSegment(
            start: match.start,
            end: match.end,
            content: match.group(1)!,
            style: styleForMatch(baseStyle),
          ),
        );
      }
    }

    addMatches(
      _code,
      (base) =>
          base.copyWith(fontFamily: 'monospace', backgroundColor: codeColor),
    );
    addMatches(_boldStar, (base) => base.copyWith(fontWeight: FontWeight.bold));
    addMatches(
      _boldUnderscore,
      (base) => base.copyWith(fontWeight: FontWeight.bold),
    );
    addMatches(
      _italicStar,
      (base) => base.copyWith(fontStyle: FontStyle.italic),
    );
    addMatches(
      _italicUnderscore,
      (base) => base.copyWith(fontStyle: FontStyle.italic),
    );

    if (segments.isEmpty) {
      return Text(data, style: baseStyle, textAlign: textAlign);
    }

    segments.sort((a, b) => a.start.compareTo(b.start));
    final spans = <InlineSpan>[];
    var cursor = 0;

    for (final segment in segments) {
      if (cursor < segment.start) {
        spans.add(TextSpan(text: data.substring(cursor, segment.start)));
      }
      spans.add(TextSpan(text: segment.content, style: segment.style));
      cursor = segment.end;
    }

    if (cursor < data.length) {
      spans.add(TextSpan(text: data.substring(cursor)));
    }

    return Text.rich(
      TextSpan(style: baseStyle, children: spans),
      textAlign: textAlign,
    );
  }

  bool _overlaps(List<bool> matched, int start, int end) {
    for (var i = start; i < end; i++) {
      if (matched[i]) return true;
    }
    return false;
  }
}

class _InlineMarkdownSegment {
  const _InlineMarkdownSegment({
    required this.start,
    required this.end,
    required this.content,
    required this.style,
  });

  final int start;
  final int end;
  final String content;
  final TextStyle style;
}
