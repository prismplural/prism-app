import 'dart:convert';
import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'member.freezed.dart';
part 'member.g.dart';

Uint8List? _uint8ListFromJson(String? json) =>
    json == null ? null : base64Decode(json);

String? _uint8ListToJson(Uint8List? bytes) =>
    bytes == null ? null : base64Encode(bytes);

@freezed
abstract class Member with _$Member {
  const factory Member({
    required String id,
    required String name,
    String? pronouns,
    @Default('❔') String emoji,
    int? age,
    String? bio,
    @JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson)
    Uint8List? avatarImageData,
    @Default(true) bool isActive,
    required DateTime createdAt,
    @Default(0) int displayOrder,
    @Default(false) bool isAdmin,
    @Default(false) bool customColorEnabled,
    String? customColorHex,
    String? parentSystemId,
    String? pluralkitUuid,
    String? pluralkitId,
    @Default(false) bool markdownEnabled,
    String? displayName,
    String? birthday,
    String? proxyTagsJson,
    @Default(false) bool pluralkitSyncIgnored,
  }) = _Member;

  factory Member.fromJson(Map<String, dynamic> json) => _$MemberFromJson(json);
}
