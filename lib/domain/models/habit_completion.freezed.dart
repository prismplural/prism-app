// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'habit_completion.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$HabitCompletion {

 String get id; String get habitId; DateTime get completedAt; String? get completedByMemberId; String? get notes; bool get wasFronting; int? get rating; DateTime get createdAt; DateTime get modifiedAt;
/// Create a copy of HabitCompletion
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$HabitCompletionCopyWith<HabitCompletion> get copyWith => _$HabitCompletionCopyWithImpl<HabitCompletion>(this as HabitCompletion, _$identity);

  /// Serializes this HabitCompletion to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is HabitCompletion&&(identical(other.id, id) || other.id == id)&&(identical(other.habitId, habitId) || other.habitId == habitId)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.completedByMemberId, completedByMemberId) || other.completedByMemberId == completedByMemberId)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.wasFronting, wasFronting) || other.wasFronting == wasFronting)&&(identical(other.rating, rating) || other.rating == rating)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.modifiedAt, modifiedAt) || other.modifiedAt == modifiedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,habitId,completedAt,completedByMemberId,notes,wasFronting,rating,createdAt,modifiedAt);

@override
String toString() {
  return 'HabitCompletion(id: $id, habitId: $habitId, completedAt: $completedAt, completedByMemberId: $completedByMemberId, notes: $notes, wasFronting: $wasFronting, rating: $rating, createdAt: $createdAt, modifiedAt: $modifiedAt)';
}


}

/// @nodoc
abstract mixin class $HabitCompletionCopyWith<$Res>  {
  factory $HabitCompletionCopyWith(HabitCompletion value, $Res Function(HabitCompletion) _then) = _$HabitCompletionCopyWithImpl;
@useResult
$Res call({
 String id, String habitId, DateTime completedAt, String? completedByMemberId, String? notes, bool wasFronting, int? rating, DateTime createdAt, DateTime modifiedAt
});




}
/// @nodoc
class _$HabitCompletionCopyWithImpl<$Res>
    implements $HabitCompletionCopyWith<$Res> {
  _$HabitCompletionCopyWithImpl(this._self, this._then);

  final HabitCompletion _self;
  final $Res Function(HabitCompletion) _then;

/// Create a copy of HabitCompletion
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? habitId = null,Object? completedAt = null,Object? completedByMemberId = freezed,Object? notes = freezed,Object? wasFronting = null,Object? rating = freezed,Object? createdAt = null,Object? modifiedAt = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,habitId: null == habitId ? _self.habitId : habitId // ignore: cast_nullable_to_non_nullable
as String,completedAt: null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as DateTime,completedByMemberId: freezed == completedByMemberId ? _self.completedByMemberId : completedByMemberId // ignore: cast_nullable_to_non_nullable
as String?,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,wasFronting: null == wasFronting ? _self.wasFronting : wasFronting // ignore: cast_nullable_to_non_nullable
as bool,rating: freezed == rating ? _self.rating : rating // ignore: cast_nullable_to_non_nullable
as int?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,modifiedAt: null == modifiedAt ? _self.modifiedAt : modifiedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [HabitCompletion].
extension HabitCompletionPatterns on HabitCompletion {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _HabitCompletion value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _HabitCompletion() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _HabitCompletion value)  $default,){
final _that = this;
switch (_that) {
case _HabitCompletion():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _HabitCompletion value)?  $default,){
final _that = this;
switch (_that) {
case _HabitCompletion() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String habitId,  DateTime completedAt,  String? completedByMemberId,  String? notes,  bool wasFronting,  int? rating,  DateTime createdAt,  DateTime modifiedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _HabitCompletion() when $default != null:
return $default(_that.id,_that.habitId,_that.completedAt,_that.completedByMemberId,_that.notes,_that.wasFronting,_that.rating,_that.createdAt,_that.modifiedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String habitId,  DateTime completedAt,  String? completedByMemberId,  String? notes,  bool wasFronting,  int? rating,  DateTime createdAt,  DateTime modifiedAt)  $default,) {final _that = this;
switch (_that) {
case _HabitCompletion():
return $default(_that.id,_that.habitId,_that.completedAt,_that.completedByMemberId,_that.notes,_that.wasFronting,_that.rating,_that.createdAt,_that.modifiedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String habitId,  DateTime completedAt,  String? completedByMemberId,  String? notes,  bool wasFronting,  int? rating,  DateTime createdAt,  DateTime modifiedAt)?  $default,) {final _that = this;
switch (_that) {
case _HabitCompletion() when $default != null:
return $default(_that.id,_that.habitId,_that.completedAt,_that.completedByMemberId,_that.notes,_that.wasFronting,_that.rating,_that.createdAt,_that.modifiedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _HabitCompletion extends HabitCompletion {
  const _HabitCompletion({required this.id, required this.habitId, required this.completedAt, this.completedByMemberId, this.notes, this.wasFronting = false, this.rating, required this.createdAt, required this.modifiedAt}): super._();
  factory _HabitCompletion.fromJson(Map<String, dynamic> json) => _$HabitCompletionFromJson(json);

@override final  String id;
@override final  String habitId;
@override final  DateTime completedAt;
@override final  String? completedByMemberId;
@override final  String? notes;
@override@JsonKey() final  bool wasFronting;
@override final  int? rating;
@override final  DateTime createdAt;
@override final  DateTime modifiedAt;

/// Create a copy of HabitCompletion
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$HabitCompletionCopyWith<_HabitCompletion> get copyWith => __$HabitCompletionCopyWithImpl<_HabitCompletion>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$HabitCompletionToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _HabitCompletion&&(identical(other.id, id) || other.id == id)&&(identical(other.habitId, habitId) || other.habitId == habitId)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.completedByMemberId, completedByMemberId) || other.completedByMemberId == completedByMemberId)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.wasFronting, wasFronting) || other.wasFronting == wasFronting)&&(identical(other.rating, rating) || other.rating == rating)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.modifiedAt, modifiedAt) || other.modifiedAt == modifiedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,habitId,completedAt,completedByMemberId,notes,wasFronting,rating,createdAt,modifiedAt);

@override
String toString() {
  return 'HabitCompletion(id: $id, habitId: $habitId, completedAt: $completedAt, completedByMemberId: $completedByMemberId, notes: $notes, wasFronting: $wasFronting, rating: $rating, createdAt: $createdAt, modifiedAt: $modifiedAt)';
}


}

/// @nodoc
abstract mixin class _$HabitCompletionCopyWith<$Res> implements $HabitCompletionCopyWith<$Res> {
  factory _$HabitCompletionCopyWith(_HabitCompletion value, $Res Function(_HabitCompletion) _then) = __$HabitCompletionCopyWithImpl;
@override @useResult
$Res call({
 String id, String habitId, DateTime completedAt, String? completedByMemberId, String? notes, bool wasFronting, int? rating, DateTime createdAt, DateTime modifiedAt
});




}
/// @nodoc
class __$HabitCompletionCopyWithImpl<$Res>
    implements _$HabitCompletionCopyWith<$Res> {
  __$HabitCompletionCopyWithImpl(this._self, this._then);

  final _HabitCompletion _self;
  final $Res Function(_HabitCompletion) _then;

/// Create a copy of HabitCompletion
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? habitId = null,Object? completedAt = null,Object? completedByMemberId = freezed,Object? notes = freezed,Object? wasFronting = null,Object? rating = freezed,Object? createdAt = null,Object? modifiedAt = null,}) {
  return _then(_HabitCompletion(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,habitId: null == habitId ? _self.habitId : habitId // ignore: cast_nullable_to_non_nullable
as String,completedAt: null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as DateTime,completedByMemberId: freezed == completedByMemberId ? _self.completedByMemberId : completedByMemberId // ignore: cast_nullable_to_non_nullable
as String?,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,wasFronting: null == wasFronting ? _self.wasFronting : wasFronting // ignore: cast_nullable_to_non_nullable
as bool,rating: freezed == rating ? _self.rating : rating // ignore: cast_nullable_to_non_nullable
as int?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,modifiedAt: null == modifiedAt ? _self.modifiedAt : modifiedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on
