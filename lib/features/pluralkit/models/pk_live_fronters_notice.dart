import 'dart:convert';

import 'package:crypto/crypto.dart';

/// A single PK member currently fronting that Prism cannot map locally yet.
class PkUnmappedFronterRef {
  /// PK short ID from switch member lists.
  final String pkId;

  /// PK UUID when available from `/fronters` member objects or a targeted
  /// member fetch.
  final String? pkUuid;
  final String? name;
  final String? displayName;
  final String? avatarUrl;

  const PkUnmappedFronterRef({
    required this.pkId,
    this.pkUuid,
    this.name,
    this.displayName,
    this.avatarUrl,
  });

  String get label {
    final display = displayName?.trim();
    if (display != null && display.isNotEmpty) return display;
    final base = name?.trim();
    if (base != null && base.isNotEmpty) return base;
    return pkId;
  }

  PkUnmappedFronterRef copyWith({
    String? pkId,
    String? pkUuid,
    String? name,
    String? displayName,
    String? avatarUrl,
  }) {
    return PkUnmappedFronterRef(
      pkId: pkId ?? this.pkId,
      pkUuid: pkUuid ?? this.pkUuid,
      name: name ?? this.name,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }

  Map<String, dynamic> toJson() => {
    'pkId': pkId,
    'pkUuid': pkUuid,
    'name': name,
    'displayName': displayName,
    'avatarUrl': avatarUrl,
  };

  factory PkUnmappedFronterRef.fromJson(Map<String, dynamic> json) {
    return PkUnmappedFronterRef(
      pkId: json['pkId'] as String,
      pkUuid: json['pkUuid'] as String?,
      name: json['name'] as String?,
      displayName: json['displayName'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
    );
  }

  @override
  String toString() => 'PkUnmappedFronterRef(redacted)';
}

class PkUnmappedFrontersNotice {
  final String? systemId;
  final String switchId;
  final DateTime switchTimestamp;

  /// Sorted PK short IDs for the complete current switch, not just the subset
  /// being displayed. This makes the notice identity change if PK's live set
  /// changes while keeping the raw string transient.
  final List<String> sortedPkIds;
  final List<PkUnmappedFronterRef> refs;

  const PkUnmappedFrontersNotice({
    required this.systemId,
    required this.switchId,
    required this.switchTimestamp,
    required this.sortedPkIds,
    required this.refs,
  });

  String get dismissalKey => pkUnmappedFrontersDismissalKey(
    systemId: systemId,
    switchId: switchId,
    switchTimestamp: switchTimestamp,
    sortedPkIds: sortedPkIds,
  );

  Map<String, dynamic> toJson() => {
    'systemId': systemId,
    'switchId': switchId,
    'switchTimestamp': switchTimestamp.toUtc().toIso8601String(),
    'sortedPkIds': sortedPkIds,
    'refs': refs.map((ref) => ref.toJson()).toList(),
  };

  factory PkUnmappedFrontersNotice.fromJson(Map<String, dynamic> json) {
    return PkUnmappedFrontersNotice(
      systemId: json['systemId'] as String?,
      switchId: json['switchId'] as String,
      switchTimestamp: DateTime.parse(json['switchTimestamp'] as String),
      sortedPkIds:
          (json['sortedPkIds'] as List?)?.whereType<String>().toList() ??
          const [],
      refs:
          (json['refs'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(PkUnmappedFronterRef.fromJson)
              .toList() ??
          const [],
    );
  }

  @override
  String toString() => 'PkUnmappedFrontersNotice(redacted)';
}

String pkUnmappedFrontersDismissalKey({
  required String? systemId,
  required String switchId,
  required DateTime switchTimestamp,
  required List<String> sortedPkIds,
}) {
  final ids = List<String>.from(sortedPkIds)..sort();
  final canonical = jsonEncode([
    systemId ?? '',
    switchId,
    switchTimestamp.toUtc().toIso8601String(),
    ...ids,
  ]);
  return sha256.convert(utf8.encode(canonical)).toString();
}
