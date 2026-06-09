import 'package:freezed_annotation/freezed_annotation.dart';

part 'typed_field_value.freezed.dart';

/// A typed, parsed representation of a CustomFieldValue's raw string.
///
/// Parsing happens via the type definition's valueParser (see
/// CustomFieldTypeDefinition.valueParser) — branch on field type first, never
/// sniff the raw string. Each definition knows its own variant.
///
/// Parsers never throw. On malformed input they return either a sensible
/// empty default (per type) or [UnsupportedFieldValue] preserving the raw
/// string for sync re-emit.
@freezed
sealed class TypedFieldValue with _$TypedFieldValue {
  const factory TypedFieldValue.text(String value) = TextFieldValue;
  const factory TypedFieldValue.longText(String value) = LongTextFieldValue;
  const factory TypedFieldValue.color({String? hex}) = ColorFieldValue;
  const factory TypedFieldValue.date({DateTime? value}) = DateFieldValue;
  const factory TypedFieldValue.choice({
    @Default(<String>{}) Set<String> optionIds,
    String? other,
  }) = ChoiceFieldValue;
  const factory TypedFieldValue.scale({int? step}) = ScaleFieldValue;
  const factory TypedFieldValue.slider({double? value}) = SliderFieldValue;
  const factory TypedFieldValue.member({
    @Default(<String>{}) Set<String> memberIds,
    @Default(<String, dynamic>{}) Map<String, dynamic> extra,
  }) = MemberFieldValue;

  /// Forward-compat for unknown field types — preserves raw bytes for
  /// sync re-emit without crashing.
  const factory TypedFieldValue.unsupported(String raw) = UnsupportedFieldValue;
}
