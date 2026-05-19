import 'dart:convert';
import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';

import 'group_sort_state.dart';

part 'member_group.freezed.dart';
part 'member_group.g.dart';

Uint8List? _uint8ListFromJson(String? json) =>
    json == null ? null : base64Decode(json);

String? _uint8ListToJson(Uint8List? bytes) =>
    bytes == null ? null : base64Encode(bytes);

@freezed
abstract class MemberGroup with _$MemberGroup {
  const factory MemberGroup({
    required String id,
    required String name,
    String? description,
    String? colorHex,
    String? emoji,
    @JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson)
    Uint8List? avatarImageData,
    @Default(0) int displayOrder,
    String? parentGroupId,
    @Default(0) int groupType,
    String? filterRules,
    required DateTime createdAt,
    @Default(GroupSortState.manualEmpty) GroupSortState sortState,
  }) = _MemberGroup;

  factory MemberGroup.fromJson(Map<String, dynamic> json) =>
      _$MemberGroupFromJson(json);
}
