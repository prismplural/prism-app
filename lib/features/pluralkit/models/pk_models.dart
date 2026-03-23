/// PluralKit API v2 data models.
///
/// Simple classes with fromJson factories — NOT freezed, as these are
/// transient API responses that don't need immutability or equality.
library;

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

  const PKMember({
    required this.id,
    required this.uuid,
    required this.name,
    this.displayName,
    this.pronouns,
    this.description,
    this.color,
    this.avatarUrl,
  });

  factory PKMember.fromJson(Map<String, dynamic> json) {
    return PKMember(
      id: json['id'] as String,
      uuid: json['uuid'] as String,
      name: json['name'] as String,
      displayName: json['display_name'] as String?,
      pronouns: json['pronouns'] as String?,
      description: json['description'] as String?,
      color: json['color'] as String?,
      avatarUrl: json['avatar_url'] as String?,
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

  factory PKSwitch.fromJson(Map<String, dynamic> json) {
    return PKSwitch(
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      members: (json['members'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
    );
  }
}
