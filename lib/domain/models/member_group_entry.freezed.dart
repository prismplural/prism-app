// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'member_group_entry.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$MemberGroupEntry {

 String get id; String get groupId; String get memberId;
/// Create a copy of MemberGroupEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MemberGroupEntryCopyWith<MemberGroupEntry> get copyWith => _$MemberGroupEntryCopyWithImpl<MemberGroupEntry>(this as MemberGroupEntry, _$identity);

  /// Serializes this MemberGroupEntry to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MemberGroupEntry&&(identical(other.id, id) || other.id == id)&&(identical(other.groupId, groupId) || other.groupId == groupId)&&(identical(other.memberId, memberId) || other.memberId == memberId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,groupId,memberId);

@override
String toString() {
  return 'MemberGroupEntry(id: $id, groupId: $groupId, memberId: $memberId)';
}


}

/// @nodoc
abstract mixin class $MemberGroupEntryCopyWith<$Res>  {
  factory $MemberGroupEntryCopyWith(MemberGroupEntry value, $Res Function(MemberGroupEntry) _then) = _$MemberGroupEntryCopyWithImpl;
@useResult
$Res call({
 String id, String groupId, String memberId
});




}
/// @nodoc
class _$MemberGroupEntryCopyWithImpl<$Res>
    implements $MemberGroupEntryCopyWith<$Res> {
  _$MemberGroupEntryCopyWithImpl(this._self, this._then);

  final MemberGroupEntry _self;
  final $Res Function(MemberGroupEntry) _then;

/// Create a copy of MemberGroupEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? groupId = null,Object? memberId = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,groupId: null == groupId ? _self.groupId : groupId // ignore: cast_nullable_to_non_nullable
as String,memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [MemberGroupEntry].
extension MemberGroupEntryPatterns on MemberGroupEntry {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MemberGroupEntry value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MemberGroupEntry() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MemberGroupEntry value)  $default,){
final _that = this;
switch (_that) {
case _MemberGroupEntry():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MemberGroupEntry value)?  $default,){
final _that = this;
switch (_that) {
case _MemberGroupEntry() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String groupId,  String memberId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MemberGroupEntry() when $default != null:
return $default(_that.id,_that.groupId,_that.memberId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String groupId,  String memberId)  $default,) {final _that = this;
switch (_that) {
case _MemberGroupEntry():
return $default(_that.id,_that.groupId,_that.memberId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String groupId,  String memberId)?  $default,) {final _that = this;
switch (_that) {
case _MemberGroupEntry() when $default != null:
return $default(_that.id,_that.groupId,_that.memberId);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _MemberGroupEntry implements MemberGroupEntry {
  const _MemberGroupEntry({required this.id, required this.groupId, required this.memberId});
  factory _MemberGroupEntry.fromJson(Map<String, dynamic> json) => _$MemberGroupEntryFromJson(json);

@override final  String id;
@override final  String groupId;
@override final  String memberId;

/// Create a copy of MemberGroupEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MemberGroupEntryCopyWith<_MemberGroupEntry> get copyWith => __$MemberGroupEntryCopyWithImpl<_MemberGroupEntry>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MemberGroupEntryToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MemberGroupEntry&&(identical(other.id, id) || other.id == id)&&(identical(other.groupId, groupId) || other.groupId == groupId)&&(identical(other.memberId, memberId) || other.memberId == memberId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,groupId,memberId);

@override
String toString() {
  return 'MemberGroupEntry(id: $id, groupId: $groupId, memberId: $memberId)';
}


}

/// @nodoc
abstract mixin class _$MemberGroupEntryCopyWith<$Res> implements $MemberGroupEntryCopyWith<$Res> {
  factory _$MemberGroupEntryCopyWith(_MemberGroupEntry value, $Res Function(_MemberGroupEntry) _then) = __$MemberGroupEntryCopyWithImpl;
@override @useResult
$Res call({
 String id, String groupId, String memberId
});




}
/// @nodoc
class __$MemberGroupEntryCopyWithImpl<$Res>
    implements _$MemberGroupEntryCopyWith<$Res> {
  __$MemberGroupEntryCopyWithImpl(this._self, this._then);

  final _MemberGroupEntry _self;
  final $Res Function(_MemberGroupEntry) _then;

/// Create a copy of MemberGroupEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? groupId = null,Object? memberId = null,}) {
  return _then(_MemberGroupEntry(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,groupId: null == groupId ? _self.groupId : groupId // ignore: cast_nullable_to_non_nullable
as String,memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
