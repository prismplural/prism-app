import 'dart:convert';

import 'package:prism_plurality/features/pluralkit/models/pk_live_fronters_notice.dart';

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
// Sync mode
// ---------------------------------------------------------------------------

/// Overall PluralKit sync mode.
enum PkSyncMode {
  /// Regular PluralKit sync behavior.
  fullSync,

  /// Only live front changes are synced; member pushes are disabled.
  liveFrontsOnly;

  String toJson() => name;

  static PkSyncMode fromJson(Object? value) {
    if (value is! String) return PkSyncMode.fullSync;
    return PkSyncMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => PkSyncMode.fullSync,
    );
  }
}

/// PluralKit handling while Prism records a local sleep session.
enum PkSleepSyncBehavior {
  /// Do not change PluralKit's current fronters while Prism records sleep.
  leaveUnchanged,

  /// Clear PluralKit's current fronters when Prism records sleep.
  clearFronters;

  String toJson() => name;

  static PkSleepSyncBehavior fromJson(Object? value) {
    if (value is! String) return PkSleepSyncBehavior.clearFronters;
    return PkSleepSyncBehavior.values.firstWhere(
      (e) => e.name == value,
      orElse: () => PkSleepSyncBehavior.clearFronters,
    );
  }
}

// ---------------------------------------------------------------------------
// Delete-risk preview
// ---------------------------------------------------------------------------

/// Read-only preview of destructive PluralKit push work.
class PkDeleteRiskPreview {
  final int membersToDelete;
  final int switchesToDelete;
  final int groupMembershipsToRemove;
  final int memberProxyTagsToRemove;
  final int membersSkipped;
  final int switchesSkipped;
  final int groupMembershipsSkipped;

  const PkDeleteRiskPreview({
    this.membersToDelete = 0,
    this.switchesToDelete = 0,
    this.groupMembershipsToRemove = 0,
    this.memberProxyTagsToRemove = 0,
    this.membersSkipped = 0,
    this.switchesSkipped = 0,
    this.groupMembershipsSkipped = 0,
  });

  int get totalToRemove =>
      membersToDelete +
      switchesToDelete +
      groupMembershipsToRemove +
      memberProxyTagsToRemove;

  int get totalSkipped =>
      membersSkipped + switchesSkipped + groupMembershipsSkipped;

  bool get hasRemovals => totalToRemove > 0;

  bool get isSignificant {
    if (membersToDelete > 0) return true;
    if (memberProxyTagsToRemove > 0) return true;
    if (switchesToDelete >= 10) return true;
    if (groupMembershipsToRemove >= 10) return true;
    return switchesToDelete + groupMembershipsToRemove >= 10;
  }
}

/// Read-only preview of pending group-membership removals.
class PkGroupMembershipRemovalPreview {
  final int toRemove;
  final int skipped;

  const PkGroupMembershipRemovalPreview({this.toRemove = 0, this.skipped = 0});
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

  /// `proxyTags` defaults to [PkSyncDirection.bidirectional] like other
  /// editable PK-backed fields; delete-risk preview guards destructive clears.
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

  /// Actionable unmapped current-fronter state observed during a live-front
  /// pull. This is intentionally separate from [staleLinkMessages], which is
  /// reserved for PK-side deletions of previously linked local rows.
  final PkUnmappedFrontersNotice? liveUnmappedFronters;
  final int _liveUnmappedFrontersCount;
  final String? _liveUnmappedFrontersDismissalKey;

  /// Whether a pull-enabled live-fronter check observed PK's current state.
  ///
  /// When true and [observedLiveFrontersDismissalKey] is null, PK currently has
  /// no active switch, so stale notices can be cleared.
  final bool observedLiveFronters;
  final String? observedLiveFrontersDismissalKey;

  const PkSyncSummary({
    this.membersPulled = 0,
    this.membersPushed = 0,
    this.membersSkipped = 0,
    this.switchesPulled = 0,
    this.switchesPushed = 0,
    this.membersDeletedOnPk = 0,
    this.switchesDeletedOnPk = 0,
    this.staleLinkMessages = const [],
    this.liveUnmappedFronters,
    int liveUnmappedFrontersCount = 0,
    String? liveUnmappedFrontersDismissalKey,
    this.observedLiveFronters = false,
    this.observedLiveFrontersDismissalKey,
  }) : assert(liveUnmappedFrontersCount >= 0),
       _liveUnmappedFrontersCount = liveUnmappedFrontersCount,
       _liveUnmappedFrontersDismissalKey = liveUnmappedFrontersDismissalKey;

  int get totalChanges =>
      membersPulled +
      membersPushed +
      switchesPulled +
      switchesPushed +
      membersDeletedOnPk +
      switchesDeletedOnPk;

  int get liveUnmappedFrontersCount =>
      liveUnmappedFronters?.refs.length ?? _liveUnmappedFrontersCount;

  String? get liveUnmappedFrontersDismissalKey =>
      liveUnmappedFronters?.dismissalKey ?? _liveUnmappedFrontersDismissalKey;

  bool get hasLiveUnmappedFronters => liveUnmappedFrontersCount > 0;

  bool get hasSummaryDetails =>
      totalChanges > 0 ||
      staleLinkMessages.isNotEmpty ||
      hasLiveUnmappedFronters;

  Map<String, dynamic> toJson() {
    final unmappedCount = liveUnmappedFrontersCount;
    final unmappedDismissalKey = liveUnmappedFrontersDismissalKey;

    return {
      'membersPulled': membersPulled,
      'membersPushed': membersPushed,
      'membersSkipped': membersSkipped,
      'switchesPulled': switchesPulled,
      'switchesPushed': switchesPushed,
      'membersDeletedOnPk': membersDeletedOnPk,
      'switchesDeletedOnPk': switchesDeletedOnPk,
      'staleLinkMessages': staleLinkMessages,
      if (unmappedCount > 0) 'liveUnmappedFrontersCount': unmappedCount,
      'liveUnmappedFrontersDismissalKey': ?unmappedDismissalKey,
      'observedLiveFronters': observedLiveFronters,
      'observedLiveFrontersDismissalKey': observedLiveFrontersDismissalKey,
    };
  }

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
      liveUnmappedFrontersCount: _nonNegativeInt(
        json['liveUnmappedFrontersCount'],
      ),
      liveUnmappedFrontersDismissalKey:
          json['liveUnmappedFrontersDismissalKey'] as String?,
      observedLiveFronters: json['observedLiveFronters'] as bool? ?? false,
      observedLiveFrontersDismissalKey:
          json['observedLiveFrontersDismissalKey'] as String?,
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
    final unmappedCount = liveUnmappedFrontersCount;
    if (unmappedCount > 0) {
      parts.add('$unmappedCount unmapped current fronters');
    }
    return parts.isEmpty ? 'No changes' : parts.join(', ');
  }
}

int _nonNegativeInt(Object? value) {
  if (value is int && value > 0) return value;
  return 0;
}

// ---------------------------------------------------------------------------
// Helpers — parse/serialize the fieldSyncConfig column
// ---------------------------------------------------------------------------

const String _globalSyncConfigKey = '__global__';
const String _syncModeConfigKey = '__mode__';
const String _sleepSyncBehaviorConfigKey = '__sleep_sync_behavior__';

bool _isReservedFieldSyncConfigKey(String key) => key.startsWith('__');

Map<String, dynamic> _decodeFieldSyncConfig(String? json) {
  if (json == null || json.isEmpty) return {};
  try {
    final decoded = jsonDecode(json);
    if (decoded is Map<String, dynamic>) return decoded;
  } catch (_) {}
  return {};
}

Map<String, dynamic> _reservedFieldSyncConfigEntries(String? json) {
  final decoded = _decodeFieldSyncConfig(json);
  return Map<String, dynamic>.fromEntries(
    decoded.entries.where((entry) => _isReservedFieldSyncConfigKey(entry.key)),
  );
}

/// Parse the `fieldSyncConfig` JSON column value into a per-member config map.
Map<String, PkFieldSyncConfig> parseFieldSyncConfig(String? json) {
  final map = _decodeFieldSyncConfig(json);
  final result = <String, PkFieldSyncConfig>{};
  for (final entry in map.entries) {
    if (_isReservedFieldSyncConfigKey(entry.key)) continue;
    final value = entry.value;
    if (value is! Map<String, dynamic>) continue;
    try {
      result[entry.key] = PkFieldSyncConfig.fromJson(value);
    } catch (_) {}
  }
  return result;
}

/// Serialize a per-member config map to JSON for the `fieldSyncConfig` column.
String serializeFieldSyncConfig(
  Map<String, PkFieldSyncConfig> config, {
  String? existingJson,
  PkSyncDirection? globalDirection,
  PkSyncMode? mode,
  PkSleepSyncBehavior? sleepSyncBehavior,
}) {
  final json = _reservedFieldSyncConfigEntries(existingJson);
  json.addEntries(
    config.entries
        .where((entry) => !_isReservedFieldSyncConfigKey(entry.key))
        .map((entry) => MapEntry(entry.key, entry.value.toJson())),
  );
  if (globalDirection != null) {
    json[_globalSyncConfigKey] = PkFieldSyncConfig(
      name: globalDirection,
      displayName: globalDirection,
      pronouns: globalDirection,
      description: globalDirection,
      color: globalDirection,
      birthday: globalDirection,
      // Proxy tags follow the global direction; delete-risk preview guards
      // destructive clears.
      proxyTags: globalDirection,
    ).toJson();
  }
  if (mode != null) {
    json[_syncModeConfigKey] = mode.toJson();
  }
  if (sleepSyncBehavior != null) {
    json[_sleepSyncBehaviorConfigKey] = sleepSyncBehavior.toJson();
  }
  return jsonEncode(json);
}

/// Parse the persisted global sync direction from `fieldSyncConfig`.
PkSyncDirection parseGlobalSyncDirection(
  String? json, {
  PkSyncDirection fallback = PkSyncDirection.pullOnly,
}) {
  final globalConfig = _decodeFieldSyncConfig(json)[_globalSyncConfigKey];
  if (globalConfig is! Map<String, dynamic>) return fallback;
  try {
    return PkFieldSyncConfig.fromJson(globalConfig).name;
  } catch (_) {
    return fallback;
  }
}

/// Parse the persisted PluralKit sync mode from `fieldSyncConfig`.
PkSyncMode parsePkSyncMode(String? json) {
  return PkSyncMode.fromJson(_decodeFieldSyncConfig(json)[_syncModeConfigKey]);
}

/// Parse the persisted sleep sync behavior from `fieldSyncConfig`.
PkSleepSyncBehavior parsePkSleepSyncBehavior(String? json) {
  return PkSleepSyncBehavior.fromJson(
    _decodeFieldSyncConfig(json)[_sleepSyncBehaviorConfigKey],
  );
}

/// Serialize a global direction update while preserving member configs + mode.
String serializeFieldSyncConfigWithGlobalDirection(
  String? existingJson,
  PkSyncDirection direction,
) {
  return serializeFieldSyncConfig(
    parseFieldSyncConfig(existingJson),
    existingJson: existingJson,
    globalDirection: direction,
  );
}

/// Serialize a sync mode update while preserving member configs + direction.
String serializeFieldSyncConfigWithMode(String? existingJson, PkSyncMode mode) {
  return serializeFieldSyncConfig(
    parseFieldSyncConfig(existingJson),
    existingJson: existingJson,
    mode: mode,
  );
}

/// Serialize a sleep sync behavior update while preserving other config.
String serializeFieldSyncConfigWithSleepSyncBehavior(
  String? existingJson,
  PkSleepSyncBehavior behavior,
) {
  return serializeFieldSyncConfig(
    parseFieldSyncConfig(existingJson),
    existingJson: existingJson,
    sleepSyncBehavior: behavior,
  );
}
