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

 String get id; String get name; String? get pronouns; String get emoji; int? get age; String? get bio;@JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson) Uint8List? get avatarImageData; bool get isActive; DateTime get createdAt; int get displayOrder; bool get isAdmin; bool get customColorEnabled; String? get customColorHex; String? get parentSystemId; String? get pluralkitUuid; String? get pluralkitId; bool get markdownEnabled; String? get displayName; String? get birthday; String? get proxyTagsJson; String? get pkBannerUrl; MemberProfileHeaderSource get profileHeaderSource; MemberProfileHeaderLayout get profileHeaderLayout; bool get profileHeaderVisible;@JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson) Uint8List? get profileHeaderImageData;@JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson) Uint8List? get pkBannerImageData; String? get pkBannerCachedUrl; bool get pluralkitSyncIgnored;// Plan 02 (PK deletion push). Set by the repo when a PK-linked member is
// soft-deleted; consumed only by the PK push path. `isDeleted` is mirrored
// onto the domain so sync-service re-read guards don't need the Drift row.
 bool get isDeleted; int? get deleteIntentEpoch; int? get deletePushStartedAt;// Per-member fronting refactor (docs/plans/fronting-per-member-sessions.md
// §2.3): when true, this member's session is treated as "background" and
// omitted from avatar stacks, surfaced instead in the "Always-present"
// header on period detail screens. Default false; opt-in per member.
 bool get isAlwaysFronting;
/// Create a copy of Member
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MemberCopyWith<Member> get copyWith => _$MemberCopyWithImpl<Member>(this as Member, _$identity);

  /// Serializes this Member to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Member&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.pronouns, pronouns) || other.pronouns == pronouns)&&(identical(other.emoji, emoji) || other.emoji == emoji)&&(identical(other.age, age) || other.age == age)&&(identical(other.bio, bio) || other.bio == bio)&&const DeepCollectionEquality().equals(other.avatarImageData, avatarImageData)&&(identical(other.isActive, isActive) || other.isActive == isActive)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.displayOrder, displayOrder) || other.displayOrder == displayOrder)&&(identical(other.isAdmin, isAdmin) || other.isAdmin == isAdmin)&&(identical(other.customColorEnabled, customColorEnabled) || other.customColorEnabled == customColorEnabled)&&(identical(other.customColorHex, customColorHex) || other.customColorHex == customColorHex)&&(identical(other.parentSystemId, parentSystemId) || other.parentSystemId == parentSystemId)&&(identical(other.pluralkitUuid, pluralkitUuid) || other.pluralkitUuid == pluralkitUuid)&&(identical(other.pluralkitId, pluralkitId) || other.pluralkitId == pluralkitId)&&(identical(other.markdownEnabled, markdownEnabled) || other.markdownEnabled == markdownEnabled)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.birthday, birthday) || other.birthday == birthday)&&(identical(other.proxyTagsJson, proxyTagsJson) || other.proxyTagsJson == proxyTagsJson)&&(identical(other.pkBannerUrl, pkBannerUrl) || other.pkBannerUrl == pkBannerUrl)&&(identical(other.profileHeaderSource, profileHeaderSource) || other.profileHeaderSource == profileHeaderSource)&&(identical(other.profileHeaderLayout, profileHeaderLayout) || other.profileHeaderLayout == profileHeaderLayout)&&(identical(other.profileHeaderVisible, profileHeaderVisible) || other.profileHeaderVisible == profileHeaderVisible)&&const DeepCollectionEquality().equals(other.profileHeaderImageData, profileHeaderImageData)&&const DeepCollectionEquality().equals(other.pkBannerImageData, pkBannerImageData)&&(identical(other.pkBannerCachedUrl, pkBannerCachedUrl) || other.pkBannerCachedUrl == pkBannerCachedUrl)&&(identical(other.pluralkitSyncIgnored, pluralkitSyncIgnored) || other.pluralkitSyncIgnored == pluralkitSyncIgnored)&&(identical(other.isDeleted, isDeleted) || other.isDeleted == isDeleted)&&(identical(other.deleteIntentEpoch, deleteIntentEpoch) || other.deleteIntentEpoch == deleteIntentEpoch)&&(identical(other.deletePushStartedAt, deletePushStartedAt) || other.deletePushStartedAt == deletePushStartedAt)&&(identical(other.isAlwaysFronting, isAlwaysFronting) || other.isAlwaysFronting == isAlwaysFronting));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,name,pronouns,emoji,age,bio,const DeepCollectionEquality().hash(avatarImageData),isActive,createdAt,displayOrder,isAdmin,customColorEnabled,customColorHex,parentSystemId,pluralkitUuid,pluralkitId,markdownEnabled,displayName,birthday,proxyTagsJson,pkBannerUrl,profileHeaderSource,profileHeaderLayout,profileHeaderVisible,const DeepCollectionEquality().hash(profileHeaderImageData),const DeepCollectionEquality().hash(pkBannerImageData),pkBannerCachedUrl,pluralkitSyncIgnored,isDeleted,deleteIntentEpoch,deletePushStartedAt,isAlwaysFronting]);

@override
String toString() {
  return 'Member(id: $id, name: $name, pronouns: $pronouns, emoji: $emoji, age: $age, bio: $bio, avatarImageData: $avatarImageData, isActive: $isActive, createdAt: $createdAt, displayOrder: $displayOrder, isAdmin: $isAdmin, customColorEnabled: $customColorEnabled, customColorHex: $customColorHex, parentSystemId: $parentSystemId, pluralkitUuid: $pluralkitUuid, pluralkitId: $pluralkitId, markdownEnabled: $markdownEnabled, displayName: $displayName, birthday: $birthday, proxyTagsJson: $proxyTagsJson, pkBannerUrl: $pkBannerUrl, profileHeaderSource: $profileHeaderSource, profileHeaderLayout: $profileHeaderLayout, profileHeaderVisible: $profileHeaderVisible, profileHeaderImageData: $profileHeaderImageData, pkBannerImageData: $pkBannerImageData, pkBannerCachedUrl: $pkBannerCachedUrl, pluralkitSyncIgnored: $pluralkitSyncIgnored, isDeleted: $isDeleted, deleteIntentEpoch: $deleteIntentEpoch, deletePushStartedAt: $deletePushStartedAt, isAlwaysFronting: $isAlwaysFronting)';
}


}

/// @nodoc
abstract mixin class $MemberCopyWith<$Res>  {
  factory $MemberCopyWith(Member value, $Res Function(Member) _then) = _$MemberCopyWithImpl;
@useResult
$Res call({
 String id, String name, String? pronouns, String emoji, int? age, String? bio,@JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson) Uint8List? avatarImageData, bool isActive, DateTime createdAt, int displayOrder, bool isAdmin, bool customColorEnabled, String? customColorHex, String? parentSystemId, String? pluralkitUuid, String? pluralkitId, bool markdownEnabled, String? displayName, String? birthday, String? proxyTagsJson, String? pkBannerUrl, MemberProfileHeaderSource profileHeaderSource, MemberProfileHeaderLayout profileHeaderLayout, bool profileHeaderVisible,@JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson) Uint8List? profileHeaderImageData,@JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson) Uint8List? pkBannerImageData, String? pkBannerCachedUrl, bool pluralkitSyncIgnored, bool isDeleted, int? deleteIntentEpoch, int? deletePushStartedAt, bool isAlwaysFronting
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
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? pronouns = freezed,Object? emoji = null,Object? age = freezed,Object? bio = freezed,Object? avatarImageData = freezed,Object? isActive = null,Object? createdAt = null,Object? displayOrder = null,Object? isAdmin = null,Object? customColorEnabled = null,Object? customColorHex = freezed,Object? parentSystemId = freezed,Object? pluralkitUuid = freezed,Object? pluralkitId = freezed,Object? markdownEnabled = null,Object? displayName = freezed,Object? birthday = freezed,Object? proxyTagsJson = freezed,Object? pkBannerUrl = freezed,Object? profileHeaderSource = null,Object? profileHeaderLayout = null,Object? profileHeaderVisible = null,Object? profileHeaderImageData = freezed,Object? pkBannerImageData = freezed,Object? pkBannerCachedUrl = freezed,Object? pluralkitSyncIgnored = null,Object? isDeleted = null,Object? deleteIntentEpoch = freezed,Object? deletePushStartedAt = freezed,Object? isAlwaysFronting = null,}) {
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
as bool,displayName: freezed == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String?,birthday: freezed == birthday ? _self.birthday : birthday // ignore: cast_nullable_to_non_nullable
as String?,proxyTagsJson: freezed == proxyTagsJson ? _self.proxyTagsJson : proxyTagsJson // ignore: cast_nullable_to_non_nullable
as String?,pkBannerUrl: freezed == pkBannerUrl ? _self.pkBannerUrl : pkBannerUrl // ignore: cast_nullable_to_non_nullable
as String?,profileHeaderSource: null == profileHeaderSource ? _self.profileHeaderSource : profileHeaderSource // ignore: cast_nullable_to_non_nullable
as MemberProfileHeaderSource,profileHeaderLayout: null == profileHeaderLayout ? _self.profileHeaderLayout : profileHeaderLayout // ignore: cast_nullable_to_non_nullable
as MemberProfileHeaderLayout,profileHeaderVisible: null == profileHeaderVisible ? _self.profileHeaderVisible : profileHeaderVisible // ignore: cast_nullable_to_non_nullable
as bool,profileHeaderImageData: freezed == profileHeaderImageData ? _self.profileHeaderImageData : profileHeaderImageData // ignore: cast_nullable_to_non_nullable
as Uint8List?,pkBannerImageData: freezed == pkBannerImageData ? _self.pkBannerImageData : pkBannerImageData // ignore: cast_nullable_to_non_nullable
as Uint8List?,pkBannerCachedUrl: freezed == pkBannerCachedUrl ? _self.pkBannerCachedUrl : pkBannerCachedUrl // ignore: cast_nullable_to_non_nullable
as String?,pluralkitSyncIgnored: null == pluralkitSyncIgnored ? _self.pluralkitSyncIgnored : pluralkitSyncIgnored // ignore: cast_nullable_to_non_nullable
as bool,isDeleted: null == isDeleted ? _self.isDeleted : isDeleted // ignore: cast_nullable_to_non_nullable
as bool,deleteIntentEpoch: freezed == deleteIntentEpoch ? _self.deleteIntentEpoch : deleteIntentEpoch // ignore: cast_nullable_to_non_nullable
as int?,deletePushStartedAt: freezed == deletePushStartedAt ? _self.deletePushStartedAt : deletePushStartedAt // ignore: cast_nullable_to_non_nullable
as int?,isAlwaysFronting: null == isAlwaysFronting ? _self.isAlwaysFronting : isAlwaysFronting // ignore: cast_nullable_to_non_nullable
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String? pronouns,  String emoji,  int? age,  String? bio, @JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson)  Uint8List? avatarImageData,  bool isActive,  DateTime createdAt,  int displayOrder,  bool isAdmin,  bool customColorEnabled,  String? customColorHex,  String? parentSystemId,  String? pluralkitUuid,  String? pluralkitId,  bool markdownEnabled,  String? displayName,  String? birthday,  String? proxyTagsJson,  String? pkBannerUrl,  MemberProfileHeaderSource profileHeaderSource,  MemberProfileHeaderLayout profileHeaderLayout,  bool profileHeaderVisible, @JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson)  Uint8List? profileHeaderImageData, @JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson)  Uint8List? pkBannerImageData,  String? pkBannerCachedUrl,  bool pluralkitSyncIgnored,  bool isDeleted,  int? deleteIntentEpoch,  int? deletePushStartedAt,  bool isAlwaysFronting)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Member() when $default != null:
return $default(_that.id,_that.name,_that.pronouns,_that.emoji,_that.age,_that.bio,_that.avatarImageData,_that.isActive,_that.createdAt,_that.displayOrder,_that.isAdmin,_that.customColorEnabled,_that.customColorHex,_that.parentSystemId,_that.pluralkitUuid,_that.pluralkitId,_that.markdownEnabled,_that.displayName,_that.birthday,_that.proxyTagsJson,_that.pkBannerUrl,_that.profileHeaderSource,_that.profileHeaderLayout,_that.profileHeaderVisible,_that.profileHeaderImageData,_that.pkBannerImageData,_that.pkBannerCachedUrl,_that.pluralkitSyncIgnored,_that.isDeleted,_that.deleteIntentEpoch,_that.deletePushStartedAt,_that.isAlwaysFronting);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String? pronouns,  String emoji,  int? age,  String? bio, @JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson)  Uint8List? avatarImageData,  bool isActive,  DateTime createdAt,  int displayOrder,  bool isAdmin,  bool customColorEnabled,  String? customColorHex,  String? parentSystemId,  String? pluralkitUuid,  String? pluralkitId,  bool markdownEnabled,  String? displayName,  String? birthday,  String? proxyTagsJson,  String? pkBannerUrl,  MemberProfileHeaderSource profileHeaderSource,  MemberProfileHeaderLayout profileHeaderLayout,  bool profileHeaderVisible, @JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson)  Uint8List? profileHeaderImageData, @JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson)  Uint8List? pkBannerImageData,  String? pkBannerCachedUrl,  bool pluralkitSyncIgnored,  bool isDeleted,  int? deleteIntentEpoch,  int? deletePushStartedAt,  bool isAlwaysFronting)  $default,) {final _that = this;
switch (_that) {
case _Member():
return $default(_that.id,_that.name,_that.pronouns,_that.emoji,_that.age,_that.bio,_that.avatarImageData,_that.isActive,_that.createdAt,_that.displayOrder,_that.isAdmin,_that.customColorEnabled,_that.customColorHex,_that.parentSystemId,_that.pluralkitUuid,_that.pluralkitId,_that.markdownEnabled,_that.displayName,_that.birthday,_that.proxyTagsJson,_that.pkBannerUrl,_that.profileHeaderSource,_that.profileHeaderLayout,_that.profileHeaderVisible,_that.profileHeaderImageData,_that.pkBannerImageData,_that.pkBannerCachedUrl,_that.pluralkitSyncIgnored,_that.isDeleted,_that.deleteIntentEpoch,_that.deletePushStartedAt,_that.isAlwaysFronting);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String? pronouns,  String emoji,  int? age,  String? bio, @JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson)  Uint8List? avatarImageData,  bool isActive,  DateTime createdAt,  int displayOrder,  bool isAdmin,  bool customColorEnabled,  String? customColorHex,  String? parentSystemId,  String? pluralkitUuid,  String? pluralkitId,  bool markdownEnabled,  String? displayName,  String? birthday,  String? proxyTagsJson,  String? pkBannerUrl,  MemberProfileHeaderSource profileHeaderSource,  MemberProfileHeaderLayout profileHeaderLayout,  bool profileHeaderVisible, @JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson)  Uint8List? profileHeaderImageData, @JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson)  Uint8List? pkBannerImageData,  String? pkBannerCachedUrl,  bool pluralkitSyncIgnored,  bool isDeleted,  int? deleteIntentEpoch,  int? deletePushStartedAt,  bool isAlwaysFronting)?  $default,) {final _that = this;
switch (_that) {
case _Member() when $default != null:
return $default(_that.id,_that.name,_that.pronouns,_that.emoji,_that.age,_that.bio,_that.avatarImageData,_that.isActive,_that.createdAt,_that.displayOrder,_that.isAdmin,_that.customColorEnabled,_that.customColorHex,_that.parentSystemId,_that.pluralkitUuid,_that.pluralkitId,_that.markdownEnabled,_that.displayName,_that.birthday,_that.proxyTagsJson,_that.pkBannerUrl,_that.profileHeaderSource,_that.profileHeaderLayout,_that.profileHeaderVisible,_that.profileHeaderImageData,_that.pkBannerImageData,_that.pkBannerCachedUrl,_that.pluralkitSyncIgnored,_that.isDeleted,_that.deleteIntentEpoch,_that.deletePushStartedAt,_that.isAlwaysFronting);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Member implements Member {
  const _Member({required this.id, required this.name, this.pronouns, this.emoji = '❔', this.age, this.bio, @JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson) this.avatarImageData, this.isActive = true, required this.createdAt, this.displayOrder = 0, this.isAdmin = false, this.customColorEnabled = false, this.customColorHex, this.parentSystemId, this.pluralkitUuid, this.pluralkitId, this.markdownEnabled = false, this.displayName, this.birthday, this.proxyTagsJson, this.pkBannerUrl, this.profileHeaderSource = MemberProfileHeaderSource.prism, this.profileHeaderLayout = MemberProfileHeaderLayout.compactBackground, this.profileHeaderVisible = true, @JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson) this.profileHeaderImageData, @JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson) this.pkBannerImageData, this.pkBannerCachedUrl, this.pluralkitSyncIgnored = false, this.isDeleted = false, this.deleteIntentEpoch, this.deletePushStartedAt, this.isAlwaysFronting = false});
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
@override final  String? displayName;
@override final  String? birthday;
@override final  String? proxyTagsJson;
@override final  String? pkBannerUrl;
@override@JsonKey() final  MemberProfileHeaderSource profileHeaderSource;
@override@JsonKey() final  MemberProfileHeaderLayout profileHeaderLayout;
@override@JsonKey() final  bool profileHeaderVisible;
@override@JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson) final  Uint8List? profileHeaderImageData;
@override@JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson) final  Uint8List? pkBannerImageData;
@override final  String? pkBannerCachedUrl;
@override@JsonKey() final  bool pluralkitSyncIgnored;
// Plan 02 (PK deletion push). Set by the repo when a PK-linked member is
// soft-deleted; consumed only by the PK push path. `isDeleted` is mirrored
// onto the domain so sync-service re-read guards don't need the Drift row.
@override@JsonKey() final  bool isDeleted;
@override final  int? deleteIntentEpoch;
@override final  int? deletePushStartedAt;
// Per-member fronting refactor (docs/plans/fronting-per-member-sessions.md
// §2.3): when true, this member's session is treated as "background" and
// omitted from avatar stacks, surfaced instead in the "Always-present"
// header on period detail screens. Default false; opt-in per member.
@override@JsonKey() final  bool isAlwaysFronting;

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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Member&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.pronouns, pronouns) || other.pronouns == pronouns)&&(identical(other.emoji, emoji) || other.emoji == emoji)&&(identical(other.age, age) || other.age == age)&&(identical(other.bio, bio) || other.bio == bio)&&const DeepCollectionEquality().equals(other.avatarImageData, avatarImageData)&&(identical(other.isActive, isActive) || other.isActive == isActive)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.displayOrder, displayOrder) || other.displayOrder == displayOrder)&&(identical(other.isAdmin, isAdmin) || other.isAdmin == isAdmin)&&(identical(other.customColorEnabled, customColorEnabled) || other.customColorEnabled == customColorEnabled)&&(identical(other.customColorHex, customColorHex) || other.customColorHex == customColorHex)&&(identical(other.parentSystemId, parentSystemId) || other.parentSystemId == parentSystemId)&&(identical(other.pluralkitUuid, pluralkitUuid) || other.pluralkitUuid == pluralkitUuid)&&(identical(other.pluralkitId, pluralkitId) || other.pluralkitId == pluralkitId)&&(identical(other.markdownEnabled, markdownEnabled) || other.markdownEnabled == markdownEnabled)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.birthday, birthday) || other.birthday == birthday)&&(identical(other.proxyTagsJson, proxyTagsJson) || other.proxyTagsJson == proxyTagsJson)&&(identical(other.pkBannerUrl, pkBannerUrl) || other.pkBannerUrl == pkBannerUrl)&&(identical(other.profileHeaderSource, profileHeaderSource) || other.profileHeaderSource == profileHeaderSource)&&(identical(other.profileHeaderLayout, profileHeaderLayout) || other.profileHeaderLayout == profileHeaderLayout)&&(identical(other.profileHeaderVisible, profileHeaderVisible) || other.profileHeaderVisible == profileHeaderVisible)&&const DeepCollectionEquality().equals(other.profileHeaderImageData, profileHeaderImageData)&&const DeepCollectionEquality().equals(other.pkBannerImageData, pkBannerImageData)&&(identical(other.pkBannerCachedUrl, pkBannerCachedUrl) || other.pkBannerCachedUrl == pkBannerCachedUrl)&&(identical(other.pluralkitSyncIgnored, pluralkitSyncIgnored) || other.pluralkitSyncIgnored == pluralkitSyncIgnored)&&(identical(other.isDeleted, isDeleted) || other.isDeleted == isDeleted)&&(identical(other.deleteIntentEpoch, deleteIntentEpoch) || other.deleteIntentEpoch == deleteIntentEpoch)&&(identical(other.deletePushStartedAt, deletePushStartedAt) || other.deletePushStartedAt == deletePushStartedAt)&&(identical(other.isAlwaysFronting, isAlwaysFronting) || other.isAlwaysFronting == isAlwaysFronting));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,name,pronouns,emoji,age,bio,const DeepCollectionEquality().hash(avatarImageData),isActive,createdAt,displayOrder,isAdmin,customColorEnabled,customColorHex,parentSystemId,pluralkitUuid,pluralkitId,markdownEnabled,displayName,birthday,proxyTagsJson,pkBannerUrl,profileHeaderSource,profileHeaderLayout,profileHeaderVisible,const DeepCollectionEquality().hash(profileHeaderImageData),const DeepCollectionEquality().hash(pkBannerImageData),pkBannerCachedUrl,pluralkitSyncIgnored,isDeleted,deleteIntentEpoch,deletePushStartedAt,isAlwaysFronting]);

@override
String toString() {
  return 'Member(id: $id, name: $name, pronouns: $pronouns, emoji: $emoji, age: $age, bio: $bio, avatarImageData: $avatarImageData, isActive: $isActive, createdAt: $createdAt, displayOrder: $displayOrder, isAdmin: $isAdmin, customColorEnabled: $customColorEnabled, customColorHex: $customColorHex, parentSystemId: $parentSystemId, pluralkitUuid: $pluralkitUuid, pluralkitId: $pluralkitId, markdownEnabled: $markdownEnabled, displayName: $displayName, birthday: $birthday, proxyTagsJson: $proxyTagsJson, pkBannerUrl: $pkBannerUrl, profileHeaderSource: $profileHeaderSource, profileHeaderLayout: $profileHeaderLayout, profileHeaderVisible: $profileHeaderVisible, profileHeaderImageData: $profileHeaderImageData, pkBannerImageData: $pkBannerImageData, pkBannerCachedUrl: $pkBannerCachedUrl, pluralkitSyncIgnored: $pluralkitSyncIgnored, isDeleted: $isDeleted, deleteIntentEpoch: $deleteIntentEpoch, deletePushStartedAt: $deletePushStartedAt, isAlwaysFronting: $isAlwaysFronting)';
}


}

/// @nodoc
abstract mixin class _$MemberCopyWith<$Res> implements $MemberCopyWith<$Res> {
  factory _$MemberCopyWith(_Member value, $Res Function(_Member) _then) = __$MemberCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String? pronouns, String emoji, int? age, String? bio,@JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson) Uint8List? avatarImageData, bool isActive, DateTime createdAt, int displayOrder, bool isAdmin, bool customColorEnabled, String? customColorHex, String? parentSystemId, String? pluralkitUuid, String? pluralkitId, bool markdownEnabled, String? displayName, String? birthday, String? proxyTagsJson, String? pkBannerUrl, MemberProfileHeaderSource profileHeaderSource, MemberProfileHeaderLayout profileHeaderLayout, bool profileHeaderVisible,@JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson) Uint8List? profileHeaderImageData,@JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson) Uint8List? pkBannerImageData, String? pkBannerCachedUrl, bool pluralkitSyncIgnored, bool isDeleted, int? deleteIntentEpoch, int? deletePushStartedAt, bool isAlwaysFronting
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
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? pronouns = freezed,Object? emoji = null,Object? age = freezed,Object? bio = freezed,Object? avatarImageData = freezed,Object? isActive = null,Object? createdAt = null,Object? displayOrder = null,Object? isAdmin = null,Object? customColorEnabled = null,Object? customColorHex = freezed,Object? parentSystemId = freezed,Object? pluralkitUuid = freezed,Object? pluralkitId = freezed,Object? markdownEnabled = null,Object? displayName = freezed,Object? birthday = freezed,Object? proxyTagsJson = freezed,Object? pkBannerUrl = freezed,Object? profileHeaderSource = null,Object? profileHeaderLayout = null,Object? profileHeaderVisible = null,Object? profileHeaderImageData = freezed,Object? pkBannerImageData = freezed,Object? pkBannerCachedUrl = freezed,Object? pluralkitSyncIgnored = null,Object? isDeleted = null,Object? deleteIntentEpoch = freezed,Object? deletePushStartedAt = freezed,Object? isAlwaysFronting = null,}) {
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
as bool,displayName: freezed == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String?,birthday: freezed == birthday ? _self.birthday : birthday // ignore: cast_nullable_to_non_nullable
as String?,proxyTagsJson: freezed == proxyTagsJson ? _self.proxyTagsJson : proxyTagsJson // ignore: cast_nullable_to_non_nullable
as String?,pkBannerUrl: freezed == pkBannerUrl ? _self.pkBannerUrl : pkBannerUrl // ignore: cast_nullable_to_non_nullable
as String?,profileHeaderSource: null == profileHeaderSource ? _self.profileHeaderSource : profileHeaderSource // ignore: cast_nullable_to_non_nullable
as MemberProfileHeaderSource,profileHeaderLayout: null == profileHeaderLayout ? _self.profileHeaderLayout : profileHeaderLayout // ignore: cast_nullable_to_non_nullable
as MemberProfileHeaderLayout,profileHeaderVisible: null == profileHeaderVisible ? _self.profileHeaderVisible : profileHeaderVisible // ignore: cast_nullable_to_non_nullable
as bool,profileHeaderImageData: freezed == profileHeaderImageData ? _self.profileHeaderImageData : profileHeaderImageData // ignore: cast_nullable_to_non_nullable
as Uint8List?,pkBannerImageData: freezed == pkBannerImageData ? _self.pkBannerImageData : pkBannerImageData // ignore: cast_nullable_to_non_nullable
as Uint8List?,pkBannerCachedUrl: freezed == pkBannerCachedUrl ? _self.pkBannerCachedUrl : pkBannerCachedUrl // ignore: cast_nullable_to_non_nullable
as String?,pluralkitSyncIgnored: null == pluralkitSyncIgnored ? _self.pluralkitSyncIgnored : pluralkitSyncIgnored // ignore: cast_nullable_to_non_nullable
as bool,isDeleted: null == isDeleted ? _self.isDeleted : isDeleted // ignore: cast_nullable_to_non_nullable
as bool,deleteIntentEpoch: freezed == deleteIntentEpoch ? _self.deleteIntentEpoch : deleteIntentEpoch // ignore: cast_nullable_to_non_nullable
as int?,deletePushStartedAt: freezed == deletePushStartedAt ? _self.deletePushStartedAt : deletePushStartedAt // ignore: cast_nullable_to_non_nullable
as int?,isAlwaysFronting: null == isAlwaysFronting ? _self.isAlwaysFronting : isAlwaysFronting // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
