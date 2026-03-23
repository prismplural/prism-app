// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'custom_field_value.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$CustomFieldValue {

 String get id; String get customFieldId; String get memberId; String get value;
/// Create a copy of CustomFieldValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CustomFieldValueCopyWith<CustomFieldValue> get copyWith => _$CustomFieldValueCopyWithImpl<CustomFieldValue>(this as CustomFieldValue, _$identity);

  /// Serializes this CustomFieldValue to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CustomFieldValue&&(identical(other.id, id) || other.id == id)&&(identical(other.customFieldId, customFieldId) || other.customFieldId == customFieldId)&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.value, value) || other.value == value));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,customFieldId,memberId,value);

@override
String toString() {
  return 'CustomFieldValue(id: $id, customFieldId: $customFieldId, memberId: $memberId, value: $value)';
}


}

/// @nodoc
abstract mixin class $CustomFieldValueCopyWith<$Res>  {
  factory $CustomFieldValueCopyWith(CustomFieldValue value, $Res Function(CustomFieldValue) _then) = _$CustomFieldValueCopyWithImpl;
@useResult
$Res call({
 String id, String customFieldId, String memberId, String value
});




}
/// @nodoc
class _$CustomFieldValueCopyWithImpl<$Res>
    implements $CustomFieldValueCopyWith<$Res> {
  _$CustomFieldValueCopyWithImpl(this._self, this._then);

  final CustomFieldValue _self;
  final $Res Function(CustomFieldValue) _then;

/// Create a copy of CustomFieldValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? customFieldId = null,Object? memberId = null,Object? value = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,customFieldId: null == customFieldId ? _self.customFieldId : customFieldId // ignore: cast_nullable_to_non_nullable
as String,memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [CustomFieldValue].
extension CustomFieldValuePatterns on CustomFieldValue {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CustomFieldValue value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CustomFieldValue() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CustomFieldValue value)  $default,){
final _that = this;
switch (_that) {
case _CustomFieldValue():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CustomFieldValue value)?  $default,){
final _that = this;
switch (_that) {
case _CustomFieldValue() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String customFieldId,  String memberId,  String value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CustomFieldValue() when $default != null:
return $default(_that.id,_that.customFieldId,_that.memberId,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String customFieldId,  String memberId,  String value)  $default,) {final _that = this;
switch (_that) {
case _CustomFieldValue():
return $default(_that.id,_that.customFieldId,_that.memberId,_that.value);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String customFieldId,  String memberId,  String value)?  $default,) {final _that = this;
switch (_that) {
case _CustomFieldValue() when $default != null:
return $default(_that.id,_that.customFieldId,_that.memberId,_that.value);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _CustomFieldValue extends CustomFieldValue {
  const _CustomFieldValue({required this.id, required this.customFieldId, required this.memberId, required this.value}): super._();
  factory _CustomFieldValue.fromJson(Map<String, dynamic> json) => _$CustomFieldValueFromJson(json);

@override final  String id;
@override final  String customFieldId;
@override final  String memberId;
@override final  String value;

/// Create a copy of CustomFieldValue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CustomFieldValueCopyWith<_CustomFieldValue> get copyWith => __$CustomFieldValueCopyWithImpl<_CustomFieldValue>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$CustomFieldValueToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CustomFieldValue&&(identical(other.id, id) || other.id == id)&&(identical(other.customFieldId, customFieldId) || other.customFieldId == customFieldId)&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.value, value) || other.value == value));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,customFieldId,memberId,value);

@override
String toString() {
  return 'CustomFieldValue(id: $id, customFieldId: $customFieldId, memberId: $memberId, value: $value)';
}


}

/// @nodoc
abstract mixin class _$CustomFieldValueCopyWith<$Res> implements $CustomFieldValueCopyWith<$Res> {
  factory _$CustomFieldValueCopyWith(_CustomFieldValue value, $Res Function(_CustomFieldValue) _then) = __$CustomFieldValueCopyWithImpl;
@override @useResult
$Res call({
 String id, String customFieldId, String memberId, String value
});




}
/// @nodoc
class __$CustomFieldValueCopyWithImpl<$Res>
    implements _$CustomFieldValueCopyWith<$Res> {
  __$CustomFieldValueCopyWithImpl(this._self, this._then);

  final _CustomFieldValue _self;
  final $Res Function(_CustomFieldValue) _then;

/// Create a copy of CustomFieldValue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? customFieldId = null,Object? memberId = null,Object? value = null,}) {
  return _then(_CustomFieldValue(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,customFieldId: null == customFieldId ? _self.customFieldId : customFieldId // ignore: cast_nullable_to_non_nullable
as String,memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
