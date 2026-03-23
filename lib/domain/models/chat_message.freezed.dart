// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'chat_message.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ChatMessage {

 String get id; String get content; DateTime get timestamp; bool get isSystemMessage; DateTime? get editedAt; String? get authorId; String get conversationId; List<MessageReaction> get reactions; String? get replyToId; String? get replyToAuthorId; String? get replyToContent;
/// Create a copy of ChatMessage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatMessageCopyWith<ChatMessage> get copyWith => _$ChatMessageCopyWithImpl<ChatMessage>(this as ChatMessage, _$identity);

  /// Serializes this ChatMessage to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatMessage&&(identical(other.id, id) || other.id == id)&&(identical(other.content, content) || other.content == content)&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp)&&(identical(other.isSystemMessage, isSystemMessage) || other.isSystemMessage == isSystemMessage)&&(identical(other.editedAt, editedAt) || other.editedAt == editedAt)&&(identical(other.authorId, authorId) || other.authorId == authorId)&&(identical(other.conversationId, conversationId) || other.conversationId == conversationId)&&const DeepCollectionEquality().equals(other.reactions, reactions)&&(identical(other.replyToId, replyToId) || other.replyToId == replyToId)&&(identical(other.replyToAuthorId, replyToAuthorId) || other.replyToAuthorId == replyToAuthorId)&&(identical(other.replyToContent, replyToContent) || other.replyToContent == replyToContent));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,content,timestamp,isSystemMessage,editedAt,authorId,conversationId,const DeepCollectionEquality().hash(reactions),replyToId,replyToAuthorId,replyToContent);

@override
String toString() {
  return 'ChatMessage(id: $id, content: $content, timestamp: $timestamp, isSystemMessage: $isSystemMessage, editedAt: $editedAt, authorId: $authorId, conversationId: $conversationId, reactions: $reactions, replyToId: $replyToId, replyToAuthorId: $replyToAuthorId, replyToContent: $replyToContent)';
}


}

/// @nodoc
abstract mixin class $ChatMessageCopyWith<$Res>  {
  factory $ChatMessageCopyWith(ChatMessage value, $Res Function(ChatMessage) _then) = _$ChatMessageCopyWithImpl;
@useResult
$Res call({
 String id, String content, DateTime timestamp, bool isSystemMessage, DateTime? editedAt, String? authorId, String conversationId, List<MessageReaction> reactions, String? replyToId, String? replyToAuthorId, String? replyToContent
});




}
/// @nodoc
class _$ChatMessageCopyWithImpl<$Res>
    implements $ChatMessageCopyWith<$Res> {
  _$ChatMessageCopyWithImpl(this._self, this._then);

  final ChatMessage _self;
  final $Res Function(ChatMessage) _then;

/// Create a copy of ChatMessage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? content = null,Object? timestamp = null,Object? isSystemMessage = null,Object? editedAt = freezed,Object? authorId = freezed,Object? conversationId = null,Object? reactions = null,Object? replyToId = freezed,Object? replyToAuthorId = freezed,Object? replyToContent = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as String,timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as DateTime,isSystemMessage: null == isSystemMessage ? _self.isSystemMessage : isSystemMessage // ignore: cast_nullable_to_non_nullable
as bool,editedAt: freezed == editedAt ? _self.editedAt : editedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,authorId: freezed == authorId ? _self.authorId : authorId // ignore: cast_nullable_to_non_nullable
as String?,conversationId: null == conversationId ? _self.conversationId : conversationId // ignore: cast_nullable_to_non_nullable
as String,reactions: null == reactions ? _self.reactions : reactions // ignore: cast_nullable_to_non_nullable
as List<MessageReaction>,replyToId: freezed == replyToId ? _self.replyToId : replyToId // ignore: cast_nullable_to_non_nullable
as String?,replyToAuthorId: freezed == replyToAuthorId ? _self.replyToAuthorId : replyToAuthorId // ignore: cast_nullable_to_non_nullable
as String?,replyToContent: freezed == replyToContent ? _self.replyToContent : replyToContent // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ChatMessage].
extension ChatMessagePatterns on ChatMessage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ChatMessage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ChatMessage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ChatMessage value)  $default,){
final _that = this;
switch (_that) {
case _ChatMessage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ChatMessage value)?  $default,){
final _that = this;
switch (_that) {
case _ChatMessage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String content,  DateTime timestamp,  bool isSystemMessage,  DateTime? editedAt,  String? authorId,  String conversationId,  List<MessageReaction> reactions,  String? replyToId,  String? replyToAuthorId,  String? replyToContent)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ChatMessage() when $default != null:
return $default(_that.id,_that.content,_that.timestamp,_that.isSystemMessage,_that.editedAt,_that.authorId,_that.conversationId,_that.reactions,_that.replyToId,_that.replyToAuthorId,_that.replyToContent);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String content,  DateTime timestamp,  bool isSystemMessage,  DateTime? editedAt,  String? authorId,  String conversationId,  List<MessageReaction> reactions,  String? replyToId,  String? replyToAuthorId,  String? replyToContent)  $default,) {final _that = this;
switch (_that) {
case _ChatMessage():
return $default(_that.id,_that.content,_that.timestamp,_that.isSystemMessage,_that.editedAt,_that.authorId,_that.conversationId,_that.reactions,_that.replyToId,_that.replyToAuthorId,_that.replyToContent);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String content,  DateTime timestamp,  bool isSystemMessage,  DateTime? editedAt,  String? authorId,  String conversationId,  List<MessageReaction> reactions,  String? replyToId,  String? replyToAuthorId,  String? replyToContent)?  $default,) {final _that = this;
switch (_that) {
case _ChatMessage() when $default != null:
return $default(_that.id,_that.content,_that.timestamp,_that.isSystemMessage,_that.editedAt,_that.authorId,_that.conversationId,_that.reactions,_that.replyToId,_that.replyToAuthorId,_that.replyToContent);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ChatMessage implements ChatMessage {
  const _ChatMessage({required this.id, required this.content, required this.timestamp, this.isSystemMessage = false, this.editedAt, this.authorId, required this.conversationId, final  List<MessageReaction> reactions = const [], this.replyToId, this.replyToAuthorId, this.replyToContent}): _reactions = reactions;
  factory _ChatMessage.fromJson(Map<String, dynamic> json) => _$ChatMessageFromJson(json);

@override final  String id;
@override final  String content;
@override final  DateTime timestamp;
@override@JsonKey() final  bool isSystemMessage;
@override final  DateTime? editedAt;
@override final  String? authorId;
@override final  String conversationId;
 final  List<MessageReaction> _reactions;
@override@JsonKey() List<MessageReaction> get reactions {
  if (_reactions is EqualUnmodifiableListView) return _reactions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_reactions);
}

@override final  String? replyToId;
@override final  String? replyToAuthorId;
@override final  String? replyToContent;

/// Create a copy of ChatMessage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChatMessageCopyWith<_ChatMessage> get copyWith => __$ChatMessageCopyWithImpl<_ChatMessage>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ChatMessageToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ChatMessage&&(identical(other.id, id) || other.id == id)&&(identical(other.content, content) || other.content == content)&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp)&&(identical(other.isSystemMessage, isSystemMessage) || other.isSystemMessage == isSystemMessage)&&(identical(other.editedAt, editedAt) || other.editedAt == editedAt)&&(identical(other.authorId, authorId) || other.authorId == authorId)&&(identical(other.conversationId, conversationId) || other.conversationId == conversationId)&&const DeepCollectionEquality().equals(other._reactions, _reactions)&&(identical(other.replyToId, replyToId) || other.replyToId == replyToId)&&(identical(other.replyToAuthorId, replyToAuthorId) || other.replyToAuthorId == replyToAuthorId)&&(identical(other.replyToContent, replyToContent) || other.replyToContent == replyToContent));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,content,timestamp,isSystemMessage,editedAt,authorId,conversationId,const DeepCollectionEquality().hash(_reactions),replyToId,replyToAuthorId,replyToContent);

@override
String toString() {
  return 'ChatMessage(id: $id, content: $content, timestamp: $timestamp, isSystemMessage: $isSystemMessage, editedAt: $editedAt, authorId: $authorId, conversationId: $conversationId, reactions: $reactions, replyToId: $replyToId, replyToAuthorId: $replyToAuthorId, replyToContent: $replyToContent)';
}


}

/// @nodoc
abstract mixin class _$ChatMessageCopyWith<$Res> implements $ChatMessageCopyWith<$Res> {
  factory _$ChatMessageCopyWith(_ChatMessage value, $Res Function(_ChatMessage) _then) = __$ChatMessageCopyWithImpl;
@override @useResult
$Res call({
 String id, String content, DateTime timestamp, bool isSystemMessage, DateTime? editedAt, String? authorId, String conversationId, List<MessageReaction> reactions, String? replyToId, String? replyToAuthorId, String? replyToContent
});




}
/// @nodoc
class __$ChatMessageCopyWithImpl<$Res>
    implements _$ChatMessageCopyWith<$Res> {
  __$ChatMessageCopyWithImpl(this._self, this._then);

  final _ChatMessage _self;
  final $Res Function(_ChatMessage) _then;

/// Create a copy of ChatMessage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? content = null,Object? timestamp = null,Object? isSystemMessage = null,Object? editedAt = freezed,Object? authorId = freezed,Object? conversationId = null,Object? reactions = null,Object? replyToId = freezed,Object? replyToAuthorId = freezed,Object? replyToContent = freezed,}) {
  return _then(_ChatMessage(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as String,timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as DateTime,isSystemMessage: null == isSystemMessage ? _self.isSystemMessage : isSystemMessage // ignore: cast_nullable_to_non_nullable
as bool,editedAt: freezed == editedAt ? _self.editedAt : editedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,authorId: freezed == authorId ? _self.authorId : authorId // ignore: cast_nullable_to_non_nullable
as String?,conversationId: null == conversationId ? _self.conversationId : conversationId // ignore: cast_nullable_to_non_nullable
as String,reactions: null == reactions ? _self._reactions : reactions // ignore: cast_nullable_to_non_nullable
as List<MessageReaction>,replyToId: freezed == replyToId ? _self.replyToId : replyToId // ignore: cast_nullable_to_non_nullable
as String?,replyToAuthorId: freezed == replyToAuthorId ? _self.replyToAuthorId : replyToAuthorId // ignore: cast_nullable_to_non_nullable
as String?,replyToContent: freezed == replyToContent ? _self.replyToContent : replyToContent // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
