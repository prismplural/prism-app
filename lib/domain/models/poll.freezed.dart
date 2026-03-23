// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'poll.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Poll {

 String get id; String get question; String? get description; bool get isAnonymous; bool get allowsMultipleVotes; bool get isClosed; DateTime? get expiresAt; DateTime get createdAt; List<PollOption> get options;
/// Create a copy of Poll
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PollCopyWith<Poll> get copyWith => _$PollCopyWithImpl<Poll>(this as Poll, _$identity);

  /// Serializes this Poll to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Poll&&(identical(other.id, id) || other.id == id)&&(identical(other.question, question) || other.question == question)&&(identical(other.description, description) || other.description == description)&&(identical(other.isAnonymous, isAnonymous) || other.isAnonymous == isAnonymous)&&(identical(other.allowsMultipleVotes, allowsMultipleVotes) || other.allowsMultipleVotes == allowsMultipleVotes)&&(identical(other.isClosed, isClosed) || other.isClosed == isClosed)&&(identical(other.expiresAt, expiresAt) || other.expiresAt == expiresAt)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&const DeepCollectionEquality().equals(other.options, options));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,question,description,isAnonymous,allowsMultipleVotes,isClosed,expiresAt,createdAt,const DeepCollectionEquality().hash(options));

@override
String toString() {
  return 'Poll(id: $id, question: $question, description: $description, isAnonymous: $isAnonymous, allowsMultipleVotes: $allowsMultipleVotes, isClosed: $isClosed, expiresAt: $expiresAt, createdAt: $createdAt, options: $options)';
}


}

/// @nodoc
abstract mixin class $PollCopyWith<$Res>  {
  factory $PollCopyWith(Poll value, $Res Function(Poll) _then) = _$PollCopyWithImpl;
@useResult
$Res call({
 String id, String question, String? description, bool isAnonymous, bool allowsMultipleVotes, bool isClosed, DateTime? expiresAt, DateTime createdAt, List<PollOption> options
});




}
/// @nodoc
class _$PollCopyWithImpl<$Res>
    implements $PollCopyWith<$Res> {
  _$PollCopyWithImpl(this._self, this._then);

  final Poll _self;
  final $Res Function(Poll) _then;

/// Create a copy of Poll
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? question = null,Object? description = freezed,Object? isAnonymous = null,Object? allowsMultipleVotes = null,Object? isClosed = null,Object? expiresAt = freezed,Object? createdAt = null,Object? options = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,question: null == question ? _self.question : question // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,isAnonymous: null == isAnonymous ? _self.isAnonymous : isAnonymous // ignore: cast_nullable_to_non_nullable
as bool,allowsMultipleVotes: null == allowsMultipleVotes ? _self.allowsMultipleVotes : allowsMultipleVotes // ignore: cast_nullable_to_non_nullable
as bool,isClosed: null == isClosed ? _self.isClosed : isClosed // ignore: cast_nullable_to_non_nullable
as bool,expiresAt: freezed == expiresAt ? _self.expiresAt : expiresAt // ignore: cast_nullable_to_non_nullable
as DateTime?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,options: null == options ? _self.options : options // ignore: cast_nullable_to_non_nullable
as List<PollOption>,
  ));
}

}


/// Adds pattern-matching-related methods to [Poll].
extension PollPatterns on Poll {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Poll value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Poll() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Poll value)  $default,){
final _that = this;
switch (_that) {
case _Poll():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Poll value)?  $default,){
final _that = this;
switch (_that) {
case _Poll() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String question,  String? description,  bool isAnonymous,  bool allowsMultipleVotes,  bool isClosed,  DateTime? expiresAt,  DateTime createdAt,  List<PollOption> options)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Poll() when $default != null:
return $default(_that.id,_that.question,_that.description,_that.isAnonymous,_that.allowsMultipleVotes,_that.isClosed,_that.expiresAt,_that.createdAt,_that.options);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String question,  String? description,  bool isAnonymous,  bool allowsMultipleVotes,  bool isClosed,  DateTime? expiresAt,  DateTime createdAt,  List<PollOption> options)  $default,) {final _that = this;
switch (_that) {
case _Poll():
return $default(_that.id,_that.question,_that.description,_that.isAnonymous,_that.allowsMultipleVotes,_that.isClosed,_that.expiresAt,_that.createdAt,_that.options);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String question,  String? description,  bool isAnonymous,  bool allowsMultipleVotes,  bool isClosed,  DateTime? expiresAt,  DateTime createdAt,  List<PollOption> options)?  $default,) {final _that = this;
switch (_that) {
case _Poll() when $default != null:
return $default(_that.id,_that.question,_that.description,_that.isAnonymous,_that.allowsMultipleVotes,_that.isClosed,_that.expiresAt,_that.createdAt,_that.options);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Poll implements Poll {
  const _Poll({required this.id, required this.question, this.description, this.isAnonymous = false, this.allowsMultipleVotes = false, this.isClosed = false, this.expiresAt, required this.createdAt, final  List<PollOption> options = const []}): _options = options;
  factory _Poll.fromJson(Map<String, dynamic> json) => _$PollFromJson(json);

@override final  String id;
@override final  String question;
@override final  String? description;
@override@JsonKey() final  bool isAnonymous;
@override@JsonKey() final  bool allowsMultipleVotes;
@override@JsonKey() final  bool isClosed;
@override final  DateTime? expiresAt;
@override final  DateTime createdAt;
 final  List<PollOption> _options;
@override@JsonKey() List<PollOption> get options {
  if (_options is EqualUnmodifiableListView) return _options;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_options);
}


/// Create a copy of Poll
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PollCopyWith<_Poll> get copyWith => __$PollCopyWithImpl<_Poll>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PollToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Poll&&(identical(other.id, id) || other.id == id)&&(identical(other.question, question) || other.question == question)&&(identical(other.description, description) || other.description == description)&&(identical(other.isAnonymous, isAnonymous) || other.isAnonymous == isAnonymous)&&(identical(other.allowsMultipleVotes, allowsMultipleVotes) || other.allowsMultipleVotes == allowsMultipleVotes)&&(identical(other.isClosed, isClosed) || other.isClosed == isClosed)&&(identical(other.expiresAt, expiresAt) || other.expiresAt == expiresAt)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&const DeepCollectionEquality().equals(other._options, _options));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,question,description,isAnonymous,allowsMultipleVotes,isClosed,expiresAt,createdAt,const DeepCollectionEquality().hash(_options));

@override
String toString() {
  return 'Poll(id: $id, question: $question, description: $description, isAnonymous: $isAnonymous, allowsMultipleVotes: $allowsMultipleVotes, isClosed: $isClosed, expiresAt: $expiresAt, createdAt: $createdAt, options: $options)';
}


}

/// @nodoc
abstract mixin class _$PollCopyWith<$Res> implements $PollCopyWith<$Res> {
  factory _$PollCopyWith(_Poll value, $Res Function(_Poll) _then) = __$PollCopyWithImpl;
@override @useResult
$Res call({
 String id, String question, String? description, bool isAnonymous, bool allowsMultipleVotes, bool isClosed, DateTime? expiresAt, DateTime createdAt, List<PollOption> options
});




}
/// @nodoc
class __$PollCopyWithImpl<$Res>
    implements _$PollCopyWith<$Res> {
  __$PollCopyWithImpl(this._self, this._then);

  final _Poll _self;
  final $Res Function(_Poll) _then;

/// Create a copy of Poll
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? question = null,Object? description = freezed,Object? isAnonymous = null,Object? allowsMultipleVotes = null,Object? isClosed = null,Object? expiresAt = freezed,Object? createdAt = null,Object? options = null,}) {
  return _then(_Poll(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,question: null == question ? _self.question : question // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,isAnonymous: null == isAnonymous ? _self.isAnonymous : isAnonymous // ignore: cast_nullable_to_non_nullable
as bool,allowsMultipleVotes: null == allowsMultipleVotes ? _self.allowsMultipleVotes : allowsMultipleVotes // ignore: cast_nullable_to_non_nullable
as bool,isClosed: null == isClosed ? _self.isClosed : isClosed // ignore: cast_nullable_to_non_nullable
as bool,expiresAt: freezed == expiresAt ? _self.expiresAt : expiresAt // ignore: cast_nullable_to_non_nullable
as DateTime?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,options: null == options ? _self._options : options // ignore: cast_nullable_to_non_nullable
as List<PollOption>,
  ));
}


}

// dart format on
