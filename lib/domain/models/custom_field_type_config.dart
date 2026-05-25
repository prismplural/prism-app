import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:prism_plurality/domain/models/choice_option.dart';

part 'custom_field_type_config.freezed.dart';
part 'custom_field_type_config.g.dart';

enum SliderMode { labeled, numeric }

/// Type-specific config for new custom field types (choice, group, scale, slider).
///
/// Legacy types (text, color, date, longText) do NOT get a variant — their
/// `typeConfigJson` column stays NULL in storage.
///
/// Serialization caveat: plain freezed JSON drops unknown top-level keys.
/// Use [CustomFieldTypeConfigCodec] (see below) — NOT [_$CustomFieldTypeConfigFromJson]
/// directly — so forward-compat unknown keys are captured into `extra` and re-emitted.
@freezed
sealed class CustomFieldTypeConfig with _$CustomFieldTypeConfig {
  const factory CustomFieldTypeConfig.choice({
    @Default(<ChoiceOption>[]) List<ChoiceOption> options,
    @Default(false) bool allowsMultiple,
    @Default(false) bool allowsOther,
    @Default(<String, dynamic>{})
    @JsonKey(includeFromJson: false, includeToJson: false)
    Map<String, dynamic> extra,
  }) = ChoiceConfig;

  const factory CustomFieldTypeConfig.group({
    String? icon,
    @Default(<String, dynamic>{})
    @JsonKey(includeFromJson: false, includeToJson: false)
    Map<String, dynamic> extra,
  }) = GroupConfig;

  const factory CustomFieldTypeConfig.scale({
    @Default('⭐') String emoji,
    @Default(5) int steps,
    List<String>? stepLabels,
    @Default(<String, dynamic>{})
    @JsonKey(includeFromJson: false, includeToJson: false)
    Map<String, dynamic> extra,
  }) = ScaleConfig;

  const factory CustomFieldTypeConfig.slider({
    required SliderMode mode,
    String? leftLabel,
    String? rightLabel,
    String? centerLabel,
    String? gradientPresetId,
    String? leftColorHex,
    String? rightColorHex,
    String? centerColorHex,
    @Default(true) bool snapToPositions,
    double? min,
    double? max,
    double? step,
    String? unit,
    @Default(false) bool showTicks,
    @Default(<String, dynamic>{})
    @JsonKey(includeFromJson: false, includeToJson: false)
    Map<String, dynamic> extra,
  }) = SliderConfig;

  factory CustomFieldTypeConfig.fromJson(Map<String, dynamic> json) =>
      _$CustomFieldTypeConfigFromJson(json);
}

/// Wrapper around [CustomFieldTypeConfig]'s generated JSON that preserves
/// unknown top-level keys for forward-compat (whole-config LWW).
///
/// IMPORTANT: Always use this class — NOT freezed's generated fromJson/toJson
/// directly — so v28 readers never silently drop config fields added by future
/// versions. This is the single sanctioned entry point for JSON ↔ sealed config.
class CustomFieldTypeConfigCodec {
  CustomFieldTypeConfigCodec._();

  /// Decode a JSON object into the sealed variant. Any top-level keys not
  /// recognized by the matched variant are captured into the variant's `extra` map.
  static CustomFieldTypeConfig fromJson(Map<String, dynamic> json) {
    final config = CustomFieldTypeConfig.fromJson(json);
    final known = _knownKeysFor(config);
    final extra = <String, dynamic>{};
    for (final entry in json.entries) {
      if (entry.key == 'runtimeType') continue;
      if (!known.contains(entry.key)) {
        extra[entry.key] = entry.value;
      }
    }
    if (extra.isEmpty) return config;
    return switch (config) {
      ChoiceConfig c => c.copyWith(extra: extra),
      GroupConfig c => c.copyWith(extra: extra),
      ScaleConfig c => c.copyWith(extra: extra),
      SliderConfig c => c.copyWith(extra: extra),
    };
  }

  /// Encode the sealed variant to JSON. The variant's `extra` map is merged
  /// back at the top level so unknown forward-compat keys re-emit intact.
  ///
  /// Note: nested [ChoiceOption] objects are explicitly serialized via their
  /// own `toJson()` so the result is a plain `Map<String, dynamic>` that can
  /// be safely passed back into [fromJson] without a jsonEncode/jsonDecode
  /// round-trip.
  static Map<String, dynamic> toJson(CustomFieldTypeConfig config) {
    final base = _toJsonDeep(config);
    final extra = switch (config) {
      ChoiceConfig c => c.extra,
      GroupConfig c => c.extra,
      ScaleConfig c => c.extra,
      SliderConfig c => c.extra,
    };
    if (extra.isEmpty) return base;
    return {...base, ...extra};
  }

  /// Produces a fully serialized map (all nested objects converted to maps).
  static Map<String, dynamic> _toJsonDeep(CustomFieldTypeConfig config) {
    return switch (config) {
      ChoiceConfig c => {
        ...c.toJson(),
        'options': c.options.map((o) => o.toJson()).toList(),
      },
      // GroupConfig, ScaleConfig, SliderConfig have no nested freezed objects.
      GroupConfig _ => config.toJson(),
      ScaleConfig _ => config.toJson(),
      SliderConfig _ => config.toJson(),
    };
  }

  /// Known top-level keys for the matched variant (everything else goes in extra).
  /// Update this when adding new fields to a variant.
  static Set<String> _knownKeysFor(CustomFieldTypeConfig config) {
    return switch (config) {
      ChoiceConfig _ => const {'runtimeType', 'options', 'allowsMultiple', 'allowsOther'},
      GroupConfig _ => const {'runtimeType', 'icon'},
      ScaleConfig _ => const {'runtimeType', 'emoji', 'steps', 'stepLabels'},
      SliderConfig _ => const {
        'runtimeType',
        'mode',
        'leftLabel',
        'rightLabel',
        'centerLabel',
        'gradientPresetId',
        'leftColorHex',
        'rightColorHex',
        'centerColorHex',
        'snapToPositions',
        'min',
        'max',
        'step',
        'unit',
        'showTicks',
      },
    };
  }
}
