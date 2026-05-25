// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'choice_option.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ChoiceOption {

 String get id;// stable UUID, never label-derived
 String get label; String? get colorHex; int get sortOrder; bool get isDeleted;
/// Create a copy of ChoiceOption
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChoiceOptionCopyWith<ChoiceOption> get copyWith => _$ChoiceOptionCopyWithImpl<ChoiceOption>(this as ChoiceOption, _$identity);

  /// Serializes this ChoiceOption to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChoiceOption&&(identical(other.id, id) || other.id == id)&&(identical(other.label, label) || other.label == label)&&(identical(other.colorHex, colorHex) || other.colorHex == colorHex)&&(identical(other.sortOrder, sortOrder) || other.sortOrder == sortOrder)&&(identical(other.isDeleted, isDeleted) || other.isDeleted == isDeleted));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,label,colorHex,sortOrder,isDeleted);

@override
String toString() {
  return 'ChoiceOption(id: $id, label: $label, colorHex: $colorHex, sortOrder: $sortOrder, isDeleted: $isDeleted)';
}


}

/// @nodoc
abstract mixin class $ChoiceOptionCopyWith<$Res>  {
  factory $ChoiceOptionCopyWith(ChoiceOption value, $Res Function(ChoiceOption) _then) = _$ChoiceOptionCopyWithImpl;
@useResult
$Res call({
 String id, String label, String? colorHex, int sortOrder, bool isDeleted
});




}
/// @nodoc
class _$ChoiceOptionCopyWithImpl<$Res>
    implements $ChoiceOptionCopyWith<$Res> {
  _$ChoiceOptionCopyWithImpl(this._self, this._then);

  final ChoiceOption _self;
  final $Res Function(ChoiceOption) _then;

/// Create a copy of ChoiceOption
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? label = null,Object? colorHex = freezed,Object? sortOrder = null,Object? isDeleted = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,colorHex: freezed == colorHex ? _self.colorHex : colorHex // ignore: cast_nullable_to_non_nullable
as String?,sortOrder: null == sortOrder ? _self.sortOrder : sortOrder // ignore: cast_nullable_to_non_nullable
as int,isDeleted: null == isDeleted ? _self.isDeleted : isDeleted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [ChoiceOption].
extension ChoiceOptionPatterns on ChoiceOption {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ChoiceOption value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ChoiceOption() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ChoiceOption value)  $default,){
final _that = this;
switch (_that) {
case _ChoiceOption():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ChoiceOption value)?  $default,){
final _that = this;
switch (_that) {
case _ChoiceOption() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String label,  String? colorHex,  int sortOrder,  bool isDeleted)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ChoiceOption() when $default != null:
return $default(_that.id,_that.label,_that.colorHex,_that.sortOrder,_that.isDeleted);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String label,  String? colorHex,  int sortOrder,  bool isDeleted)  $default,) {final _that = this;
switch (_that) {
case _ChoiceOption():
return $default(_that.id,_that.label,_that.colorHex,_that.sortOrder,_that.isDeleted);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String label,  String? colorHex,  int sortOrder,  bool isDeleted)?  $default,) {final _that = this;
switch (_that) {
case _ChoiceOption() when $default != null:
return $default(_that.id,_that.label,_that.colorHex,_that.sortOrder,_that.isDeleted);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ChoiceOption implements ChoiceOption {
  const _ChoiceOption({required this.id, required this.label, this.colorHex, this.sortOrder = 0, this.isDeleted = false});
  factory _ChoiceOption.fromJson(Map<String, dynamic> json) => _$ChoiceOptionFromJson(json);

@override final  String id;
// stable UUID, never label-derived
@override final  String label;
@override final  String? colorHex;
@override@JsonKey() final  int sortOrder;
@override@JsonKey() final  bool isDeleted;

/// Create a copy of ChoiceOption
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChoiceOptionCopyWith<_ChoiceOption> get copyWith => __$ChoiceOptionCopyWithImpl<_ChoiceOption>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ChoiceOptionToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ChoiceOption&&(identical(other.id, id) || other.id == id)&&(identical(other.label, label) || other.label == label)&&(identical(other.colorHex, colorHex) || other.colorHex == colorHex)&&(identical(other.sortOrder, sortOrder) || other.sortOrder == sortOrder)&&(identical(other.isDeleted, isDeleted) || other.isDeleted == isDeleted));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,label,colorHex,sortOrder,isDeleted);

@override
String toString() {
  return 'ChoiceOption(id: $id, label: $label, colorHex: $colorHex, sortOrder: $sortOrder, isDeleted: $isDeleted)';
}


}

/// @nodoc
abstract mixin class _$ChoiceOptionCopyWith<$Res> implements $ChoiceOptionCopyWith<$Res> {
  factory _$ChoiceOptionCopyWith(_ChoiceOption value, $Res Function(_ChoiceOption) _then) = __$ChoiceOptionCopyWithImpl;
@override @useResult
$Res call({
 String id, String label, String? colorHex, int sortOrder, bool isDeleted
});




}
/// @nodoc
class __$ChoiceOptionCopyWithImpl<$Res>
    implements _$ChoiceOptionCopyWith<$Res> {
  __$ChoiceOptionCopyWithImpl(this._self, this._then);

  final _ChoiceOption _self;
  final $Res Function(_ChoiceOption) _then;

/// Create a copy of ChoiceOption
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? label = null,Object? colorHex = freezed,Object? sortOrder = null,Object? isDeleted = null,}) {
  return _then(_ChoiceOption(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,colorHex: freezed == colorHex ? _self.colorHex : colorHex // ignore: cast_nullable_to_non_nullable
as String?,sortOrder: null == sortOrder ? _self.sortOrder : sortOrder // ignore: cast_nullable_to_non_nullable
as int,isDeleted: null == isDeleted ? _self.isDeleted : isDeleted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
