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
    @Default(<String, dynamic>{})
    @JsonKey(includeFromJson: false, includeToJson: false)
    Map<String, dynamic> extra,
  }) = _ChoiceOption;

  factory ChoiceOption.fromJson(Map<String, dynamic> json) =>
      _$ChoiceOptionFromJson(json);
}

/// Wrapper around [ChoiceOption]'s generated JSON that preserves unknown
/// keys for forward-compat. Mirrors [CustomFieldTypeConfigCodec] so a v28
/// device never silently drops keys added by future versions of the option
/// shape (e.g. `iconKey`, `description`).
///
/// Always use this — NOT freezed's generated fromJson/toJson directly — when
/// serializing options inside a [ChoiceConfig]. The top-level
/// [CustomFieldTypeConfigCodec] calls into this for every nested option so
/// forward-compat is uniform between the variant and its nested options.
class ChoiceOptionCodec {
  ChoiceOptionCodec._();

  /// Top-level keys known to [ChoiceOption]. Everything else goes into [extra].
  static const Set<String> _knownKeys = {
    'id',
    'label',
    'colorHex',
    'sortOrder',
    'isDeleted',
  };

  /// Decode a JSON object into a [ChoiceOption]. Any keys not in [_knownKeys]
  /// are captured into the option's [extra] map.
  static ChoiceOption fromJson(Map<String, dynamic> json) {
    final option = ChoiceOption.fromJson(json);
    final extra = <String, dynamic>{};
    for (final entry in json.entries) {
      if (!_knownKeys.contains(entry.key)) {
        extra[entry.key] = entry.value;
      }
    }
    if (extra.isEmpty) return option;
    return option.copyWith(extra: extra);
  }

  /// Encode the option to JSON. Known keys come from the generated `toJson`;
  /// any [extra] keys are merged on top, sorted alphabetically for stable
  /// byte-order across read→write cycles (no phantom sync emits).
  static Map<String, dynamic> toJson(ChoiceOption option) {
    final base = option.toJson();
    if (option.extra.isEmpty) return base;
    final sortedExtraKeys = option.extra.keys.toList()..sort();
    final out = <String, dynamic>{...base};
    for (final key in sortedExtraKeys) {
      out[key] = option.extra[key];
    }
    return out;
  }
}
