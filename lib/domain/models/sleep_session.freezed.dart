// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'sleep_session.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$SleepSession {

 String get id; DateTime get startTime; DateTime? get endTime; SleepQuality get quality; String? get notes; bool get isHealthKitImport;
/// Create a copy of SleepSession
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SleepSessionCopyWith<SleepSession> get copyWith => _$SleepSessionCopyWithImpl<SleepSession>(this as SleepSession, _$identity);

  /// Serializes this SleepSession to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SleepSession&&(identical(other.id, id) || other.id == id)&&(identical(other.startTime, startTime) || other.startTime == startTime)&&(identical(other.endTime, endTime) || other.endTime == endTime)&&(identical(other.quality, quality) || other.quality == quality)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.isHealthKitImport, isHealthKitImport) || other.isHealthKitImport == isHealthKitImport));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,startTime,endTime,quality,notes,isHealthKitImport);

@override
String toString() {
  return 'SleepSession(id: $id, startTime: $startTime, endTime: $endTime, quality: $quality, notes: $notes, isHealthKitImport: $isHealthKitImport)';
}


}

/// @nodoc
abstract mixin class $SleepSessionCopyWith<$Res>  {
  factory $SleepSessionCopyWith(SleepSession value, $Res Function(SleepSession) _then) = _$SleepSessionCopyWithImpl;
@useResult
$Res call({
 String id, DateTime startTime, DateTime? endTime, SleepQuality quality, String? notes, bool isHealthKitImport
});




}
/// @nodoc
class _$SleepSessionCopyWithImpl<$Res>
    implements $SleepSessionCopyWith<$Res> {
  _$SleepSessionCopyWithImpl(this._self, this._then);

  final SleepSession _self;
  final $Res Function(SleepSession) _then;

/// Create a copy of SleepSession
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? startTime = null,Object? endTime = freezed,Object? quality = null,Object? notes = freezed,Object? isHealthKitImport = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,startTime: null == startTime ? _self.startTime : startTime // ignore: cast_nullable_to_non_nullable
as DateTime,endTime: freezed == endTime ? _self.endTime : endTime // ignore: cast_nullable_to_non_nullable
as DateTime?,quality: null == quality ? _self.quality : quality // ignore: cast_nullable_to_non_nullable
as SleepQuality,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,isHealthKitImport: null == isHealthKitImport ? _self.isHealthKitImport : isHealthKitImport // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [SleepSession].
extension SleepSessionPatterns on SleepSession {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SleepSession value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SleepSession() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SleepSession value)  $default,){
final _that = this;
switch (_that) {
case _SleepSession():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SleepSession value)?  $default,){
final _that = this;
switch (_that) {
case _SleepSession() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  DateTime startTime,  DateTime? endTime,  SleepQuality quality,  String? notes,  bool isHealthKitImport)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SleepSession() when $default != null:
return $default(_that.id,_that.startTime,_that.endTime,_that.quality,_that.notes,_that.isHealthKitImport);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  DateTime startTime,  DateTime? endTime,  SleepQuality quality,  String? notes,  bool isHealthKitImport)  $default,) {final _that = this;
switch (_that) {
case _SleepSession():
return $default(_that.id,_that.startTime,_that.endTime,_that.quality,_that.notes,_that.isHealthKitImport);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  DateTime startTime,  DateTime? endTime,  SleepQuality quality,  String? notes,  bool isHealthKitImport)?  $default,) {final _that = this;
switch (_that) {
case _SleepSession() when $default != null:
return $default(_that.id,_that.startTime,_that.endTime,_that.quality,_that.notes,_that.isHealthKitImport);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SleepSession extends SleepSession {
  const _SleepSession({required this.id, required this.startTime, this.endTime, this.quality = SleepQuality.unknown, this.notes, this.isHealthKitImport = false}): super._();
  factory _SleepSession.fromJson(Map<String, dynamic> json) => _$SleepSessionFromJson(json);

@override final  String id;
@override final  DateTime startTime;
@override final  DateTime? endTime;
@override@JsonKey() final  SleepQuality quality;
@override final  String? notes;
@override@JsonKey() final  bool isHealthKitImport;

/// Create a copy of SleepSession
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SleepSessionCopyWith<_SleepSession> get copyWith => __$SleepSessionCopyWithImpl<_SleepSession>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SleepSessionToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SleepSession&&(identical(other.id, id) || other.id == id)&&(identical(other.startTime, startTime) || other.startTime == startTime)&&(identical(other.endTime, endTime) || other.endTime == endTime)&&(identical(other.quality, quality) || other.quality == quality)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.isHealthKitImport, isHealthKitImport) || other.isHealthKitImport == isHealthKitImport));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,startTime,endTime,quality,notes,isHealthKitImport);

@override
String toString() {
  return 'SleepSession(id: $id, startTime: $startTime, endTime: $endTime, quality: $quality, notes: $notes, isHealthKitImport: $isHealthKitImport)';
}


}

/// @nodoc
abstract mixin class _$SleepSessionCopyWith<$Res> implements $SleepSessionCopyWith<$Res> {
  factory _$SleepSessionCopyWith(_SleepSession value, $Res Function(_SleepSession) _then) = __$SleepSessionCopyWithImpl;
@override @useResult
$Res call({
 String id, DateTime startTime, DateTime? endTime, SleepQuality quality, String? notes, bool isHealthKitImport
});




}
/// @nodoc
class __$SleepSessionCopyWithImpl<$Res>
    implements _$SleepSessionCopyWith<$Res> {
  __$SleepSessionCopyWithImpl(this._self, this._then);

  final _SleepSession _self;
  final $Res Function(_SleepSession) _then;

/// Create a copy of SleepSession
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? startTime = null,Object? endTime = freezed,Object? quality = null,Object? notes = freezed,Object? isHealthKitImport = null,}) {
  return _then(_SleepSession(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,startTime: null == startTime ? _self.startTime : startTime // ignore: cast_nullable_to_non_nullable
as DateTime,endTime: freezed == endTime ? _self.endTime : endTime // ignore: cast_nullable_to_non_nullable
as DateTime?,quality: null == quality ? _self.quality : quality // ignore: cast_nullable_to_non_nullable
as SleepQuality,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,isHealthKitImport: null == isHealthKitImport ? _self.isHealthKitImport : isHealthKitImport // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
