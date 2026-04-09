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

 String get id;/// The ID of the chat message this attachment belongs to.
 String get messageId;/// Media type: 'image', 'voice', 'video', 'file'.
 String get mediaType;/// Server-side media ID for download.
 String get mediaId;/// MIME type (e.g. 'image/jpeg', 'audio/aac').
 String? get mimeType;/// Original filename.
 String? get fileName;/// File size in bytes.
 int? get sizeBytes;/// Image/video width in pixels.
 int? get width;/// Image/video height in pixels.
 int? get height;/// BlurHash placeholder string for progressive image loading.
 String get blurhash;/// Voice note / video duration in milliseconds.
 int? get durationMs;/// Base64-encoded encryption key for this media blob.
 String get encryptionKeyB64;/// SHA-256 hash of the ciphertext blob.
 String get contentHash;/// SHA-256 hash of the plaintext.
 String get plaintextHash;/// Display sort order within a message (for multi-image).
 int get sortOrder;/// Whether the media has expired on the relay and is no longer downloadable.
 bool get isExpired; DateTime get createdAt;
/// Create a copy of MediaAttachment
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MediaAttachmentCopyWith<MediaAttachment> get copyWith => _$MediaAttachmentCopyWithImpl<MediaAttachment>(this as MediaAttachment, _$identity);

  /// Serializes this MediaAttachment to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MediaAttachment&&(identical(other.id, id) || other.id == id)&&(identical(other.messageId, messageId) || other.messageId == messageId)&&(identical(other.mediaType, mediaType) || other.mediaType == mediaType)&&(identical(other.mediaId, mediaId) || other.mediaId == mediaId)&&(identical(other.mimeType, mimeType) || other.mimeType == mimeType)&&(identical(other.fileName, fileName) || other.fileName == fileName)&&(identical(other.sizeBytes, sizeBytes) || other.sizeBytes == sizeBytes)&&(identical(other.width, width) || other.width == width)&&(identical(other.height, height) || other.height == height)&&(identical(other.blurhash, blurhash) || other.blurhash == blurhash)&&(identical(other.durationMs, durationMs) || other.durationMs == durationMs)&&(identical(other.encryptionKeyB64, encryptionKeyB64) || other.encryptionKeyB64 == encryptionKeyB64)&&(identical(other.contentHash, contentHash) || other.contentHash == contentHash)&&(identical(other.plaintextHash, plaintextHash) || other.plaintextHash == plaintextHash)&&(identical(other.sortOrder, sortOrder) || other.sortOrder == sortOrder)&&(identical(other.isExpired, isExpired) || other.isExpired == isExpired)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,messageId,mediaType,mediaId,mimeType,fileName,sizeBytes,width,height,blurhash,durationMs,encryptionKeyB64,contentHash,plaintextHash,sortOrder,isExpired,createdAt);

@override
String toString() {
  return 'MediaAttachment(id: $id, messageId: $messageId, mediaType: $mediaType, mediaId: $mediaId, mimeType: $mimeType, fileName: $fileName, sizeBytes: $sizeBytes, width: $width, height: $height, blurhash: $blurhash, durationMs: $durationMs, encryptionKeyB64: $encryptionKeyB64, contentHash: $contentHash, plaintextHash: $plaintextHash, sortOrder: $sortOrder, isExpired: $isExpired, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class $MediaAttachmentCopyWith<$Res>  {
  factory $MediaAttachmentCopyWith(MediaAttachment value, $Res Function(MediaAttachment) _then) = _$MediaAttachmentCopyWithImpl;
@useResult
$Res call({
 String id, String messageId, String mediaType, String mediaId, String? mimeType, String? fileName, int? sizeBytes, int? width, int? height, String blurhash, int? durationMs, String encryptionKeyB64, String contentHash, String plaintextHash, int sortOrder, bool isExpired, DateTime createdAt
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
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? messageId = null,Object? mediaType = null,Object? mediaId = null,Object? mimeType = freezed,Object? fileName = freezed,Object? sizeBytes = freezed,Object? width = freezed,Object? height = freezed,Object? blurhash = null,Object? durationMs = freezed,Object? encryptionKeyB64 = null,Object? contentHash = null,Object? plaintextHash = null,Object? sortOrder = null,Object? isExpired = null,Object? createdAt = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,messageId: null == messageId ? _self.messageId : messageId // ignore: cast_nullable_to_non_nullable
as String,mediaType: null == mediaType ? _self.mediaType : mediaType // ignore: cast_nullable_to_non_nullable
as String,mediaId: null == mediaId ? _self.mediaId : mediaId // ignore: cast_nullable_to_non_nullable
as String,mimeType: freezed == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String?,fileName: freezed == fileName ? _self.fileName : fileName // ignore: cast_nullable_to_non_nullable
as String?,sizeBytes: freezed == sizeBytes ? _self.sizeBytes : sizeBytes // ignore: cast_nullable_to_non_nullable
as int?,width: freezed == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as int?,height: freezed == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as int?,blurhash: null == blurhash ? _self.blurhash : blurhash // ignore: cast_nullable_to_non_nullable
as String,durationMs: freezed == durationMs ? _self.durationMs : durationMs // ignore: cast_nullable_to_non_nullable
as int?,encryptionKeyB64: null == encryptionKeyB64 ? _self.encryptionKeyB64 : encryptionKeyB64 // ignore: cast_nullable_to_non_nullable
as String,contentHash: null == contentHash ? _self.contentHash : contentHash // ignore: cast_nullable_to_non_nullable
as String,plaintextHash: null == plaintextHash ? _self.plaintextHash : plaintextHash // ignore: cast_nullable_to_non_nullable
as String,sortOrder: null == sortOrder ? _self.sortOrder : sortOrder // ignore: cast_nullable_to_non_nullable
as int,isExpired: null == isExpired ? _self.isExpired : isExpired // ignore: cast_nullable_to_non_nullable
as bool,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String messageId,  String mediaType,  String mediaId,  String? mimeType,  String? fileName,  int? sizeBytes,  int? width,  int? height,  String blurhash,  int? durationMs,  String encryptionKeyB64,  String contentHash,  String plaintextHash,  int sortOrder,  bool isExpired,  DateTime createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MediaAttachment() when $default != null:
return $default(_that.id,_that.messageId,_that.mediaType,_that.mediaId,_that.mimeType,_that.fileName,_that.sizeBytes,_that.width,_that.height,_that.blurhash,_that.durationMs,_that.encryptionKeyB64,_that.contentHash,_that.plaintextHash,_that.sortOrder,_that.isExpired,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String messageId,  String mediaType,  String mediaId,  String? mimeType,  String? fileName,  int? sizeBytes,  int? width,  int? height,  String blurhash,  int? durationMs,  String encryptionKeyB64,  String contentHash,  String plaintextHash,  int sortOrder,  bool isExpired,  DateTime createdAt)  $default,) {final _that = this;
switch (_that) {
case _MediaAttachment():
return $default(_that.id,_that.messageId,_that.mediaType,_that.mediaId,_that.mimeType,_that.fileName,_that.sizeBytes,_that.width,_that.height,_that.blurhash,_that.durationMs,_that.encryptionKeyB64,_that.contentHash,_that.plaintextHash,_that.sortOrder,_that.isExpired,_that.createdAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String messageId,  String mediaType,  String mediaId,  String? mimeType,  String? fileName,  int? sizeBytes,  int? width,  int? height,  String blurhash,  int? durationMs,  String encryptionKeyB64,  String contentHash,  String plaintextHash,  int sortOrder,  bool isExpired,  DateTime createdAt)?  $default,) {final _that = this;
switch (_that) {
case _MediaAttachment() when $default != null:
return $default(_that.id,_that.messageId,_that.mediaType,_that.mediaId,_that.mimeType,_that.fileName,_that.sizeBytes,_that.width,_that.height,_that.blurhash,_that.durationMs,_that.encryptionKeyB64,_that.contentHash,_that.plaintextHash,_that.sortOrder,_that.isExpired,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _MediaAttachment implements MediaAttachment {
  const _MediaAttachment({required this.id, required this.messageId, required this.mediaType, required this.mediaId, this.mimeType, this.fileName, this.sizeBytes, this.width, this.height, this.blurhash = '', this.durationMs, this.encryptionKeyB64 = '', this.contentHash = '', this.plaintextHash = '', this.sortOrder = 0, this.isExpired = false, required this.createdAt});
  factory _MediaAttachment.fromJson(Map<String, dynamic> json) => _$MediaAttachmentFromJson(json);

@override final  String id;
/// The ID of the chat message this attachment belongs to.
@override final  String messageId;
/// Media type: 'image', 'voice', 'video', 'file'.
@override final  String mediaType;
/// Server-side media ID for download.
@override final  String mediaId;
/// MIME type (e.g. 'image/jpeg', 'audio/aac').
@override final  String? mimeType;
/// Original filename.
@override final  String? fileName;
/// File size in bytes.
@override final  int? sizeBytes;
/// Image/video width in pixels.
@override final  int? width;
/// Image/video height in pixels.
@override final  int? height;
/// BlurHash placeholder string for progressive image loading.
@override@JsonKey() final  String blurhash;
/// Voice note / video duration in milliseconds.
@override final  int? durationMs;
/// Base64-encoded encryption key for this media blob.
@override@JsonKey() final  String encryptionKeyB64;
/// SHA-256 hash of the ciphertext blob.
@override@JsonKey() final  String contentHash;
/// SHA-256 hash of the plaintext.
@override@JsonKey() final  String plaintextHash;
/// Display sort order within a message (for multi-image).
@override@JsonKey() final  int sortOrder;
/// Whether the media has expired on the relay and is no longer downloadable.
@override@JsonKey() final  bool isExpired;
@override final  DateTime createdAt;

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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MediaAttachment&&(identical(other.id, id) || other.id == id)&&(identical(other.messageId, messageId) || other.messageId == messageId)&&(identical(other.mediaType, mediaType) || other.mediaType == mediaType)&&(identical(other.mediaId, mediaId) || other.mediaId == mediaId)&&(identical(other.mimeType, mimeType) || other.mimeType == mimeType)&&(identical(other.fileName, fileName) || other.fileName == fileName)&&(identical(other.sizeBytes, sizeBytes) || other.sizeBytes == sizeBytes)&&(identical(other.width, width) || other.width == width)&&(identical(other.height, height) || other.height == height)&&(identical(other.blurhash, blurhash) || other.blurhash == blurhash)&&(identical(other.durationMs, durationMs) || other.durationMs == durationMs)&&(identical(other.encryptionKeyB64, encryptionKeyB64) || other.encryptionKeyB64 == encryptionKeyB64)&&(identical(other.contentHash, contentHash) || other.contentHash == contentHash)&&(identical(other.plaintextHash, plaintextHash) || other.plaintextHash == plaintextHash)&&(identical(other.sortOrder, sortOrder) || other.sortOrder == sortOrder)&&(identical(other.isExpired, isExpired) || other.isExpired == isExpired)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,messageId,mediaType,mediaId,mimeType,fileName,sizeBytes,width,height,blurhash,durationMs,encryptionKeyB64,contentHash,plaintextHash,sortOrder,isExpired,createdAt);

@override
String toString() {
  return 'MediaAttachment(id: $id, messageId: $messageId, mediaType: $mediaType, mediaId: $mediaId, mimeType: $mimeType, fileName: $fileName, sizeBytes: $sizeBytes, width: $width, height: $height, blurhash: $blurhash, durationMs: $durationMs, encryptionKeyB64: $encryptionKeyB64, contentHash: $contentHash, plaintextHash: $plaintextHash, sortOrder: $sortOrder, isExpired: $isExpired, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$MediaAttachmentCopyWith<$Res> implements $MediaAttachmentCopyWith<$Res> {
  factory _$MediaAttachmentCopyWith(_MediaAttachment value, $Res Function(_MediaAttachment) _then) = __$MediaAttachmentCopyWithImpl;
@override @useResult
$Res call({
 String id, String messageId, String mediaType, String mediaId, String? mimeType, String? fileName, int? sizeBytes, int? width, int? height, String blurhash, int? durationMs, String encryptionKeyB64, String contentHash, String plaintextHash, int sortOrder, bool isExpired, DateTime createdAt
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
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? messageId = null,Object? mediaType = null,Object? mediaId = null,Object? mimeType = freezed,Object? fileName = freezed,Object? sizeBytes = freezed,Object? width = freezed,Object? height = freezed,Object? blurhash = null,Object? durationMs = freezed,Object? encryptionKeyB64 = null,Object? contentHash = null,Object? plaintextHash = null,Object? sortOrder = null,Object? isExpired = null,Object? createdAt = null,}) {
  return _then(_MediaAttachment(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,messageId: null == messageId ? _self.messageId : messageId // ignore: cast_nullable_to_non_nullable
as String,mediaType: null == mediaType ? _self.mediaType : mediaType // ignore: cast_nullable_to_non_nullable
as String,mediaId: null == mediaId ? _self.mediaId : mediaId // ignore: cast_nullable_to_non_nullable
as String,mimeType: freezed == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String?,fileName: freezed == fileName ? _self.fileName : fileName // ignore: cast_nullable_to_non_nullable
as String?,sizeBytes: freezed == sizeBytes ? _self.sizeBytes : sizeBytes // ignore: cast_nullable_to_non_nullable
as int?,width: freezed == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as int?,height: freezed == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as int?,blurhash: null == blurhash ? _self.blurhash : blurhash // ignore: cast_nullable_to_non_nullable
as String,durationMs: freezed == durationMs ? _self.durationMs : durationMs // ignore: cast_nullable_to_non_nullable
as int?,encryptionKeyB64: null == encryptionKeyB64 ? _self.encryptionKeyB64 : encryptionKeyB64 // ignore: cast_nullable_to_non_nullable
as String,contentHash: null == contentHash ? _self.contentHash : contentHash // ignore: cast_nullable_to_non_nullable
as String,plaintextHash: null == plaintextHash ? _self.plaintextHash : plaintextHash // ignore: cast_nullable_to_non_nullable
as String,sortOrder: null == sortOrder ? _self.sortOrder : sortOrder // ignore: cast_nullable_to_non_nullable
as int,isExpired: null == isExpired ? _self.isExpired : isExpired // ignore: cast_nullable_to_non_nullable
as bool,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on
