// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'poll_vote.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$PollVote {

 String get id; String get memberId; DateTime get votedAt; String? get responseText;
/// Create a copy of PollVote
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PollVoteCopyWith<PollVote> get copyWith => _$PollVoteCopyWithImpl<PollVote>(this as PollVote, _$identity);

  /// Serializes this PollVote to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PollVote&&(identical(other.id, id) || other.id == id)&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.votedAt, votedAt) || other.votedAt == votedAt)&&(identical(other.responseText, responseText) || other.responseText == responseText));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,memberId,votedAt,responseText);

@override
String toString() {
  return 'PollVote(id: $id, memberId: $memberId, votedAt: $votedAt, responseText: $responseText)';
}


}

/// @nodoc
abstract mixin class $PollVoteCopyWith<$Res>  {
  factory $PollVoteCopyWith(PollVote value, $Res Function(PollVote) _then) = _$PollVoteCopyWithImpl;
@useResult
$Res call({
 String id, String memberId, DateTime votedAt, String? responseText
});




}
/// @nodoc
class _$PollVoteCopyWithImpl<$Res>
    implements $PollVoteCopyWith<$Res> {
  _$PollVoteCopyWithImpl(this._self, this._then);

  final PollVote _self;
  final $Res Function(PollVote) _then;

/// Create a copy of PollVote
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? memberId = null,Object? votedAt = null,Object? responseText = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String,votedAt: null == votedAt ? _self.votedAt : votedAt // ignore: cast_nullable_to_non_nullable
as DateTime,responseText: freezed == responseText ? _self.responseText : responseText // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [PollVote].
extension PollVotePatterns on PollVote {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PollVote value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PollVote() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PollVote value)  $default,){
final _that = this;
switch (_that) {
case _PollVote():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PollVote value)?  $default,){
final _that = this;
switch (_that) {
case _PollVote() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String memberId,  DateTime votedAt,  String? responseText)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PollVote() when $default != null:
return $default(_that.id,_that.memberId,_that.votedAt,_that.responseText);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String memberId,  DateTime votedAt,  String? responseText)  $default,) {final _that = this;
switch (_that) {
case _PollVote():
return $default(_that.id,_that.memberId,_that.votedAt,_that.responseText);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String memberId,  DateTime votedAt,  String? responseText)?  $default,) {final _that = this;
switch (_that) {
case _PollVote() when $default != null:
return $default(_that.id,_that.memberId,_that.votedAt,_that.responseText);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PollVote implements PollVote {
  const _PollVote({required this.id, required this.memberId, required this.votedAt, this.responseText});
  factory _PollVote.fromJson(Map<String, dynamic> json) => _$PollVoteFromJson(json);

@override final  String id;
@override final  String memberId;
@override final  DateTime votedAt;
@override final  String? responseText;

/// Create a copy of PollVote
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PollVoteCopyWith<_PollVote> get copyWith => __$PollVoteCopyWithImpl<_PollVote>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PollVoteToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PollVote&&(identical(other.id, id) || other.id == id)&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.votedAt, votedAt) || other.votedAt == votedAt)&&(identical(other.responseText, responseText) || other.responseText == responseText));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,memberId,votedAt,responseText);

@override
String toString() {
  return 'PollVote(id: $id, memberId: $memberId, votedAt: $votedAt, responseText: $responseText)';
}


}

/// @nodoc
abstract mixin class _$PollVoteCopyWith<$Res> implements $PollVoteCopyWith<$Res> {
  factory _$PollVoteCopyWith(_PollVote value, $Res Function(_PollVote) _then) = __$PollVoteCopyWithImpl;
@override @useResult
$Res call({
 String id, String memberId, DateTime votedAt, String? responseText
});




}
/// @nodoc
class __$PollVoteCopyWithImpl<$Res>
    implements _$PollVoteCopyWith<$Res> {
  __$PollVoteCopyWithImpl(this._self, this._then);

  final _PollVote _self;
  final $Res Function(_PollVote) _then;

/// Create a copy of PollVote
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? memberId = null,Object? votedAt = null,Object? responseText = freezed,}) {
  return _then(_PollVote(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String,votedAt: null == votedAt ? _self.votedAt : votedAt // ignore: cast_nullable_to_non_nullable
as DateTime,responseText: freezed == responseText ? _self.responseText : responseText // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
