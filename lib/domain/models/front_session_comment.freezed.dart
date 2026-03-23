// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'front_session_comment.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$FrontSessionComment {

 String get id; String get sessionId; String get body; DateTime get timestamp; DateTime get createdAt;
/// Create a copy of FrontSessionComment
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FrontSessionCommentCopyWith<FrontSessionComment> get copyWith => _$FrontSessionCommentCopyWithImpl<FrontSessionComment>(this as FrontSessionComment, _$identity);

  /// Serializes this FrontSessionComment to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FrontSessionComment&&(identical(other.id, id) || other.id == id)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.body, body) || other.body == body)&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,sessionId,body,timestamp,createdAt);

@override
String toString() {
  return 'FrontSessionComment(id: $id, sessionId: $sessionId, body: $body, timestamp: $timestamp, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class $FrontSessionCommentCopyWith<$Res>  {
  factory $FrontSessionCommentCopyWith(FrontSessionComment value, $Res Function(FrontSessionComment) _then) = _$FrontSessionCommentCopyWithImpl;
@useResult
$Res call({
 String id, String sessionId, String body, DateTime timestamp, DateTime createdAt
});




}
/// @nodoc
class _$FrontSessionCommentCopyWithImpl<$Res>
    implements $FrontSessionCommentCopyWith<$Res> {
  _$FrontSessionCommentCopyWithImpl(this._self, this._then);

  final FrontSessionComment _self;
  final $Res Function(FrontSessionComment) _then;

/// Create a copy of FrontSessionComment
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? sessionId = null,Object? body = null,Object? timestamp = null,Object? createdAt = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,body: null == body ? _self.body : body // ignore: cast_nullable_to_non_nullable
as String,timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as DateTime,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [FrontSessionComment].
extension FrontSessionCommentPatterns on FrontSessionComment {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FrontSessionComment value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FrontSessionComment() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FrontSessionComment value)  $default,){
final _that = this;
switch (_that) {
case _FrontSessionComment():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FrontSessionComment value)?  $default,){
final _that = this;
switch (_that) {
case _FrontSessionComment() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String sessionId,  String body,  DateTime timestamp,  DateTime createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FrontSessionComment() when $default != null:
return $default(_that.id,_that.sessionId,_that.body,_that.timestamp,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String sessionId,  String body,  DateTime timestamp,  DateTime createdAt)  $default,) {final _that = this;
switch (_that) {
case _FrontSessionComment():
return $default(_that.id,_that.sessionId,_that.body,_that.timestamp,_that.createdAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String sessionId,  String body,  DateTime timestamp,  DateTime createdAt)?  $default,) {final _that = this;
switch (_that) {
case _FrontSessionComment() when $default != null:
return $default(_that.id,_that.sessionId,_that.body,_that.timestamp,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _FrontSessionComment implements FrontSessionComment {
  const _FrontSessionComment({required this.id, required this.sessionId, required this.body, required this.timestamp, required this.createdAt});
  factory _FrontSessionComment.fromJson(Map<String, dynamic> json) => _$FrontSessionCommentFromJson(json);

@override final  String id;
@override final  String sessionId;
@override final  String body;
@override final  DateTime timestamp;
@override final  DateTime createdAt;

/// Create a copy of FrontSessionComment
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FrontSessionCommentCopyWith<_FrontSessionComment> get copyWith => __$FrontSessionCommentCopyWithImpl<_FrontSessionComment>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$FrontSessionCommentToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FrontSessionComment&&(identical(other.id, id) || other.id == id)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.body, body) || other.body == body)&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,sessionId,body,timestamp,createdAt);

@override
String toString() {
  return 'FrontSessionComment(id: $id, sessionId: $sessionId, body: $body, timestamp: $timestamp, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$FrontSessionCommentCopyWith<$Res> implements $FrontSessionCommentCopyWith<$Res> {
  factory _$FrontSessionCommentCopyWith(_FrontSessionComment value, $Res Function(_FrontSessionComment) _then) = __$FrontSessionCommentCopyWithImpl;
@override @useResult
$Res call({
 String id, String sessionId, String body, DateTime timestamp, DateTime createdAt
});




}
/// @nodoc
class __$FrontSessionCommentCopyWithImpl<$Res>
    implements _$FrontSessionCommentCopyWith<$Res> {
  __$FrontSessionCommentCopyWithImpl(this._self, this._then);

  final _FrontSessionComment _self;
  final $Res Function(_FrontSessionComment) _then;

/// Create a copy of FrontSessionComment
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? sessionId = null,Object? body = null,Object? timestamp = null,Object? createdAt = null,}) {
  return _then(_FrontSessionComment(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,body: null == body ? _self.body : body // ignore: cast_nullable_to_non_nullable
as String,timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as DateTime,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on
