// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'search_result.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$MessageSearchResult {

 String get messageId; String get conversationId; String get snippet; DateTime get timestamp; String? get authorId; String? get authorName; String? get authorEmoji; Uint8List? get authorAvatarData; bool? get authorCustomColorEnabled; String? get authorCustomColorHex; String? get conversationTitle; String? get conversationEmoji;
/// Create a copy of MessageSearchResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MessageSearchResultCopyWith<MessageSearchResult> get copyWith => _$MessageSearchResultCopyWithImpl<MessageSearchResult>(this as MessageSearchResult, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MessageSearchResult&&(identical(other.messageId, messageId) || other.messageId == messageId)&&(identical(other.conversationId, conversationId) || other.conversationId == conversationId)&&(identical(other.snippet, snippet) || other.snippet == snippet)&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp)&&(identical(other.authorId, authorId) || other.authorId == authorId)&&(identical(other.authorName, authorName) || other.authorName == authorName)&&(identical(other.authorEmoji, authorEmoji) || other.authorEmoji == authorEmoji)&&const DeepCollectionEquality().equals(other.authorAvatarData, authorAvatarData)&&(identical(other.authorCustomColorEnabled, authorCustomColorEnabled) || other.authorCustomColorEnabled == authorCustomColorEnabled)&&(identical(other.authorCustomColorHex, authorCustomColorHex) || other.authorCustomColorHex == authorCustomColorHex)&&(identical(other.conversationTitle, conversationTitle) || other.conversationTitle == conversationTitle)&&(identical(other.conversationEmoji, conversationEmoji) || other.conversationEmoji == conversationEmoji));
}


@override
int get hashCode => Object.hash(runtimeType,messageId,conversationId,snippet,timestamp,authorId,authorName,authorEmoji,const DeepCollectionEquality().hash(authorAvatarData),authorCustomColorEnabled,authorCustomColorHex,conversationTitle,conversationEmoji);

@override
String toString() {
  return 'MessageSearchResult(messageId: $messageId, conversationId: $conversationId, snippet: $snippet, timestamp: $timestamp, authorId: $authorId, authorName: $authorName, authorEmoji: $authorEmoji, authorAvatarData: $authorAvatarData, authorCustomColorEnabled: $authorCustomColorEnabled, authorCustomColorHex: $authorCustomColorHex, conversationTitle: $conversationTitle, conversationEmoji: $conversationEmoji)';
}


}

/// @nodoc
abstract mixin class $MessageSearchResultCopyWith<$Res>  {
  factory $MessageSearchResultCopyWith(MessageSearchResult value, $Res Function(MessageSearchResult) _then) = _$MessageSearchResultCopyWithImpl;
@useResult
$Res call({
 String messageId, String conversationId, String snippet, DateTime timestamp, String? authorId, String? authorName, String? authorEmoji, Uint8List? authorAvatarData, bool? authorCustomColorEnabled, String? authorCustomColorHex, String? conversationTitle, String? conversationEmoji
});




}
/// @nodoc
class _$MessageSearchResultCopyWithImpl<$Res>
    implements $MessageSearchResultCopyWith<$Res> {
  _$MessageSearchResultCopyWithImpl(this._self, this._then);

  final MessageSearchResult _self;
  final $Res Function(MessageSearchResult) _then;

/// Create a copy of MessageSearchResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? messageId = null,Object? conversationId = null,Object? snippet = null,Object? timestamp = null,Object? authorId = freezed,Object? authorName = freezed,Object? authorEmoji = freezed,Object? authorAvatarData = freezed,Object? authorCustomColorEnabled = freezed,Object? authorCustomColorHex = freezed,Object? conversationTitle = freezed,Object? conversationEmoji = freezed,}) {
  return _then(_self.copyWith(
messageId: null == messageId ? _self.messageId : messageId // ignore: cast_nullable_to_non_nullable
as String,conversationId: null == conversationId ? _self.conversationId : conversationId // ignore: cast_nullable_to_non_nullable
as String,snippet: null == snippet ? _self.snippet : snippet // ignore: cast_nullable_to_non_nullable
as String,timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as DateTime,authorId: freezed == authorId ? _self.authorId : authorId // ignore: cast_nullable_to_non_nullable
as String?,authorName: freezed == authorName ? _self.authorName : authorName // ignore: cast_nullable_to_non_nullable
as String?,authorEmoji: freezed == authorEmoji ? _self.authorEmoji : authorEmoji // ignore: cast_nullable_to_non_nullable
as String?,authorAvatarData: freezed == authorAvatarData ? _self.authorAvatarData : authorAvatarData // ignore: cast_nullable_to_non_nullable
as Uint8List?,authorCustomColorEnabled: freezed == authorCustomColorEnabled ? _self.authorCustomColorEnabled : authorCustomColorEnabled // ignore: cast_nullable_to_non_nullable
as bool?,authorCustomColorHex: freezed == authorCustomColorHex ? _self.authorCustomColorHex : authorCustomColorHex // ignore: cast_nullable_to_non_nullable
as String?,conversationTitle: freezed == conversationTitle ? _self.conversationTitle : conversationTitle // ignore: cast_nullable_to_non_nullable
as String?,conversationEmoji: freezed == conversationEmoji ? _self.conversationEmoji : conversationEmoji // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [MessageSearchResult].
extension MessageSearchResultPatterns on MessageSearchResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MessageSearchResult value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MessageSearchResult() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MessageSearchResult value)  $default,){
final _that = this;
switch (_that) {
case _MessageSearchResult():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MessageSearchResult value)?  $default,){
final _that = this;
switch (_that) {
case _MessageSearchResult() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String messageId,  String conversationId,  String snippet,  DateTime timestamp,  String? authorId,  String? authorName,  String? authorEmoji,  Uint8List? authorAvatarData,  bool? authorCustomColorEnabled,  String? authorCustomColorHex,  String? conversationTitle,  String? conversationEmoji)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MessageSearchResult() when $default != null:
return $default(_that.messageId,_that.conversationId,_that.snippet,_that.timestamp,_that.authorId,_that.authorName,_that.authorEmoji,_that.authorAvatarData,_that.authorCustomColorEnabled,_that.authorCustomColorHex,_that.conversationTitle,_that.conversationEmoji);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String messageId,  String conversationId,  String snippet,  DateTime timestamp,  String? authorId,  String? authorName,  String? authorEmoji,  Uint8List? authorAvatarData,  bool? authorCustomColorEnabled,  String? authorCustomColorHex,  String? conversationTitle,  String? conversationEmoji)  $default,) {final _that = this;
switch (_that) {
case _MessageSearchResult():
return $default(_that.messageId,_that.conversationId,_that.snippet,_that.timestamp,_that.authorId,_that.authorName,_that.authorEmoji,_that.authorAvatarData,_that.authorCustomColorEnabled,_that.authorCustomColorHex,_that.conversationTitle,_that.conversationEmoji);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String messageId,  String conversationId,  String snippet,  DateTime timestamp,  String? authorId,  String? authorName,  String? authorEmoji,  Uint8List? authorAvatarData,  bool? authorCustomColorEnabled,  String? authorCustomColorHex,  String? conversationTitle,  String? conversationEmoji)?  $default,) {final _that = this;
switch (_that) {
case _MessageSearchResult() when $default != null:
return $default(_that.messageId,_that.conversationId,_that.snippet,_that.timestamp,_that.authorId,_that.authorName,_that.authorEmoji,_that.authorAvatarData,_that.authorCustomColorEnabled,_that.authorCustomColorHex,_that.conversationTitle,_that.conversationEmoji);case _:
  return null;

}
}

}

/// @nodoc


class _MessageSearchResult implements MessageSearchResult {
  const _MessageSearchResult({required this.messageId, required this.conversationId, required this.snippet, required this.timestamp, this.authorId, this.authorName, this.authorEmoji, this.authorAvatarData, this.authorCustomColorEnabled, this.authorCustomColorHex, this.conversationTitle, this.conversationEmoji});
  

@override final  String messageId;
@override final  String conversationId;
@override final  String snippet;
@override final  DateTime timestamp;
@override final  String? authorId;
@override final  String? authorName;
@override final  String? authorEmoji;
@override final  Uint8List? authorAvatarData;
@override final  bool? authorCustomColorEnabled;
@override final  String? authorCustomColorHex;
@override final  String? conversationTitle;
@override final  String? conversationEmoji;

/// Create a copy of MessageSearchResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MessageSearchResultCopyWith<_MessageSearchResult> get copyWith => __$MessageSearchResultCopyWithImpl<_MessageSearchResult>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MessageSearchResult&&(identical(other.messageId, messageId) || other.messageId == messageId)&&(identical(other.conversationId, conversationId) || other.conversationId == conversationId)&&(identical(other.snippet, snippet) || other.snippet == snippet)&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp)&&(identical(other.authorId, authorId) || other.authorId == authorId)&&(identical(other.authorName, authorName) || other.authorName == authorName)&&(identical(other.authorEmoji, authorEmoji) || other.authorEmoji == authorEmoji)&&const DeepCollectionEquality().equals(other.authorAvatarData, authorAvatarData)&&(identical(other.authorCustomColorEnabled, authorCustomColorEnabled) || other.authorCustomColorEnabled == authorCustomColorEnabled)&&(identical(other.authorCustomColorHex, authorCustomColorHex) || other.authorCustomColorHex == authorCustomColorHex)&&(identical(other.conversationTitle, conversationTitle) || other.conversationTitle == conversationTitle)&&(identical(other.conversationEmoji, conversationEmoji) || other.conversationEmoji == conversationEmoji));
}


@override
int get hashCode => Object.hash(runtimeType,messageId,conversationId,snippet,timestamp,authorId,authorName,authorEmoji,const DeepCollectionEquality().hash(authorAvatarData),authorCustomColorEnabled,authorCustomColorHex,conversationTitle,conversationEmoji);

@override
String toString() {
  return 'MessageSearchResult(messageId: $messageId, conversationId: $conversationId, snippet: $snippet, timestamp: $timestamp, authorId: $authorId, authorName: $authorName, authorEmoji: $authorEmoji, authorAvatarData: $authorAvatarData, authorCustomColorEnabled: $authorCustomColorEnabled, authorCustomColorHex: $authorCustomColorHex, conversationTitle: $conversationTitle, conversationEmoji: $conversationEmoji)';
}


}

/// @nodoc
abstract mixin class _$MessageSearchResultCopyWith<$Res> implements $MessageSearchResultCopyWith<$Res> {
  factory _$MessageSearchResultCopyWith(_MessageSearchResult value, $Res Function(_MessageSearchResult) _then) = __$MessageSearchResultCopyWithImpl;
@override @useResult
$Res call({
 String messageId, String conversationId, String snippet, DateTime timestamp, String? authorId, String? authorName, String? authorEmoji, Uint8List? authorAvatarData, bool? authorCustomColorEnabled, String? authorCustomColorHex, String? conversationTitle, String? conversationEmoji
});




}
/// @nodoc
class __$MessageSearchResultCopyWithImpl<$Res>
    implements _$MessageSearchResultCopyWith<$Res> {
  __$MessageSearchResultCopyWithImpl(this._self, this._then);

  final _MessageSearchResult _self;
  final $Res Function(_MessageSearchResult) _then;

/// Create a copy of MessageSearchResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? messageId = null,Object? conversationId = null,Object? snippet = null,Object? timestamp = null,Object? authorId = freezed,Object? authorName = freezed,Object? authorEmoji = freezed,Object? authorAvatarData = freezed,Object? authorCustomColorEnabled = freezed,Object? authorCustomColorHex = freezed,Object? conversationTitle = freezed,Object? conversationEmoji = freezed,}) {
  return _then(_MessageSearchResult(
messageId: null == messageId ? _self.messageId : messageId // ignore: cast_nullable_to_non_nullable
as String,conversationId: null == conversationId ? _self.conversationId : conversationId // ignore: cast_nullable_to_non_nullable
as String,snippet: null == snippet ? _self.snippet : snippet // ignore: cast_nullable_to_non_nullable
as String,timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as DateTime,authorId: freezed == authorId ? _self.authorId : authorId // ignore: cast_nullable_to_non_nullable
as String?,authorName: freezed == authorName ? _self.authorName : authorName // ignore: cast_nullable_to_non_nullable
as String?,authorEmoji: freezed == authorEmoji ? _self.authorEmoji : authorEmoji // ignore: cast_nullable_to_non_nullable
as String?,authorAvatarData: freezed == authorAvatarData ? _self.authorAvatarData : authorAvatarData // ignore: cast_nullable_to_non_nullable
as Uint8List?,authorCustomColorEnabled: freezed == authorCustomColorEnabled ? _self.authorCustomColorEnabled : authorCustomColorEnabled // ignore: cast_nullable_to_non_nullable
as bool?,authorCustomColorHex: freezed == authorCustomColorHex ? _self.authorCustomColorHex : authorCustomColorHex // ignore: cast_nullable_to_non_nullable
as String?,conversationTitle: freezed == conversationTitle ? _self.conversationTitle : conversationTitle // ignore: cast_nullable_to_non_nullable
as String?,conversationEmoji: freezed == conversationEmoji ? _self.conversationEmoji : conversationEmoji // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
