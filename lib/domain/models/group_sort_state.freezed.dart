// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'group_sort_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$GroupSortState {

 GroupSortMode get mode; List<String> get manualOrder;
/// Create a copy of GroupSortState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GroupSortStateCopyWith<GroupSortState> get copyWith => _$GroupSortStateCopyWithImpl<GroupSortState>(this as GroupSortState, _$identity);

  /// Serializes this GroupSortState to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GroupSortState&&(identical(other.mode, mode) || other.mode == mode)&&const DeepCollectionEquality().equals(other.manualOrder, manualOrder));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,mode,const DeepCollectionEquality().hash(manualOrder));

@override
String toString() {
  return 'GroupSortState(mode: $mode, manualOrder: $manualOrder)';
}


}

/// @nodoc
abstract mixin class $GroupSortStateCopyWith<$Res>  {
  factory $GroupSortStateCopyWith(GroupSortState value, $Res Function(GroupSortState) _then) = _$GroupSortStateCopyWithImpl;
@useResult
$Res call({
 GroupSortMode mode, List<String> manualOrder
});




}
/// @nodoc
class _$GroupSortStateCopyWithImpl<$Res>
    implements $GroupSortStateCopyWith<$Res> {
  _$GroupSortStateCopyWithImpl(this._self, this._then);

  final GroupSortState _self;
  final $Res Function(GroupSortState) _then;

/// Create a copy of GroupSortState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? mode = null,Object? manualOrder = null,}) {
  return _then(_self.copyWith(
mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as GroupSortMode,manualOrder: null == manualOrder ? _self.manualOrder : manualOrder // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [GroupSortState].
extension GroupSortStatePatterns on GroupSortState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GroupSortState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GroupSortState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GroupSortState value)  $default,){
final _that = this;
switch (_that) {
case _GroupSortState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GroupSortState value)?  $default,){
final _that = this;
switch (_that) {
case _GroupSortState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( GroupSortMode mode,  List<String> manualOrder)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GroupSortState() when $default != null:
return $default(_that.mode,_that.manualOrder);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( GroupSortMode mode,  List<String> manualOrder)  $default,) {final _that = this;
switch (_that) {
case _GroupSortState():
return $default(_that.mode,_that.manualOrder);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( GroupSortMode mode,  List<String> manualOrder)?  $default,) {final _that = this;
switch (_that) {
case _GroupSortState() when $default != null:
return $default(_that.mode,_that.manualOrder);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _GroupSortState extends GroupSortState {
  const _GroupSortState({this.mode = GroupSortMode.manual, final  List<String> manualOrder = const <String>[]}): _manualOrder = manualOrder,super._();
  factory _GroupSortState.fromJson(Map<String, dynamic> json) => _$GroupSortStateFromJson(json);

@override@JsonKey() final  GroupSortMode mode;
 final  List<String> _manualOrder;
@override@JsonKey() List<String> get manualOrder {
  if (_manualOrder is EqualUnmodifiableListView) return _manualOrder;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_manualOrder);
}


/// Create a copy of GroupSortState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GroupSortStateCopyWith<_GroupSortState> get copyWith => __$GroupSortStateCopyWithImpl<_GroupSortState>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$GroupSortStateToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _GroupSortState&&(identical(other.mode, mode) || other.mode == mode)&&const DeepCollectionEquality().equals(other._manualOrder, _manualOrder));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,mode,const DeepCollectionEquality().hash(_manualOrder));

@override
String toString() {
  return 'GroupSortState(mode: $mode, manualOrder: $manualOrder)';
}


}

/// @nodoc
abstract mixin class _$GroupSortStateCopyWith<$Res> implements $GroupSortStateCopyWith<$Res> {
  factory _$GroupSortStateCopyWith(_GroupSortState value, $Res Function(_GroupSortState) _then) = __$GroupSortStateCopyWithImpl;
@override @useResult
$Res call({
 GroupSortMode mode, List<String> manualOrder
});




}
/// @nodoc
class __$GroupSortStateCopyWithImpl<$Res>
    implements _$GroupSortStateCopyWith<$Res> {
  __$GroupSortStateCopyWithImpl(this._self, this._then);

  final _GroupSortState _self;
  final $Res Function(_GroupSortState) _then;

/// Create a copy of GroupSortState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? mode = null,Object? manualOrder = null,}) {
  return _then(_GroupSortState(
mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as GroupSortMode,manualOrder: null == manualOrder ? _self._manualOrder : manualOrder // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}

// dart format on
