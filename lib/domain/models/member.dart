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

enum MemberNameFont { standard, display, serif, mono, rounded }

enum MemberNameColorMode { standard, accent, custom }

@freezed
abstract class Member with _$Member {
  const factory Member({
    required String id,
    required String name,
    String? pronouns,
    @Default('❔') String emoji,
    String? age,
    String? bio,
    @JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson)
    Uint8List? avatarImageData,
    String? pkAvatarCachedUrl,
    @Default(true) bool isActive,
    required DateTime createdAt,
    @Default(0) int displayOrder,
    @Default(false) bool isAdmin,
    @Default(false) bool customColorEnabled,
    String? customColorHex,
    String? parentSystemId,
    String? pluralkitUuid,
    String? pluralkitId,
    String? pluralkitDisplayName,
    @Default(true) bool markdownEnabled,
    String? displayName,
    String? birthday,
    String? proxyTagsJson,
    String? pkBannerUrl,
    @Default(MemberProfileHeaderSource.prism)
    MemberProfileHeaderSource profileHeaderSource,
    @Default(MemberProfileHeaderLayout.compactBackground)
    MemberProfileHeaderLayout profileHeaderLayout,
    @Default(true) bool profileHeaderVisible,
    @Default(MemberNameFont.standard) MemberNameFont nameStyleFont,
    @Default(true) bool nameStyleBold,
    @Default(false) bool nameStyleItalic,
    @Default(MemberNameColorMode.standard)
    MemberNameColorMode nameStyleColorMode,
    String? nameStyleColorHex,
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
    // F4 create-push coordination lease (ms since epoch, synced). Mirrors
    // deletePushStartedAt for the member CREATE/POST path.
    int? createPushStartedAt,
    // Per-member fronting refactor (docs/plans/fronting-per-member-sessions.md
    // §2.3): when true, this member's session is treated as "background" and
    // omitted from avatar stacks, surfaced instead in the "Always-present"
    // header on period detail screens. Default false; opt-in per member.
    @Default(false) bool isAlwaysFronting,
  }) = _Member;

  factory Member.fromJson(Map<String, dynamic> json) => _$MemberFromJson(json);
}

extension MemberEffectiveName on Member {
  /// The name to show for this member: the canonical `name` in legacy mode,
  /// else the first non-blank of `displayName` → `pluralkitDisplayName` →
  /// `name`. Takes a plain bool, not the `MemberNameDisplay` enum, to avoid a
  /// model↔settings import cycle.
  String effectiveName({required bool preferDisplayName}) {
    if (!preferDisplayName) return name;
    for (final candidate in [displayName, pluralkitDisplayName]) {
      final trimmed = candidate?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return name;
  }
}
