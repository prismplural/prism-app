// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'poll_option.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$PollOption {

 String get id; String get text; int get sortOrder; bool get isOtherOption; String? get colorHex; List<PollVote> get votes;
/// Create a copy of PollOption
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PollOptionCopyWith<PollOption> get copyWith => _$PollOptionCopyWithImpl<PollOption>(this as PollOption, _$identity);

  /// Serializes this PollOption to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PollOption&&(identical(other.id, id) || other.id == id)&&(identical(other.text, text) || other.text == text)&&(identical(other.sortOrder, sortOrder) || other.sortOrder == sortOrder)&&(identical(other.isOtherOption, isOtherOption) || other.isOtherOption == isOtherOption)&&(identical(other.colorHex, colorHex) || other.colorHex == colorHex)&&const DeepCollectionEquality().equals(other.votes, votes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,text,sortOrder,isOtherOption,colorHex,const DeepCollectionEquality().hash(votes));

@override
String toString() {
  return 'PollOption(id: $id, text: $text, sortOrder: $sortOrder, isOtherOption: $isOtherOption, colorHex: $colorHex, votes: $votes)';
}


}

/// @nodoc
abstract mixin class $PollOptionCopyWith<$Res>  {
  factory $PollOptionCopyWith(PollOption value, $Res Function(PollOption) _then) = _$PollOptionCopyWithImpl;
@useResult
$Res call({
 String id, String text, int sortOrder, bool isOtherOption, String? colorHex, List<PollVote> votes
});




}
/// @nodoc
class _$PollOptionCopyWithImpl<$Res>
    implements $PollOptionCopyWith<$Res> {
  _$PollOptionCopyWithImpl(this._self, this._then);

  final PollOption _self;
  final $Res Function(PollOption) _then;

/// Create a copy of PollOption
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? text = null,Object? sortOrder = null,Object? isOtherOption = null,Object? colorHex = freezed,Object? votes = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,sortOrder: null == sortOrder ? _self.sortOrder : sortOrder // ignore: cast_nullable_to_non_nullable
as int,isOtherOption: null == isOtherOption ? _self.isOtherOption : isOtherOption // ignore: cast_nullable_to_non_nullable
as bool,colorHex: freezed == colorHex ? _self.colorHex : colorHex // ignore: cast_nullable_to_non_nullable
as String?,votes: null == votes ? _self.votes : votes // ignore: cast_nullable_to_non_nullable
as List<PollVote>,
  ));
}

}


/// Adds pattern-matching-related methods to [PollOption].
extension PollOptionPatterns on PollOption {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PollOption value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PollOption() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PollOption value)  $default,){
final _that = this;
switch (_that) {
case _PollOption():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PollOption value)?  $default,){
final _that = this;
switch (_that) {
case _PollOption() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String text,  int sortOrder,  bool isOtherOption,  String? colorHex,  List<PollVote> votes)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PollOption() when $default != null:
return $default(_that.id,_that.text,_that.sortOrder,_that.isOtherOption,_that.colorHex,_that.votes);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String text,  int sortOrder,  bool isOtherOption,  String? colorHex,  List<PollVote> votes)  $default,) {final _that = this;
switch (_that) {
case _PollOption():
return $default(_that.id,_that.text,_that.sortOrder,_that.isOtherOption,_that.colorHex,_that.votes);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String text,  int sortOrder,  bool isOtherOption,  String? colorHex,  List<PollVote> votes)?  $default,) {final _that = this;
switch (_that) {
case _PollOption() when $default != null:
return $default(_that.id,_that.text,_that.sortOrder,_that.isOtherOption,_that.colorHex,_that.votes);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PollOption implements PollOption {
  const _PollOption({required this.id, required this.text, this.sortOrder = 0, this.isOtherOption = false, this.colorHex, final  List<PollVote> votes = const []}): _votes = votes;
  factory _PollOption.fromJson(Map<String, dynamic> json) => _$PollOptionFromJson(json);

@override final  String id;
@override final  String text;
@override@JsonKey() final  int sortOrder;
@override@JsonKey() final  bool isOtherOption;
@override final  String? colorHex;
 final  List<PollVote> _votes;
@override@JsonKey() List<PollVote> get votes {
  if (_votes is EqualUnmodifiableListView) return _votes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_votes);
}


/// Create a copy of PollOption
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PollOptionCopyWith<_PollOption> get copyWith => __$PollOptionCopyWithImpl<_PollOption>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PollOptionToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PollOption&&(identical(other.id, id) || other.id == id)&&(identical(other.text, text) || other.text == text)&&(identical(other.sortOrder, sortOrder) || other.sortOrder == sortOrder)&&(identical(other.isOtherOption, isOtherOption) || other.isOtherOption == isOtherOption)&&(identical(other.colorHex, colorHex) || other.colorHex == colorHex)&&const DeepCollectionEquality().equals(other._votes, _votes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,text,sortOrder,isOtherOption,colorHex,const DeepCollectionEquality().hash(_votes));

@override
String toString() {
  return 'PollOption(id: $id, text: $text, sortOrder: $sortOrder, isOtherOption: $isOtherOption, colorHex: $colorHex, votes: $votes)';
}


}

/// @nodoc
abstract mixin class _$PollOptionCopyWith<$Res> implements $PollOptionCopyWith<$Res> {
  factory _$PollOptionCopyWith(_PollOption value, $Res Function(_PollOption) _then) = __$PollOptionCopyWithImpl;
@override @useResult
$Res call({
 String id, String text, int sortOrder, bool isOtherOption, String? colorHex, List<PollVote> votes
});




}
/// @nodoc
class __$PollOptionCopyWithImpl<$Res>
    implements _$PollOptionCopyWith<$Res> {
  __$PollOptionCopyWithImpl(this._self, this._then);

  final _PollOption _self;
  final $Res Function(_PollOption) _then;

/// Create a copy of PollOption
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? text = null,Object? sortOrder = null,Object? isOtherOption = null,Object? colorHex = freezed,Object? votes = null,}) {
  return _then(_PollOption(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,sortOrder: null == sortOrder ? _self.sortOrder : sortOrder // ignore: cast_nullable_to_non_nullable
as int,isOtherOption: null == isOtherOption ? _self.isOtherOption : isOtherOption // ignore: cast_nullable_to_non_nullable
as bool,colorHex: freezed == colorHex ? _self.colorHex : colorHex // ignore: cast_nullable_to_non_nullable
as String?,votes: null == votes ? _self._votes : votes // ignore: cast_nullable_to_non_nullable
as List<PollVote>,
  ));
}


}

// dart format on
