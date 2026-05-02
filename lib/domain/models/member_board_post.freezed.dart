// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'member_board_post.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$MemberBoardPost {

 String get id; String? get targetMemberId; String? get authorId;/// Audience — exactly `'public'` or `'private'`.
 String get audience; String? get title; String get body; DateTime get createdAt;/// User-facing post timestamp. Equals [createdAt] for native posts;
/// equals SP `writtenAt` for SP-imported posts.
 DateTime get writtenAt;/// Non-null when the post has been edited at least once.
 DateTime? get editedAt; bool get isDeleted;
/// Create a copy of MemberBoardPost
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MemberBoardPostCopyWith<MemberBoardPost> get copyWith => _$MemberBoardPostCopyWithImpl<MemberBoardPost>(this as MemberBoardPost, _$identity);

  /// Serializes this MemberBoardPost to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MemberBoardPost&&(identical(other.id, id) || other.id == id)&&(identical(other.targetMemberId, targetMemberId) || other.targetMemberId == targetMemberId)&&(identical(other.authorId, authorId) || other.authorId == authorId)&&(identical(other.audience, audience) || other.audience == audience)&&(identical(other.title, title) || other.title == title)&&(identical(other.body, body) || other.body == body)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.writtenAt, writtenAt) || other.writtenAt == writtenAt)&&(identical(other.editedAt, editedAt) || other.editedAt == editedAt)&&(identical(other.isDeleted, isDeleted) || other.isDeleted == isDeleted));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,targetMemberId,authorId,audience,title,body,createdAt,writtenAt,editedAt,isDeleted);

@override
String toString() {
  return 'MemberBoardPost(id: $id, targetMemberId: $targetMemberId, authorId: $authorId, audience: $audience, title: $title, body: $body, createdAt: $createdAt, writtenAt: $writtenAt, editedAt: $editedAt, isDeleted: $isDeleted)';
}


}

/// @nodoc
abstract mixin class $MemberBoardPostCopyWith<$Res>  {
  factory $MemberBoardPostCopyWith(MemberBoardPost value, $Res Function(MemberBoardPost) _then) = _$MemberBoardPostCopyWithImpl;
@useResult
$Res call({
 String id, String? targetMemberId, String? authorId, String audience, String? title, String body, DateTime createdAt, DateTime writtenAt, DateTime? editedAt, bool isDeleted
});




}
/// @nodoc
class _$MemberBoardPostCopyWithImpl<$Res>
    implements $MemberBoardPostCopyWith<$Res> {
  _$MemberBoardPostCopyWithImpl(this._self, this._then);

  final MemberBoardPost _self;
  final $Res Function(MemberBoardPost) _then;

/// Create a copy of MemberBoardPost
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? targetMemberId = freezed,Object? authorId = freezed,Object? audience = null,Object? title = freezed,Object? body = null,Object? createdAt = null,Object? writtenAt = null,Object? editedAt = freezed,Object? isDeleted = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,targetMemberId: freezed == targetMemberId ? _self.targetMemberId : targetMemberId // ignore: cast_nullable_to_non_nullable
as String?,authorId: freezed == authorId ? _self.authorId : authorId // ignore: cast_nullable_to_non_nullable
as String?,audience: null == audience ? _self.audience : audience // ignore: cast_nullable_to_non_nullable
as String,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,body: null == body ? _self.body : body // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,writtenAt: null == writtenAt ? _self.writtenAt : writtenAt // ignore: cast_nullable_to_non_nullable
as DateTime,editedAt: freezed == editedAt ? _self.editedAt : editedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,isDeleted: null == isDeleted ? _self.isDeleted : isDeleted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [MemberBoardPost].
extension MemberBoardPostPatterns on MemberBoardPost {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MemberBoardPost value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MemberBoardPost() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MemberBoardPost value)  $default,){
final _that = this;
switch (_that) {
case _MemberBoardPost():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MemberBoardPost value)?  $default,){
final _that = this;
switch (_that) {
case _MemberBoardPost() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String? targetMemberId,  String? authorId,  String audience,  String? title,  String body,  DateTime createdAt,  DateTime writtenAt,  DateTime? editedAt,  bool isDeleted)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MemberBoardPost() when $default != null:
return $default(_that.id,_that.targetMemberId,_that.authorId,_that.audience,_that.title,_that.body,_that.createdAt,_that.writtenAt,_that.editedAt,_that.isDeleted);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String? targetMemberId,  String? authorId,  String audience,  String? title,  String body,  DateTime createdAt,  DateTime writtenAt,  DateTime? editedAt,  bool isDeleted)  $default,) {final _that = this;
switch (_that) {
case _MemberBoardPost():
return $default(_that.id,_that.targetMemberId,_that.authorId,_that.audience,_that.title,_that.body,_that.createdAt,_that.writtenAt,_that.editedAt,_that.isDeleted);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String? targetMemberId,  String? authorId,  String audience,  String? title,  String body,  DateTime createdAt,  DateTime writtenAt,  DateTime? editedAt,  bool isDeleted)?  $default,) {final _that = this;
switch (_that) {
case _MemberBoardPost() when $default != null:
return $default(_that.id,_that.targetMemberId,_that.authorId,_that.audience,_that.title,_that.body,_that.createdAt,_that.writtenAt,_that.editedAt,_that.isDeleted);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _MemberBoardPost implements MemberBoardPost {
  const _MemberBoardPost({required this.id, this.targetMemberId, this.authorId, required this.audience, this.title, required this.body, required this.createdAt, required this.writtenAt, this.editedAt, this.isDeleted = false});
  factory _MemberBoardPost.fromJson(Map<String, dynamic> json) => _$MemberBoardPostFromJson(json);

@override final  String id;
@override final  String? targetMemberId;
@override final  String? authorId;
/// Audience — exactly `'public'` or `'private'`.
@override final  String audience;
@override final  String? title;
@override final  String body;
@override final  DateTime createdAt;
/// User-facing post timestamp. Equals [createdAt] for native posts;
/// equals SP `writtenAt` for SP-imported posts.
@override final  DateTime writtenAt;
/// Non-null when the post has been edited at least once.
@override final  DateTime? editedAt;
@override@JsonKey() final  bool isDeleted;

/// Create a copy of MemberBoardPost
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MemberBoardPostCopyWith<_MemberBoardPost> get copyWith => __$MemberBoardPostCopyWithImpl<_MemberBoardPost>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MemberBoardPostToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MemberBoardPost&&(identical(other.id, id) || other.id == id)&&(identical(other.targetMemberId, targetMemberId) || other.targetMemberId == targetMemberId)&&(identical(other.authorId, authorId) || other.authorId == authorId)&&(identical(other.audience, audience) || other.audience == audience)&&(identical(other.title, title) || other.title == title)&&(identical(other.body, body) || other.body == body)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.writtenAt, writtenAt) || other.writtenAt == writtenAt)&&(identical(other.editedAt, editedAt) || other.editedAt == editedAt)&&(identical(other.isDeleted, isDeleted) || other.isDeleted == isDeleted));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,targetMemberId,authorId,audience,title,body,createdAt,writtenAt,editedAt,isDeleted);

@override
String toString() {
  return 'MemberBoardPost(id: $id, targetMemberId: $targetMemberId, authorId: $authorId, audience: $audience, title: $title, body: $body, createdAt: $createdAt, writtenAt: $writtenAt, editedAt: $editedAt, isDeleted: $isDeleted)';
}


}

/// @nodoc
abstract mixin class _$MemberBoardPostCopyWith<$Res> implements $MemberBoardPostCopyWith<$Res> {
  factory _$MemberBoardPostCopyWith(_MemberBoardPost value, $Res Function(_MemberBoardPost) _then) = __$MemberBoardPostCopyWithImpl;
@override @useResult
$Res call({
 String id, String? targetMemberId, String? authorId, String audience, String? title, String body, DateTime createdAt, DateTime writtenAt, DateTime? editedAt, bool isDeleted
});




}
/// @nodoc
class __$MemberBoardPostCopyWithImpl<$Res>
    implements _$MemberBoardPostCopyWith<$Res> {
  __$MemberBoardPostCopyWithImpl(this._self, this._then);

  final _MemberBoardPost _self;
  final $Res Function(_MemberBoardPost) _then;

/// Create a copy of MemberBoardPost
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? targetMemberId = freezed,Object? authorId = freezed,Object? audience = null,Object? title = freezed,Object? body = null,Object? createdAt = null,Object? writtenAt = null,Object? editedAt = freezed,Object? isDeleted = null,}) {
  return _then(_MemberBoardPost(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,targetMemberId: freezed == targetMemberId ? _self.targetMemberId : targetMemberId // ignore: cast_nullable_to_non_nullable
as String?,authorId: freezed == authorId ? _self.authorId : authorId // ignore: cast_nullable_to_non_nullable
as String?,audience: null == audience ? _self.audience : audience // ignore: cast_nullable_to_non_nullable
as String,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,body: null == body ? _self.body : body // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,writtenAt: null == writtenAt ? _self.writtenAt : writtenAt // ignore: cast_nullable_to_non_nullable
as DateTime,editedAt: freezed == editedAt ? _self.editedAt : editedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,isDeleted: null == isDeleted ? _self.isDeleted : isDeleted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
