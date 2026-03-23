// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'friend_record.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$FriendRecord {

 String get id; String get displayName; String get publicKeyHex; String? get sharedSecretHex; List<String> get grantedScopes; bool get isVerified; DateTime get createdAt; DateTime? get lastSyncAt;
/// Create a copy of FriendRecord
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FriendRecordCopyWith<FriendRecord> get copyWith => _$FriendRecordCopyWithImpl<FriendRecord>(this as FriendRecord, _$identity);

  /// Serializes this FriendRecord to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FriendRecord&&(identical(other.id, id) || other.id == id)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.publicKeyHex, publicKeyHex) || other.publicKeyHex == publicKeyHex)&&(identical(other.sharedSecretHex, sharedSecretHex) || other.sharedSecretHex == sharedSecretHex)&&const DeepCollectionEquality().equals(other.grantedScopes, grantedScopes)&&(identical(other.isVerified, isVerified) || other.isVerified == isVerified)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.lastSyncAt, lastSyncAt) || other.lastSyncAt == lastSyncAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,displayName,publicKeyHex,sharedSecretHex,const DeepCollectionEquality().hash(grantedScopes),isVerified,createdAt,lastSyncAt);

@override
String toString() {
  return 'FriendRecord(id: $id, displayName: $displayName, publicKeyHex: $publicKeyHex, sharedSecretHex: $sharedSecretHex, grantedScopes: $grantedScopes, isVerified: $isVerified, createdAt: $createdAt, lastSyncAt: $lastSyncAt)';
}


}

/// @nodoc
abstract mixin class $FriendRecordCopyWith<$Res>  {
  factory $FriendRecordCopyWith(FriendRecord value, $Res Function(FriendRecord) _then) = _$FriendRecordCopyWithImpl;
@useResult
$Res call({
 String id, String displayName, String publicKeyHex, String? sharedSecretHex, List<String> grantedScopes, bool isVerified, DateTime createdAt, DateTime? lastSyncAt
});




}
/// @nodoc
class _$FriendRecordCopyWithImpl<$Res>
    implements $FriendRecordCopyWith<$Res> {
  _$FriendRecordCopyWithImpl(this._self, this._then);

  final FriendRecord _self;
  final $Res Function(FriendRecord) _then;

/// Create a copy of FriendRecord
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? displayName = null,Object? publicKeyHex = null,Object? sharedSecretHex = freezed,Object? grantedScopes = null,Object? isVerified = null,Object? createdAt = null,Object? lastSyncAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,publicKeyHex: null == publicKeyHex ? _self.publicKeyHex : publicKeyHex // ignore: cast_nullable_to_non_nullable
as String,sharedSecretHex: freezed == sharedSecretHex ? _self.sharedSecretHex : sharedSecretHex // ignore: cast_nullable_to_non_nullable
as String?,grantedScopes: null == grantedScopes ? _self.grantedScopes : grantedScopes // ignore: cast_nullable_to_non_nullable
as List<String>,isVerified: null == isVerified ? _self.isVerified : isVerified // ignore: cast_nullable_to_non_nullable
as bool,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,lastSyncAt: freezed == lastSyncAt ? _self.lastSyncAt : lastSyncAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [FriendRecord].
extension FriendRecordPatterns on FriendRecord {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FriendRecord value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FriendRecord() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FriendRecord value)  $default,){
final _that = this;
switch (_that) {
case _FriendRecord():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FriendRecord value)?  $default,){
final _that = this;
switch (_that) {
case _FriendRecord() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String displayName,  String publicKeyHex,  String? sharedSecretHex,  List<String> grantedScopes,  bool isVerified,  DateTime createdAt,  DateTime? lastSyncAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FriendRecord() when $default != null:
return $default(_that.id,_that.displayName,_that.publicKeyHex,_that.sharedSecretHex,_that.grantedScopes,_that.isVerified,_that.createdAt,_that.lastSyncAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String displayName,  String publicKeyHex,  String? sharedSecretHex,  List<String> grantedScopes,  bool isVerified,  DateTime createdAt,  DateTime? lastSyncAt)  $default,) {final _that = this;
switch (_that) {
case _FriendRecord():
return $default(_that.id,_that.displayName,_that.publicKeyHex,_that.sharedSecretHex,_that.grantedScopes,_that.isVerified,_that.createdAt,_that.lastSyncAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String displayName,  String publicKeyHex,  String? sharedSecretHex,  List<String> grantedScopes,  bool isVerified,  DateTime createdAt,  DateTime? lastSyncAt)?  $default,) {final _that = this;
switch (_that) {
case _FriendRecord() when $default != null:
return $default(_that.id,_that.displayName,_that.publicKeyHex,_that.sharedSecretHex,_that.grantedScopes,_that.isVerified,_that.createdAt,_that.lastSyncAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _FriendRecord implements FriendRecord {
  const _FriendRecord({required this.id, required this.displayName, required this.publicKeyHex, this.sharedSecretHex, final  List<String> grantedScopes = const <String>[], this.isVerified = false, required this.createdAt, this.lastSyncAt}): _grantedScopes = grantedScopes;
  factory _FriendRecord.fromJson(Map<String, dynamic> json) => _$FriendRecordFromJson(json);

@override final  String id;
@override final  String displayName;
@override final  String publicKeyHex;
@override final  String? sharedSecretHex;
 final  List<String> _grantedScopes;
@override@JsonKey() List<String> get grantedScopes {
  if (_grantedScopes is EqualUnmodifiableListView) return _grantedScopes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_grantedScopes);
}

@override@JsonKey() final  bool isVerified;
@override final  DateTime createdAt;
@override final  DateTime? lastSyncAt;

/// Create a copy of FriendRecord
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FriendRecordCopyWith<_FriendRecord> get copyWith => __$FriendRecordCopyWithImpl<_FriendRecord>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$FriendRecordToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FriendRecord&&(identical(other.id, id) || other.id == id)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.publicKeyHex, publicKeyHex) || other.publicKeyHex == publicKeyHex)&&(identical(other.sharedSecretHex, sharedSecretHex) || other.sharedSecretHex == sharedSecretHex)&&const DeepCollectionEquality().equals(other._grantedScopes, _grantedScopes)&&(identical(other.isVerified, isVerified) || other.isVerified == isVerified)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.lastSyncAt, lastSyncAt) || other.lastSyncAt == lastSyncAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,displayName,publicKeyHex,sharedSecretHex,const DeepCollectionEquality().hash(_grantedScopes),isVerified,createdAt,lastSyncAt);

@override
String toString() {
  return 'FriendRecord(id: $id, displayName: $displayName, publicKeyHex: $publicKeyHex, sharedSecretHex: $sharedSecretHex, grantedScopes: $grantedScopes, isVerified: $isVerified, createdAt: $createdAt, lastSyncAt: $lastSyncAt)';
}


}

/// @nodoc
abstract mixin class _$FriendRecordCopyWith<$Res> implements $FriendRecordCopyWith<$Res> {
  factory _$FriendRecordCopyWith(_FriendRecord value, $Res Function(_FriendRecord) _then) = __$FriendRecordCopyWithImpl;
@override @useResult
$Res call({
 String id, String displayName, String publicKeyHex, String? sharedSecretHex, List<String> grantedScopes, bool isVerified, DateTime createdAt, DateTime? lastSyncAt
});




}
/// @nodoc
class __$FriendRecordCopyWithImpl<$Res>
    implements _$FriendRecordCopyWith<$Res> {
  __$FriendRecordCopyWithImpl(this._self, this._then);

  final _FriendRecord _self;
  final $Res Function(_FriendRecord) _then;

/// Create a copy of FriendRecord
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? displayName = null,Object? publicKeyHex = null,Object? sharedSecretHex = freezed,Object? grantedScopes = null,Object? isVerified = null,Object? createdAt = null,Object? lastSyncAt = freezed,}) {
  return _then(_FriendRecord(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,publicKeyHex: null == publicKeyHex ? _self.publicKeyHex : publicKeyHex // ignore: cast_nullable_to_non_nullable
as String,sharedSecretHex: freezed == sharedSecretHex ? _self.sharedSecretHex : sharedSecretHex // ignore: cast_nullable_to_non_nullable
as String?,grantedScopes: null == grantedScopes ? _self._grantedScopes : grantedScopes // ignore: cast_nullable_to_non_nullable
as List<String>,isVerified: null == isVerified ? _self.isVerified : isVerified // ignore: cast_nullable_to_non_nullable
as bool,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,lastSyncAt: freezed == lastSyncAt ? _self.lastSyncAt : lastSyncAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
