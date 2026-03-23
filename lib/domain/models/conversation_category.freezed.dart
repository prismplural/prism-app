// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'conversation_category.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ConversationCategory {

 String get id; String get name; int get displayOrder; DateTime get createdAt; DateTime get modifiedAt;
/// Create a copy of ConversationCategory
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConversationCategoryCopyWith<ConversationCategory> get copyWith => _$ConversationCategoryCopyWithImpl<ConversationCategory>(this as ConversationCategory, _$identity);

  /// Serializes this ConversationCategory to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConversationCategory&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.displayOrder, displayOrder) || other.displayOrder == displayOrder)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.modifiedAt, modifiedAt) || other.modifiedAt == modifiedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,displayOrder,createdAt,modifiedAt);

@override
String toString() {
  return 'ConversationCategory(id: $id, name: $name, displayOrder: $displayOrder, createdAt: $createdAt, modifiedAt: $modifiedAt)';
}


}

/// @nodoc
abstract mixin class $ConversationCategoryCopyWith<$Res>  {
  factory $ConversationCategoryCopyWith(ConversationCategory value, $Res Function(ConversationCategory) _then) = _$ConversationCategoryCopyWithImpl;
@useResult
$Res call({
 String id, String name, int displayOrder, DateTime createdAt, DateTime modifiedAt
});




}
/// @nodoc
class _$ConversationCategoryCopyWithImpl<$Res>
    implements $ConversationCategoryCopyWith<$Res> {
  _$ConversationCategoryCopyWithImpl(this._self, this._then);

  final ConversationCategory _self;
  final $Res Function(ConversationCategory) _then;

/// Create a copy of ConversationCategory
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? displayOrder = null,Object? createdAt = null,Object? modifiedAt = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,displayOrder: null == displayOrder ? _self.displayOrder : displayOrder // ignore: cast_nullable_to_non_nullable
as int,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,modifiedAt: null == modifiedAt ? _self.modifiedAt : modifiedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [ConversationCategory].
extension ConversationCategoryPatterns on ConversationCategory {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConversationCategory value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConversationCategory() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConversationCategory value)  $default,){
final _that = this;
switch (_that) {
case _ConversationCategory():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConversationCategory value)?  $default,){
final _that = this;
switch (_that) {
case _ConversationCategory() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  int displayOrder,  DateTime createdAt,  DateTime modifiedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConversationCategory() when $default != null:
return $default(_that.id,_that.name,_that.displayOrder,_that.createdAt,_that.modifiedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  int displayOrder,  DateTime createdAt,  DateTime modifiedAt)  $default,) {final _that = this;
switch (_that) {
case _ConversationCategory():
return $default(_that.id,_that.name,_that.displayOrder,_that.createdAt,_that.modifiedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  int displayOrder,  DateTime createdAt,  DateTime modifiedAt)?  $default,) {final _that = this;
switch (_that) {
case _ConversationCategory() when $default != null:
return $default(_that.id,_that.name,_that.displayOrder,_that.createdAt,_that.modifiedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ConversationCategory implements ConversationCategory {
  const _ConversationCategory({required this.id, required this.name, this.displayOrder = 0, required this.createdAt, required this.modifiedAt});
  factory _ConversationCategory.fromJson(Map<String, dynamic> json) => _$ConversationCategoryFromJson(json);

@override final  String id;
@override final  String name;
@override@JsonKey() final  int displayOrder;
@override final  DateTime createdAt;
@override final  DateTime modifiedAt;

/// Create a copy of ConversationCategory
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConversationCategoryCopyWith<_ConversationCategory> get copyWith => __$ConversationCategoryCopyWithImpl<_ConversationCategory>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ConversationCategoryToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConversationCategory&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.displayOrder, displayOrder) || other.displayOrder == displayOrder)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.modifiedAt, modifiedAt) || other.modifiedAt == modifiedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,displayOrder,createdAt,modifiedAt);

@override
String toString() {
  return 'ConversationCategory(id: $id, name: $name, displayOrder: $displayOrder, createdAt: $createdAt, modifiedAt: $modifiedAt)';
}


}

/// @nodoc
abstract mixin class _$ConversationCategoryCopyWith<$Res> implements $ConversationCategoryCopyWith<$Res> {
  factory _$ConversationCategoryCopyWith(_ConversationCategory value, $Res Function(_ConversationCategory) _then) = __$ConversationCategoryCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, int displayOrder, DateTime createdAt, DateTime modifiedAt
});




}
/// @nodoc
class __$ConversationCategoryCopyWithImpl<$Res>
    implements _$ConversationCategoryCopyWith<$Res> {
  __$ConversationCategoryCopyWithImpl(this._self, this._then);

  final _ConversationCategory _self;
  final $Res Function(_ConversationCategory) _then;

/// Create a copy of ConversationCategory
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? displayOrder = null,Object? createdAt = null,Object? modifiedAt = null,}) {
  return _then(_ConversationCategory(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,displayOrder: null == displayOrder ? _self.displayOrder : displayOrder // ignore: cast_nullable_to_non_nullable
as int,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,modifiedAt: null == modifiedAt ? _self.modifiedAt : modifiedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on
