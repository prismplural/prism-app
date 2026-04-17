// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'member_group.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$MemberGroup {

 String get id; String get name; String? get description; String? get colorHex; String? get emoji; int get displayOrder; String? get parentGroupId; int get groupType; String? get filterRules; DateTime get createdAt;
/// Create a copy of MemberGroup
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MemberGroupCopyWith<MemberGroup> get copyWith => _$MemberGroupCopyWithImpl<MemberGroup>(this as MemberGroup, _$identity);

  /// Serializes this MemberGroup to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MemberGroup&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description)&&(identical(other.colorHex, colorHex) || other.colorHex == colorHex)&&(identical(other.emoji, emoji) || other.emoji == emoji)&&(identical(other.displayOrder, displayOrder) || other.displayOrder == displayOrder)&&(identical(other.parentGroupId, parentGroupId) || other.parentGroupId == parentGroupId)&&(identical(other.groupType, groupType) || other.groupType == groupType)&&(identical(other.filterRules, filterRules) || other.filterRules == filterRules)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,description,colorHex,emoji,displayOrder,parentGroupId,groupType,filterRules,createdAt);

@override
String toString() {
  return 'MemberGroup(id: $id, name: $name, description: $description, colorHex: $colorHex, emoji: $emoji, displayOrder: $displayOrder, parentGroupId: $parentGroupId, groupType: $groupType, filterRules: $filterRules, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class $MemberGroupCopyWith<$Res>  {
  factory $MemberGroupCopyWith(MemberGroup value, $Res Function(MemberGroup) _then) = _$MemberGroupCopyWithImpl;
@useResult
$Res call({
 String id, String name, String? description, String? colorHex, String? emoji, int displayOrder, String? parentGroupId, int groupType, String? filterRules, DateTime createdAt
});




}
/// @nodoc
class _$MemberGroupCopyWithImpl<$Res>
    implements $MemberGroupCopyWith<$Res> {
  _$MemberGroupCopyWithImpl(this._self, this._then);

  final MemberGroup _self;
  final $Res Function(MemberGroup) _then;

/// Create a copy of MemberGroup
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? description = freezed,Object? colorHex = freezed,Object? emoji = freezed,Object? displayOrder = null,Object? parentGroupId = freezed,Object? groupType = null,Object? filterRules = freezed,Object? createdAt = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,colorHex: freezed == colorHex ? _self.colorHex : colorHex // ignore: cast_nullable_to_non_nullable
as String?,emoji: freezed == emoji ? _self.emoji : emoji // ignore: cast_nullable_to_non_nullable
as String?,displayOrder: null == displayOrder ? _self.displayOrder : displayOrder // ignore: cast_nullable_to_non_nullable
as int,parentGroupId: freezed == parentGroupId ? _self.parentGroupId : parentGroupId // ignore: cast_nullable_to_non_nullable
as String?,groupType: null == groupType ? _self.groupType : groupType // ignore: cast_nullable_to_non_nullable
as int,filterRules: freezed == filterRules ? _self.filterRules : filterRules // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [MemberGroup].
extension MemberGroupPatterns on MemberGroup {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MemberGroup value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MemberGroup() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MemberGroup value)  $default,){
final _that = this;
switch (_that) {
case _MemberGroup():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MemberGroup value)?  $default,){
final _that = this;
switch (_that) {
case _MemberGroup() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String? description,  String? colorHex,  String? emoji,  int displayOrder,  String? parentGroupId,  int groupType,  String? filterRules,  DateTime createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MemberGroup() when $default != null:
return $default(_that.id,_that.name,_that.description,_that.colorHex,_that.emoji,_that.displayOrder,_that.parentGroupId,_that.groupType,_that.filterRules,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String? description,  String? colorHex,  String? emoji,  int displayOrder,  String? parentGroupId,  int groupType,  String? filterRules,  DateTime createdAt)  $default,) {final _that = this;
switch (_that) {
case _MemberGroup():
return $default(_that.id,_that.name,_that.description,_that.colorHex,_that.emoji,_that.displayOrder,_that.parentGroupId,_that.groupType,_that.filterRules,_that.createdAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String? description,  String? colorHex,  String? emoji,  int displayOrder,  String? parentGroupId,  int groupType,  String? filterRules,  DateTime createdAt)?  $default,) {final _that = this;
switch (_that) {
case _MemberGroup() when $default != null:
return $default(_that.id,_that.name,_that.description,_that.colorHex,_that.emoji,_that.displayOrder,_that.parentGroupId,_that.groupType,_that.filterRules,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _MemberGroup implements MemberGroup {
  const _MemberGroup({required this.id, required this.name, this.description, this.colorHex, this.emoji, this.displayOrder = 0, this.parentGroupId, this.groupType = 0, this.filterRules, required this.createdAt});
  factory _MemberGroup.fromJson(Map<String, dynamic> json) => _$MemberGroupFromJson(json);

@override final  String id;
@override final  String name;
@override final  String? description;
@override final  String? colorHex;
@override final  String? emoji;
@override@JsonKey() final  int displayOrder;
@override final  String? parentGroupId;
@override@JsonKey() final  int groupType;
@override final  String? filterRules;
@override final  DateTime createdAt;

/// Create a copy of MemberGroup
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MemberGroupCopyWith<_MemberGroup> get copyWith => __$MemberGroupCopyWithImpl<_MemberGroup>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MemberGroupToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MemberGroup&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description)&&(identical(other.colorHex, colorHex) || other.colorHex == colorHex)&&(identical(other.emoji, emoji) || other.emoji == emoji)&&(identical(other.displayOrder, displayOrder) || other.displayOrder == displayOrder)&&(identical(other.parentGroupId, parentGroupId) || other.parentGroupId == parentGroupId)&&(identical(other.groupType, groupType) || other.groupType == groupType)&&(identical(other.filterRules, filterRules) || other.filterRules == filterRules)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,description,colorHex,emoji,displayOrder,parentGroupId,groupType,filterRules,createdAt);

@override
String toString() {
  return 'MemberGroup(id: $id, name: $name, description: $description, colorHex: $colorHex, emoji: $emoji, displayOrder: $displayOrder, parentGroupId: $parentGroupId, groupType: $groupType, filterRules: $filterRules, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$MemberGroupCopyWith<$Res> implements $MemberGroupCopyWith<$Res> {
  factory _$MemberGroupCopyWith(_MemberGroup value, $Res Function(_MemberGroup) _then) = __$MemberGroupCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String? description, String? colorHex, String? emoji, int displayOrder, String? parentGroupId, int groupType, String? filterRules, DateTime createdAt
});




}
/// @nodoc
class __$MemberGroupCopyWithImpl<$Res>
    implements _$MemberGroupCopyWith<$Res> {
  __$MemberGroupCopyWithImpl(this._self, this._then);

  final _MemberGroup _self;
  final $Res Function(_MemberGroup) _then;

/// Create a copy of MemberGroup
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? description = freezed,Object? colorHex = freezed,Object? emoji = freezed,Object? displayOrder = null,Object? parentGroupId = freezed,Object? groupType = null,Object? filterRules = freezed,Object? createdAt = null,}) {
  return _then(_MemberGroup(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,colorHex: freezed == colorHex ? _self.colorHex : colorHex // ignore: cast_nullable_to_non_nullable
as String?,emoji: freezed == emoji ? _self.emoji : emoji // ignore: cast_nullable_to_non_nullable
as String?,displayOrder: null == displayOrder ? _self.displayOrder : displayOrder // ignore: cast_nullable_to_non_nullable
as int,parentGroupId: freezed == parentGroupId ? _self.parentGroupId : parentGroupId // ignore: cast_nullable_to_non_nullable
as String?,groupType: null == groupType ? _self.groupType : groupType // ignore: cast_nullable_to_non_nullable
as int,filterRules: freezed == filterRules ? _self.filterRules : filterRules // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on
