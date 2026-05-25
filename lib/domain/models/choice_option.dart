import 'package:freezed_annotation/freezed_annotation.dart';

part 'choice_option.freezed.dart';
part 'choice_option.g.dart';

@freezed
abstract class ChoiceOption with _$ChoiceOption {
  const factory ChoiceOption({
    required String id, // stable UUID, never label-derived
    required String label,
    String? colorHex,
    @Default(0) int sortOrder,
    @Default(false) bool isDeleted,
  }) = _ChoiceOption;

  factory ChoiceOption.fromJson(Map<String, dynamic> json) =>
      _$ChoiceOptionFromJson(json);
}
