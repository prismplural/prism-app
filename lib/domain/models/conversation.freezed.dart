// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'conversation.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Conversation {

 String get id; DateTime get createdAt; DateTime get lastActivityAt; String? get title; String? get emoji; bool get isDirectMessage; String? get creatorId; List<String> get participantIds; List<String> get archivedByMemberIds; List<String> get mutedByMemberIds; Map<String, DateTime> get lastReadTimestamps; String? get description; String? get categoryId; int get displayOrder;
/// Create a copy of Conversation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConversationCopyWith<Conversation> get copyWith => _$ConversationCopyWithImpl<Conversation>(this as Conversation, _$identity);

  /// Serializes this Conversation to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Conversation&&(identical(other.id, id) || other.id == id)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.lastActivityAt, lastActivityAt) || other.lastActivityAt == lastActivityAt)&&(identical(other.title, title) || other.title == title)&&(identical(other.emoji, emoji) || other.emoji == emoji)&&(identical(other.isDirectMessage, isDirectMessage) || other.isDirectMessage == isDirectMessage)&&(identical(other.creatorId, creatorId) || other.creatorId == creatorId)&&const DeepCollectionEquality().equals(other.participantIds, participantIds)&&const DeepCollectionEquality().equals(other.archivedByMemberIds, archivedByMemberIds)&&const DeepCollectionEquality().equals(other.mutedByMemberIds, mutedByMemberIds)&&const DeepCollectionEquality().equals(other.lastReadTimestamps, lastReadTimestamps)&&(identical(other.description, description) || other.description == description)&&(identical(other.categoryId, categoryId) || other.categoryId == categoryId)&&(identical(other.displayOrder, displayOrder) || other.displayOrder == displayOrder));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,createdAt,lastActivityAt,title,emoji,isDirectMessage,creatorId,const DeepCollectionEquality().hash(participantIds),const DeepCollectionEquality().hash(archivedByMemberIds),const DeepCollectionEquality().hash(mutedByMemberIds),const DeepCollectionEquality().hash(lastReadTimestamps),description,categoryId,displayOrder);

@override
String toString() {
  return 'Conversation(id: $id, createdAt: $createdAt, lastActivityAt: $lastActivityAt, title: $title, emoji: $emoji, isDirectMessage: $isDirectMessage, creatorId: $creatorId, participantIds: $participantIds, archivedByMemberIds: $archivedByMemberIds, mutedByMemberIds: $mutedByMemberIds, lastReadTimestamps: $lastReadTimestamps, description: $description, categoryId: $categoryId, displayOrder: $displayOrder)';
}


}

/// @nodoc
abstract mixin class $ConversationCopyWith<$Res>  {
  factory $ConversationCopyWith(Conversation value, $Res Function(Conversation) _then) = _$ConversationCopyWithImpl;
@useResult
$Res call({
 String id, DateTime createdAt, DateTime lastActivityAt, String? title, String? emoji, bool isDirectMessage, String? creatorId, List<String> participantIds, List<String> archivedByMemberIds, List<String> mutedByMemberIds, Map<String, DateTime> lastReadTimestamps, String? description, String? categoryId, int displayOrder
});




}
/// @nodoc
class _$ConversationCopyWithImpl<$Res>
    implements $ConversationCopyWith<$Res> {
  _$ConversationCopyWithImpl(this._self, this._then);

  final Conversation _self;
  final $Res Function(Conversation) _then;

/// Create a copy of Conversation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? createdAt = null,Object? lastActivityAt = null,Object? title = freezed,Object? emoji = freezed,Object? isDirectMessage = null,Object? creatorId = freezed,Object? participantIds = null,Object? archivedByMemberIds = null,Object? mutedByMemberIds = null,Object? lastReadTimestamps = null,Object? description = freezed,Object? categoryId = freezed,Object? displayOrder = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,lastActivityAt: null == lastActivityAt ? _self.lastActivityAt : lastActivityAt // ignore: cast_nullable_to_non_nullable
as DateTime,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,emoji: freezed == emoji ? _self.emoji : emoji // ignore: cast_nullable_to_non_nullable
as String?,isDirectMessage: null == isDirectMessage ? _self.isDirectMessage : isDirectMessage // ignore: cast_nullable_to_non_nullable
as bool,creatorId: freezed == creatorId ? _self.creatorId : creatorId // ignore: cast_nullable_to_non_nullable
as String?,participantIds: null == participantIds ? _self.participantIds : participantIds // ignore: cast_nullable_to_non_nullable
as List<String>,archivedByMemberIds: null == archivedByMemberIds ? _self.archivedByMemberIds : archivedByMemberIds // ignore: cast_nullable_to_non_nullable
as List<String>,mutedByMemberIds: null == mutedByMemberIds ? _self.mutedByMemberIds : mutedByMemberIds // ignore: cast_nullable_to_non_nullable
as List<String>,lastReadTimestamps: null == lastReadTimestamps ? _self.lastReadTimestamps : lastReadTimestamps // ignore: cast_nullable_to_non_nullable
as Map<String, DateTime>,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,categoryId: freezed == categoryId ? _self.categoryId : categoryId // ignore: cast_nullable_to_non_nullable
as String?,displayOrder: null == displayOrder ? _self.displayOrder : displayOrder // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [Conversation].
extension ConversationPatterns on Conversation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Conversation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Conversation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Conversation value)  $default,){
final _that = this;
switch (_that) {
case _Conversation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Conversation value)?  $default,){
final _that = this;
switch (_that) {
case _Conversation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  DateTime createdAt,  DateTime lastActivityAt,  String? title,  String? emoji,  bool isDirectMessage,  String? creatorId,  List<String> participantIds,  List<String> archivedByMemberIds,  List<String> mutedByMemberIds,  Map<String, DateTime> lastReadTimestamps,  String? description,  String? categoryId,  int displayOrder)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Conversation() when $default != null:
return $default(_that.id,_that.createdAt,_that.lastActivityAt,_that.title,_that.emoji,_that.isDirectMessage,_that.creatorId,_that.participantIds,_that.archivedByMemberIds,_that.mutedByMemberIds,_that.lastReadTimestamps,_that.description,_that.categoryId,_that.displayOrder);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  DateTime createdAt,  DateTime lastActivityAt,  String? title,  String? emoji,  bool isDirectMessage,  String? creatorId,  List<String> participantIds,  List<String> archivedByMemberIds,  List<String> mutedByMemberIds,  Map<String, DateTime> lastReadTimestamps,  String? description,  String? categoryId,  int displayOrder)  $default,) {final _that = this;
switch (_that) {
case _Conversation():
return $default(_that.id,_that.createdAt,_that.lastActivityAt,_that.title,_that.emoji,_that.isDirectMessage,_that.creatorId,_that.participantIds,_that.archivedByMemberIds,_that.mutedByMemberIds,_that.lastReadTimestamps,_that.description,_that.categoryId,_that.displayOrder);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  DateTime createdAt,  DateTime lastActivityAt,  String? title,  String? emoji,  bool isDirectMessage,  String? creatorId,  List<String> participantIds,  List<String> archivedByMemberIds,  List<String> mutedByMemberIds,  Map<String, DateTime> lastReadTimestamps,  String? description,  String? categoryId,  int displayOrder)?  $default,) {final _that = this;
switch (_that) {
case _Conversation() when $default != null:
return $default(_that.id,_that.createdAt,_that.lastActivityAt,_that.title,_that.emoji,_that.isDirectMessage,_that.creatorId,_that.participantIds,_that.archivedByMemberIds,_that.mutedByMemberIds,_that.lastReadTimestamps,_that.description,_that.categoryId,_that.displayOrder);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Conversation implements Conversation {
  const _Conversation({required this.id, required this.createdAt, required this.lastActivityAt, this.title, this.emoji, this.isDirectMessage = false, this.creatorId, final  List<String> participantIds = const [], final  List<String> archivedByMemberIds = const [], final  List<String> mutedByMemberIds = const [], final  Map<String, DateTime> lastReadTimestamps = const {}, this.description, this.categoryId, this.displayOrder = 0}): _participantIds = participantIds,_archivedByMemberIds = archivedByMemberIds,_mutedByMemberIds = mutedByMemberIds,_lastReadTimestamps = lastReadTimestamps;
  factory _Conversation.fromJson(Map<String, dynamic> json) => _$ConversationFromJson(json);

@override final  String id;
@override final  DateTime createdAt;
@override final  DateTime lastActivityAt;
@override final  String? title;
@override final  String? emoji;
@override@JsonKey() final  bool isDirectMessage;
@override final  String? creatorId;
 final  List<String> _participantIds;
@override@JsonKey() List<String> get participantIds {
  if (_participantIds is EqualUnmodifiableListView) return _participantIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_participantIds);
}

 final  List<String> _archivedByMemberIds;
@override@JsonKey() List<String> get archivedByMemberIds {
  if (_archivedByMemberIds is EqualUnmodifiableListView) return _archivedByMemberIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_archivedByMemberIds);
}

 final  List<String> _mutedByMemberIds;
@override@JsonKey() List<String> get mutedByMemberIds {
  if (_mutedByMemberIds is EqualUnmodifiableListView) return _mutedByMemberIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_mutedByMemberIds);
}

 final  Map<String, DateTime> _lastReadTimestamps;
@override@JsonKey() Map<String, DateTime> get lastReadTimestamps {
  if (_lastReadTimestamps is EqualUnmodifiableMapView) return _lastReadTimestamps;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_lastReadTimestamps);
}

@override final  String? description;
@override final  String? categoryId;
@override@JsonKey() final  int displayOrder;

/// Create a copy of Conversation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConversationCopyWith<_Conversation> get copyWith => __$ConversationCopyWithImpl<_Conversation>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ConversationToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Conversation&&(identical(other.id, id) || other.id == id)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.lastActivityAt, lastActivityAt) || other.lastActivityAt == lastActivityAt)&&(identical(other.title, title) || other.title == title)&&(identical(other.emoji, emoji) || other.emoji == emoji)&&(identical(other.isDirectMessage, isDirectMessage) || other.isDirectMessage == isDirectMessage)&&(identical(other.creatorId, creatorId) || other.creatorId == creatorId)&&const DeepCollectionEquality().equals(other._participantIds, _participantIds)&&const DeepCollectionEquality().equals(other._archivedByMemberIds, _archivedByMemberIds)&&const DeepCollectionEquality().equals(other._mutedByMemberIds, _mutedByMemberIds)&&const DeepCollectionEquality().equals(other._lastReadTimestamps, _lastReadTimestamps)&&(identical(other.description, description) || other.description == description)&&(identical(other.categoryId, categoryId) || other.categoryId == categoryId)&&(identical(other.displayOrder, displayOrder) || other.displayOrder == displayOrder));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,createdAt,lastActivityAt,title,emoji,isDirectMessage,creatorId,const DeepCollectionEquality().hash(_participantIds),const DeepCollectionEquality().hash(_archivedByMemberIds),const DeepCollectionEquality().hash(_mutedByMemberIds),const DeepCollectionEquality().hash(_lastReadTimestamps),description,categoryId,displayOrder);

@override
String toString() {
  return 'Conversation(id: $id, createdAt: $createdAt, lastActivityAt: $lastActivityAt, title: $title, emoji: $emoji, isDirectMessage: $isDirectMessage, creatorId: $creatorId, participantIds: $participantIds, archivedByMemberIds: $archivedByMemberIds, mutedByMemberIds: $mutedByMemberIds, lastReadTimestamps: $lastReadTimestamps, description: $description, categoryId: $categoryId, displayOrder: $displayOrder)';
}


}

/// @nodoc
abstract mixin class _$ConversationCopyWith<$Res> implements $ConversationCopyWith<$Res> {
  factory _$ConversationCopyWith(_Conversation value, $Res Function(_Conversation) _then) = __$ConversationCopyWithImpl;
@override @useResult
$Res call({
 String id, DateTime createdAt, DateTime lastActivityAt, String? title, String? emoji, bool isDirectMessage, String? creatorId, List<String> participantIds, List<String> archivedByMemberIds, List<String> mutedByMemberIds, Map<String, DateTime> lastReadTimestamps, String? description, String? categoryId, int displayOrder
});




}
/// @nodoc
class __$ConversationCopyWithImpl<$Res>
    implements _$ConversationCopyWith<$Res> {
  __$ConversationCopyWithImpl(this._self, this._then);

  final _Conversation _self;
  final $Res Function(_Conversation) _then;

/// Create a copy of Conversation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? createdAt = null,Object? lastActivityAt = null,Object? title = freezed,Object? emoji = freezed,Object? isDirectMessage = null,Object? creatorId = freezed,Object? participantIds = null,Object? archivedByMemberIds = null,Object? mutedByMemberIds = null,Object? lastReadTimestamps = null,Object? description = freezed,Object? categoryId = freezed,Object? displayOrder = null,}) {
  return _then(_Conversation(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,lastActivityAt: null == lastActivityAt ? _self.lastActivityAt : lastActivityAt // ignore: cast_nullable_to_non_nullable
as DateTime,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,emoji: freezed == emoji ? _self.emoji : emoji // ignore: cast_nullable_to_non_nullable
as String?,isDirectMessage: null == isDirectMessage ? _self.isDirectMessage : isDirectMessage // ignore: cast_nullable_to_non_nullable
as bool,creatorId: freezed == creatorId ? _self.creatorId : creatorId // ignore: cast_nullable_to_non_nullable
as String?,participantIds: null == participantIds ? _self._participantIds : participantIds // ignore: cast_nullable_to_non_nullable
as List<String>,archivedByMemberIds: null == archivedByMemberIds ? _self._archivedByMemberIds : archivedByMemberIds // ignore: cast_nullable_to_non_nullable
as List<String>,mutedByMemberIds: null == mutedByMemberIds ? _self._mutedByMemberIds : mutedByMemberIds // ignore: cast_nullable_to_non_nullable
as List<String>,lastReadTimestamps: null == lastReadTimestamps ? _self._lastReadTimestamps : lastReadTimestamps // ignore: cast_nullable_to_non_nullable
as Map<String, DateTime>,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,categoryId: freezed == categoryId ? _self.categoryId : categoryId // ignore: cast_nullable_to_non_nullable
as String?,displayOrder: null == displayOrder ? _self.displayOrder : displayOrder // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
