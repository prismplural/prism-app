// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'analytics_insight.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AnalyticsInsight {

 AnalyticsInsightType get type; AnalyticsInsightIconType get iconType; String get headline; String get body; int get signalStrength;
/// Create a copy of AnalyticsInsight
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AnalyticsInsightCopyWith<AnalyticsInsight> get copyWith => _$AnalyticsInsightCopyWithImpl<AnalyticsInsight>(this as AnalyticsInsight, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AnalyticsInsight&&(identical(other.type, type) || other.type == type)&&(identical(other.iconType, iconType) || other.iconType == iconType)&&(identical(other.headline, headline) || other.headline == headline)&&(identical(other.body, body) || other.body == body)&&(identical(other.signalStrength, signalStrength) || other.signalStrength == signalStrength));
}


@override
int get hashCode => Object.hash(runtimeType,type,iconType,headline,body,signalStrength);

@override
String toString() {
  return 'AnalyticsInsight(type: $type, iconType: $iconType, headline: $headline, body: $body, signalStrength: $signalStrength)';
}


}

/// @nodoc
abstract mixin class $AnalyticsInsightCopyWith<$Res>  {
  factory $AnalyticsInsightCopyWith(AnalyticsInsight value, $Res Function(AnalyticsInsight) _then) = _$AnalyticsInsightCopyWithImpl;
@useResult
$Res call({
 AnalyticsInsightType type, AnalyticsInsightIconType iconType, String headline, String body, int signalStrength
});




}
/// @nodoc
class _$AnalyticsInsightCopyWithImpl<$Res>
    implements $AnalyticsInsightCopyWith<$Res> {
  _$AnalyticsInsightCopyWithImpl(this._self, this._then);

  final AnalyticsInsight _self;
  final $Res Function(AnalyticsInsight) _then;

/// Create a copy of AnalyticsInsight
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? type = null,Object? iconType = null,Object? headline = null,Object? body = null,Object? signalStrength = null,}) {
  return _then(_self.copyWith(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as AnalyticsInsightType,iconType: null == iconType ? _self.iconType : iconType // ignore: cast_nullable_to_non_nullable
as AnalyticsInsightIconType,headline: null == headline ? _self.headline : headline // ignore: cast_nullable_to_non_nullable
as String,body: null == body ? _self.body : body // ignore: cast_nullable_to_non_nullable
as String,signalStrength: null == signalStrength ? _self.signalStrength : signalStrength // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [AnalyticsInsight].
extension AnalyticsInsightPatterns on AnalyticsInsight {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AnalyticsInsight value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AnalyticsInsight() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AnalyticsInsight value)  $default,){
final _that = this;
switch (_that) {
case _AnalyticsInsight():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AnalyticsInsight value)?  $default,){
final _that = this;
switch (_that) {
case _AnalyticsInsight() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AnalyticsInsightType type,  AnalyticsInsightIconType iconType,  String headline,  String body,  int signalStrength)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AnalyticsInsight() when $default != null:
return $default(_that.type,_that.iconType,_that.headline,_that.body,_that.signalStrength);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AnalyticsInsightType type,  AnalyticsInsightIconType iconType,  String headline,  String body,  int signalStrength)  $default,) {final _that = this;
switch (_that) {
case _AnalyticsInsight():
return $default(_that.type,_that.iconType,_that.headline,_that.body,_that.signalStrength);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AnalyticsInsightType type,  AnalyticsInsightIconType iconType,  String headline,  String body,  int signalStrength)?  $default,) {final _that = this;
switch (_that) {
case _AnalyticsInsight() when $default != null:
return $default(_that.type,_that.iconType,_that.headline,_that.body,_that.signalStrength);case _:
  return null;

}
}

}

/// @nodoc


class _AnalyticsInsight implements AnalyticsInsight {
  const _AnalyticsInsight({required this.type, required this.iconType, required this.headline, required this.body, required this.signalStrength});
  

@override final  AnalyticsInsightType type;
@override final  AnalyticsInsightIconType iconType;
@override final  String headline;
@override final  String body;
@override final  int signalStrength;

/// Create a copy of AnalyticsInsight
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AnalyticsInsightCopyWith<_AnalyticsInsight> get copyWith => __$AnalyticsInsightCopyWithImpl<_AnalyticsInsight>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AnalyticsInsight&&(identical(other.type, type) || other.type == type)&&(identical(other.iconType, iconType) || other.iconType == iconType)&&(identical(other.headline, headline) || other.headline == headline)&&(identical(other.body, body) || other.body == body)&&(identical(other.signalStrength, signalStrength) || other.signalStrength == signalStrength));
}


@override
int get hashCode => Object.hash(runtimeType,type,iconType,headline,body,signalStrength);

@override
String toString() {
  return 'AnalyticsInsight(type: $type, iconType: $iconType, headline: $headline, body: $body, signalStrength: $signalStrength)';
}


}

/// @nodoc
abstract mixin class _$AnalyticsInsightCopyWith<$Res> implements $AnalyticsInsightCopyWith<$Res> {
  factory _$AnalyticsInsightCopyWith(_AnalyticsInsight value, $Res Function(_AnalyticsInsight) _then) = __$AnalyticsInsightCopyWithImpl;
@override @useResult
$Res call({
 AnalyticsInsightType type, AnalyticsInsightIconType iconType, String headline, String body, int signalStrength
});




}
/// @nodoc
class __$AnalyticsInsightCopyWithImpl<$Res>
    implements _$AnalyticsInsightCopyWith<$Res> {
  __$AnalyticsInsightCopyWithImpl(this._self, this._then);

  final _AnalyticsInsight _self;
  final $Res Function(_AnalyticsInsight) _then;

/// Create a copy of AnalyticsInsight
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? type = null,Object? iconType = null,Object? headline = null,Object? body = null,Object? signalStrength = null,}) {
  return _then(_AnalyticsInsight(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as AnalyticsInsightType,iconType: null == iconType ? _self.iconType : iconType // ignore: cast_nullable_to_non_nullable
as AnalyticsInsightIconType,headline: null == headline ? _self.headline : headline // ignore: cast_nullable_to_non_nullable
as String,body: null == body ? _self.body : body // ignore: cast_nullable_to_non_nullable
as String,signalStrength: null == signalStrength ? _self.signalStrength : signalStrength // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
