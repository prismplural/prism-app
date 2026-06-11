/// PluralKit API v2 data models.
///
/// Simple classes with fromJson factories — NOT freezed, as these are
/// transient API responses that don't need immutability or equality.
library;

import 'dart:convert';

class PKSystem {
  final String id;

  /// Full UUID — the only stable cross-time identity key. Short ids become
  /// user-changeable with PK Premium (~Feb 2026), so the UUID is what the
  /// file-import system-identity check (2026-06 PK audit H8) prefers.
  ///
  /// Nullable because some legacy/partial payloads (and older `pk;export`
  /// roots) may omit it; callers must fall back to [id] when it is absent.
  final String? uuid;
  final String? name;
  final String? description;
  final String? tag;
  final String? avatarUrl;

  const PKSystem({
    required this.id,
    this.uuid,
    this.name,
    this.description,
    this.tag,
    this.avatarUrl,
  });

  factory PKSystem.fromJson(Map<String, dynamic> json) {
    return PKSystem(
      id: json['id'] as String,
      // Both the API (`GET /systems/@me`) and the `pk;export` root carry
      // `uuid`; parse it so the file-import identity check has a stable key
      // (2026-06 PK audit H8).
      uuid: json['uuid'] as String?,
      name: json['name'] as String?,
      description: json['description'] as String?,
      tag: json['tag'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}

class PKMember {
  /// 5-character PluralKit ID.
  final String id;

  /// Full UUID for stable cross-system identification.
  final String uuid;
  final String name;
  final String? displayName;
  final String? pronouns;
  final String? description;
  final String? color;
  final String? avatarUrl;

  /// PK birthday wire string — `YYYY-MM-DD`. Year `0004` means "no year"
  /// (PK's sentinel for hidden year). Kept as a raw string to avoid lossy
  /// DateTime round-trips.
  final String? birthday;

  /// Raw JSON for PK `proxy_tags` array (`[{prefix, suffix}, ...]`).
  /// Stored verbatim so we can pull without a dedicated editor UI.
  /// `null` means PK did not supply the field; `"[]"` means empty array.
  final String? proxyTagsJson;

  /// PK `banner` URL.
  final String? bannerUrl;

  /// Whether the PK payload included the `banner` field at all.
  ///
  /// Missing means "unknown/preserve"; present null means "clear".
  final bool hasBannerField;

  /// PK-assigned creation timestamp (read-only on the API).
  final DateTime? created;

  /// Owning system's short id, present ONLY on the `GET /members/{ref}`
  /// single-member endpoint (the list endpoints `GET /systems/@me/members`
  /// and the inline switch/fronter member objects omit it).
  ///
  /// 2026-06 PK audit H12a — short ids are a globally-dense namespace, so a
  /// stale or foreign short id can resolve to ANOTHER system's member
  /// (live-verified: `GET /members/zzzzz` → 200, system "venus"). Whenever a
  /// fetched member carries this field, ownership-sensitive call sites
  /// (link / import / re-link / crash-recovery reuse) compare it against the
  /// connected system id and treat a mismatch exactly like a 404/stale link
  /// rather than adopting foreign data. Null means "PK didn't tell us"
  /// (a list-endpoint object, or an older payload) — callers keep their
  /// prior behavior when ownership is unknowable.
  final String? system;

  const PKMember({
    required this.id,
    required this.uuid,
    required this.name,
    this.displayName,
    this.pronouns,
    this.description,
    this.color,
    this.avatarUrl,
    this.birthday,
    this.proxyTagsJson,
    this.bannerUrl,
    this.hasBannerField = false,
    this.created,
    this.system,
  });

  factory PKMember.fromJson(Map<String, dynamic> json) {
    String? proxyTagsJson;
    final rawProxyTags = json['proxy_tags'];
    if (rawProxyTags is List) {
      proxyTagsJson = jsonEncode(rawProxyTags);
    }
    DateTime? created;
    final rawCreated = json['created'];
    if (rawCreated is String) {
      created = DateTime.tryParse(rawCreated);
    }

    return PKMember(
      id: json['id'] as String,
      uuid: json['uuid'] as String,
      name: json['name'] as String,
      displayName: json['display_name'] as String?,
      pronouns: json['pronouns'] as String?,
      description: json['description'] as String?,
      color: json['color'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      birthday: json['birthday'] as String?,
      proxyTagsJson: proxyTagsJson,
      bannerUrl: json['banner'] as String?,
      hasBannerField: json.containsKey('banner'),
      created: created,
      // 2026-06 PK audit H12a: only `GET /members/{ref}` includes `system`;
      // list/embedded shapes leave it absent → null → ownership unknown.
      system: json['system'] as String?,
    );
  }
}

class PKGroup {
  /// 5-character PluralKit short ID (display only).
  final String id;

  /// Full UUID — the canonical identity key.
  final String uuid;
  final String name;
  final String? displayName;
  final String? description;

  /// 6-char hex without `#`.
  final String? color;

  /// PK `icon` is a URL (not an emoji). Phase 1 stores this nowhere; kept on
  /// the model for future use (group avatar blob follow-up).
  final String? iconUrl;

  /// PK `banner` URL. Not persisted today.
  final String? bannerUrl;

  /// Membership list for this group, as PK member UUIDs (PK returns `members`
  /// inline when `with_members=true`).
  ///
  /// **Null means "unknown"** — e.g. privacy hid the field or the fallback
  /// fetch failed. Callers MUST NOT use null to drive removals (see plan R2).
  /// An empty list means legitimately empty (no members).
  final List<String>? memberIds;

  const PKGroup({
    required this.id,
    required this.uuid,
    required this.name,
    this.displayName,
    this.description,
    this.color,
    this.iconUrl,
    this.bannerUrl,
    this.memberIds,
  });

  factory PKGroup.fromJson(Map<String, dynamic> json) {
    List<String>? memberIds;
    if (json.containsKey('members')) {
      final raw = json['members'];
      if (raw is List) {
        final parsed = <String>[];
        for (final entry in raw) {
          if (entry is String) {
            // `/groups/{ref}/members` returns String[] of UUIDs when
            // `with_members=true` isn't used, but the groups list itself
            // with `with_members=true` returns full member objects.
            parsed.add(entry);
          } else if (entry is Map<String, dynamic>) {
            final uuid = entry['uuid'];
            if (uuid is String) {
              parsed.add(uuid);
            }
          }
        }
        memberIds = parsed;
      } else if (raw == null) {
        // PK can serialize `members: null` when the caller lacks scope — treat
        // the same as "unknown" to be safe.
        memberIds = null;
      }
    }

    return PKGroup(
      id: json['id'] as String,
      uuid: json['uuid'] as String,
      name: json['name'] as String,
      displayName: json['display_name'] as String?,
      description: json['description'] as String?,
      color: json['color'] as String?,
      iconUrl: json['icon'] as String?,
      bannerUrl: json['banner'] as String?,
      memberIds: memberIds,
    );
  }
}

/// Tolerant member summary embedded in switch/fronter responses.
///
/// `/systems/@me/fronters` returns member objects, but callers using older
/// switch endpoints can still receive short ID strings. This summary keeps the
/// useful identity/display fields without requiring the full [PKMember] shape.
class PKMemberSummary {
  /// 5-character PluralKit ID.
  final String id;

  /// Full UUID when PK included it in the payload.
  final String? uuid;
  final String? name;
  final String? displayName;
  final String? avatarUrl;

  const PKMemberSummary({
    required this.id,
    this.uuid,
    this.name,
    this.displayName,
    this.avatarUrl,
  });

  factory PKMemberSummary.fromJson(Map<String, dynamic> json) {
    return PKMemberSummary(
      id: json['id'] as String,
      uuid: json['uuid'] as String?,
      name: json['name'] as String?,
      displayName: json['display_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}

class PKSwitch {
  final String id;
  final DateTime timestamp;

  /// List of PK 5-character member IDs that are fronting in this switch.
  final List<String> members;

  /// Member summaries included by endpoints such as `/fronters`.
  ///
  /// Empty when the API returned `members` as `String[]`.
  final List<PKMemberSummary> memberDetails;

  const PKSwitch({
    required this.id,
    required this.timestamp,
    required this.members,
    this.memberDetails = const [],
  });

  /// Parses a switch from either shape the PK API returns:
  /// - `GET /systems/{ref}/switches` returns `members: string[]` (short IDs).
  /// - `POST /systems/{ref}/switches` and `GET /systems/{ref}/fronters`
  ///   return `members: Member[]` (full member objects).
  ///
  /// In both cases we keep `PKSwitch.members` as a `List<String>` of short IDs.
  factory PKSwitch.fromJson(Map<String, dynamic> json) {
    final rawMembers = json['members'] as List<dynamic>? ?? const [];
    final memberIds = <String>[];
    final memberDetails = <PKMemberSummary>[];
    for (final entry in rawMembers) {
      if (entry is String) {
        memberIds.add(entry);
      } else if (entry is Map<String, dynamic>) {
        final id = entry['id'];
        if (id is String) {
          memberIds.add(id);
          memberDetails.add(PKMemberSummary.fromJson(entry));
        }
      }
    }
    return PKSwitch(
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      members: memberIds,
      memberDetails: memberDetails,
    );
  }
}
