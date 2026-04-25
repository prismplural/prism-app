/// PluralKit API v2 data models.
///
/// Simple classes with fromJson factories — NOT freezed, as these are
/// transient API responses that don't need immutability or equality.
library;

import 'dart:convert';

class PKSystem {
  final String id;
  final String? name;
  final String? description;
  final String? tag;
  final String? avatarUrl;

  const PKSystem({
    required this.id,
    this.name,
    this.description,
    this.tag,
    this.avatarUrl,
  });

  factory PKSystem.fromJson(Map<String, dynamic> json) {
    return PKSystem(
      id: json['id'] as String,
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

  /// PK `banner` URL. Stored as a URL; no bytes download until UI exists.
  final String? bannerUrl;

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
  });

  factory PKMember.fromJson(Map<String, dynamic> json) {
    String? proxyTagsJson;
    final rawProxyTags = json['proxy_tags'];
    if (rawProxyTags is List) {
      proxyTagsJson = jsonEncode(rawProxyTags);
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

class PKSwitch {
  final String id;
  final DateTime timestamp;

  /// List of PK 5-character member IDs that are fronting in this switch.
  final List<String> members;

  const PKSwitch({
    required this.id,
    required this.timestamp,
    required this.members,
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
    for (final entry in rawMembers) {
      if (entry is String) {
        memberIds.add(entry);
      } else if (entry is Map<String, dynamic>) {
        final id = entry['id'];
        if (id is String) {
          memberIds.add(id);
        }
      }
    }
    return PKSwitch(
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      members: memberIds,
    );
  }
}
