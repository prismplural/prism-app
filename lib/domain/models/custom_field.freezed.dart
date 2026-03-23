// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'custom_field.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$CustomField {

 String get id; String get name; CustomFieldType get fieldType; DatePrecision? get datePrecision; int get displayOrder; DateTime get createdAt;
/// Create a copy of CustomField
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CustomFieldCopyWith<CustomField> get copyWith => _$CustomFieldCopyWithImpl<CustomField>(this as CustomField, _$identity);

  /// Serializes this CustomField to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CustomField&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.fieldType, fieldType) || other.fieldType == fieldType)&&(identical(other.datePrecision, datePrecision) || other.datePrecision == datePrecision)&&(identical(other.displayOrder, displayOrder) || other.displayOrder == displayOrder)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,fieldType,datePrecision,displayOrder,createdAt);

@override
String toString() {
  return 'CustomField(id: $id, name: $name, fieldType: $fieldType, datePrecision: $datePrecision, displayOrder: $displayOrder, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class $CustomFieldCopyWith<$Res>  {
  factory $CustomFieldCopyWith(CustomField value, $Res Function(CustomField) _then) = _$CustomFieldCopyWithImpl;
@useResult
$Res call({
 String id, String name, CustomFieldType fieldType, DatePrecision? datePrecision, int displayOrder, DateTime createdAt
});




}
/// @nodoc
class _$CustomFieldCopyWithImpl<$Res>
    implements $CustomFieldCopyWith<$Res> {
  _$CustomFieldCopyWithImpl(this._self, this._then);

  final CustomField _self;
  final $Res Function(CustomField) _then;

/// Create a copy of CustomField
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? fieldType = null,Object? datePrecision = freezed,Object? displayOrder = null,Object? createdAt = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,fieldType: null == fieldType ? _self.fieldType : fieldType // ignore: cast_nullable_to_non_nullable
as CustomFieldType,datePrecision: freezed == datePrecision ? _self.datePrecision : datePrecision // ignore: cast_nullable_to_non_nullable
as DatePrecision?,displayOrder: null == displayOrder ? _self.displayOrder : displayOrder // ignore: cast_nullable_to_non_nullable
as int,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [CustomField].
extension CustomFieldPatterns on CustomField {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CustomField value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CustomField() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CustomField value)  $default,){
final _that = this;
switch (_that) {
case _CustomField():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CustomField value)?  $default,){
final _that = this;
switch (_that) {
case _CustomField() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  CustomFieldType fieldType,  DatePrecision? datePrecision,  int displayOrder,  DateTime createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CustomField() when $default != null:
return $default(_that.id,_that.name,_that.fieldType,_that.datePrecision,_that.displayOrder,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  CustomFieldType fieldType,  DatePrecision? datePrecision,  int displayOrder,  DateTime createdAt)  $default,) {final _that = this;
switch (_that) {
case _CustomField():
return $default(_that.id,_that.name,_that.fieldType,_that.datePrecision,_that.displayOrder,_that.createdAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  CustomFieldType fieldType,  DatePrecision? datePrecision,  int displayOrder,  DateTime createdAt)?  $default,) {final _that = this;
switch (_that) {
case _CustomField() when $default != null:
return $default(_that.id,_that.name,_that.fieldType,_that.datePrecision,_that.displayOrder,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _CustomField extends CustomField {
  const _CustomField({required this.id, required this.name, required this.fieldType, this.datePrecision, this.displayOrder = 0, required this.createdAt}): super._();
  factory _CustomField.fromJson(Map<String, dynamic> json) => _$CustomFieldFromJson(json);

@override final  String id;
@override final  String name;
@override final  CustomFieldType fieldType;
@override final  DatePrecision? datePrecision;
@override@JsonKey() final  int displayOrder;
@override final  DateTime createdAt;

/// Create a copy of CustomField
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CustomFieldCopyWith<_CustomField> get copyWith => __$CustomFieldCopyWithImpl<_CustomField>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$CustomFieldToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CustomField&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.fieldType, fieldType) || other.fieldType == fieldType)&&(identical(other.datePrecision, datePrecision) || other.datePrecision == datePrecision)&&(identical(other.displayOrder, displayOrder) || other.displayOrder == displayOrder)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,fieldType,datePrecision,displayOrder,createdAt);

@override
String toString() {
  return 'CustomField(id: $id, name: $name, fieldType: $fieldType, datePrecision: $datePrecision, displayOrder: $displayOrder, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$CustomFieldCopyWith<$Res> implements $CustomFieldCopyWith<$Res> {
  factory _$CustomFieldCopyWith(_CustomField value, $Res Function(_CustomField) _then) = __$CustomFieldCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, CustomFieldType fieldType, DatePrecision? datePrecision, int displayOrder, DateTime createdAt
});




}
/// @nodoc
class __$CustomFieldCopyWithImpl<$Res>
    implements _$CustomFieldCopyWith<$Res> {
  __$CustomFieldCopyWithImpl(this._self, this._then);

  final _CustomField _self;
  final $Res Function(_CustomField) _then;

/// Create a copy of CustomField
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? fieldType = null,Object? datePrecision = freezed,Object? displayOrder = null,Object? createdAt = null,}) {
  return _then(_CustomField(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,fieldType: null == fieldType ? _self.fieldType : fieldType // ignore: cast_nullable_to_non_nullable
as CustomFieldType,datePrecision: freezed == datePrecision ? _self.datePrecision : datePrecision // ignore: cast_nullable_to_non_nullable
as DatePrecision?,displayOrder: null == displayOrder ? _self.displayOrder : displayOrder // ignore: cast_nullable_to_non_nullable
as int,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on
