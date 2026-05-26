// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'custom_field_type_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ChoiceConfig _$ChoiceConfigFromJson(Map<String, dynamic> json) => ChoiceConfig(
  options:
      (json['options'] as List<dynamic>?)
          ?.map((e) => ChoiceOption.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <ChoiceOption>[],
  allowsMultiple: json['allowsMultiple'] as bool? ?? false,
  allowsOther: json['allowsOther'] as bool? ?? false,
  $type: json['runtimeType'] as String?,
);

Map<String, dynamic> _$ChoiceConfigToJson(ChoiceConfig instance) =>
    <String, dynamic>{
      'options': instance.options,
      'allowsMultiple': instance.allowsMultiple,
      'allowsOther': instance.allowsOther,
      'runtimeType': instance.$type,
    };

GroupConfig _$GroupConfigFromJson(Map<String, dynamic> json) => GroupConfig(
  icon: json['icon'] as String?,
  hideTitleOnProfile: json['hideTitleOnProfile'] as bool? ?? false,
  $type: json['runtimeType'] as String?,
);

Map<String, dynamic> _$GroupConfigToJson(GroupConfig instance) =>
    <String, dynamic>{
      'icon': instance.icon,
      'hideTitleOnProfile': instance.hideTitleOnProfile,
      'runtimeType': instance.$type,
    };

ScaleConfig _$ScaleConfigFromJson(Map<String, dynamic> json) => ScaleConfig(
  emoji: json['emoji'] as String? ?? '⭐',
  steps: (json['steps'] as num?)?.toInt() ?? 5,
  stepLabels: (json['stepLabels'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  $type: json['runtimeType'] as String?,
);

Map<String, dynamic> _$ScaleConfigToJson(ScaleConfig instance) =>
    <String, dynamic>{
      'emoji': instance.emoji,
      'steps': instance.steps,
      'stepLabels': instance.stepLabels,
      'runtimeType': instance.$type,
    };

SliderConfig _$SliderConfigFromJson(Map<String, dynamic> json) => SliderConfig(
  mode: $enumDecode(_$SliderModeEnumMap, json['mode']),
  leftLabel: json['leftLabel'] as String?,
  rightLabel: json['rightLabel'] as String?,
  centerLabel: json['centerLabel'] as String?,
  gradientPresetId: json['gradientPresetId'] as String?,
  leftColorHex: json['leftColorHex'] as String?,
  rightColorHex: json['rightColorHex'] as String?,
  centerColorHex: json['centerColorHex'] as String?,
  snapToPositions: json['snapToPositions'] as bool? ?? false,
  min: (json['min'] as num?)?.toDouble(),
  max: (json['max'] as num?)?.toDouble(),
  step: (json['step'] as num?)?.toDouble(),
  unit: json['unit'] as String?,
  showTicks: json['showTicks'] as bool? ?? false,
  $type: json['runtimeType'] as String?,
);

Map<String, dynamic> _$SliderConfigToJson(SliderConfig instance) =>
    <String, dynamic>{
      'mode': _$SliderModeEnumMap[instance.mode]!,
      'leftLabel': instance.leftLabel,
      'rightLabel': instance.rightLabel,
      'centerLabel': instance.centerLabel,
      'gradientPresetId': instance.gradientPresetId,
      'leftColorHex': instance.leftColorHex,
      'rightColorHex': instance.rightColorHex,
      'centerColorHex': instance.centerColorHex,
      'snapToPositions': instance.snapToPositions,
      'min': instance.min,
      'max': instance.max,
      'step': instance.step,
      'unit': instance.unit,
      'showTicks': instance.showTicks,
      'runtimeType': instance.$type,
    };

const _$SliderModeEnumMap = {
  SliderMode.labeled: 'labeled',
  SliderMode.numeric: 'numeric',
};
