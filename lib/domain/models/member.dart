import 'dart:convert';
import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'member.freezed.dart';
part 'member.g.dart';

Uint8List? _uint8ListFromJson(String? json) =>
    json == null ? null : base64Decode(json);

String? _uint8ListToJson(Uint8List? bytes) =>
    bytes == null ? null : base64Encode(bytes);

enum MemberProfileHeaderSource { pluralKit, prism }

enum MemberProfileHeaderLayout { compactBackground, classicOverlap }

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
    String? pkBannerUrl,
    @Default(MemberProfileHeaderSource.prism)
    MemberProfileHeaderSource profileHeaderSource,
    @Default(MemberProfileHeaderLayout.compactBackground)
    MemberProfileHeaderLayout profileHeaderLayout,
    @JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson)
    Uint8List? profileHeaderImageData,
    @JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson)
    Uint8List? pkBannerImageData,
    String? pkBannerCachedUrl,
    @Default(false) bool pluralkitSyncIgnored,
    // Plan 02 (PK deletion push). Set by the repo when a PK-linked member is
    // soft-deleted; consumed only by the PK push path. `isDeleted` is mirrored
    // onto the domain so sync-service re-read guards don't need the Drift row.
    @Default(false) bool isDeleted,
    int? deleteIntentEpoch,
    int? deletePushStartedAt,
    // Per-member fronting refactor (docs/plans/fronting-per-member-sessions.md
    // §2.3): when true, this member's session is treated as "background" and
    // omitted from avatar stacks, surfaced instead in the "Always-present"
    // header on period detail screens. Default false; opt-in per member.
    @Default(false) bool isAlwaysFronting,
  }) = _Member;

  factory Member.fromJson(Map<String, dynamic> json) => _$MemberFromJson(json);
}
