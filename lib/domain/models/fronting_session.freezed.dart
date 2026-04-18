// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'fronting_session.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$FrontingSession {

 String get id; DateTime get startTime; DateTime? get endTime; String? get memberId; List<String> get coFronterIds; String? get notes; FrontConfidence? get confidence; String? get pluralkitUuid; SessionType get sessionType; SleepQuality? get quality; bool get isHealthKitImport; String? get pkMemberIdsJson;// Plan 02 (PK deletion push). See Member for rationale.
 bool get isDeleted; int? get deleteIntentEpoch; int? get deletePushStartedAt;
/// Create a copy of FrontingSession
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FrontingSessionCopyWith<FrontingSession> get copyWith => _$FrontingSessionCopyWithImpl<FrontingSession>(this as FrontingSession, _$identity);

  /// Serializes this FrontingSession to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FrontingSession&&(identical(other.id, id) || other.id == id)&&(identical(other.startTime, startTime) || other.startTime == startTime)&&(identical(other.endTime, endTime) || other.endTime == endTime)&&(identical(other.memberId, memberId) || other.memberId == memberId)&&const DeepCollectionEquality().equals(other.coFronterIds, coFronterIds)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.confidence, confidence) || other.confidence == confidence)&&(identical(other.pluralkitUuid, pluralkitUuid) || other.pluralkitUuid == pluralkitUuid)&&(identical(other.sessionType, sessionType) || other.sessionType == sessionType)&&(identical(other.quality, quality) || other.quality == quality)&&(identical(other.isHealthKitImport, isHealthKitImport) || other.isHealthKitImport == isHealthKitImport)&&(identical(other.pkMemberIdsJson, pkMemberIdsJson) || other.pkMemberIdsJson == pkMemberIdsJson)&&(identical(other.isDeleted, isDeleted) || other.isDeleted == isDeleted)&&(identical(other.deleteIntentEpoch, deleteIntentEpoch) || other.deleteIntentEpoch == deleteIntentEpoch)&&(identical(other.deletePushStartedAt, deletePushStartedAt) || other.deletePushStartedAt == deletePushStartedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,startTime,endTime,memberId,const DeepCollectionEquality().hash(coFronterIds),notes,confidence,pluralkitUuid,sessionType,quality,isHealthKitImport,pkMemberIdsJson,isDeleted,deleteIntentEpoch,deletePushStartedAt);

@override
String toString() {
  return 'FrontingSession(id: $id, startTime: $startTime, endTime: $endTime, memberId: $memberId, coFronterIds: $coFronterIds, notes: $notes, confidence: $confidence, pluralkitUuid: $pluralkitUuid, sessionType: $sessionType, quality: $quality, isHealthKitImport: $isHealthKitImport, pkMemberIdsJson: $pkMemberIdsJson, isDeleted: $isDeleted, deleteIntentEpoch: $deleteIntentEpoch, deletePushStartedAt: $deletePushStartedAt)';
}


}

/// @nodoc
abstract mixin class $FrontingSessionCopyWith<$Res>  {
  factory $FrontingSessionCopyWith(FrontingSession value, $Res Function(FrontingSession) _then) = _$FrontingSessionCopyWithImpl;
@useResult
$Res call({
 String id, DateTime startTime, DateTime? endTime, String? memberId, List<String> coFronterIds, String? notes, FrontConfidence? confidence, String? pluralkitUuid, SessionType sessionType, SleepQuality? quality, bool isHealthKitImport, String? pkMemberIdsJson, bool isDeleted, int? deleteIntentEpoch, int? deletePushStartedAt
});




}
/// @nodoc
class _$FrontingSessionCopyWithImpl<$Res>
    implements $FrontingSessionCopyWith<$Res> {
  _$FrontingSessionCopyWithImpl(this._self, this._then);

  final FrontingSession _self;
  final $Res Function(FrontingSession) _then;

/// Create a copy of FrontingSession
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? startTime = null,Object? endTime = freezed,Object? memberId = freezed,Object? coFronterIds = null,Object? notes = freezed,Object? confidence = freezed,Object? pluralkitUuid = freezed,Object? sessionType = null,Object? quality = freezed,Object? isHealthKitImport = null,Object? pkMemberIdsJson = freezed,Object? isDeleted = null,Object? deleteIntentEpoch = freezed,Object? deletePushStartedAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,startTime: null == startTime ? _self.startTime : startTime // ignore: cast_nullable_to_non_nullable
as DateTime,endTime: freezed == endTime ? _self.endTime : endTime // ignore: cast_nullable_to_non_nullable
as DateTime?,memberId: freezed == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String?,coFronterIds: null == coFronterIds ? _self.coFronterIds : coFronterIds // ignore: cast_nullable_to_non_nullable
as List<String>,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,confidence: freezed == confidence ? _self.confidence : confidence // ignore: cast_nullable_to_non_nullable
as FrontConfidence?,pluralkitUuid: freezed == pluralkitUuid ? _self.pluralkitUuid : pluralkitUuid // ignore: cast_nullable_to_non_nullable
as String?,sessionType: null == sessionType ? _self.sessionType : sessionType // ignore: cast_nullable_to_non_nullable
as SessionType,quality: freezed == quality ? _self.quality : quality // ignore: cast_nullable_to_non_nullable
as SleepQuality?,isHealthKitImport: null == isHealthKitImport ? _self.isHealthKitImport : isHealthKitImport // ignore: cast_nullable_to_non_nullable
as bool,pkMemberIdsJson: freezed == pkMemberIdsJson ? _self.pkMemberIdsJson : pkMemberIdsJson // ignore: cast_nullable_to_non_nullable
as String?,isDeleted: null == isDeleted ? _self.isDeleted : isDeleted // ignore: cast_nullable_to_non_nullable
as bool,deleteIntentEpoch: freezed == deleteIntentEpoch ? _self.deleteIntentEpoch : deleteIntentEpoch // ignore: cast_nullable_to_non_nullable
as int?,deletePushStartedAt: freezed == deletePushStartedAt ? _self.deletePushStartedAt : deletePushStartedAt // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [FrontingSession].
extension FrontingSessionPatterns on FrontingSession {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FrontingSession value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FrontingSession() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FrontingSession value)  $default,){
final _that = this;
switch (_that) {
case _FrontingSession():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FrontingSession value)?  $default,){
final _that = this;
switch (_that) {
case _FrontingSession() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  DateTime startTime,  DateTime? endTime,  String? memberId,  List<String> coFronterIds,  String? notes,  FrontConfidence? confidence,  String? pluralkitUuid,  SessionType sessionType,  SleepQuality? quality,  bool isHealthKitImport,  String? pkMemberIdsJson,  bool isDeleted,  int? deleteIntentEpoch,  int? deletePushStartedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FrontingSession() when $default != null:
return $default(_that.id,_that.startTime,_that.endTime,_that.memberId,_that.coFronterIds,_that.notes,_that.confidence,_that.pluralkitUuid,_that.sessionType,_that.quality,_that.isHealthKitImport,_that.pkMemberIdsJson,_that.isDeleted,_that.deleteIntentEpoch,_that.deletePushStartedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  DateTime startTime,  DateTime? endTime,  String? memberId,  List<String> coFronterIds,  String? notes,  FrontConfidence? confidence,  String? pluralkitUuid,  SessionType sessionType,  SleepQuality? quality,  bool isHealthKitImport,  String? pkMemberIdsJson,  bool isDeleted,  int? deleteIntentEpoch,  int? deletePushStartedAt)  $default,) {final _that = this;
switch (_that) {
case _FrontingSession():
return $default(_that.id,_that.startTime,_that.endTime,_that.memberId,_that.coFronterIds,_that.notes,_that.confidence,_that.pluralkitUuid,_that.sessionType,_that.quality,_that.isHealthKitImport,_that.pkMemberIdsJson,_that.isDeleted,_that.deleteIntentEpoch,_that.deletePushStartedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  DateTime startTime,  DateTime? endTime,  String? memberId,  List<String> coFronterIds,  String? notes,  FrontConfidence? confidence,  String? pluralkitUuid,  SessionType sessionType,  SleepQuality? quality,  bool isHealthKitImport,  String? pkMemberIdsJson,  bool isDeleted,  int? deleteIntentEpoch,  int? deletePushStartedAt)?  $default,) {final _that = this;
switch (_that) {
case _FrontingSession() when $default != null:
return $default(_that.id,_that.startTime,_that.endTime,_that.memberId,_that.coFronterIds,_that.notes,_that.confidence,_that.pluralkitUuid,_that.sessionType,_that.quality,_that.isHealthKitImport,_that.pkMemberIdsJson,_that.isDeleted,_that.deleteIntentEpoch,_that.deletePushStartedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _FrontingSession extends FrontingSession {
  const _FrontingSession({required this.id, required this.startTime, this.endTime, this.memberId, final  List<String> coFronterIds = const [], this.notes, this.confidence, this.pluralkitUuid, this.sessionType = SessionType.normal, this.quality, this.isHealthKitImport = false, this.pkMemberIdsJson, this.isDeleted = false, this.deleteIntentEpoch, this.deletePushStartedAt}): _coFronterIds = coFronterIds,super._();
  factory _FrontingSession.fromJson(Map<String, dynamic> json) => _$FrontingSessionFromJson(json);

@override final  String id;
@override final  DateTime startTime;
@override final  DateTime? endTime;
@override final  String? memberId;
 final  List<String> _coFronterIds;
@override@JsonKey() List<String> get coFronterIds {
  if (_coFronterIds is EqualUnmodifiableListView) return _coFronterIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_coFronterIds);
}

@override final  String? notes;
@override final  FrontConfidence? confidence;
@override final  String? pluralkitUuid;
@override@JsonKey() final  SessionType sessionType;
@override final  SleepQuality? quality;
@override@JsonKey() final  bool isHealthKitImport;
@override final  String? pkMemberIdsJson;
// Plan 02 (PK deletion push). See Member for rationale.
@override@JsonKey() final  bool isDeleted;
@override final  int? deleteIntentEpoch;
@override final  int? deletePushStartedAt;

/// Create a copy of FrontingSession
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FrontingSessionCopyWith<_FrontingSession> get copyWith => __$FrontingSessionCopyWithImpl<_FrontingSession>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$FrontingSessionToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FrontingSession&&(identical(other.id, id) || other.id == id)&&(identical(other.startTime, startTime) || other.startTime == startTime)&&(identical(other.endTime, endTime) || other.endTime == endTime)&&(identical(other.memberId, memberId) || other.memberId == memberId)&&const DeepCollectionEquality().equals(other._coFronterIds, _coFronterIds)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.confidence, confidence) || other.confidence == confidence)&&(identical(other.pluralkitUuid, pluralkitUuid) || other.pluralkitUuid == pluralkitUuid)&&(identical(other.sessionType, sessionType) || other.sessionType == sessionType)&&(identical(other.quality, quality) || other.quality == quality)&&(identical(other.isHealthKitImport, isHealthKitImport) || other.isHealthKitImport == isHealthKitImport)&&(identical(other.pkMemberIdsJson, pkMemberIdsJson) || other.pkMemberIdsJson == pkMemberIdsJson)&&(identical(other.isDeleted, isDeleted) || other.isDeleted == isDeleted)&&(identical(other.deleteIntentEpoch, deleteIntentEpoch) || other.deleteIntentEpoch == deleteIntentEpoch)&&(identical(other.deletePushStartedAt, deletePushStartedAt) || other.deletePushStartedAt == deletePushStartedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,startTime,endTime,memberId,const DeepCollectionEquality().hash(_coFronterIds),notes,confidence,pluralkitUuid,sessionType,quality,isHealthKitImport,pkMemberIdsJson,isDeleted,deleteIntentEpoch,deletePushStartedAt);

@override
String toString() {
  return 'FrontingSession(id: $id, startTime: $startTime, endTime: $endTime, memberId: $memberId, coFronterIds: $coFronterIds, notes: $notes, confidence: $confidence, pluralkitUuid: $pluralkitUuid, sessionType: $sessionType, quality: $quality, isHealthKitImport: $isHealthKitImport, pkMemberIdsJson: $pkMemberIdsJson, isDeleted: $isDeleted, deleteIntentEpoch: $deleteIntentEpoch, deletePushStartedAt: $deletePushStartedAt)';
}


}

/// @nodoc
abstract mixin class _$FrontingSessionCopyWith<$Res> implements $FrontingSessionCopyWith<$Res> {
  factory _$FrontingSessionCopyWith(_FrontingSession value, $Res Function(_FrontingSession) _then) = __$FrontingSessionCopyWithImpl;
@override @useResult
$Res call({
 String id, DateTime startTime, DateTime? endTime, String? memberId, List<String> coFronterIds, String? notes, FrontConfidence? confidence, String? pluralkitUuid, SessionType sessionType, SleepQuality? quality, bool isHealthKitImport, String? pkMemberIdsJson, bool isDeleted, int? deleteIntentEpoch, int? deletePushStartedAt
});




}
/// @nodoc
class __$FrontingSessionCopyWithImpl<$Res>
    implements _$FrontingSessionCopyWith<$Res> {
  __$FrontingSessionCopyWithImpl(this._self, this._then);

  final _FrontingSession _self;
  final $Res Function(_FrontingSession) _then;

/// Create a copy of FrontingSession
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? startTime = null,Object? endTime = freezed,Object? memberId = freezed,Object? coFronterIds = null,Object? notes = freezed,Object? confidence = freezed,Object? pluralkitUuid = freezed,Object? sessionType = null,Object? quality = freezed,Object? isHealthKitImport = null,Object? pkMemberIdsJson = freezed,Object? isDeleted = null,Object? deleteIntentEpoch = freezed,Object? deletePushStartedAt = freezed,}) {
  return _then(_FrontingSession(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,startTime: null == startTime ? _self.startTime : startTime // ignore: cast_nullable_to_non_nullable
as DateTime,endTime: freezed == endTime ? _self.endTime : endTime // ignore: cast_nullable_to_non_nullable
as DateTime?,memberId: freezed == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String?,coFronterIds: null == coFronterIds ? _self._coFronterIds : coFronterIds // ignore: cast_nullable_to_non_nullable
as List<String>,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,confidence: freezed == confidence ? _self.confidence : confidence // ignore: cast_nullable_to_non_nullable
as FrontConfidence?,pluralkitUuid: freezed == pluralkitUuid ? _self.pluralkitUuid : pluralkitUuid // ignore: cast_nullable_to_non_nullable
as String?,sessionType: null == sessionType ? _self.sessionType : sessionType // ignore: cast_nullable_to_non_nullable
as SessionType,quality: freezed == quality ? _self.quality : quality // ignore: cast_nullable_to_non_nullable
as SleepQuality?,isHealthKitImport: null == isHealthKitImport ? _self.isHealthKitImport : isHealthKitImport // ignore: cast_nullable_to_non_nullable
as bool,pkMemberIdsJson: freezed == pkMemberIdsJson ? _self.pkMemberIdsJson : pkMemberIdsJson // ignore: cast_nullable_to_non_nullable
as String?,isDeleted: null == isDeleted ? _self.isDeleted : isDeleted // ignore: cast_nullable_to_non_nullable
as bool,deleteIntentEpoch: freezed == deleteIntentEpoch ? _self.deleteIntentEpoch : deleteIntentEpoch // ignore: cast_nullable_to_non_nullable
as int?,deletePushStartedAt: freezed == deletePushStartedAt ? _self.deletePushStartedAt : deletePushStartedAt // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
