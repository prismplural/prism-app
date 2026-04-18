import 'dart:convert';

// ---------------------------------------------------------------------------
// Sync direction
// ---------------------------------------------------------------------------

/// Direction of PluralKit sync.
enum PkSyncDirection {
  /// Import from PluralKit only.
  pullOnly,

  /// Export to PluralKit only.
  pushOnly,

  /// Two-way sync (compare timestamps, push newer, pull older).
  bidirectional,

  /// Sync disabled.
  disabled;

  /// Whether this direction includes pulling from PK.
  bool get pullEnabled =>
      this == PkSyncDirection.pullOnly || this == PkSyncDirection.bidirectional;

  /// Whether this direction includes pushing to PK.
  bool get pushEnabled =>
      this == PkSyncDirection.pushOnly || this == PkSyncDirection.bidirectional;

  String toJson() => name;

  static PkSyncDirection fromJson(String value) {
    return PkSyncDirection.values.firstWhere(
      (e) => e.name == value,
      orElse: () => PkSyncDirection.pullOnly,
    );
  }
}

// ---------------------------------------------------------------------------
// Per-field sync config
// ---------------------------------------------------------------------------

/// Per-field sync direction for a specific member.
///
/// Stored as JSON in the `fieldSyncConfig` column of `pluralkit_sync_state`.
/// The top-level JSON is a map keyed by member ID to [PkFieldSyncConfig].
class PkFieldSyncConfig {
  final PkSyncDirection name;
  final PkSyncDirection displayName;
  final PkSyncDirection pronouns;
  final PkSyncDirection description;
  final PkSyncDirection color;
  final PkSyncDirection birthday;

  const PkFieldSyncConfig({
    this.name = PkSyncDirection.bidirectional,
    this.displayName = PkSyncDirection.bidirectional,
    this.pronouns = PkSyncDirection.bidirectional,
    this.description = PkSyncDirection.bidirectional,
    this.color = PkSyncDirection.bidirectional,
    this.birthday = PkSyncDirection.bidirectional,
  });

  /// Returns the direction for a named field.
  PkSyncDirection directionFor(String field) {
    switch (field) {
      case 'name':
        return name;
      case 'displayName':
        return displayName;
      case 'pronouns':
        return pronouns;
      case 'description':
        return description;
      case 'color':
        return color;
      case 'birthday':
        return birthday;
      default:
        return PkSyncDirection.bidirectional;
    }
  }

  Map<String, dynamic> toJson() => {
        'name': name.toJson(),
        'displayName': displayName.toJson(),
        'pronouns': pronouns.toJson(),
        'description': description.toJson(),
        'color': color.toJson(),
        'birthday': birthday.toJson(),
      };

  factory PkFieldSyncConfig.fromJson(Map<String, dynamic> json) {
    return PkFieldSyncConfig(
      name: PkSyncDirection.fromJson(json['name'] as String? ?? 'bidirectional'),
      displayName: PkSyncDirection.fromJson(
          json['displayName'] as String? ?? 'bidirectional'),
      pronouns:
          PkSyncDirection.fromJson(json['pronouns'] as String? ?? 'bidirectional'),
      description: PkSyncDirection.fromJson(
          json['description'] as String? ?? 'bidirectional'),
      color:
          PkSyncDirection.fromJson(json['color'] as String? ?? 'bidirectional'),
      birthday: PkSyncDirection.fromJson(
          json['birthday'] as String? ?? 'bidirectional'),
    );
  }

  PkFieldSyncConfig copyWith({
    PkSyncDirection? name,
    PkSyncDirection? displayName,
    PkSyncDirection? pronouns,
    PkSyncDirection? description,
    PkSyncDirection? color,
    PkSyncDirection? birthday,
  }) {
    return PkFieldSyncConfig(
      name: name ?? this.name,
      displayName: displayName ?? this.displayName,
      pronouns: pronouns ?? this.pronouns,
      description: description ?? this.description,
      color: color ?? this.color,
      birthday: birthday ?? this.birthday,
    );
  }
}

// ---------------------------------------------------------------------------
// Sync summary
// ---------------------------------------------------------------------------

/// Summary of a bidirectional sync run.
class PkSyncSummary {
  final int membersPulled;
  final int membersPushed;
  final int membersSkipped;
  final int switchesPulled;
  final int switchesPushed;

  const PkSyncSummary({
    this.membersPulled = 0,
    this.membersPushed = 0,
    this.membersSkipped = 0,
    this.switchesPulled = 0,
    this.switchesPushed = 0,
  });

  int get totalChanges =>
      membersPulled + membersPushed + switchesPulled + switchesPushed;

  Map<String, dynamic> toJson() => {
        'membersPulled': membersPulled,
        'membersPushed': membersPushed,
        'membersSkipped': membersSkipped,
        'switchesPulled': switchesPulled,
        'switchesPushed': switchesPushed,
      };

  factory PkSyncSummary.fromJson(Map<String, dynamic> json) {
    return PkSyncSummary(
      membersPulled: json['membersPulled'] as int? ?? 0,
      membersPushed: json['membersPushed'] as int? ?? 0,
      membersSkipped: json['membersSkipped'] as int? ?? 0,
      switchesPulled: json['switchesPulled'] as int? ?? 0,
      switchesPushed: json['switchesPushed'] as int? ?? 0,
    );
  }

  @override
  String toString() {
    final parts = <String>[];
    if (membersPulled > 0) parts.add('$membersPulled pulled');
    if (membersPushed > 0) parts.add('$membersPushed pushed');
    if (membersSkipped > 0) parts.add('$membersSkipped skipped');
    if (switchesPulled > 0) parts.add('$switchesPulled switches pulled');
    if (switchesPushed > 0) parts.add('$switchesPushed switches pushed');
    return parts.isEmpty ? 'No changes' : parts.join(', ');
  }
}

// ---------------------------------------------------------------------------
// Helpers — parse/serialize the fieldSyncConfig column
// ---------------------------------------------------------------------------

/// Parse the `fieldSyncConfig` JSON column value into a per-member config map.
Map<String, PkFieldSyncConfig> parseFieldSyncConfig(String? json) {
  if (json == null || json.isEmpty) return {};
  try {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return map.map(
      (key, value) => MapEntry(
        key,
        PkFieldSyncConfig.fromJson(value as Map<String, dynamic>),
      ),
    );
  } catch (_) {
    return {};
  }
}

/// Serialize a per-member config map to JSON for the `fieldSyncConfig` column.
String serializeFieldSyncConfig(Map<String, PkFieldSyncConfig> config) {
  return jsonEncode(config.map((key, value) => MapEntry(key, value.toJson())));
}
