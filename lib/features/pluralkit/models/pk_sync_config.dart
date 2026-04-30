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
  final PkSyncDirection proxyTags;

  /// `proxyTags` defaults to [PkSyncDirection.bidirectional] by intentional
  /// product policy: proxy tags are now editable inside Prism, and bidirectional
  /// is the right default for an editable field — local edits should propagate
  /// to PK and PK-side edits should propagate back. Keep this default; do not
  /// flip to pull-only or disabled without re-deciding the product behavior of
  /// the editable proxy-tag UI in `member_profile_header_editor.dart`.
  const PkFieldSyncConfig({
    this.name = PkSyncDirection.bidirectional,
    this.displayName = PkSyncDirection.bidirectional,
    this.pronouns = PkSyncDirection.bidirectional,
    this.description = PkSyncDirection.bidirectional,
    this.color = PkSyncDirection.bidirectional,
    this.birthday = PkSyncDirection.bidirectional,
    this.proxyTags = PkSyncDirection.bidirectional,
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
      case 'proxyTags':
        return proxyTags;
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
    'proxyTags': proxyTags.toJson(),
  };

  factory PkFieldSyncConfig.fromJson(Map<String, dynamic> json) {
    return PkFieldSyncConfig(
      name: PkSyncDirection.fromJson(
        json['name'] as String? ?? 'bidirectional',
      ),
      displayName: PkSyncDirection.fromJson(
        json['displayName'] as String? ?? 'bidirectional',
      ),
      pronouns: PkSyncDirection.fromJson(
        json['pronouns'] as String? ?? 'bidirectional',
      ),
      description: PkSyncDirection.fromJson(
        json['description'] as String? ?? 'bidirectional',
      ),
      color: PkSyncDirection.fromJson(
        json['color'] as String? ?? 'bidirectional',
      ),
      birthday: PkSyncDirection.fromJson(
        json['birthday'] as String? ?? 'bidirectional',
      ),
      proxyTags: PkSyncDirection.fromJson(
        json['proxyTags'] as String? ?? 'bidirectional',
      ),
    );
  }

  PkFieldSyncConfig copyWith({
    PkSyncDirection? name,
    PkSyncDirection? displayName,
    PkSyncDirection? pronouns,
    PkSyncDirection? description,
    PkSyncDirection? color,
    PkSyncDirection? birthday,
    PkSyncDirection? proxyTags,
  }) {
    return PkFieldSyncConfig(
      name: name ?? this.name,
      displayName: displayName ?? this.displayName,
      pronouns: pronouns ?? this.pronouns,
      description: description ?? this.description,
      color: color ?? this.color,
      birthday: birthday ?? this.birthday,
      proxyTags: proxyTags ?? this.proxyTags,
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

  /// How many PK-side deletions this push executed.
  final int membersDeletedOnPk;
  final int switchesDeletedOnPk;

  /// Human-readable messages describing links that PK 404'd during this run
  /// (member or switch targets that no longer exist on PK). These are
  /// surfaced to the user via `syncError` after the sync finishes — each
  /// corresponds to a local link that was cleared so the user can re-link
  /// from the mapping screen.
  final List<String> staleLinkMessages;

  const PkSyncSummary({
    this.membersPulled = 0,
    this.membersPushed = 0,
    this.membersSkipped = 0,
    this.switchesPulled = 0,
    this.switchesPushed = 0,
    this.membersDeletedOnPk = 0,
    this.switchesDeletedOnPk = 0,
    this.staleLinkMessages = const [],
  });

  int get totalChanges =>
      membersPulled +
      membersPushed +
      switchesPulled +
      switchesPushed +
      membersDeletedOnPk +
      switchesDeletedOnPk;

  Map<String, dynamic> toJson() => {
    'membersPulled': membersPulled,
    'membersPushed': membersPushed,
    'membersSkipped': membersSkipped,
    'switchesPulled': switchesPulled,
    'switchesPushed': switchesPushed,
    'membersDeletedOnPk': membersDeletedOnPk,
    'switchesDeletedOnPk': switchesDeletedOnPk,
    'staleLinkMessages': staleLinkMessages,
  };

  factory PkSyncSummary.fromJson(Map<String, dynamic> json) {
    return PkSyncSummary(
      membersPulled: json['membersPulled'] as int? ?? 0,
      membersPushed: json['membersPushed'] as int? ?? 0,
      membersSkipped: json['membersSkipped'] as int? ?? 0,
      switchesPulled: json['switchesPulled'] as int? ?? 0,
      switchesPushed: json['switchesPushed'] as int? ?? 0,
      membersDeletedOnPk: json['membersDeletedOnPk'] as int? ?? 0,
      switchesDeletedOnPk: json['switchesDeletedOnPk'] as int? ?? 0,
      staleLinkMessages:
          (json['staleLinkMessages'] as List?)?.whereType<String>().toList() ??
          const [],
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
    if (membersDeletedOnPk > 0) {
      parts.add('$membersDeletedOnPk members deleted on PK');
    }
    if (switchesDeletedOnPk > 0) {
      parts.add('$switchesDeletedOnPk switches deleted on PK');
    }
    if (staleLinkMessages.isNotEmpty) {
      parts.add('${staleLinkMessages.length} stale links cleared');
    }
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
