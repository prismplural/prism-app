import 'package:freezed_annotation/freezed_annotation.dart';

part 'custom_field_value.freezed.dart';
part 'custom_field_value.g.dart';

@freezed
abstract class CustomFieldValue with _$CustomFieldValue {
  const CustomFieldValue._();

  const factory CustomFieldValue({
    required String id,
    required String customFieldId,
    required String memberId,
    required String value,
  }) = _CustomFieldValue;

  factory CustomFieldValue.fromJson(Map<String, dynamic> json) =>
      _$CustomFieldValueFromJson(json);
}
