// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'friend.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Friend {

 String get id; String get displayName; String? get peerSharingId;@JsonKey(fromJson: _friendBytesFromJson, toJson: _friendBytesToJson) Uint8List? get pairwiseSecret;@JsonKey(fromJson: _friendBytesFromJson, toJson: _friendBytesToJson) Uint8List? get pinnedIdentity;/// Scopes this friend has offered to us.
 List<ShareScope> get offeredScopes;/// Legacy public identity material, hex-encoded.
///
/// For Phase 4 relationships this stores the canonical identity bundle hex
/// so older persistence/export paths still have a non-secret public value.
 String get publicKeyHex;/// Scopes we have granted this friend.
 List<ShareScope> get grantedScopes; DateTime get addedAt; DateTime? get establishedAt; DateTime? get lastSyncAt;/// Legacy shared secret mirror, hex-encoded.
///
/// For Phase 4 relationships this mirrors [pairwiseSecret] in hex so older
/// persistence/export paths still have a compatible field.
 String? get sharedSecretHex; String? get initId;/// Whether out-of-band verification has been completed.
 bool get isVerified;
/// Create a copy of Friend
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FriendCopyWith<Friend> get copyWith => _$FriendCopyWithImpl<Friend>(this as Friend, _$identity);

  /// Serializes this Friend to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Friend&&(identical(other.id, id) || other.id == id)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.peerSharingId, peerSharingId) || other.peerSharingId == peerSharingId)&&const DeepCollectionEquality().equals(other.pairwiseSecret, pairwiseSecret)&&const DeepCollectionEquality().equals(other.pinnedIdentity, pinnedIdentity)&&const DeepCollectionEquality().equals(other.offeredScopes, offeredScopes)&&(identical(other.publicKeyHex, publicKeyHex) || other.publicKeyHex == publicKeyHex)&&const DeepCollectionEquality().equals(other.grantedScopes, grantedScopes)&&(identical(other.addedAt, addedAt) || other.addedAt == addedAt)&&(identical(other.establishedAt, establishedAt) || other.establishedAt == establishedAt)&&(identical(other.lastSyncAt, lastSyncAt) || other.lastSyncAt == lastSyncAt)&&(identical(other.sharedSecretHex, sharedSecretHex) || other.sharedSecretHex == sharedSecretHex)&&(identical(other.initId, initId) || other.initId == initId)&&(identical(other.isVerified, isVerified) || other.isVerified == isVerified));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,displayName,peerSharingId,const DeepCollectionEquality().hash(pairwiseSecret),const DeepCollectionEquality().hash(pinnedIdentity),const DeepCollectionEquality().hash(offeredScopes),publicKeyHex,const DeepCollectionEquality().hash(grantedScopes),addedAt,establishedAt,lastSyncAt,sharedSecretHex,initId,isVerified);

@override
String toString() {
  return 'Friend(id: $id, displayName: $displayName, peerSharingId: $peerSharingId, pairwiseSecret: $pairwiseSecret, pinnedIdentity: $pinnedIdentity, offeredScopes: $offeredScopes, publicKeyHex: $publicKeyHex, grantedScopes: $grantedScopes, addedAt: $addedAt, establishedAt: $establishedAt, lastSyncAt: $lastSyncAt, sharedSecretHex: $sharedSecretHex, initId: $initId, isVerified: $isVerified)';
}


}

/// @nodoc
abstract mixin class $FriendCopyWith<$Res>  {
  factory $FriendCopyWith(Friend value, $Res Function(Friend) _then) = _$FriendCopyWithImpl;
@useResult
$Res call({
 String id, String displayName, String? peerSharingId,@JsonKey(fromJson: _friendBytesFromJson, toJson: _friendBytesToJson) Uint8List? pairwiseSecret,@JsonKey(fromJson: _friendBytesFromJson, toJson: _friendBytesToJson) Uint8List? pinnedIdentity, List<ShareScope> offeredScopes, String publicKeyHex, List<ShareScope> grantedScopes, DateTime addedAt, DateTime? establishedAt, DateTime? lastSyncAt, String? sharedSecretHex, String? initId, bool isVerified
});




}
/// @nodoc
class _$FriendCopyWithImpl<$Res>
    implements $FriendCopyWith<$Res> {
  _$FriendCopyWithImpl(this._self, this._then);

  final Friend _self;
  final $Res Function(Friend) _then;

/// Create a copy of Friend
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? displayName = null,Object? peerSharingId = freezed,Object? pairwiseSecret = freezed,Object? pinnedIdentity = freezed,Object? offeredScopes = null,Object? publicKeyHex = null,Object? grantedScopes = null,Object? addedAt = null,Object? establishedAt = freezed,Object? lastSyncAt = freezed,Object? sharedSecretHex = freezed,Object? initId = freezed,Object? isVerified = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,peerSharingId: freezed == peerSharingId ? _self.peerSharingId : peerSharingId // ignore: cast_nullable_to_non_nullable
as String?,pairwiseSecret: freezed == pairwiseSecret ? _self.pairwiseSecret : pairwiseSecret // ignore: cast_nullable_to_non_nullable
as Uint8List?,pinnedIdentity: freezed == pinnedIdentity ? _self.pinnedIdentity : pinnedIdentity // ignore: cast_nullable_to_non_nullable
as Uint8List?,offeredScopes: null == offeredScopes ? _self.offeredScopes : offeredScopes // ignore: cast_nullable_to_non_nullable
as List<ShareScope>,publicKeyHex: null == publicKeyHex ? _self.publicKeyHex : publicKeyHex // ignore: cast_nullable_to_non_nullable
as String,grantedScopes: null == grantedScopes ? _self.grantedScopes : grantedScopes // ignore: cast_nullable_to_non_nullable
as List<ShareScope>,addedAt: null == addedAt ? _self.addedAt : addedAt // ignore: cast_nullable_to_non_nullable
as DateTime,establishedAt: freezed == establishedAt ? _self.establishedAt : establishedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,lastSyncAt: freezed == lastSyncAt ? _self.lastSyncAt : lastSyncAt // ignore: cast_nullable_to_non_nullable
as DateTime?,sharedSecretHex: freezed == sharedSecretHex ? _self.sharedSecretHex : sharedSecretHex // ignore: cast_nullable_to_non_nullable
as String?,initId: freezed == initId ? _self.initId : initId // ignore: cast_nullable_to_non_nullable
as String?,isVerified: null == isVerified ? _self.isVerified : isVerified // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [Friend].
extension FriendPatterns on Friend {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Friend value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Friend() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Friend value)  $default,){
final _that = this;
switch (_that) {
case _Friend():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Friend value)?  $default,){
final _that = this;
switch (_that) {
case _Friend() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String displayName,  String? peerSharingId, @JsonKey(fromJson: _friendBytesFromJson, toJson: _friendBytesToJson)  Uint8List? pairwiseSecret, @JsonKey(fromJson: _friendBytesFromJson, toJson: _friendBytesToJson)  Uint8List? pinnedIdentity,  List<ShareScope> offeredScopes,  String publicKeyHex,  List<ShareScope> grantedScopes,  DateTime addedAt,  DateTime? establishedAt,  DateTime? lastSyncAt,  String? sharedSecretHex,  String? initId,  bool isVerified)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Friend() when $default != null:
return $default(_that.id,_that.displayName,_that.peerSharingId,_that.pairwiseSecret,_that.pinnedIdentity,_that.offeredScopes,_that.publicKeyHex,_that.grantedScopes,_that.addedAt,_that.establishedAt,_that.lastSyncAt,_that.sharedSecretHex,_that.initId,_that.isVerified);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String displayName,  String? peerSharingId, @JsonKey(fromJson: _friendBytesFromJson, toJson: _friendBytesToJson)  Uint8List? pairwiseSecret, @JsonKey(fromJson: _friendBytesFromJson, toJson: _friendBytesToJson)  Uint8List? pinnedIdentity,  List<ShareScope> offeredScopes,  String publicKeyHex,  List<ShareScope> grantedScopes,  DateTime addedAt,  DateTime? establishedAt,  DateTime? lastSyncAt,  String? sharedSecretHex,  String? initId,  bool isVerified)  $default,) {final _that = this;
switch (_that) {
case _Friend():
return $default(_that.id,_that.displayName,_that.peerSharingId,_that.pairwiseSecret,_that.pinnedIdentity,_that.offeredScopes,_that.publicKeyHex,_that.grantedScopes,_that.addedAt,_that.establishedAt,_that.lastSyncAt,_that.sharedSecretHex,_that.initId,_that.isVerified);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String displayName,  String? peerSharingId, @JsonKey(fromJson: _friendBytesFromJson, toJson: _friendBytesToJson)  Uint8List? pairwiseSecret, @JsonKey(fromJson: _friendBytesFromJson, toJson: _friendBytesToJson)  Uint8List? pinnedIdentity,  List<ShareScope> offeredScopes,  String publicKeyHex,  List<ShareScope> grantedScopes,  DateTime addedAt,  DateTime? establishedAt,  DateTime? lastSyncAt,  String? sharedSecretHex,  String? initId,  bool isVerified)?  $default,) {final _that = this;
switch (_that) {
case _Friend() when $default != null:
return $default(_that.id,_that.displayName,_that.peerSharingId,_that.pairwiseSecret,_that.pinnedIdentity,_that.offeredScopes,_that.publicKeyHex,_that.grantedScopes,_that.addedAt,_that.establishedAt,_that.lastSyncAt,_that.sharedSecretHex,_that.initId,_that.isVerified);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Friend implements Friend {
  const _Friend({required this.id, required this.displayName, this.peerSharingId, @JsonKey(fromJson: _friendBytesFromJson, toJson: _friendBytesToJson) this.pairwiseSecret, @JsonKey(fromJson: _friendBytesFromJson, toJson: _friendBytesToJson) this.pinnedIdentity, final  List<ShareScope> offeredScopes = const <ShareScope>[], required this.publicKeyHex, required final  List<ShareScope> grantedScopes, required this.addedAt, this.establishedAt, this.lastSyncAt, this.sharedSecretHex, this.initId, this.isVerified = false}): _offeredScopes = offeredScopes,_grantedScopes = grantedScopes;
  factory _Friend.fromJson(Map<String, dynamic> json) => _$FriendFromJson(json);

@override final  String id;
@override final  String displayName;
@override final  String? peerSharingId;
@override@JsonKey(fromJson: _friendBytesFromJson, toJson: _friendBytesToJson) final  Uint8List? pairwiseSecret;
@override@JsonKey(fromJson: _friendBytesFromJson, toJson: _friendBytesToJson) final  Uint8List? pinnedIdentity;
/// Scopes this friend has offered to us.
 final  List<ShareScope> _offeredScopes;
/// Scopes this friend has offered to us.
@override@JsonKey() List<ShareScope> get offeredScopes {
  if (_offeredScopes is EqualUnmodifiableListView) return _offeredScopes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_offeredScopes);
}

/// Legacy public identity material, hex-encoded.
///
/// For Phase 4 relationships this stores the canonical identity bundle hex
/// so older persistence/export paths still have a non-secret public value.
@override final  String publicKeyHex;
/// Scopes we have granted this friend.
 final  List<ShareScope> _grantedScopes;
/// Scopes we have granted this friend.
@override List<ShareScope> get grantedScopes {
  if (_grantedScopes is EqualUnmodifiableListView) return _grantedScopes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_grantedScopes);
}

@override final  DateTime addedAt;
@override final  DateTime? establishedAt;
@override final  DateTime? lastSyncAt;
/// Legacy shared secret mirror, hex-encoded.
///
/// For Phase 4 relationships this mirrors [pairwiseSecret] in hex so older
/// persistence/export paths still have a compatible field.
@override final  String? sharedSecretHex;
@override final  String? initId;
/// Whether out-of-band verification has been completed.
@override@JsonKey() final  bool isVerified;

/// Create a copy of Friend
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FriendCopyWith<_Friend> get copyWith => __$FriendCopyWithImpl<_Friend>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$FriendToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Friend&&(identical(other.id, id) || other.id == id)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.peerSharingId, peerSharingId) || other.peerSharingId == peerSharingId)&&const DeepCollectionEquality().equals(other.pairwiseSecret, pairwiseSecret)&&const DeepCollectionEquality().equals(other.pinnedIdentity, pinnedIdentity)&&const DeepCollectionEquality().equals(other._offeredScopes, _offeredScopes)&&(identical(other.publicKeyHex, publicKeyHex) || other.publicKeyHex == publicKeyHex)&&const DeepCollectionEquality().equals(other._grantedScopes, _grantedScopes)&&(identical(other.addedAt, addedAt) || other.addedAt == addedAt)&&(identical(other.establishedAt, establishedAt) || other.establishedAt == establishedAt)&&(identical(other.lastSyncAt, lastSyncAt) || other.lastSyncAt == lastSyncAt)&&(identical(other.sharedSecretHex, sharedSecretHex) || other.sharedSecretHex == sharedSecretHex)&&(identical(other.initId, initId) || other.initId == initId)&&(identical(other.isVerified, isVerified) || other.isVerified == isVerified));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,displayName,peerSharingId,const DeepCollectionEquality().hash(pairwiseSecret),const DeepCollectionEquality().hash(pinnedIdentity),const DeepCollectionEquality().hash(_offeredScopes),publicKeyHex,const DeepCollectionEquality().hash(_grantedScopes),addedAt,establishedAt,lastSyncAt,sharedSecretHex,initId,isVerified);

@override
String toString() {
  return 'Friend(id: $id, displayName: $displayName, peerSharingId: $peerSharingId, pairwiseSecret: $pairwiseSecret, pinnedIdentity: $pinnedIdentity, offeredScopes: $offeredScopes, publicKeyHex: $publicKeyHex, grantedScopes: $grantedScopes, addedAt: $addedAt, establishedAt: $establishedAt, lastSyncAt: $lastSyncAt, sharedSecretHex: $sharedSecretHex, initId: $initId, isVerified: $isVerified)';
}


}

/// @nodoc
abstract mixin class _$FriendCopyWith<$Res> implements $FriendCopyWith<$Res> {
  factory _$FriendCopyWith(_Friend value, $Res Function(_Friend) _then) = __$FriendCopyWithImpl;
@override @useResult
$Res call({
 String id, String displayName, String? peerSharingId,@JsonKey(fromJson: _friendBytesFromJson, toJson: _friendBytesToJson) Uint8List? pairwiseSecret,@JsonKey(fromJson: _friendBytesFromJson, toJson: _friendBytesToJson) Uint8List? pinnedIdentity, List<ShareScope> offeredScopes, String publicKeyHex, List<ShareScope> grantedScopes, DateTime addedAt, DateTime? establishedAt, DateTime? lastSyncAt, String? sharedSecretHex, String? initId, bool isVerified
});




}
/// @nodoc
class __$FriendCopyWithImpl<$Res>
    implements _$FriendCopyWith<$Res> {
  __$FriendCopyWithImpl(this._self, this._then);

  final _Friend _self;
  final $Res Function(_Friend) _then;

/// Create a copy of Friend
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? displayName = null,Object? peerSharingId = freezed,Object? pairwiseSecret = freezed,Object? pinnedIdentity = freezed,Object? offeredScopes = null,Object? publicKeyHex = null,Object? grantedScopes = null,Object? addedAt = null,Object? establishedAt = freezed,Object? lastSyncAt = freezed,Object? sharedSecretHex = freezed,Object? initId = freezed,Object? isVerified = null,}) {
  return _then(_Friend(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,peerSharingId: freezed == peerSharingId ? _self.peerSharingId : peerSharingId // ignore: cast_nullable_to_non_nullable
as String?,pairwiseSecret: freezed == pairwiseSecret ? _self.pairwiseSecret : pairwiseSecret // ignore: cast_nullable_to_non_nullable
as Uint8List?,pinnedIdentity: freezed == pinnedIdentity ? _self.pinnedIdentity : pinnedIdentity // ignore: cast_nullable_to_non_nullable
as Uint8List?,offeredScopes: null == offeredScopes ? _self._offeredScopes : offeredScopes // ignore: cast_nullable_to_non_nullable
as List<ShareScope>,publicKeyHex: null == publicKeyHex ? _self.publicKeyHex : publicKeyHex // ignore: cast_nullable_to_non_nullable
as String,grantedScopes: null == grantedScopes ? _self._grantedScopes : grantedScopes // ignore: cast_nullable_to_non_nullable
as List<ShareScope>,addedAt: null == addedAt ? _self.addedAt : addedAt // ignore: cast_nullable_to_non_nullable
as DateTime,establishedAt: freezed == establishedAt ? _self.establishedAt : establishedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,lastSyncAt: freezed == lastSyncAt ? _self.lastSyncAt : lastSyncAt // ignore: cast_nullable_to_non_nullable
as DateTime?,sharedSecretHex: freezed == sharedSecretHex ? _self.sharedSecretHex : sharedSecretHex // ignore: cast_nullable_to_non_nullable
as String?,initId: freezed == initId ? _self.initId : initId // ignore: cast_nullable_to_non_nullable
as String?,isVerified: null == isVerified ? _self.isVerified : isVerified // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
