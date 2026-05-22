import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kSyncDisconnectMarkerKey = 'sync_disconnect_marker_v1';
const kDeviceInstallIdKey = 'prism.device_install_id_v1';

enum SyncDisconnectReason {
  userDisconnect('user_disconnect'),
  syncTroubleshooting('sync_troubleshooting'),
  replaceByPairing('replace_by_pairing'),
  frontingMigration('fronting_migration'),
  setupRollback('setup_rollback'),
  fullReset('full_reset'),
  unknown('unknown');

  const SyncDisconnectReason(this.wireName);
  final String wireName;

  static SyncDisconnectReason fromWireName(String? value) {
    for (final reason in values) {
      if (reason.wireName == value) return reason;
    }
    return SyncDisconnectReason.unknown;
  }
}

enum RelayCleanupMarkerOutcome {
  deregistered('deregistered'),
  groupDeleted('group_deleted'),
  fallbackFailed('fallback_failed'),
  failed('failed'),
  skippedMissingCredentials('skipped_missing_credentials'),
  skippedNoHandle('skipped_no_handle'),
  notAttempted('not_attempted');

  const RelayCleanupMarkerOutcome(this.wireName);
  final String wireName;

  static RelayCleanupMarkerOutcome fromWireName(String? value) {
    for (final outcome in values) {
      if (outcome.wireName == value) return outcome;
    }
    return RelayCleanupMarkerOutcome.notAttempted;
  }
}

enum LocalAppDataOutcome {
  preserved('preserved'),
  wiped('wiped'),
  unknown('unknown');

  const LocalAppDataOutcome(this.wireName);
  final String wireName;

  static LocalAppDataOutcome fromWireName(String? value) {
    for (final outcome in values) {
      if (outcome.wireName == value) return outcome;
    }
    return LocalAppDataOutcome.unknown;
  }
}

enum SyncSetupConstraint {
  localOnly('local_only'),
  joinOnlyReplaceLocalData('join_only_replace_local_data'),
  createNewGroupWithLocalData('create_new_group_with_local_data'),
  freshSetupChoice('fresh_setup_choice');

  const SyncSetupConstraint(this.wireName);
  final String wireName;

  static SyncSetupConstraint fromWireName(String? value) {
    for (final constraint in values) {
      if (constraint.wireName == value) return constraint;
    }
    return SyncSetupConstraint.localOnly;
  }
}

enum SyncSetupMode {
  chooseForFreshInstall,
  localOnlyAfterDisconnect,
  joinOnlyReplaceLocalData,
  createNewGroupWithLocalData,
}

enum SyncRelayCleanupPolicy { conservative, aggressive }

class SyncDisconnectMarker {
  const SyncDisconnectMarker({
    required this.markerId,
    required this.deviceInstallId,
    required this.reason,
    required this.startedAt,
    required this.relayCleanupOutcome,
    required this.localAppDataOutcome,
    required this.nextSetupConstraint,
    this.previousSyncId,
    this.previousDeviceId,
    this.relayUrl,
    this.completedAt,
  });

  final String markerId;
  final String deviceInstallId;
  final SyncDisconnectReason reason;
  final String? previousSyncId;
  final String? previousDeviceId;
  final String? relayUrl;
  final DateTime startedAt;
  final DateTime? completedAt;
  final RelayCleanupMarkerOutcome relayCleanupOutcome;
  final LocalAppDataOutcome localAppDataOutcome;
  final SyncSetupConstraint nextSetupConstraint;

  SyncSetupMode get setupMode => setupModeForConstraint(nextSetupConstraint);

  bool get hasPreviousSyncId =>
      previousSyncId != null && previousSyncId!.trim().isNotEmpty;

  SyncDisconnectMarker copyWith({
    RelayCleanupMarkerOutcome? relayCleanupOutcome,
    LocalAppDataOutcome? localAppDataOutcome,
    SyncSetupConstraint? nextSetupConstraint,
    DateTime? completedAt,
  }) {
    return SyncDisconnectMarker(
      markerId: markerId,
      deviceInstallId: deviceInstallId,
      reason: reason,
      previousSyncId: previousSyncId,
      previousDeviceId: previousDeviceId,
      relayUrl: relayUrl,
      startedAt: startedAt,
      completedAt: completedAt ?? this.completedAt,
      relayCleanupOutcome: relayCleanupOutcome ?? this.relayCleanupOutcome,
      localAppDataOutcome: localAppDataOutcome ?? this.localAppDataOutcome,
      nextSetupConstraint: nextSetupConstraint ?? this.nextSetupConstraint,
    );
  }

  Map<String, Object?> toJson() => {
    'schema_version': 1,
    'marker_id': markerId,
    'device_install_id': deviceInstallId,
    'reason': reason.wireName,
    'previous_sync_id': previousSyncId,
    'previous_device_id': previousDeviceId,
    'relay_url': relayUrl,
    'started_at': startedAt.toUtc().toIso8601String(),
    'completed_at': completedAt?.toUtc().toIso8601String(),
    'relay_cleanup_outcome': relayCleanupOutcome.wireName,
    'local_app_data_outcome': localAppDataOutcome.wireName,
    'next_setup_constraint': nextSetupConstraint.wireName,
  };

  static SyncDisconnectMarker? fromJson(Map<String, dynamic> json) {
    final version = json['schema_version'];
    if (version is! int || version != 1) return null;
    final markerId = json['marker_id'] as String?;
    final deviceInstallId = json['device_install_id'] as String?;
    final startedAtRaw = json['started_at'] as String?;
    final startedAt = startedAtRaw == null
        ? null
        : DateTime.tryParse(startedAtRaw);
    if (markerId == null || deviceInstallId == null || startedAt == null) {
      return null;
    }
    final completedAtRaw = json['completed_at'] as String?;
    return SyncDisconnectMarker(
      markerId: markerId,
      deviceInstallId: deviceInstallId,
      reason: SyncDisconnectReason.fromWireName(json['reason'] as String?),
      previousSyncId: json['previous_sync_id'] as String?,
      previousDeviceId: json['previous_device_id'] as String?,
      relayUrl: json['relay_url'] as String?,
      startedAt: startedAt,
      completedAt: completedAtRaw == null
          ? null
          : DateTime.tryParse(completedAtRaw),
      relayCleanupOutcome: RelayCleanupMarkerOutcome.fromWireName(
        json['relay_cleanup_outcome'] as String?,
      ),
      localAppDataOutcome: LocalAppDataOutcome.fromWireName(
        json['local_app_data_outcome'] as String?,
      ),
      nextSetupConstraint: SyncSetupConstraint.fromWireName(
        json['next_setup_constraint'] as String?,
      ),
    );
  }
}

SyncSetupMode setupModeForConstraint(SyncSetupConstraint constraint) {
  return switch (constraint) {
    SyncSetupConstraint.localOnly => SyncSetupMode.localOnlyAfterDisconnect,
    SyncSetupConstraint.joinOnlyReplaceLocalData =>
      SyncSetupMode.joinOnlyReplaceLocalData,
    SyncSetupConstraint.createNewGroupWithLocalData =>
      SyncSetupMode.createNewGroupWithLocalData,
    SyncSetupConstraint.freshSetupChoice => SyncSetupMode.chooseForFreshInstall,
  };
}

class SyncDisconnectMarkerStore {
  const SyncDisconnectMarkerStore();

  Future<String> deviceInstallId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(kDeviceInstallIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final created = _randomId();
    await prefs.setString(kDeviceInstallIdKey, created);
    return created;
  }

  Future<SyncDisconnectMarker?> readRaw() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kSyncDisconnectMarkerKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return SyncDisconnectMarker.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<SyncDisconnectMarker?> readForCurrentInstall() async {
    final marker = await readRaw();
    if (marker == null) return null;
    final currentInstallId = await deviceInstallId();
    if (marker.deviceInstallId != currentInstallId) return null;
    return marker;
  }

  Future<SyncDisconnectMarker> writeInitial({
    required SyncDisconnectReason reason,
    required LocalAppDataOutcome localAppDataOutcome,
    required SyncSetupConstraint nextSetupConstraint,
    String? previousSyncId,
    String? previousDeviceId,
    String? relayUrl,
  }) async {
    final marker = SyncDisconnectMarker(
      markerId: _randomId(),
      deviceInstallId: await deviceInstallId(),
      reason: reason,
      previousSyncId: _emptyToNull(previousSyncId),
      previousDeviceId: _emptyToNull(previousDeviceId),
      relayUrl: _emptyToNull(relayUrl),
      startedAt: DateTime.now().toUtc(),
      completedAt: null,
      relayCleanupOutcome: RelayCleanupMarkerOutcome.notAttempted,
      localAppDataOutcome: localAppDataOutcome,
      nextSetupConstraint: nextSetupConstraint,
    );
    await write(marker);
    return marker;
  }

  Future<void> write(SyncDisconnectMarker marker) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      kSyncDisconnectMarkerKey,
      jsonEncode(marker.toJson()),
    );
  }

  Future<void> delete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kSyncDisconnectMarkerKey);
  }
}

final syncDisconnectMarkerStoreProvider = Provider<SyncDisconnectMarkerStore>((
  ref,
) {
  return const SyncDisconnectMarkerStore();
});

final syncDisconnectMarkerProvider = FutureProvider<SyncDisconnectMarker?>((
  ref,
) {
  return ref.watch(syncDisconnectMarkerStoreProvider).readForCurrentInstall();
});

String? _emptyToNull(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  return value;
}

String _randomId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  String hex(int byte) => byte.toRadixString(16).padLeft(2, '0');
  return bytes.map(hex).join();
}
