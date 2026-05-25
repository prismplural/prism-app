import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

part 'custom_field.freezed.dart';
part 'custom_field.g.dart';

/// Field type identity used in legacy exhaustive switches throughout the app.
///
/// **Extension policy:** New types are registered via `customFieldTypeRegistry`
/// in `lib/domain/custom_fields/registry.dart`. Enum entries here are
/// back-compat fallbacks ONLY — for code that hasn't been migrated to dispatch
/// through the registry yet. Adding a new entry should be considered tech debt;
/// prefer extending the registry without adding here.
///
/// BATCH 3+ types (group, scale, slider) must NOT extend this enum. They
/// register only through the registry. If a switch on [CustomFieldType]
/// requires exhaustiveness, add a wildcard/default branch for future types
/// rather than widening the enum.
enum CustomFieldType {
  text, // 0 - short text
  color, // 1
  date, // 2
  longText, // 3
  choice; // 4 - single/multi-select (fieldTypeId='choice', legacyIntValue=4)

  String get label => switch (this) {
    CustomFieldType.text => 'Short Text',
    CustomFieldType.color => 'Color',
    CustomFieldType.date => 'Date',
    CustomFieldType.longText => 'Long Text',
    CustomFieldType.choice => 'Choice',
  };

  String localizedLabel(AppLocalizations l10n) => switch (this) {
    CustomFieldType.text => l10n.customFieldTypeShortText,
    CustomFieldType.color => l10n.customFieldTypeColor,
    CustomFieldType.date => l10n.customFieldTypeDate,
    CustomFieldType.longText => l10n.customFieldTypeLongText,
    CustomFieldType.choice => l10n.customFieldTypeChoice,
  };

  bool get isTextual => switch (this) {
    CustomFieldType.text || CustomFieldType.longText => true,
    CustomFieldType.color || CustomFieldType.date || CustomFieldType.choice => false,
  };
}

enum DatePrecision {
  full, // 0 - year-month-day
  monthYear, // 1
  monthDay, // 2
  month, // 3
  year, // 4
  timestamp; // 5 - date + time

  String get label => switch (this) {
    DatePrecision.full => 'Full Date',
    DatePrecision.monthYear => 'Month & Year',
    DatePrecision.monthDay => 'Month & Day',
    DatePrecision.month => 'Month',
    DatePrecision.year => 'Year',
    DatePrecision.timestamp => 'Date & Time',
  };

  String localizedLabel(AppLocalizations l10n) => switch (this) {
    DatePrecision.full => l10n.customFieldDatePrecisionFull,
    DatePrecision.monthYear => l10n.customFieldDatePrecisionMonthYear,
    DatePrecision.monthDay => l10n.customFieldDatePrecisionMonthDay,
    DatePrecision.month => l10n.customFieldDatePrecisionMonth,
    DatePrecision.year => l10n.customFieldDatePrecisionYear,
    DatePrecision.timestamp => l10n.customFieldDatePrecisionTimestamp,
  };
}

@freezed
abstract class CustomField with _$CustomField {
  const CustomField._();

  const factory CustomField({
    required String id,
    required String name,
    required CustomFieldType fieldType,
    DatePrecision? datePrecision,
    @Default(0) int displayOrder,
    required DateTime createdAt,
    String? fieldTypeId,
    String? parentFieldId,
    @JsonKey(includeFromJson: false, includeToJson: false)
    CustomFieldTypeConfig? typeConfig,
  }) = _CustomField;

  factory CustomField.fromJson(Map<String, dynamic> json) =>
      _$CustomFieldFromJson(json);
}
