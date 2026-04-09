// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'media_attachment.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$MediaAttachment {

 String get id; String get messageId; String get mediaId; String get mediaType; String get encryptionKeyB64; String get contentHash; String get plaintextHash; String get mimeType; int get sizeBytes; int get width; int get height; int get durationMs; String get blurhash; String get waveformB64; String get thumbnailMediaId; String get sourceUrl; String get previewUrl; bool get isDeleted;
/// Create a copy of MediaAttachment
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MediaAttachmentCopyWith<MediaAttachment> get copyWith => _$MediaAttachmentCopyWithImpl<MediaAttachment>(this as MediaAttachment, _$identity);

  /// Serializes this MediaAttachment to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MediaAttachment&&(identical(other.id, id) || other.id == id)&&(identical(other.messageId, messageId) || other.messageId == messageId)&&(identical(other.mediaId, mediaId) || other.mediaId == mediaId)&&(identical(other.mediaType, mediaType) || other.mediaType == mediaType)&&(identical(other.encryptionKeyB64, encryptionKeyB64) || other.encryptionKeyB64 == encryptionKeyB64)&&(identical(other.contentHash, contentHash) || other.contentHash == contentHash)&&(identical(other.plaintextHash, plaintextHash) || other.plaintextHash == plaintextHash)&&(identical(other.mimeType, mimeType) || other.mimeType == mimeType)&&(identical(other.sizeBytes, sizeBytes) || other.sizeBytes == sizeBytes)&&(identical(other.width, width) || other.width == width)&&(identical(other.height, height) || other.height == height)&&(identical(other.durationMs, durationMs) || other.durationMs == durationMs)&&(identical(other.blurhash, blurhash) || other.blurhash == blurhash)&&(identical(other.waveformB64, waveformB64) || other.waveformB64 == waveformB64)&&(identical(other.thumbnailMediaId, thumbnailMediaId) || other.thumbnailMediaId == thumbnailMediaId)&&(identical(other.sourceUrl, sourceUrl) || other.sourceUrl == sourceUrl)&&(identical(other.previewUrl, previewUrl) || other.previewUrl == previewUrl)&&(identical(other.isDeleted, isDeleted) || other.isDeleted == isDeleted));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,messageId,mediaId,mediaType,encryptionKeyB64,contentHash,plaintextHash,mimeType,sizeBytes,width,height,durationMs,blurhash,waveformB64,thumbnailMediaId,sourceUrl,previewUrl,isDeleted);

@override
String toString() {
  return 'MediaAttachment(id: $id, messageId: $messageId, mediaId: $mediaId, mediaType: $mediaType, encryptionKeyB64: $encryptionKeyB64, contentHash: $contentHash, plaintextHash: $plaintextHash, mimeType: $mimeType, sizeBytes: $sizeBytes, width: $width, height: $height, durationMs: $durationMs, blurhash: $blurhash, waveformB64: $waveformB64, thumbnailMediaId: $thumbnailMediaId, sourceUrl: $sourceUrl, previewUrl: $previewUrl, isDeleted: $isDeleted)';
}


}

/// @nodoc
abstract mixin class $MediaAttachmentCopyWith<$Res>  {
  factory $MediaAttachmentCopyWith(MediaAttachment value, $Res Function(MediaAttachment) _then) = _$MediaAttachmentCopyWithImpl;
@useResult
$Res call({
 String id, String messageId, String mediaId, String mediaType, String encryptionKeyB64, String contentHash, String plaintextHash, String mimeType, int sizeBytes, int width, int height, int durationMs, String blurhash, String waveformB64, String thumbnailMediaId, String sourceUrl, String previewUrl, bool isDeleted
});




}
/// @nodoc
class _$MediaAttachmentCopyWithImpl<$Res>
    implements $MediaAttachmentCopyWith<$Res> {
  _$MediaAttachmentCopyWithImpl(this._self, this._then);

  final MediaAttachment _self;
  final $Res Function(MediaAttachment) _then;

/// Create a copy of MediaAttachment
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? messageId = null,Object? mediaId = null,Object? mediaType = null,Object? encryptionKeyB64 = null,Object? contentHash = null,Object? plaintextHash = null,Object? mimeType = null,Object? sizeBytes = null,Object? width = null,Object? height = null,Object? durationMs = null,Object? blurhash = null,Object? waveformB64 = null,Object? thumbnailMediaId = null,Object? sourceUrl = null,Object? previewUrl = null,Object? isDeleted = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,messageId: null == messageId ? _self.messageId : messageId // ignore: cast_nullable_to_non_nullable
as String,mediaId: null == mediaId ? _self.mediaId : mediaId // ignore: cast_nullable_to_non_nullable
as String,mediaType: null == mediaType ? _self.mediaType : mediaType // ignore: cast_nullable_to_non_nullable
as String,encryptionKeyB64: null == encryptionKeyB64 ? _self.encryptionKeyB64 : encryptionKeyB64 // ignore: cast_nullable_to_non_nullable
as String,contentHash: null == contentHash ? _self.contentHash : contentHash // ignore: cast_nullable_to_non_nullable
as String,plaintextHash: null == plaintextHash ? _self.plaintextHash : plaintextHash // ignore: cast_nullable_to_non_nullable
as String,mimeType: null == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String,sizeBytes: null == sizeBytes ? _self.sizeBytes : sizeBytes // ignore: cast_nullable_to_non_nullable
as int,width: null == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as int,height: null == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as int,durationMs: null == durationMs ? _self.durationMs : durationMs // ignore: cast_nullable_to_non_nullable
as int,blurhash: null == blurhash ? _self.blurhash : blurhash // ignore: cast_nullable_to_non_nullable
as String,waveformB64: null == waveformB64 ? _self.waveformB64 : waveformB64 // ignore: cast_nullable_to_non_nullable
as String,thumbnailMediaId: null == thumbnailMediaId ? _self.thumbnailMediaId : thumbnailMediaId // ignore: cast_nullable_to_non_nullable
as String,sourceUrl: null == sourceUrl ? _self.sourceUrl : sourceUrl // ignore: cast_nullable_to_non_nullable
as String,previewUrl: null == previewUrl ? _self.previewUrl : previewUrl // ignore: cast_nullable_to_non_nullable
as String,isDeleted: null == isDeleted ? _self.isDeleted : isDeleted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [MediaAttachment].
extension MediaAttachmentPatterns on MediaAttachment {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MediaAttachment value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MediaAttachment() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MediaAttachment value)  $default,){
final _that = this;
switch (_that) {
case _MediaAttachment():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MediaAttachment value)?  $default,){
final _that = this;
switch (_that) {
case _MediaAttachment() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String messageId,  String mediaId,  String mediaType,  String encryptionKeyB64,  String contentHash,  String plaintextHash,  String mimeType,  int sizeBytes,  int width,  int height,  int durationMs,  String blurhash,  String waveformB64,  String thumbnailMediaId,  String sourceUrl,  String previewUrl,  bool isDeleted)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MediaAttachment() when $default != null:
return $default(_that.id,_that.messageId,_that.mediaId,_that.mediaType,_that.encryptionKeyB64,_that.contentHash,_that.plaintextHash,_that.mimeType,_that.sizeBytes,_that.width,_that.height,_that.durationMs,_that.blurhash,_that.waveformB64,_that.thumbnailMediaId,_that.sourceUrl,_that.previewUrl,_that.isDeleted);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String messageId,  String mediaId,  String mediaType,  String encryptionKeyB64,  String contentHash,  String plaintextHash,  String mimeType,  int sizeBytes,  int width,  int height,  int durationMs,  String blurhash,  String waveformB64,  String thumbnailMediaId,  String sourceUrl,  String previewUrl,  bool isDeleted)  $default,) {final _that = this;
switch (_that) {
case _MediaAttachment():
return $default(_that.id,_that.messageId,_that.mediaId,_that.mediaType,_that.encryptionKeyB64,_that.contentHash,_that.plaintextHash,_that.mimeType,_that.sizeBytes,_that.width,_that.height,_that.durationMs,_that.blurhash,_that.waveformB64,_that.thumbnailMediaId,_that.sourceUrl,_that.previewUrl,_that.isDeleted);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String messageId,  String mediaId,  String mediaType,  String encryptionKeyB64,  String contentHash,  String plaintextHash,  String mimeType,  int sizeBytes,  int width,  int height,  int durationMs,  String blurhash,  String waveformB64,  String thumbnailMediaId,  String sourceUrl,  String previewUrl,  bool isDeleted)?  $default,) {final _that = this;
switch (_that) {
case _MediaAttachment() when $default != null:
return $default(_that.id,_that.messageId,_that.mediaId,_that.mediaType,_that.encryptionKeyB64,_that.contentHash,_that.plaintextHash,_that.mimeType,_that.sizeBytes,_that.width,_that.height,_that.durationMs,_that.blurhash,_that.waveformB64,_that.thumbnailMediaId,_that.sourceUrl,_that.previewUrl,_that.isDeleted);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _MediaAttachment implements MediaAttachment {
  const _MediaAttachment({required this.id, required this.messageId, required this.mediaId, required this.mediaType, required this.encryptionKeyB64, required this.contentHash, required this.plaintextHash, required this.mimeType, required this.sizeBytes, required this.width, required this.height, required this.durationMs, required this.blurhash, required this.waveformB64, required this.thumbnailMediaId, required this.sourceUrl, required this.previewUrl, this.isDeleted = false});
  factory _MediaAttachment.fromJson(Map<String, dynamic> json) => _$MediaAttachmentFromJson(json);

@override final  String id;
@override final  String messageId;
@override final  String mediaId;
@override final  String mediaType;
@override final  String encryptionKeyB64;
@override final  String contentHash;
@override final  String plaintextHash;
@override final  String mimeType;
@override final  int sizeBytes;
@override final  int width;
@override final  int height;
@override final  int durationMs;
@override final  String blurhash;
@override final  String waveformB64;
@override final  String thumbnailMediaId;
@override final  String sourceUrl;
@override final  String previewUrl;
@override@JsonKey() final  bool isDeleted;

/// Create a copy of MediaAttachment
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MediaAttachmentCopyWith<_MediaAttachment> get copyWith => __$MediaAttachmentCopyWithImpl<_MediaAttachment>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MediaAttachmentToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MediaAttachment&&(identical(other.id, id) || other.id == id)&&(identical(other.messageId, messageId) || other.messageId == messageId)&&(identical(other.mediaId, mediaId) || other.mediaId == mediaId)&&(identical(other.mediaType, mediaType) || other.mediaType == mediaType)&&(identical(other.encryptionKeyB64, encryptionKeyB64) || other.encryptionKeyB64 == encryptionKeyB64)&&(identical(other.contentHash, contentHash) || other.contentHash == contentHash)&&(identical(other.plaintextHash, plaintextHash) || other.plaintextHash == plaintextHash)&&(identical(other.mimeType, mimeType) || other.mimeType == mimeType)&&(identical(other.sizeBytes, sizeBytes) || other.sizeBytes == sizeBytes)&&(identical(other.width, width) || other.width == width)&&(identical(other.height, height) || other.height == height)&&(identical(other.durationMs, durationMs) || other.durationMs == durationMs)&&(identical(other.blurhash, blurhash) || other.blurhash == blurhash)&&(identical(other.waveformB64, waveformB64) || other.waveformB64 == waveformB64)&&(identical(other.thumbnailMediaId, thumbnailMediaId) || other.thumbnailMediaId == thumbnailMediaId)&&(identical(other.sourceUrl, sourceUrl) || other.sourceUrl == sourceUrl)&&(identical(other.previewUrl, previewUrl) || other.previewUrl == previewUrl)&&(identical(other.isDeleted, isDeleted) || other.isDeleted == isDeleted));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,messageId,mediaId,mediaType,encryptionKeyB64,contentHash,plaintextHash,mimeType,sizeBytes,width,height,durationMs,blurhash,waveformB64,thumbnailMediaId,sourceUrl,previewUrl,isDeleted);

@override
String toString() {
  return 'MediaAttachment(id: $id, messageId: $messageId, mediaId: $mediaId, mediaType: $mediaType, encryptionKeyB64: $encryptionKeyB64, contentHash: $contentHash, plaintextHash: $plaintextHash, mimeType: $mimeType, sizeBytes: $sizeBytes, width: $width, height: $height, durationMs: $durationMs, blurhash: $blurhash, waveformB64: $waveformB64, thumbnailMediaId: $thumbnailMediaId, sourceUrl: $sourceUrl, previewUrl: $previewUrl, isDeleted: $isDeleted)';
}


}

/// @nodoc
abstract mixin class _$MediaAttachmentCopyWith<$Res> implements $MediaAttachmentCopyWith<$Res> {
  factory _$MediaAttachmentCopyWith(_MediaAttachment value, $Res Function(_MediaAttachment) _then) = __$MediaAttachmentCopyWithImpl;
@override @useResult
$Res call({
 String id, String messageId, String mediaId, String mediaType, String encryptionKeyB64, String contentHash, String plaintextHash, String mimeType, int sizeBytes, int width, int height, int durationMs, String blurhash, String waveformB64, String thumbnailMediaId, String sourceUrl, String previewUrl, bool isDeleted
});




}
/// @nodoc
class __$MediaAttachmentCopyWithImpl<$Res>
    implements _$MediaAttachmentCopyWith<$Res> {
  __$MediaAttachmentCopyWithImpl(this._self, this._then);

  final _MediaAttachment _self;
  final $Res Function(_MediaAttachment) _then;

/// Create a copy of MediaAttachment
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? messageId = null,Object? mediaId = null,Object? mediaType = null,Object? encryptionKeyB64 = null,Object? contentHash = null,Object? plaintextHash = null,Object? mimeType = null,Object? sizeBytes = null,Object? width = null,Object? height = null,Object? durationMs = null,Object? blurhash = null,Object? waveformB64 = null,Object? thumbnailMediaId = null,Object? sourceUrl = null,Object? previewUrl = null,Object? isDeleted = null,}) {
  return _then(_MediaAttachment(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,messageId: null == messageId ? _self.messageId : messageId // ignore: cast_nullable_to_non_nullable
as String,mediaId: null == mediaId ? _self.mediaId : mediaId // ignore: cast_nullable_to_non_nullable
as String,mediaType: null == mediaType ? _self.mediaType : mediaType // ignore: cast_nullable_to_non_nullable
as String,encryptionKeyB64: null == encryptionKeyB64 ? _self.encryptionKeyB64 : encryptionKeyB64 // ignore: cast_nullable_to_non_nullable
as String,contentHash: null == contentHash ? _self.contentHash : contentHash // ignore: cast_nullable_to_non_nullable
as String,plaintextHash: null == plaintextHash ? _self.plaintextHash : plaintextHash // ignore: cast_nullable_to_non_nullable
as String,mimeType: null == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String,sizeBytes: null == sizeBytes ? _self.sizeBytes : sizeBytes // ignore: cast_nullable_to_non_nullable
as int,width: null == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as int,height: null == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as int,durationMs: null == durationMs ? _self.durationMs : durationMs // ignore: cast_nullable_to_non_nullable
as int,blurhash: null == blurhash ? _self.blurhash : blurhash // ignore: cast_nullable_to_non_nullable
as String,waveformB64: null == waveformB64 ? _self.waveformB64 : waveformB64 // ignore: cast_nullable_to_non_nullable
as String,thumbnailMediaId: null == thumbnailMediaId ? _self.thumbnailMediaId : thumbnailMediaId // ignore: cast_nullable_to_non_nullable
as String,sourceUrl: null == sourceUrl ? _self.sourceUrl : sourceUrl // ignore: cast_nullable_to_non_nullable
as String,previewUrl: null == previewUrl ? _self.previewUrl : previewUrl // ignore: cast_nullable_to_non_nullable
as String,isDeleted: null == isDeleted ? _self.isDeleted : isDeleted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
