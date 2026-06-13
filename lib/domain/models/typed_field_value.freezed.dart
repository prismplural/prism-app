// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'typed_field_value.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TypedFieldValue {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TypedFieldValue);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TypedFieldValue()';
}


}

/// @nodoc
class $TypedFieldValueCopyWith<$Res>  {
$TypedFieldValueCopyWith(TypedFieldValue _, $Res Function(TypedFieldValue) __);
}


/// Adds pattern-matching-related methods to [TypedFieldValue].
extension TypedFieldValuePatterns on TypedFieldValue {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( TextFieldValue value)?  text,TResult Function( LongTextFieldValue value)?  longText,TResult Function( ColorFieldValue value)?  color,TResult Function( DateFieldValue value)?  date,TResult Function( ChoiceFieldValue value)?  choice,TResult Function( ScaleFieldValue value)?  scale,TResult Function( SliderFieldValue value)?  slider,TResult Function( MemberFieldValue value)?  member,TResult Function( UnsupportedFieldValue value)?  unsupported,required TResult orElse(),}){
final _that = this;
switch (_that) {
case TextFieldValue() when text != null:
return text(_that);case LongTextFieldValue() when longText != null:
return longText(_that);case ColorFieldValue() when color != null:
return color(_that);case DateFieldValue() when date != null:
return date(_that);case ChoiceFieldValue() when choice != null:
return choice(_that);case ScaleFieldValue() when scale != null:
return scale(_that);case SliderFieldValue() when slider != null:
return slider(_that);case MemberFieldValue() when member != null:
return member(_that);case UnsupportedFieldValue() when unsupported != null:
return unsupported(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( TextFieldValue value)  text,required TResult Function( LongTextFieldValue value)  longText,required TResult Function( ColorFieldValue value)  color,required TResult Function( DateFieldValue value)  date,required TResult Function( ChoiceFieldValue value)  choice,required TResult Function( ScaleFieldValue value)  scale,required TResult Function( SliderFieldValue value)  slider,required TResult Function( MemberFieldValue value)  member,required TResult Function( UnsupportedFieldValue value)  unsupported,}){
final _that = this;
switch (_that) {
case TextFieldValue():
return text(_that);case LongTextFieldValue():
return longText(_that);case ColorFieldValue():
return color(_that);case DateFieldValue():
return date(_that);case ChoiceFieldValue():
return choice(_that);case ScaleFieldValue():
return scale(_that);case SliderFieldValue():
return slider(_that);case MemberFieldValue():
return member(_that);case UnsupportedFieldValue():
return unsupported(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( TextFieldValue value)?  text,TResult? Function( LongTextFieldValue value)?  longText,TResult? Function( ColorFieldValue value)?  color,TResult? Function( DateFieldValue value)?  date,TResult? Function( ChoiceFieldValue value)?  choice,TResult? Function( ScaleFieldValue value)?  scale,TResult? Function( SliderFieldValue value)?  slider,TResult? Function( MemberFieldValue value)?  member,TResult? Function( UnsupportedFieldValue value)?  unsupported,}){
final _that = this;
switch (_that) {
case TextFieldValue() when text != null:
return text(_that);case LongTextFieldValue() when longText != null:
return longText(_that);case ColorFieldValue() when color != null:
return color(_that);case DateFieldValue() when date != null:
return date(_that);case ChoiceFieldValue() when choice != null:
return choice(_that);case ScaleFieldValue() when scale != null:
return scale(_that);case SliderFieldValue() when slider != null:
return slider(_that);case MemberFieldValue() when member != null:
return member(_that);case UnsupportedFieldValue() when unsupported != null:
return unsupported(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String value)?  text,TResult Function( String value)?  longText,TResult Function( String? hex)?  color,TResult Function( DateTime? value)?  date,TResult Function( Set<String> optionIds,  String? other)?  choice,TResult Function( int? step)?  scale,TResult Function( double? value)?  slider,TResult Function( Set<String> memberIds,  Map<String, dynamic> extra)?  member,TResult Function( String raw)?  unsupported,required TResult orElse(),}) {final _that = this;
switch (_that) {
case TextFieldValue() when text != null:
return text(_that.value);case LongTextFieldValue() when longText != null:
return longText(_that.value);case ColorFieldValue() when color != null:
return color(_that.hex);case DateFieldValue() when date != null:
return date(_that.value);case ChoiceFieldValue() when choice != null:
return choice(_that.optionIds,_that.other);case ScaleFieldValue() when scale != null:
return scale(_that.step);case SliderFieldValue() when slider != null:
return slider(_that.value);case MemberFieldValue() when member != null:
return member(_that.memberIds,_that.extra);case UnsupportedFieldValue() when unsupported != null:
return unsupported(_that.raw);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String value)  text,required TResult Function( String value)  longText,required TResult Function( String? hex)  color,required TResult Function( DateTime? value)  date,required TResult Function( Set<String> optionIds,  String? other)  choice,required TResult Function( int? step)  scale,required TResult Function( double? value)  slider,required TResult Function( Set<String> memberIds,  Map<String, dynamic> extra)  member,required TResult Function( String raw)  unsupported,}) {final _that = this;
switch (_that) {
case TextFieldValue():
return text(_that.value);case LongTextFieldValue():
return longText(_that.value);case ColorFieldValue():
return color(_that.hex);case DateFieldValue():
return date(_that.value);case ChoiceFieldValue():
return choice(_that.optionIds,_that.other);case ScaleFieldValue():
return scale(_that.step);case SliderFieldValue():
return slider(_that.value);case MemberFieldValue():
return member(_that.memberIds,_that.extra);case UnsupportedFieldValue():
return unsupported(_that.raw);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String value)?  text,TResult? Function( String value)?  longText,TResult? Function( String? hex)?  color,TResult? Function( DateTime? value)?  date,TResult? Function( Set<String> optionIds,  String? other)?  choice,TResult? Function( int? step)?  scale,TResult? Function( double? value)?  slider,TResult? Function( Set<String> memberIds,  Map<String, dynamic> extra)?  member,TResult? Function( String raw)?  unsupported,}) {final _that = this;
switch (_that) {
case TextFieldValue() when text != null:
return text(_that.value);case LongTextFieldValue() when longText != null:
return longText(_that.value);case ColorFieldValue() when color != null:
return color(_that.hex);case DateFieldValue() when date != null:
return date(_that.value);case ChoiceFieldValue() when choice != null:
return choice(_that.optionIds,_that.other);case ScaleFieldValue() when scale != null:
return scale(_that.step);case SliderFieldValue() when slider != null:
return slider(_that.value);case MemberFieldValue() when member != null:
return member(_that.memberIds,_that.extra);case UnsupportedFieldValue() when unsupported != null:
return unsupported(_that.raw);case _:
  return null;

}
}

}

/// @nodoc


class TextFieldValue implements TypedFieldValue {
  const TextFieldValue(this.value);
  

 final  String value;

/// Create a copy of TypedFieldValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TextFieldValueCopyWith<TextFieldValue> get copyWith => _$TextFieldValueCopyWithImpl<TextFieldValue>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TextFieldValue&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'TypedFieldValue.text(value: $value)';
}


}

/// @nodoc
abstract mixin class $TextFieldValueCopyWith<$Res> implements $TypedFieldValueCopyWith<$Res> {
  factory $TextFieldValueCopyWith(TextFieldValue value, $Res Function(TextFieldValue) _then) = _$TextFieldValueCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$TextFieldValueCopyWithImpl<$Res>
    implements $TextFieldValueCopyWith<$Res> {
  _$TextFieldValueCopyWithImpl(this._self, this._then);

  final TextFieldValue _self;
  final $Res Function(TextFieldValue) _then;

/// Create a copy of TypedFieldValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(TextFieldValue(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class LongTextFieldValue implements TypedFieldValue {
  const LongTextFieldValue(this.value);
  

 final  String value;

/// Create a copy of TypedFieldValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LongTextFieldValueCopyWith<LongTextFieldValue> get copyWith => _$LongTextFieldValueCopyWithImpl<LongTextFieldValue>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LongTextFieldValue&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'TypedFieldValue.longText(value: $value)';
}


}

/// @nodoc
abstract mixin class $LongTextFieldValueCopyWith<$Res> implements $TypedFieldValueCopyWith<$Res> {
  factory $LongTextFieldValueCopyWith(LongTextFieldValue value, $Res Function(LongTextFieldValue) _then) = _$LongTextFieldValueCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$LongTextFieldValueCopyWithImpl<$Res>
    implements $LongTextFieldValueCopyWith<$Res> {
  _$LongTextFieldValueCopyWithImpl(this._self, this._then);

  final LongTextFieldValue _self;
  final $Res Function(LongTextFieldValue) _then;

/// Create a copy of TypedFieldValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(LongTextFieldValue(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ColorFieldValue implements TypedFieldValue {
  const ColorFieldValue({this.hex});
  

 final  String? hex;

/// Create a copy of TypedFieldValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ColorFieldValueCopyWith<ColorFieldValue> get copyWith => _$ColorFieldValueCopyWithImpl<ColorFieldValue>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ColorFieldValue&&(identical(other.hex, hex) || other.hex == hex));
}


@override
int get hashCode => Object.hash(runtimeType,hex);

@override
String toString() {
  return 'TypedFieldValue.color(hex: $hex)';
}


}

/// @nodoc
abstract mixin class $ColorFieldValueCopyWith<$Res> implements $TypedFieldValueCopyWith<$Res> {
  factory $ColorFieldValueCopyWith(ColorFieldValue value, $Res Function(ColorFieldValue) _then) = _$ColorFieldValueCopyWithImpl;
@useResult
$Res call({
 String? hex
});




}
/// @nodoc
class _$ColorFieldValueCopyWithImpl<$Res>
    implements $ColorFieldValueCopyWith<$Res> {
  _$ColorFieldValueCopyWithImpl(this._self, this._then);

  final ColorFieldValue _self;
  final $Res Function(ColorFieldValue) _then;

/// Create a copy of TypedFieldValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? hex = freezed,}) {
  return _then(ColorFieldValue(
hex: freezed == hex ? _self.hex : hex // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class DateFieldValue implements TypedFieldValue {
  const DateFieldValue({this.value});
  

 final  DateTime? value;

/// Create a copy of TypedFieldValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DateFieldValueCopyWith<DateFieldValue> get copyWith => _$DateFieldValueCopyWithImpl<DateFieldValue>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DateFieldValue&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'TypedFieldValue.date(value: $value)';
}


}

/// @nodoc
abstract mixin class $DateFieldValueCopyWith<$Res> implements $TypedFieldValueCopyWith<$Res> {
  factory $DateFieldValueCopyWith(DateFieldValue value, $Res Function(DateFieldValue) _then) = _$DateFieldValueCopyWithImpl;
@useResult
$Res call({
 DateTime? value
});




}
/// @nodoc
class _$DateFieldValueCopyWithImpl<$Res>
    implements $DateFieldValueCopyWith<$Res> {
  _$DateFieldValueCopyWithImpl(this._self, this._then);

  final DateFieldValue _self;
  final $Res Function(DateFieldValue) _then;

/// Create a copy of TypedFieldValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = freezed,}) {
  return _then(DateFieldValue(
value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

/// @nodoc


class ChoiceFieldValue implements TypedFieldValue {
  const ChoiceFieldValue({final  Set<String> optionIds = const <String>{}, this.other}): _optionIds = optionIds;
  

 final  Set<String> _optionIds;
@JsonKey() Set<String> get optionIds {
  if (_optionIds is EqualUnmodifiableSetView) return _optionIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_optionIds);
}

 final  String? other;

/// Create a copy of TypedFieldValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChoiceFieldValueCopyWith<ChoiceFieldValue> get copyWith => _$ChoiceFieldValueCopyWithImpl<ChoiceFieldValue>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChoiceFieldValue&&const DeepCollectionEquality().equals(other._optionIds, _optionIds)&&(identical(other.other, this.other) || other.other == this.other));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_optionIds),other);

@override
String toString() {
  return 'TypedFieldValue.choice(optionIds: $optionIds, other: $other)';
}


}

/// @nodoc
abstract mixin class $ChoiceFieldValueCopyWith<$Res> implements $TypedFieldValueCopyWith<$Res> {
  factory $ChoiceFieldValueCopyWith(ChoiceFieldValue value, $Res Function(ChoiceFieldValue) _then) = _$ChoiceFieldValueCopyWithImpl;
@useResult
$Res call({
 Set<String> optionIds, String? other
});




}
/// @nodoc
class _$ChoiceFieldValueCopyWithImpl<$Res>
    implements $ChoiceFieldValueCopyWith<$Res> {
  _$ChoiceFieldValueCopyWithImpl(this._self, this._then);

  final ChoiceFieldValue _self;
  final $Res Function(ChoiceFieldValue) _then;

/// Create a copy of TypedFieldValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? optionIds = null,Object? other = freezed,}) {
  return _then(ChoiceFieldValue(
optionIds: null == optionIds ? _self._optionIds : optionIds // ignore: cast_nullable_to_non_nullable
as Set<String>,other: freezed == other ? _self.other : other // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class ScaleFieldValue implements TypedFieldValue {
  const ScaleFieldValue({this.step});
  

 final  int? step;

/// Create a copy of TypedFieldValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ScaleFieldValueCopyWith<ScaleFieldValue> get copyWith => _$ScaleFieldValueCopyWithImpl<ScaleFieldValue>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ScaleFieldValue&&(identical(other.step, step) || other.step == step));
}


@override
int get hashCode => Object.hash(runtimeType,step);

@override
String toString() {
  return 'TypedFieldValue.scale(step: $step)';
}


}

/// @nodoc
abstract mixin class $ScaleFieldValueCopyWith<$Res> implements $TypedFieldValueCopyWith<$Res> {
  factory $ScaleFieldValueCopyWith(ScaleFieldValue value, $Res Function(ScaleFieldValue) _then) = _$ScaleFieldValueCopyWithImpl;
@useResult
$Res call({
 int? step
});




}
/// @nodoc
class _$ScaleFieldValueCopyWithImpl<$Res>
    implements $ScaleFieldValueCopyWith<$Res> {
  _$ScaleFieldValueCopyWithImpl(this._self, this._then);

  final ScaleFieldValue _self;
  final $Res Function(ScaleFieldValue) _then;

/// Create a copy of TypedFieldValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? step = freezed,}) {
  return _then(ScaleFieldValue(
step: freezed == step ? _self.step : step // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc


class SliderFieldValue implements TypedFieldValue {
  const SliderFieldValue({this.value});
  

 final  double? value;

/// Create a copy of TypedFieldValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SliderFieldValueCopyWith<SliderFieldValue> get copyWith => _$SliderFieldValueCopyWithImpl<SliderFieldValue>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SliderFieldValue&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'TypedFieldValue.slider(value: $value)';
}


}

/// @nodoc
abstract mixin class $SliderFieldValueCopyWith<$Res> implements $TypedFieldValueCopyWith<$Res> {
  factory $SliderFieldValueCopyWith(SliderFieldValue value, $Res Function(SliderFieldValue) _then) = _$SliderFieldValueCopyWithImpl;
@useResult
$Res call({
 double? value
});




}
/// @nodoc
class _$SliderFieldValueCopyWithImpl<$Res>
    implements $SliderFieldValueCopyWith<$Res> {
  _$SliderFieldValueCopyWithImpl(this._self, this._then);

  final SliderFieldValue _self;
  final $Res Function(SliderFieldValue) _then;

/// Create a copy of TypedFieldValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = freezed,}) {
  return _then(SliderFieldValue(
value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}


}

/// @nodoc


class MemberFieldValue implements TypedFieldValue {
  const MemberFieldValue({final  Set<String> memberIds = const <String>{}, final  Map<String, dynamic> extra = const <String, dynamic>{}}): _memberIds = memberIds,_extra = extra;
  

 final  Set<String> _memberIds;
@JsonKey() Set<String> get memberIds {
  if (_memberIds is EqualUnmodifiableSetView) return _memberIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_memberIds);
}

 final  Map<String, dynamic> _extra;
@JsonKey() Map<String, dynamic> get extra {
  if (_extra is EqualUnmodifiableMapView) return _extra;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_extra);
}


/// Create a copy of TypedFieldValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MemberFieldValueCopyWith<MemberFieldValue> get copyWith => _$MemberFieldValueCopyWithImpl<MemberFieldValue>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MemberFieldValue&&const DeepCollectionEquality().equals(other._memberIds, _memberIds)&&const DeepCollectionEquality().equals(other._extra, _extra));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_memberIds),const DeepCollectionEquality().hash(_extra));

@override
String toString() {
  return 'TypedFieldValue.member(memberIds: $memberIds, extra: $extra)';
}


}

/// @nodoc
abstract mixin class $MemberFieldValueCopyWith<$Res> implements $TypedFieldValueCopyWith<$Res> {
  factory $MemberFieldValueCopyWith(MemberFieldValue value, $Res Function(MemberFieldValue) _then) = _$MemberFieldValueCopyWithImpl;
@useResult
$Res call({
 Set<String> memberIds, Map<String, dynamic> extra
});




}
/// @nodoc
class _$MemberFieldValueCopyWithImpl<$Res>
    implements $MemberFieldValueCopyWith<$Res> {
  _$MemberFieldValueCopyWithImpl(this._self, this._then);

  final MemberFieldValue _self;
  final $Res Function(MemberFieldValue) _then;

/// Create a copy of TypedFieldValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? memberIds = null,Object? extra = null,}) {
  return _then(MemberFieldValue(
memberIds: null == memberIds ? _self._memberIds : memberIds // ignore: cast_nullable_to_non_nullable
as Set<String>,extra: null == extra ? _self._extra : extra // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}


}

/// @nodoc


class UnsupportedFieldValue implements TypedFieldValue {
  const UnsupportedFieldValue(this.raw);
  

 final  String raw;

/// Create a copy of TypedFieldValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UnsupportedFieldValueCopyWith<UnsupportedFieldValue> get copyWith => _$UnsupportedFieldValueCopyWithImpl<UnsupportedFieldValue>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UnsupportedFieldValue&&(identical(other.raw, raw) || other.raw == raw));
}


@override
int get hashCode => Object.hash(runtimeType,raw);

@override
String toString() {
  return 'TypedFieldValue.unsupported(raw: $raw)';
}


}

/// @nodoc
abstract mixin class $UnsupportedFieldValueCopyWith<$Res> implements $TypedFieldValueCopyWith<$Res> {
  factory $UnsupportedFieldValueCopyWith(UnsupportedFieldValue value, $Res Function(UnsupportedFieldValue) _then) = _$UnsupportedFieldValueCopyWithImpl;
@useResult
$Res call({
 String raw
});




}
/// @nodoc
class _$UnsupportedFieldValueCopyWithImpl<$Res>
    implements $UnsupportedFieldValueCopyWith<$Res> {
  _$UnsupportedFieldValueCopyWithImpl(this._self, this._then);

  final UnsupportedFieldValue _self;
  final $Res Function(UnsupportedFieldValue) _then;

/// Create a copy of TypedFieldValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? raw = null,}) {
  return _then(UnsupportedFieldValue(
null == raw ? _self.raw : raw // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
