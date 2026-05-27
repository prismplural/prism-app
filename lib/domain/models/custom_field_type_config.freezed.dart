// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'custom_field_type_config.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
CustomFieldTypeConfig _$CustomFieldTypeConfigFromJson(
  Map<String, dynamic> json
) {
        switch (json['runtimeType']) {
                  case 'choice':
          return ChoiceConfig.fromJson(
            json
          );
                case 'group':
          return GroupConfig.fromJson(
            json
          );
                case 'scale':
          return ScaleConfig.fromJson(
            json
          );
                case 'slider':
          return SliderConfig.fromJson(
            json
          );
        
          default:
            throw CheckedFromJsonException(
  json,
  'runtimeType',
  'CustomFieldTypeConfig',
  'Invalid union type "${json['runtimeType']}"!'
);
        }
      
}

/// @nodoc
mixin _$CustomFieldTypeConfig {

@JsonKey(includeFromJson: false, includeToJson: false) Map<String, dynamic> get extra;
/// Create a copy of CustomFieldTypeConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CustomFieldTypeConfigCopyWith<CustomFieldTypeConfig> get copyWith => _$CustomFieldTypeConfigCopyWithImpl<CustomFieldTypeConfig>(this as CustomFieldTypeConfig, _$identity);

  /// Serializes this CustomFieldTypeConfig to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CustomFieldTypeConfig&&const DeepCollectionEquality().equals(other.extra, extra));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(extra));

@override
String toString() {
  return 'CustomFieldTypeConfig(extra: $extra)';
}


}

/// @nodoc
abstract mixin class $CustomFieldTypeConfigCopyWith<$Res>  {
  factory $CustomFieldTypeConfigCopyWith(CustomFieldTypeConfig value, $Res Function(CustomFieldTypeConfig) _then) = _$CustomFieldTypeConfigCopyWithImpl;
@useResult
$Res call({
@JsonKey(includeFromJson: false, includeToJson: false) Map<String, dynamic> extra
});




}
/// @nodoc
class _$CustomFieldTypeConfigCopyWithImpl<$Res>
    implements $CustomFieldTypeConfigCopyWith<$Res> {
  _$CustomFieldTypeConfigCopyWithImpl(this._self, this._then);

  final CustomFieldTypeConfig _self;
  final $Res Function(CustomFieldTypeConfig) _then;

/// Create a copy of CustomFieldTypeConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? extra = null,}) {
  return _then(_self.copyWith(
extra: null == extra ? _self.extra : extra // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}

}


/// Adds pattern-matching-related methods to [CustomFieldTypeConfig].
extension CustomFieldTypeConfigPatterns on CustomFieldTypeConfig {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ChoiceConfig value)?  choice,TResult Function( GroupConfig value)?  group,TResult Function( ScaleConfig value)?  scale,TResult Function( SliderConfig value)?  slider,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ChoiceConfig() when choice != null:
return choice(_that);case GroupConfig() when group != null:
return group(_that);case ScaleConfig() when scale != null:
return scale(_that);case SliderConfig() when slider != null:
return slider(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ChoiceConfig value)  choice,required TResult Function( GroupConfig value)  group,required TResult Function( ScaleConfig value)  scale,required TResult Function( SliderConfig value)  slider,}){
final _that = this;
switch (_that) {
case ChoiceConfig():
return choice(_that);case GroupConfig():
return group(_that);case ScaleConfig():
return scale(_that);case SliderConfig():
return slider(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ChoiceConfig value)?  choice,TResult? Function( GroupConfig value)?  group,TResult? Function( ScaleConfig value)?  scale,TResult? Function( SliderConfig value)?  slider,}){
final _that = this;
switch (_that) {
case ChoiceConfig() when choice != null:
return choice(_that);case GroupConfig() when group != null:
return group(_that);case ScaleConfig() when scale != null:
return scale(_that);case SliderConfig() when slider != null:
return slider(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( List<ChoiceOption> options,  bool allowsMultiple,  bool allowsOther, @JsonKey(includeFromJson: false, includeToJson: false)  Map<String, dynamic> extra)?  choice,TResult Function( String? icon,  bool hideTitleOnProfile, @JsonKey(includeFromJson: false, includeToJson: false)  Map<String, dynamic> extra)?  group,TResult Function( String emoji,  int steps,  List<String>? stepLabels,  DisplayLayout? displayLayout, @JsonKey(includeFromJson: false, includeToJson: false)  Map<String, dynamic> extra)?  scale,TResult Function( SliderMode mode,  String? leftLabel,  String? rightLabel,  String? centerLabel,  String? gradientPresetId,  String? leftColorHex,  String? rightColorHex,  String? centerColorHex,  bool snapToPositions,  double? min,  double? max,  double? step,  String? unit,  bool showTicks, @JsonKey(includeFromJson: false, includeToJson: false)  Map<String, dynamic> extra)?  slider,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ChoiceConfig() when choice != null:
return choice(_that.options,_that.allowsMultiple,_that.allowsOther,_that.extra);case GroupConfig() when group != null:
return group(_that.icon,_that.hideTitleOnProfile,_that.extra);case ScaleConfig() when scale != null:
return scale(_that.emoji,_that.steps,_that.stepLabels,_that.displayLayout,_that.extra);case SliderConfig() when slider != null:
return slider(_that.mode,_that.leftLabel,_that.rightLabel,_that.centerLabel,_that.gradientPresetId,_that.leftColorHex,_that.rightColorHex,_that.centerColorHex,_that.snapToPositions,_that.min,_that.max,_that.step,_that.unit,_that.showTicks,_that.extra);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( List<ChoiceOption> options,  bool allowsMultiple,  bool allowsOther, @JsonKey(includeFromJson: false, includeToJson: false)  Map<String, dynamic> extra)  choice,required TResult Function( String? icon,  bool hideTitleOnProfile, @JsonKey(includeFromJson: false, includeToJson: false)  Map<String, dynamic> extra)  group,required TResult Function( String emoji,  int steps,  List<String>? stepLabels,  DisplayLayout? displayLayout, @JsonKey(includeFromJson: false, includeToJson: false)  Map<String, dynamic> extra)  scale,required TResult Function( SliderMode mode,  String? leftLabel,  String? rightLabel,  String? centerLabel,  String? gradientPresetId,  String? leftColorHex,  String? rightColorHex,  String? centerColorHex,  bool snapToPositions,  double? min,  double? max,  double? step,  String? unit,  bool showTicks, @JsonKey(includeFromJson: false, includeToJson: false)  Map<String, dynamic> extra)  slider,}) {final _that = this;
switch (_that) {
case ChoiceConfig():
return choice(_that.options,_that.allowsMultiple,_that.allowsOther,_that.extra);case GroupConfig():
return group(_that.icon,_that.hideTitleOnProfile,_that.extra);case ScaleConfig():
return scale(_that.emoji,_that.steps,_that.stepLabels,_that.displayLayout,_that.extra);case SliderConfig():
return slider(_that.mode,_that.leftLabel,_that.rightLabel,_that.centerLabel,_that.gradientPresetId,_that.leftColorHex,_that.rightColorHex,_that.centerColorHex,_that.snapToPositions,_that.min,_that.max,_that.step,_that.unit,_that.showTicks,_that.extra);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( List<ChoiceOption> options,  bool allowsMultiple,  bool allowsOther, @JsonKey(includeFromJson: false, includeToJson: false)  Map<String, dynamic> extra)?  choice,TResult? Function( String? icon,  bool hideTitleOnProfile, @JsonKey(includeFromJson: false, includeToJson: false)  Map<String, dynamic> extra)?  group,TResult? Function( String emoji,  int steps,  List<String>? stepLabels,  DisplayLayout? displayLayout, @JsonKey(includeFromJson: false, includeToJson: false)  Map<String, dynamic> extra)?  scale,TResult? Function( SliderMode mode,  String? leftLabel,  String? rightLabel,  String? centerLabel,  String? gradientPresetId,  String? leftColorHex,  String? rightColorHex,  String? centerColorHex,  bool snapToPositions,  double? min,  double? max,  double? step,  String? unit,  bool showTicks, @JsonKey(includeFromJson: false, includeToJson: false)  Map<String, dynamic> extra)?  slider,}) {final _that = this;
switch (_that) {
case ChoiceConfig() when choice != null:
return choice(_that.options,_that.allowsMultiple,_that.allowsOther,_that.extra);case GroupConfig() when group != null:
return group(_that.icon,_that.hideTitleOnProfile,_that.extra);case ScaleConfig() when scale != null:
return scale(_that.emoji,_that.steps,_that.stepLabels,_that.displayLayout,_that.extra);case SliderConfig() when slider != null:
return slider(_that.mode,_that.leftLabel,_that.rightLabel,_that.centerLabel,_that.gradientPresetId,_that.leftColorHex,_that.rightColorHex,_that.centerColorHex,_that.snapToPositions,_that.min,_that.max,_that.step,_that.unit,_that.showTicks,_that.extra);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class ChoiceConfig implements CustomFieldTypeConfig {
  const ChoiceConfig({final  List<ChoiceOption> options = const <ChoiceOption>[], this.allowsMultiple = false, this.allowsOther = false, @JsonKey(includeFromJson: false, includeToJson: false) final  Map<String, dynamic> extra = const <String, dynamic>{}, final  String? $type}): _options = options,_extra = extra,$type = $type ?? 'choice';
  factory ChoiceConfig.fromJson(Map<String, dynamic> json) => _$ChoiceConfigFromJson(json);

 final  List<ChoiceOption> _options;
@JsonKey() List<ChoiceOption> get options {
  if (_options is EqualUnmodifiableListView) return _options;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_options);
}

@JsonKey() final  bool allowsMultiple;
@JsonKey() final  bool allowsOther;
 final  Map<String, dynamic> _extra;
@override@JsonKey(includeFromJson: false, includeToJson: false) Map<String, dynamic> get extra {
  if (_extra is EqualUnmodifiableMapView) return _extra;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_extra);
}


@JsonKey(name: 'runtimeType')
final String $type;


/// Create a copy of CustomFieldTypeConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChoiceConfigCopyWith<ChoiceConfig> get copyWith => _$ChoiceConfigCopyWithImpl<ChoiceConfig>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ChoiceConfigToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChoiceConfig&&const DeepCollectionEquality().equals(other._options, _options)&&(identical(other.allowsMultiple, allowsMultiple) || other.allowsMultiple == allowsMultiple)&&(identical(other.allowsOther, allowsOther) || other.allowsOther == allowsOther)&&const DeepCollectionEquality().equals(other._extra, _extra));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_options),allowsMultiple,allowsOther,const DeepCollectionEquality().hash(_extra));

@override
String toString() {
  return 'CustomFieldTypeConfig.choice(options: $options, allowsMultiple: $allowsMultiple, allowsOther: $allowsOther, extra: $extra)';
}


}

/// @nodoc
abstract mixin class $ChoiceConfigCopyWith<$Res> implements $CustomFieldTypeConfigCopyWith<$Res> {
  factory $ChoiceConfigCopyWith(ChoiceConfig value, $Res Function(ChoiceConfig) _then) = _$ChoiceConfigCopyWithImpl;
@override @useResult
$Res call({
 List<ChoiceOption> options, bool allowsMultiple, bool allowsOther,@JsonKey(includeFromJson: false, includeToJson: false) Map<String, dynamic> extra
});




}
/// @nodoc
class _$ChoiceConfigCopyWithImpl<$Res>
    implements $ChoiceConfigCopyWith<$Res> {
  _$ChoiceConfigCopyWithImpl(this._self, this._then);

  final ChoiceConfig _self;
  final $Res Function(ChoiceConfig) _then;

/// Create a copy of CustomFieldTypeConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? options = null,Object? allowsMultiple = null,Object? allowsOther = null,Object? extra = null,}) {
  return _then(ChoiceConfig(
options: null == options ? _self._options : options // ignore: cast_nullable_to_non_nullable
as List<ChoiceOption>,allowsMultiple: null == allowsMultiple ? _self.allowsMultiple : allowsMultiple // ignore: cast_nullable_to_non_nullable
as bool,allowsOther: null == allowsOther ? _self.allowsOther : allowsOther // ignore: cast_nullable_to_non_nullable
as bool,extra: null == extra ? _self._extra : extra // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}


}

/// @nodoc
@JsonSerializable()

class GroupConfig implements CustomFieldTypeConfig {
  const GroupConfig({this.icon, this.hideTitleOnProfile = false, @JsonKey(includeFromJson: false, includeToJson: false) final  Map<String, dynamic> extra = const <String, dynamic>{}, final  String? $type}): _extra = extra,$type = $type ?? 'group';
  factory GroupConfig.fromJson(Map<String, dynamic> json) => _$GroupConfigFromJson(json);

 final  String? icon;
@JsonKey() final  bool hideTitleOnProfile;
 final  Map<String, dynamic> _extra;
@override@JsonKey(includeFromJson: false, includeToJson: false) Map<String, dynamic> get extra {
  if (_extra is EqualUnmodifiableMapView) return _extra;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_extra);
}


@JsonKey(name: 'runtimeType')
final String $type;


/// Create a copy of CustomFieldTypeConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GroupConfigCopyWith<GroupConfig> get copyWith => _$GroupConfigCopyWithImpl<GroupConfig>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$GroupConfigToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GroupConfig&&(identical(other.icon, icon) || other.icon == icon)&&(identical(other.hideTitleOnProfile, hideTitleOnProfile) || other.hideTitleOnProfile == hideTitleOnProfile)&&const DeepCollectionEquality().equals(other._extra, _extra));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,icon,hideTitleOnProfile,const DeepCollectionEquality().hash(_extra));

@override
String toString() {
  return 'CustomFieldTypeConfig.group(icon: $icon, hideTitleOnProfile: $hideTitleOnProfile, extra: $extra)';
}


}

/// @nodoc
abstract mixin class $GroupConfigCopyWith<$Res> implements $CustomFieldTypeConfigCopyWith<$Res> {
  factory $GroupConfigCopyWith(GroupConfig value, $Res Function(GroupConfig) _then) = _$GroupConfigCopyWithImpl;
@override @useResult
$Res call({
 String? icon, bool hideTitleOnProfile,@JsonKey(includeFromJson: false, includeToJson: false) Map<String, dynamic> extra
});




}
/// @nodoc
class _$GroupConfigCopyWithImpl<$Res>
    implements $GroupConfigCopyWith<$Res> {
  _$GroupConfigCopyWithImpl(this._self, this._then);

  final GroupConfig _self;
  final $Res Function(GroupConfig) _then;

/// Create a copy of CustomFieldTypeConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? icon = freezed,Object? hideTitleOnProfile = null,Object? extra = null,}) {
  return _then(GroupConfig(
icon: freezed == icon ? _self.icon : icon // ignore: cast_nullable_to_non_nullable
as String?,hideTitleOnProfile: null == hideTitleOnProfile ? _self.hideTitleOnProfile : hideTitleOnProfile // ignore: cast_nullable_to_non_nullable
as bool,extra: null == extra ? _self._extra : extra // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}


}

/// @nodoc
@JsonSerializable()

class ScaleConfig implements CustomFieldTypeConfig {
  const ScaleConfig({this.emoji = '⭐', this.steps = 5, final  List<String>? stepLabels, this.displayLayout, @JsonKey(includeFromJson: false, includeToJson: false) final  Map<String, dynamic> extra = const <String, dynamic>{}, final  String? $type}): _stepLabels = stepLabels,_extra = extra,$type = $type ?? 'scale';
  factory ScaleConfig.fromJson(Map<String, dynamic> json) => _$ScaleConfigFromJson(json);

@JsonKey() final  String emoji;
@JsonKey() final  int steps;
 final  List<String>? _stepLabels;
 List<String>? get stepLabels {
  final value = _stepLabels;
  if (value == null) return null;
  if (_stepLabels is EqualUnmodifiableListView) return _stepLabels;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

 final  DisplayLayout? displayLayout;
 final  Map<String, dynamic> _extra;
@override@JsonKey(includeFromJson: false, includeToJson: false) Map<String, dynamic> get extra {
  if (_extra is EqualUnmodifiableMapView) return _extra;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_extra);
}


@JsonKey(name: 'runtimeType')
final String $type;


/// Create a copy of CustomFieldTypeConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ScaleConfigCopyWith<ScaleConfig> get copyWith => _$ScaleConfigCopyWithImpl<ScaleConfig>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ScaleConfigToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ScaleConfig&&(identical(other.emoji, emoji) || other.emoji == emoji)&&(identical(other.steps, steps) || other.steps == steps)&&const DeepCollectionEquality().equals(other._stepLabels, _stepLabels)&&(identical(other.displayLayout, displayLayout) || other.displayLayout == displayLayout)&&const DeepCollectionEquality().equals(other._extra, _extra));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,emoji,steps,const DeepCollectionEquality().hash(_stepLabels),displayLayout,const DeepCollectionEquality().hash(_extra));

@override
String toString() {
  return 'CustomFieldTypeConfig.scale(emoji: $emoji, steps: $steps, stepLabels: $stepLabels, displayLayout: $displayLayout, extra: $extra)';
}


}

/// @nodoc
abstract mixin class $ScaleConfigCopyWith<$Res> implements $CustomFieldTypeConfigCopyWith<$Res> {
  factory $ScaleConfigCopyWith(ScaleConfig value, $Res Function(ScaleConfig) _then) = _$ScaleConfigCopyWithImpl;
@override @useResult
$Res call({
 String emoji, int steps, List<String>? stepLabels, DisplayLayout? displayLayout,@JsonKey(includeFromJson: false, includeToJson: false) Map<String, dynamic> extra
});




}
/// @nodoc
class _$ScaleConfigCopyWithImpl<$Res>
    implements $ScaleConfigCopyWith<$Res> {
  _$ScaleConfigCopyWithImpl(this._self, this._then);

  final ScaleConfig _self;
  final $Res Function(ScaleConfig) _then;

/// Create a copy of CustomFieldTypeConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? emoji = null,Object? steps = null,Object? stepLabels = freezed,Object? displayLayout = freezed,Object? extra = null,}) {
  return _then(ScaleConfig(
emoji: null == emoji ? _self.emoji : emoji // ignore: cast_nullable_to_non_nullable
as String,steps: null == steps ? _self.steps : steps // ignore: cast_nullable_to_non_nullable
as int,stepLabels: freezed == stepLabels ? _self._stepLabels : stepLabels // ignore: cast_nullable_to_non_nullable
as List<String>?,displayLayout: freezed == displayLayout ? _self.displayLayout : displayLayout // ignore: cast_nullable_to_non_nullable
as DisplayLayout?,extra: null == extra ? _self._extra : extra // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}


}

/// @nodoc
@JsonSerializable()

class SliderConfig implements CustomFieldTypeConfig {
  const SliderConfig({required this.mode, this.leftLabel, this.rightLabel, this.centerLabel, this.gradientPresetId, this.leftColorHex, this.rightColorHex, this.centerColorHex, this.snapToPositions = false, this.min, this.max, this.step, this.unit, this.showTicks = false, @JsonKey(includeFromJson: false, includeToJson: false) final  Map<String, dynamic> extra = const <String, dynamic>{}, final  String? $type}): _extra = extra,$type = $type ?? 'slider';
  factory SliderConfig.fromJson(Map<String, dynamic> json) => _$SliderConfigFromJson(json);

 final  SliderMode mode;
 final  String? leftLabel;
 final  String? rightLabel;
 final  String? centerLabel;
 final  String? gradientPresetId;
 final  String? leftColorHex;
 final  String? rightColorHex;
 final  String? centerColorHex;
@JsonKey() final  bool snapToPositions;
 final  double? min;
 final  double? max;
 final  double? step;
 final  String? unit;
@JsonKey() final  bool showTicks;
 final  Map<String, dynamic> _extra;
@override@JsonKey(includeFromJson: false, includeToJson: false) Map<String, dynamic> get extra {
  if (_extra is EqualUnmodifiableMapView) return _extra;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_extra);
}


@JsonKey(name: 'runtimeType')
final String $type;


/// Create a copy of CustomFieldTypeConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SliderConfigCopyWith<SliderConfig> get copyWith => _$SliderConfigCopyWithImpl<SliderConfig>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SliderConfigToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SliderConfig&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.leftLabel, leftLabel) || other.leftLabel == leftLabel)&&(identical(other.rightLabel, rightLabel) || other.rightLabel == rightLabel)&&(identical(other.centerLabel, centerLabel) || other.centerLabel == centerLabel)&&(identical(other.gradientPresetId, gradientPresetId) || other.gradientPresetId == gradientPresetId)&&(identical(other.leftColorHex, leftColorHex) || other.leftColorHex == leftColorHex)&&(identical(other.rightColorHex, rightColorHex) || other.rightColorHex == rightColorHex)&&(identical(other.centerColorHex, centerColorHex) || other.centerColorHex == centerColorHex)&&(identical(other.snapToPositions, snapToPositions) || other.snapToPositions == snapToPositions)&&(identical(other.min, min) || other.min == min)&&(identical(other.max, max) || other.max == max)&&(identical(other.step, step) || other.step == step)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.showTicks, showTicks) || other.showTicks == showTicks)&&const DeepCollectionEquality().equals(other._extra, _extra));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,mode,leftLabel,rightLabel,centerLabel,gradientPresetId,leftColorHex,rightColorHex,centerColorHex,snapToPositions,min,max,step,unit,showTicks,const DeepCollectionEquality().hash(_extra));

@override
String toString() {
  return 'CustomFieldTypeConfig.slider(mode: $mode, leftLabel: $leftLabel, rightLabel: $rightLabel, centerLabel: $centerLabel, gradientPresetId: $gradientPresetId, leftColorHex: $leftColorHex, rightColorHex: $rightColorHex, centerColorHex: $centerColorHex, snapToPositions: $snapToPositions, min: $min, max: $max, step: $step, unit: $unit, showTicks: $showTicks, extra: $extra)';
}


}

/// @nodoc
abstract mixin class $SliderConfigCopyWith<$Res> implements $CustomFieldTypeConfigCopyWith<$Res> {
  factory $SliderConfigCopyWith(SliderConfig value, $Res Function(SliderConfig) _then) = _$SliderConfigCopyWithImpl;
@override @useResult
$Res call({
 SliderMode mode, String? leftLabel, String? rightLabel, String? centerLabel, String? gradientPresetId, String? leftColorHex, String? rightColorHex, String? centerColorHex, bool snapToPositions, double? min, double? max, double? step, String? unit, bool showTicks,@JsonKey(includeFromJson: false, includeToJson: false) Map<String, dynamic> extra
});




}
/// @nodoc
class _$SliderConfigCopyWithImpl<$Res>
    implements $SliderConfigCopyWith<$Res> {
  _$SliderConfigCopyWithImpl(this._self, this._then);

  final SliderConfig _self;
  final $Res Function(SliderConfig) _then;

/// Create a copy of CustomFieldTypeConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? mode = null,Object? leftLabel = freezed,Object? rightLabel = freezed,Object? centerLabel = freezed,Object? gradientPresetId = freezed,Object? leftColorHex = freezed,Object? rightColorHex = freezed,Object? centerColorHex = freezed,Object? snapToPositions = null,Object? min = freezed,Object? max = freezed,Object? step = freezed,Object? unit = freezed,Object? showTicks = null,Object? extra = null,}) {
  return _then(SliderConfig(
mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as SliderMode,leftLabel: freezed == leftLabel ? _self.leftLabel : leftLabel // ignore: cast_nullable_to_non_nullable
as String?,rightLabel: freezed == rightLabel ? _self.rightLabel : rightLabel // ignore: cast_nullable_to_non_nullable
as String?,centerLabel: freezed == centerLabel ? _self.centerLabel : centerLabel // ignore: cast_nullable_to_non_nullable
as String?,gradientPresetId: freezed == gradientPresetId ? _self.gradientPresetId : gradientPresetId // ignore: cast_nullable_to_non_nullable
as String?,leftColorHex: freezed == leftColorHex ? _self.leftColorHex : leftColorHex // ignore: cast_nullable_to_non_nullable
as String?,rightColorHex: freezed == rightColorHex ? _self.rightColorHex : rightColorHex // ignore: cast_nullable_to_non_nullable
as String?,centerColorHex: freezed == centerColorHex ? _self.centerColorHex : centerColorHex // ignore: cast_nullable_to_non_nullable
as String?,snapToPositions: null == snapToPositions ? _self.snapToPositions : snapToPositions // ignore: cast_nullable_to_non_nullable
as bool,min: freezed == min ? _self.min : min // ignore: cast_nullable_to_non_nullable
as double?,max: freezed == max ? _self.max : max // ignore: cast_nullable_to_non_nullable
as double?,step: freezed == step ? _self.step : step // ignore: cast_nullable_to_non_nullable
as double?,unit: freezed == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as String?,showTicks: null == showTicks ? _self.showTicks : showTicks // ignore: cast_nullable_to_non_nullable
as bool,extra: null == extra ? _self._extra : extra // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}


}

// dart format on
