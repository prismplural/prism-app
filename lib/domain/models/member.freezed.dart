// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'member.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Member {

 String get id; String get name; String? get pronouns; String get emoji; int? get age; String? get bio;@JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson) Uint8List? get avatarImageData; bool get isActive; DateTime get createdAt; int get displayOrder; bool get isAdmin; bool get customColorEnabled; String? get customColorHex; String? get parentSystemId; String? get pluralkitUuid; String? get pluralkitId; bool get markdownEnabled;
/// Create a copy of Member
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MemberCopyWith<Member> get copyWith => _$MemberCopyWithImpl<Member>(this as Member, _$identity);

  /// Serializes this Member to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Member&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.pronouns, pronouns) || other.pronouns == pronouns)&&(identical(other.emoji, emoji) || other.emoji == emoji)&&(identical(other.age, age) || other.age == age)&&(identical(other.bio, bio) || other.bio == bio)&&const DeepCollectionEquality().equals(other.avatarImageData, avatarImageData)&&(identical(other.isActive, isActive) || other.isActive == isActive)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.displayOrder, displayOrder) || other.displayOrder == displayOrder)&&(identical(other.isAdmin, isAdmin) || other.isAdmin == isAdmin)&&(identical(other.customColorEnabled, customColorEnabled) || other.customColorEnabled == customColorEnabled)&&(identical(other.customColorHex, customColorHex) || other.customColorHex == customColorHex)&&(identical(other.parentSystemId, parentSystemId) || other.parentSystemId == parentSystemId)&&(identical(other.pluralkitUuid, pluralkitUuid) || other.pluralkitUuid == pluralkitUuid)&&(identical(other.pluralkitId, pluralkitId) || other.pluralkitId == pluralkitId)&&(identical(other.markdownEnabled, markdownEnabled) || other.markdownEnabled == markdownEnabled));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,pronouns,emoji,age,bio,const DeepCollectionEquality().hash(avatarImageData),isActive,createdAt,displayOrder,isAdmin,customColorEnabled,customColorHex,parentSystemId,pluralkitUuid,pluralkitId,markdownEnabled);

@override
String toString() {
  return 'Member(id: $id, name: $name, pronouns: $pronouns, emoji: $emoji, age: $age, bio: $bio, avatarImageData: $avatarImageData, isActive: $isActive, createdAt: $createdAt, displayOrder: $displayOrder, isAdmin: $isAdmin, customColorEnabled: $customColorEnabled, customColorHex: $customColorHex, parentSystemId: $parentSystemId, pluralkitUuid: $pluralkitUuid, pluralkitId: $pluralkitId, markdownEnabled: $markdownEnabled)';
}


}

/// @nodoc
abstract mixin class $MemberCopyWith<$Res>  {
  factory $MemberCopyWith(Member value, $Res Function(Member) _then) = _$MemberCopyWithImpl;
@useResult
$Res call({
 String id, String name, String? pronouns, String emoji, int? age, String? bio,@JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson) Uint8List? avatarImageData, bool isActive, DateTime createdAt, int displayOrder, bool isAdmin, bool customColorEnabled, String? customColorHex, String? parentSystemId, String? pluralkitUuid, String? pluralkitId, bool markdownEnabled
});




}
/// @nodoc
class _$MemberCopyWithImpl<$Res>
    implements $MemberCopyWith<$Res> {
  _$MemberCopyWithImpl(this._self, this._then);

  final Member _self;
  final $Res Function(Member) _then;

/// Create a copy of Member
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? pronouns = freezed,Object? emoji = null,Object? age = freezed,Object? bio = freezed,Object? avatarImageData = freezed,Object? isActive = null,Object? createdAt = null,Object? displayOrder = null,Object? isAdmin = null,Object? customColorEnabled = null,Object? customColorHex = freezed,Object? parentSystemId = freezed,Object? pluralkitUuid = freezed,Object? pluralkitId = freezed,Object? markdownEnabled = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,pronouns: freezed == pronouns ? _self.pronouns : pronouns // ignore: cast_nullable_to_non_nullable
as String?,emoji: null == emoji ? _self.emoji : emoji // ignore: cast_nullable_to_non_nullable
as String,age: freezed == age ? _self.age : age // ignore: cast_nullable_to_non_nullable
as int?,bio: freezed == bio ? _self.bio : bio // ignore: cast_nullable_to_non_nullable
as String?,avatarImageData: freezed == avatarImageData ? _self.avatarImageData : avatarImageData // ignore: cast_nullable_to_non_nullable
as Uint8List?,isActive: null == isActive ? _self.isActive : isActive // ignore: cast_nullable_to_non_nullable
as bool,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,displayOrder: null == displayOrder ? _self.displayOrder : displayOrder // ignore: cast_nullable_to_non_nullable
as int,isAdmin: null == isAdmin ? _self.isAdmin : isAdmin // ignore: cast_nullable_to_non_nullable
as bool,customColorEnabled: null == customColorEnabled ? _self.customColorEnabled : customColorEnabled // ignore: cast_nullable_to_non_nullable
as bool,customColorHex: freezed == customColorHex ? _self.customColorHex : customColorHex // ignore: cast_nullable_to_non_nullable
as String?,parentSystemId: freezed == parentSystemId ? _self.parentSystemId : parentSystemId // ignore: cast_nullable_to_non_nullable
as String?,pluralkitUuid: freezed == pluralkitUuid ? _self.pluralkitUuid : pluralkitUuid // ignore: cast_nullable_to_non_nullable
as String?,pluralkitId: freezed == pluralkitId ? _self.pluralkitId : pluralkitId // ignore: cast_nullable_to_non_nullable
as String?,markdownEnabled: null == markdownEnabled ? _self.markdownEnabled : markdownEnabled // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [Member].
extension MemberPatterns on Member {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Member value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Member() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Member value)  $default,){
final _that = this;
switch (_that) {
case _Member():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Member value)?  $default,){
final _that = this;
switch (_that) {
case _Member() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String? pronouns,  String emoji,  int? age,  String? bio, @JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson)  Uint8List? avatarImageData,  bool isActive,  DateTime createdAt,  int displayOrder,  bool isAdmin,  bool customColorEnabled,  String? customColorHex,  String? parentSystemId,  String? pluralkitUuid,  String? pluralkitId,  bool markdownEnabled)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Member() when $default != null:
return $default(_that.id,_that.name,_that.pronouns,_that.emoji,_that.age,_that.bio,_that.avatarImageData,_that.isActive,_that.createdAt,_that.displayOrder,_that.isAdmin,_that.customColorEnabled,_that.customColorHex,_that.parentSystemId,_that.pluralkitUuid,_that.pluralkitId,_that.markdownEnabled);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String? pronouns,  String emoji,  int? age,  String? bio, @JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson)  Uint8List? avatarImageData,  bool isActive,  DateTime createdAt,  int displayOrder,  bool isAdmin,  bool customColorEnabled,  String? customColorHex,  String? parentSystemId,  String? pluralkitUuid,  String? pluralkitId,  bool markdownEnabled)  $default,) {final _that = this;
switch (_that) {
case _Member():
return $default(_that.id,_that.name,_that.pronouns,_that.emoji,_that.age,_that.bio,_that.avatarImageData,_that.isActive,_that.createdAt,_that.displayOrder,_that.isAdmin,_that.customColorEnabled,_that.customColorHex,_that.parentSystemId,_that.pluralkitUuid,_that.pluralkitId,_that.markdownEnabled);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String? pronouns,  String emoji,  int? age,  String? bio, @JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson)  Uint8List? avatarImageData,  bool isActive,  DateTime createdAt,  int displayOrder,  bool isAdmin,  bool customColorEnabled,  String? customColorHex,  String? parentSystemId,  String? pluralkitUuid,  String? pluralkitId,  bool markdownEnabled)?  $default,) {final _that = this;
switch (_that) {
case _Member() when $default != null:
return $default(_that.id,_that.name,_that.pronouns,_that.emoji,_that.age,_that.bio,_that.avatarImageData,_that.isActive,_that.createdAt,_that.displayOrder,_that.isAdmin,_that.customColorEnabled,_that.customColorHex,_that.parentSystemId,_that.pluralkitUuid,_that.pluralkitId,_that.markdownEnabled);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Member implements Member {
  const _Member({required this.id, required this.name, this.pronouns, this.emoji = '❔', this.age, this.bio, @JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson) this.avatarImageData, this.isActive = true, required this.createdAt, this.displayOrder = 0, this.isAdmin = false, this.customColorEnabled = false, this.customColorHex, this.parentSystemId, this.pluralkitUuid, this.pluralkitId, this.markdownEnabled = false});
  factory _Member.fromJson(Map<String, dynamic> json) => _$MemberFromJson(json);

@override final  String id;
@override final  String name;
@override final  String? pronouns;
@override@JsonKey() final  String emoji;
@override final  int? age;
@override final  String? bio;
@override@JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson) final  Uint8List? avatarImageData;
@override@JsonKey() final  bool isActive;
@override final  DateTime createdAt;
@override@JsonKey() final  int displayOrder;
@override@JsonKey() final  bool isAdmin;
@override@JsonKey() final  bool customColorEnabled;
@override final  String? customColorHex;
@override final  String? parentSystemId;
@override final  String? pluralkitUuid;
@override final  String? pluralkitId;
@override@JsonKey() final  bool markdownEnabled;

/// Create a copy of Member
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MemberCopyWith<_Member> get copyWith => __$MemberCopyWithImpl<_Member>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MemberToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Member&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.pronouns, pronouns) || other.pronouns == pronouns)&&(identical(other.emoji, emoji) || other.emoji == emoji)&&(identical(other.age, age) || other.age == age)&&(identical(other.bio, bio) || other.bio == bio)&&const DeepCollectionEquality().equals(other.avatarImageData, avatarImageData)&&(identical(other.isActive, isActive) || other.isActive == isActive)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.displayOrder, displayOrder) || other.displayOrder == displayOrder)&&(identical(other.isAdmin, isAdmin) || other.isAdmin == isAdmin)&&(identical(other.customColorEnabled, customColorEnabled) || other.customColorEnabled == customColorEnabled)&&(identical(other.customColorHex, customColorHex) || other.customColorHex == customColorHex)&&(identical(other.parentSystemId, parentSystemId) || other.parentSystemId == parentSystemId)&&(identical(other.pluralkitUuid, pluralkitUuid) || other.pluralkitUuid == pluralkitUuid)&&(identical(other.pluralkitId, pluralkitId) || other.pluralkitId == pluralkitId)&&(identical(other.markdownEnabled, markdownEnabled) || other.markdownEnabled == markdownEnabled));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,pronouns,emoji,age,bio,const DeepCollectionEquality().hash(avatarImageData),isActive,createdAt,displayOrder,isAdmin,customColorEnabled,customColorHex,parentSystemId,pluralkitUuid,pluralkitId,markdownEnabled);

@override
String toString() {
  return 'Member(id: $id, name: $name, pronouns: $pronouns, emoji: $emoji, age: $age, bio: $bio, avatarImageData: $avatarImageData, isActive: $isActive, createdAt: $createdAt, displayOrder: $displayOrder, isAdmin: $isAdmin, customColorEnabled: $customColorEnabled, customColorHex: $customColorHex, parentSystemId: $parentSystemId, pluralkitUuid: $pluralkitUuid, pluralkitId: $pluralkitId, markdownEnabled: $markdownEnabled)';
}


}

/// @nodoc
abstract mixin class _$MemberCopyWith<$Res> implements $MemberCopyWith<$Res> {
  factory _$MemberCopyWith(_Member value, $Res Function(_Member) _then) = __$MemberCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String? pronouns, String emoji, int? age, String? bio,@JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson) Uint8List? avatarImageData, bool isActive, DateTime createdAt, int displayOrder, bool isAdmin, bool customColorEnabled, String? customColorHex, String? parentSystemId, String? pluralkitUuid, String? pluralkitId, bool markdownEnabled
});




}
/// @nodoc
class __$MemberCopyWithImpl<$Res>
    implements _$MemberCopyWith<$Res> {
  __$MemberCopyWithImpl(this._self, this._then);

  final _Member _self;
  final $Res Function(_Member) _then;

/// Create a copy of Member
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? pronouns = freezed,Object? emoji = null,Object? age = freezed,Object? bio = freezed,Object? avatarImageData = freezed,Object? isActive = null,Object? createdAt = null,Object? displayOrder = null,Object? isAdmin = null,Object? customColorEnabled = null,Object? customColorHex = freezed,Object? parentSystemId = freezed,Object? pluralkitUuid = freezed,Object? pluralkitId = freezed,Object? markdownEnabled = null,}) {
  return _then(_Member(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,pronouns: freezed == pronouns ? _self.pronouns : pronouns // ignore: cast_nullable_to_non_nullable
as String?,emoji: null == emoji ? _self.emoji : emoji // ignore: cast_nullable_to_non_nullable
as String,age: freezed == age ? _self.age : age // ignore: cast_nullable_to_non_nullable
as int?,bio: freezed == bio ? _self.bio : bio // ignore: cast_nullable_to_non_nullable
as String?,avatarImageData: freezed == avatarImageData ? _self.avatarImageData : avatarImageData // ignore: cast_nullable_to_non_nullable
as Uint8List?,isActive: null == isActive ? _self.isActive : isActive // ignore: cast_nullable_to_non_nullable
as bool,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,displayOrder: null == displayOrder ? _self.displayOrder : displayOrder // ignore: cast_nullable_to_non_nullable
as int,isAdmin: null == isAdmin ? _self.isAdmin : isAdmin // ignore: cast_nullable_to_non_nullable
as bool,customColorEnabled: null == customColorEnabled ? _self.customColorEnabled : customColorEnabled // ignore: cast_nullable_to_non_nullable
as bool,customColorHex: freezed == customColorHex ? _self.customColorHex : customColorHex // ignore: cast_nullable_to_non_nullable
as String?,parentSystemId: freezed == parentSystemId ? _self.parentSystemId : parentSystemId // ignore: cast_nullable_to_non_nullable
as String?,pluralkitUuid: freezed == pluralkitUuid ? _self.pluralkitUuid : pluralkitUuid // ignore: cast_nullable_to_non_nullable
as String?,pluralkitId: freezed == pluralkitId ? _self.pluralkitId : pluralkitId // ignore: cast_nullable_to_non_nullable
as String?,markdownEnabled: null == markdownEnabled ? _self.markdownEnabled : markdownEnabled // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
