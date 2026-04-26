// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'fronting_analytics.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$FrontingAnalytics {

 DateTime get rangeStart; DateTime get rangeEnd; Duration get totalTrackedTime; Duration get totalGapTime; int get totalSessions; int get uniqueFronters; double get switchesPerDay; List<MemberAnalytics> get memberStats;/// System-wide median session length across the range. `Duration.zero`
/// when there are no sessions.
 Duration get medianSession; List<CoFrontingPair> get topCoFrontingPairs;
/// Create a copy of FrontingAnalytics
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FrontingAnalyticsCopyWith<FrontingAnalytics> get copyWith => _$FrontingAnalyticsCopyWithImpl<FrontingAnalytics>(this as FrontingAnalytics, _$identity);

  /// Serializes this FrontingAnalytics to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FrontingAnalytics&&(identical(other.rangeStart, rangeStart) || other.rangeStart == rangeStart)&&(identical(other.rangeEnd, rangeEnd) || other.rangeEnd == rangeEnd)&&(identical(other.totalTrackedTime, totalTrackedTime) || other.totalTrackedTime == totalTrackedTime)&&(identical(other.totalGapTime, totalGapTime) || other.totalGapTime == totalGapTime)&&(identical(other.totalSessions, totalSessions) || other.totalSessions == totalSessions)&&(identical(other.uniqueFronters, uniqueFronters) || other.uniqueFronters == uniqueFronters)&&(identical(other.switchesPerDay, switchesPerDay) || other.switchesPerDay == switchesPerDay)&&const DeepCollectionEquality().equals(other.memberStats, memberStats)&&(identical(other.medianSession, medianSession) || other.medianSession == medianSession)&&const DeepCollectionEquality().equals(other.topCoFrontingPairs, topCoFrontingPairs));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,rangeStart,rangeEnd,totalTrackedTime,totalGapTime,totalSessions,uniqueFronters,switchesPerDay,const DeepCollectionEquality().hash(memberStats),medianSession,const DeepCollectionEquality().hash(topCoFrontingPairs));

@override
String toString() {
  return 'FrontingAnalytics(rangeStart: $rangeStart, rangeEnd: $rangeEnd, totalTrackedTime: $totalTrackedTime, totalGapTime: $totalGapTime, totalSessions: $totalSessions, uniqueFronters: $uniqueFronters, switchesPerDay: $switchesPerDay, memberStats: $memberStats, medianSession: $medianSession, topCoFrontingPairs: $topCoFrontingPairs)';
}


}

/// @nodoc
abstract mixin class $FrontingAnalyticsCopyWith<$Res>  {
  factory $FrontingAnalyticsCopyWith(FrontingAnalytics value, $Res Function(FrontingAnalytics) _then) = _$FrontingAnalyticsCopyWithImpl;
@useResult
$Res call({
 DateTime rangeStart, DateTime rangeEnd, Duration totalTrackedTime, Duration totalGapTime, int totalSessions, int uniqueFronters, double switchesPerDay, List<MemberAnalytics> memberStats, Duration medianSession, List<CoFrontingPair> topCoFrontingPairs
});




}
/// @nodoc
class _$FrontingAnalyticsCopyWithImpl<$Res>
    implements $FrontingAnalyticsCopyWith<$Res> {
  _$FrontingAnalyticsCopyWithImpl(this._self, this._then);

  final FrontingAnalytics _self;
  final $Res Function(FrontingAnalytics) _then;

/// Create a copy of FrontingAnalytics
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? rangeStart = null,Object? rangeEnd = null,Object? totalTrackedTime = null,Object? totalGapTime = null,Object? totalSessions = null,Object? uniqueFronters = null,Object? switchesPerDay = null,Object? memberStats = null,Object? medianSession = null,Object? topCoFrontingPairs = null,}) {
  return _then(_self.copyWith(
rangeStart: null == rangeStart ? _self.rangeStart : rangeStart // ignore: cast_nullable_to_non_nullable
as DateTime,rangeEnd: null == rangeEnd ? _self.rangeEnd : rangeEnd // ignore: cast_nullable_to_non_nullable
as DateTime,totalTrackedTime: null == totalTrackedTime ? _self.totalTrackedTime : totalTrackedTime // ignore: cast_nullable_to_non_nullable
as Duration,totalGapTime: null == totalGapTime ? _self.totalGapTime : totalGapTime // ignore: cast_nullable_to_non_nullable
as Duration,totalSessions: null == totalSessions ? _self.totalSessions : totalSessions // ignore: cast_nullable_to_non_nullable
as int,uniqueFronters: null == uniqueFronters ? _self.uniqueFronters : uniqueFronters // ignore: cast_nullable_to_non_nullable
as int,switchesPerDay: null == switchesPerDay ? _self.switchesPerDay : switchesPerDay // ignore: cast_nullable_to_non_nullable
as double,memberStats: null == memberStats ? _self.memberStats : memberStats // ignore: cast_nullable_to_non_nullable
as List<MemberAnalytics>,medianSession: null == medianSession ? _self.medianSession : medianSession // ignore: cast_nullable_to_non_nullable
as Duration,topCoFrontingPairs: null == topCoFrontingPairs ? _self.topCoFrontingPairs : topCoFrontingPairs // ignore: cast_nullable_to_non_nullable
as List<CoFrontingPair>,
  ));
}

}


/// Adds pattern-matching-related methods to [FrontingAnalytics].
extension FrontingAnalyticsPatterns on FrontingAnalytics {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FrontingAnalytics value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FrontingAnalytics() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FrontingAnalytics value)  $default,){
final _that = this;
switch (_that) {
case _FrontingAnalytics():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FrontingAnalytics value)?  $default,){
final _that = this;
switch (_that) {
case _FrontingAnalytics() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( DateTime rangeStart,  DateTime rangeEnd,  Duration totalTrackedTime,  Duration totalGapTime,  int totalSessions,  int uniqueFronters,  double switchesPerDay,  List<MemberAnalytics> memberStats,  Duration medianSession,  List<CoFrontingPair> topCoFrontingPairs)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FrontingAnalytics() when $default != null:
return $default(_that.rangeStart,_that.rangeEnd,_that.totalTrackedTime,_that.totalGapTime,_that.totalSessions,_that.uniqueFronters,_that.switchesPerDay,_that.memberStats,_that.medianSession,_that.topCoFrontingPairs);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( DateTime rangeStart,  DateTime rangeEnd,  Duration totalTrackedTime,  Duration totalGapTime,  int totalSessions,  int uniqueFronters,  double switchesPerDay,  List<MemberAnalytics> memberStats,  Duration medianSession,  List<CoFrontingPair> topCoFrontingPairs)  $default,) {final _that = this;
switch (_that) {
case _FrontingAnalytics():
return $default(_that.rangeStart,_that.rangeEnd,_that.totalTrackedTime,_that.totalGapTime,_that.totalSessions,_that.uniqueFronters,_that.switchesPerDay,_that.memberStats,_that.medianSession,_that.topCoFrontingPairs);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( DateTime rangeStart,  DateTime rangeEnd,  Duration totalTrackedTime,  Duration totalGapTime,  int totalSessions,  int uniqueFronters,  double switchesPerDay,  List<MemberAnalytics> memberStats,  Duration medianSession,  List<CoFrontingPair> topCoFrontingPairs)?  $default,) {final _that = this;
switch (_that) {
case _FrontingAnalytics() when $default != null:
return $default(_that.rangeStart,_that.rangeEnd,_that.totalTrackedTime,_that.totalGapTime,_that.totalSessions,_that.uniqueFronters,_that.switchesPerDay,_that.memberStats,_that.medianSession,_that.topCoFrontingPairs);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _FrontingAnalytics implements FrontingAnalytics {
  const _FrontingAnalytics({required this.rangeStart, required this.rangeEnd, required this.totalTrackedTime, required this.totalGapTime, required this.totalSessions, required this.uniqueFronters, required this.switchesPerDay, required final  List<MemberAnalytics> memberStats, this.medianSession = Duration.zero, final  List<CoFrontingPair> topCoFrontingPairs = const []}): _memberStats = memberStats,_topCoFrontingPairs = topCoFrontingPairs;
  factory _FrontingAnalytics.fromJson(Map<String, dynamic> json) => _$FrontingAnalyticsFromJson(json);

@override final  DateTime rangeStart;
@override final  DateTime rangeEnd;
@override final  Duration totalTrackedTime;
@override final  Duration totalGapTime;
@override final  int totalSessions;
@override final  int uniqueFronters;
@override final  double switchesPerDay;
 final  List<MemberAnalytics> _memberStats;
@override List<MemberAnalytics> get memberStats {
  if (_memberStats is EqualUnmodifiableListView) return _memberStats;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_memberStats);
}

/// System-wide median session length across the range. `Duration.zero`
/// when there are no sessions.
@override@JsonKey() final  Duration medianSession;
 final  List<CoFrontingPair> _topCoFrontingPairs;
@override@JsonKey() List<CoFrontingPair> get topCoFrontingPairs {
  if (_topCoFrontingPairs is EqualUnmodifiableListView) return _topCoFrontingPairs;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_topCoFrontingPairs);
}


/// Create a copy of FrontingAnalytics
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FrontingAnalyticsCopyWith<_FrontingAnalytics> get copyWith => __$FrontingAnalyticsCopyWithImpl<_FrontingAnalytics>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$FrontingAnalyticsToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FrontingAnalytics&&(identical(other.rangeStart, rangeStart) || other.rangeStart == rangeStart)&&(identical(other.rangeEnd, rangeEnd) || other.rangeEnd == rangeEnd)&&(identical(other.totalTrackedTime, totalTrackedTime) || other.totalTrackedTime == totalTrackedTime)&&(identical(other.totalGapTime, totalGapTime) || other.totalGapTime == totalGapTime)&&(identical(other.totalSessions, totalSessions) || other.totalSessions == totalSessions)&&(identical(other.uniqueFronters, uniqueFronters) || other.uniqueFronters == uniqueFronters)&&(identical(other.switchesPerDay, switchesPerDay) || other.switchesPerDay == switchesPerDay)&&const DeepCollectionEquality().equals(other._memberStats, _memberStats)&&(identical(other.medianSession, medianSession) || other.medianSession == medianSession)&&const DeepCollectionEquality().equals(other._topCoFrontingPairs, _topCoFrontingPairs));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,rangeStart,rangeEnd,totalTrackedTime,totalGapTime,totalSessions,uniqueFronters,switchesPerDay,const DeepCollectionEquality().hash(_memberStats),medianSession,const DeepCollectionEquality().hash(_topCoFrontingPairs));

@override
String toString() {
  return 'FrontingAnalytics(rangeStart: $rangeStart, rangeEnd: $rangeEnd, totalTrackedTime: $totalTrackedTime, totalGapTime: $totalGapTime, totalSessions: $totalSessions, uniqueFronters: $uniqueFronters, switchesPerDay: $switchesPerDay, memberStats: $memberStats, medianSession: $medianSession, topCoFrontingPairs: $topCoFrontingPairs)';
}


}

/// @nodoc
abstract mixin class _$FrontingAnalyticsCopyWith<$Res> implements $FrontingAnalyticsCopyWith<$Res> {
  factory _$FrontingAnalyticsCopyWith(_FrontingAnalytics value, $Res Function(_FrontingAnalytics) _then) = __$FrontingAnalyticsCopyWithImpl;
@override @useResult
$Res call({
 DateTime rangeStart, DateTime rangeEnd, Duration totalTrackedTime, Duration totalGapTime, int totalSessions, int uniqueFronters, double switchesPerDay, List<MemberAnalytics> memberStats, Duration medianSession, List<CoFrontingPair> topCoFrontingPairs
});




}
/// @nodoc
class __$FrontingAnalyticsCopyWithImpl<$Res>
    implements _$FrontingAnalyticsCopyWith<$Res> {
  __$FrontingAnalyticsCopyWithImpl(this._self, this._then);

  final _FrontingAnalytics _self;
  final $Res Function(_FrontingAnalytics) _then;

/// Create a copy of FrontingAnalytics
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? rangeStart = null,Object? rangeEnd = null,Object? totalTrackedTime = null,Object? totalGapTime = null,Object? totalSessions = null,Object? uniqueFronters = null,Object? switchesPerDay = null,Object? memberStats = null,Object? medianSession = null,Object? topCoFrontingPairs = null,}) {
  return _then(_FrontingAnalytics(
rangeStart: null == rangeStart ? _self.rangeStart : rangeStart // ignore: cast_nullable_to_non_nullable
as DateTime,rangeEnd: null == rangeEnd ? _self.rangeEnd : rangeEnd // ignore: cast_nullable_to_non_nullable
as DateTime,totalTrackedTime: null == totalTrackedTime ? _self.totalTrackedTime : totalTrackedTime // ignore: cast_nullable_to_non_nullable
as Duration,totalGapTime: null == totalGapTime ? _self.totalGapTime : totalGapTime // ignore: cast_nullable_to_non_nullable
as Duration,totalSessions: null == totalSessions ? _self.totalSessions : totalSessions // ignore: cast_nullable_to_non_nullable
as int,uniqueFronters: null == uniqueFronters ? _self.uniqueFronters : uniqueFronters // ignore: cast_nullable_to_non_nullable
as int,switchesPerDay: null == switchesPerDay ? _self.switchesPerDay : switchesPerDay // ignore: cast_nullable_to_non_nullable
as double,memberStats: null == memberStats ? _self._memberStats : memberStats // ignore: cast_nullable_to_non_nullable
as List<MemberAnalytics>,medianSession: null == medianSession ? _self.medianSession : medianSession // ignore: cast_nullable_to_non_nullable
as Duration,topCoFrontingPairs: null == topCoFrontingPairs ? _self._topCoFrontingPairs : topCoFrontingPairs // ignore: cast_nullable_to_non_nullable
as List<CoFrontingPair>,
  ));
}


}


/// @nodoc
mixin _$MemberAnalytics {

 String get memberId; Duration get totalTime; double get percentageOfTotal; int get sessionCount; Duration get averageDuration; Duration get medianDuration; Duration get shortestSession; Duration get longestSession; Map<String, int> get timeOfDayBreakdown;
/// Create a copy of MemberAnalytics
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MemberAnalyticsCopyWith<MemberAnalytics> get copyWith => _$MemberAnalyticsCopyWithImpl<MemberAnalytics>(this as MemberAnalytics, _$identity);

  /// Serializes this MemberAnalytics to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MemberAnalytics&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.totalTime, totalTime) || other.totalTime == totalTime)&&(identical(other.percentageOfTotal, percentageOfTotal) || other.percentageOfTotal == percentageOfTotal)&&(identical(other.sessionCount, sessionCount) || other.sessionCount == sessionCount)&&(identical(other.averageDuration, averageDuration) || other.averageDuration == averageDuration)&&(identical(other.medianDuration, medianDuration) || other.medianDuration == medianDuration)&&(identical(other.shortestSession, shortestSession) || other.shortestSession == shortestSession)&&(identical(other.longestSession, longestSession) || other.longestSession == longestSession)&&const DeepCollectionEquality().equals(other.timeOfDayBreakdown, timeOfDayBreakdown));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,memberId,totalTime,percentageOfTotal,sessionCount,averageDuration,medianDuration,shortestSession,longestSession,const DeepCollectionEquality().hash(timeOfDayBreakdown));

@override
String toString() {
  return 'MemberAnalytics(memberId: $memberId, totalTime: $totalTime, percentageOfTotal: $percentageOfTotal, sessionCount: $sessionCount, averageDuration: $averageDuration, medianDuration: $medianDuration, shortestSession: $shortestSession, longestSession: $longestSession, timeOfDayBreakdown: $timeOfDayBreakdown)';
}


}

/// @nodoc
abstract mixin class $MemberAnalyticsCopyWith<$Res>  {
  factory $MemberAnalyticsCopyWith(MemberAnalytics value, $Res Function(MemberAnalytics) _then) = _$MemberAnalyticsCopyWithImpl;
@useResult
$Res call({
 String memberId, Duration totalTime, double percentageOfTotal, int sessionCount, Duration averageDuration, Duration medianDuration, Duration shortestSession, Duration longestSession, Map<String, int> timeOfDayBreakdown
});




}
/// @nodoc
class _$MemberAnalyticsCopyWithImpl<$Res>
    implements $MemberAnalyticsCopyWith<$Res> {
  _$MemberAnalyticsCopyWithImpl(this._self, this._then);

  final MemberAnalytics _self;
  final $Res Function(MemberAnalytics) _then;

/// Create a copy of MemberAnalytics
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? memberId = null,Object? totalTime = null,Object? percentageOfTotal = null,Object? sessionCount = null,Object? averageDuration = null,Object? medianDuration = null,Object? shortestSession = null,Object? longestSession = null,Object? timeOfDayBreakdown = null,}) {
  return _then(_self.copyWith(
memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String,totalTime: null == totalTime ? _self.totalTime : totalTime // ignore: cast_nullable_to_non_nullable
as Duration,percentageOfTotal: null == percentageOfTotal ? _self.percentageOfTotal : percentageOfTotal // ignore: cast_nullable_to_non_nullable
as double,sessionCount: null == sessionCount ? _self.sessionCount : sessionCount // ignore: cast_nullable_to_non_nullable
as int,averageDuration: null == averageDuration ? _self.averageDuration : averageDuration // ignore: cast_nullable_to_non_nullable
as Duration,medianDuration: null == medianDuration ? _self.medianDuration : medianDuration // ignore: cast_nullable_to_non_nullable
as Duration,shortestSession: null == shortestSession ? _self.shortestSession : shortestSession // ignore: cast_nullable_to_non_nullable
as Duration,longestSession: null == longestSession ? _self.longestSession : longestSession // ignore: cast_nullable_to_non_nullable
as Duration,timeOfDayBreakdown: null == timeOfDayBreakdown ? _self.timeOfDayBreakdown : timeOfDayBreakdown // ignore: cast_nullable_to_non_nullable
as Map<String, int>,
  ));
}

}


/// Adds pattern-matching-related methods to [MemberAnalytics].
extension MemberAnalyticsPatterns on MemberAnalytics {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MemberAnalytics value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MemberAnalytics() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MemberAnalytics value)  $default,){
final _that = this;
switch (_that) {
case _MemberAnalytics():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MemberAnalytics value)?  $default,){
final _that = this;
switch (_that) {
case _MemberAnalytics() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String memberId,  Duration totalTime,  double percentageOfTotal,  int sessionCount,  Duration averageDuration,  Duration medianDuration,  Duration shortestSession,  Duration longestSession,  Map<String, int> timeOfDayBreakdown)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MemberAnalytics() when $default != null:
return $default(_that.memberId,_that.totalTime,_that.percentageOfTotal,_that.sessionCount,_that.averageDuration,_that.medianDuration,_that.shortestSession,_that.longestSession,_that.timeOfDayBreakdown);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String memberId,  Duration totalTime,  double percentageOfTotal,  int sessionCount,  Duration averageDuration,  Duration medianDuration,  Duration shortestSession,  Duration longestSession,  Map<String, int> timeOfDayBreakdown)  $default,) {final _that = this;
switch (_that) {
case _MemberAnalytics():
return $default(_that.memberId,_that.totalTime,_that.percentageOfTotal,_that.sessionCount,_that.averageDuration,_that.medianDuration,_that.shortestSession,_that.longestSession,_that.timeOfDayBreakdown);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String memberId,  Duration totalTime,  double percentageOfTotal,  int sessionCount,  Duration averageDuration,  Duration medianDuration,  Duration shortestSession,  Duration longestSession,  Map<String, int> timeOfDayBreakdown)?  $default,) {final _that = this;
switch (_that) {
case _MemberAnalytics() when $default != null:
return $default(_that.memberId,_that.totalTime,_that.percentageOfTotal,_that.sessionCount,_that.averageDuration,_that.medianDuration,_that.shortestSession,_that.longestSession,_that.timeOfDayBreakdown);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _MemberAnalytics implements MemberAnalytics {
  const _MemberAnalytics({required this.memberId, required this.totalTime, required this.percentageOfTotal, required this.sessionCount, required this.averageDuration, required this.medianDuration, required this.shortestSession, required this.longestSession, required final  Map<String, int> timeOfDayBreakdown}): _timeOfDayBreakdown = timeOfDayBreakdown;
  factory _MemberAnalytics.fromJson(Map<String, dynamic> json) => _$MemberAnalyticsFromJson(json);

@override final  String memberId;
@override final  Duration totalTime;
@override final  double percentageOfTotal;
@override final  int sessionCount;
@override final  Duration averageDuration;
@override final  Duration medianDuration;
@override final  Duration shortestSession;
@override final  Duration longestSession;
 final  Map<String, int> _timeOfDayBreakdown;
@override Map<String, int> get timeOfDayBreakdown {
  if (_timeOfDayBreakdown is EqualUnmodifiableMapView) return _timeOfDayBreakdown;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_timeOfDayBreakdown);
}


/// Create a copy of MemberAnalytics
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MemberAnalyticsCopyWith<_MemberAnalytics> get copyWith => __$MemberAnalyticsCopyWithImpl<_MemberAnalytics>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MemberAnalyticsToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MemberAnalytics&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.totalTime, totalTime) || other.totalTime == totalTime)&&(identical(other.percentageOfTotal, percentageOfTotal) || other.percentageOfTotal == percentageOfTotal)&&(identical(other.sessionCount, sessionCount) || other.sessionCount == sessionCount)&&(identical(other.averageDuration, averageDuration) || other.averageDuration == averageDuration)&&(identical(other.medianDuration, medianDuration) || other.medianDuration == medianDuration)&&(identical(other.shortestSession, shortestSession) || other.shortestSession == shortestSession)&&(identical(other.longestSession, longestSession) || other.longestSession == longestSession)&&const DeepCollectionEquality().equals(other._timeOfDayBreakdown, _timeOfDayBreakdown));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,memberId,totalTime,percentageOfTotal,sessionCount,averageDuration,medianDuration,shortestSession,longestSession,const DeepCollectionEquality().hash(_timeOfDayBreakdown));

@override
String toString() {
  return 'MemberAnalytics(memberId: $memberId, totalTime: $totalTime, percentageOfTotal: $percentageOfTotal, sessionCount: $sessionCount, averageDuration: $averageDuration, medianDuration: $medianDuration, shortestSession: $shortestSession, longestSession: $longestSession, timeOfDayBreakdown: $timeOfDayBreakdown)';
}


}

/// @nodoc
abstract mixin class _$MemberAnalyticsCopyWith<$Res> implements $MemberAnalyticsCopyWith<$Res> {
  factory _$MemberAnalyticsCopyWith(_MemberAnalytics value, $Res Function(_MemberAnalytics) _then) = __$MemberAnalyticsCopyWithImpl;
@override @useResult
$Res call({
 String memberId, Duration totalTime, double percentageOfTotal, int sessionCount, Duration averageDuration, Duration medianDuration, Duration shortestSession, Duration longestSession, Map<String, int> timeOfDayBreakdown
});




}
/// @nodoc
class __$MemberAnalyticsCopyWithImpl<$Res>
    implements _$MemberAnalyticsCopyWith<$Res> {
  __$MemberAnalyticsCopyWithImpl(this._self, this._then);

  final _MemberAnalytics _self;
  final $Res Function(_MemberAnalytics) _then;

/// Create a copy of MemberAnalytics
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? memberId = null,Object? totalTime = null,Object? percentageOfTotal = null,Object? sessionCount = null,Object? averageDuration = null,Object? medianDuration = null,Object? shortestSession = null,Object? longestSession = null,Object? timeOfDayBreakdown = null,}) {
  return _then(_MemberAnalytics(
memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String,totalTime: null == totalTime ? _self.totalTime : totalTime // ignore: cast_nullable_to_non_nullable
as Duration,percentageOfTotal: null == percentageOfTotal ? _self.percentageOfTotal : percentageOfTotal // ignore: cast_nullable_to_non_nullable
as double,sessionCount: null == sessionCount ? _self.sessionCount : sessionCount // ignore: cast_nullable_to_non_nullable
as int,averageDuration: null == averageDuration ? _self.averageDuration : averageDuration // ignore: cast_nullable_to_non_nullable
as Duration,medianDuration: null == medianDuration ? _self.medianDuration : medianDuration // ignore: cast_nullable_to_non_nullable
as Duration,shortestSession: null == shortestSession ? _self.shortestSession : shortestSession // ignore: cast_nullable_to_non_nullable
as Duration,longestSession: null == longestSession ? _self.longestSession : longestSession // ignore: cast_nullable_to_non_nullable
as Duration,timeOfDayBreakdown: null == timeOfDayBreakdown ? _self._timeOfDayBreakdown : timeOfDayBreakdown // ignore: cast_nullable_to_non_nullable
as Map<String, int>,
  ));
}


}


/// @nodoc
mixin _$CoFrontingPair {

/// Member ID that comes first alphabetically.
 String get memberIdA; String get memberIdB; Duration get totalTime;
/// Create a copy of CoFrontingPair
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoFrontingPairCopyWith<CoFrontingPair> get copyWith => _$CoFrontingPairCopyWithImpl<CoFrontingPair>(this as CoFrontingPair, _$identity);

  /// Serializes this CoFrontingPair to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CoFrontingPair&&(identical(other.memberIdA, memberIdA) || other.memberIdA == memberIdA)&&(identical(other.memberIdB, memberIdB) || other.memberIdB == memberIdB)&&(identical(other.totalTime, totalTime) || other.totalTime == totalTime));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,memberIdA,memberIdB,totalTime);

@override
String toString() {
  return 'CoFrontingPair(memberIdA: $memberIdA, memberIdB: $memberIdB, totalTime: $totalTime)';
}


}

/// @nodoc
abstract mixin class $CoFrontingPairCopyWith<$Res>  {
  factory $CoFrontingPairCopyWith(CoFrontingPair value, $Res Function(CoFrontingPair) _then) = _$CoFrontingPairCopyWithImpl;
@useResult
$Res call({
 String memberIdA, String memberIdB, Duration totalTime
});




}
/// @nodoc
class _$CoFrontingPairCopyWithImpl<$Res>
    implements $CoFrontingPairCopyWith<$Res> {
  _$CoFrontingPairCopyWithImpl(this._self, this._then);

  final CoFrontingPair _self;
  final $Res Function(CoFrontingPair) _then;

/// Create a copy of CoFrontingPair
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? memberIdA = null,Object? memberIdB = null,Object? totalTime = null,}) {
  return _then(_self.copyWith(
memberIdA: null == memberIdA ? _self.memberIdA : memberIdA // ignore: cast_nullable_to_non_nullable
as String,memberIdB: null == memberIdB ? _self.memberIdB : memberIdB // ignore: cast_nullable_to_non_nullable
as String,totalTime: null == totalTime ? _self.totalTime : totalTime // ignore: cast_nullable_to_non_nullable
as Duration,
  ));
}

}


/// Adds pattern-matching-related methods to [CoFrontingPair].
extension CoFrontingPairPatterns on CoFrontingPair {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CoFrontingPair value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CoFrontingPair() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CoFrontingPair value)  $default,){
final _that = this;
switch (_that) {
case _CoFrontingPair():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CoFrontingPair value)?  $default,){
final _that = this;
switch (_that) {
case _CoFrontingPair() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String memberIdA,  String memberIdB,  Duration totalTime)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CoFrontingPair() when $default != null:
return $default(_that.memberIdA,_that.memberIdB,_that.totalTime);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String memberIdA,  String memberIdB,  Duration totalTime)  $default,) {final _that = this;
switch (_that) {
case _CoFrontingPair():
return $default(_that.memberIdA,_that.memberIdB,_that.totalTime);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String memberIdA,  String memberIdB,  Duration totalTime)?  $default,) {final _that = this;
switch (_that) {
case _CoFrontingPair() when $default != null:
return $default(_that.memberIdA,_that.memberIdB,_that.totalTime);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _CoFrontingPair implements CoFrontingPair {
  const _CoFrontingPair({required this.memberIdA, required this.memberIdB, required this.totalTime});
  factory _CoFrontingPair.fromJson(Map<String, dynamic> json) => _$CoFrontingPairFromJson(json);

/// Member ID that comes first alphabetically.
@override final  String memberIdA;
@override final  String memberIdB;
@override final  Duration totalTime;

/// Create a copy of CoFrontingPair
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CoFrontingPairCopyWith<_CoFrontingPair> get copyWith => __$CoFrontingPairCopyWithImpl<_CoFrontingPair>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$CoFrontingPairToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CoFrontingPair&&(identical(other.memberIdA, memberIdA) || other.memberIdA == memberIdA)&&(identical(other.memberIdB, memberIdB) || other.memberIdB == memberIdB)&&(identical(other.totalTime, totalTime) || other.totalTime == totalTime));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,memberIdA,memberIdB,totalTime);

@override
String toString() {
  return 'CoFrontingPair(memberIdA: $memberIdA, memberIdB: $memberIdB, totalTime: $totalTime)';
}


}

/// @nodoc
abstract mixin class _$CoFrontingPairCopyWith<$Res> implements $CoFrontingPairCopyWith<$Res> {
  factory _$CoFrontingPairCopyWith(_CoFrontingPair value, $Res Function(_CoFrontingPair) _then) = __$CoFrontingPairCopyWithImpl;
@override @useResult
$Res call({
 String memberIdA, String memberIdB, Duration totalTime
});




}
/// @nodoc
class __$CoFrontingPairCopyWithImpl<$Res>
    implements _$CoFrontingPairCopyWith<$Res> {
  __$CoFrontingPairCopyWithImpl(this._self, this._then);

  final _CoFrontingPair _self;
  final $Res Function(_CoFrontingPair) _then;

/// Create a copy of CoFrontingPair
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? memberIdA = null,Object? memberIdB = null,Object? totalTime = null,}) {
  return _then(_CoFrontingPair(
memberIdA: null == memberIdA ? _self.memberIdA : memberIdA // ignore: cast_nullable_to_non_nullable
as String,memberIdB: null == memberIdB ? _self.memberIdB : memberIdB // ignore: cast_nullable_to_non_nullable
as String,totalTime: null == totalTime ? _self.totalTime : totalTime // ignore: cast_nullable_to_non_nullable
as Duration,
  ));
}


}

// dart format on
