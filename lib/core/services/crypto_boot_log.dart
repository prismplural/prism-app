/// Persistent crypto-boot diagnostic log.
///
/// On every cold start, after the sync handle has been created and
/// `_autoConfigureIfReady` has classified the device's health, we capture
/// a snapshot of which `prism_sync.*` keychain entries exist. The snapshot
/// is appended to a small JSON file in the app's documents directory,
/// capped at [_maxEntries] (oldest dropped first).
///
/// The goal is to diagnose intermittent re-prompts on platforms whose
/// secure storage occasionally drops entries (Android Keystore with
/// `resetOnError: true` is the typical culprit). Scrolling back through
/// the log lets a user — or whoever they're handing a screenshot to —
/// see exactly which boot was the one where a key disappeared.
///
/// Values are NEVER recorded; only presence + decoded byte length.

library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:prism_plurality/core/database/database_encryption.dart'
    show kDatabaseKeyStorageKey, kSyncDatabaseKeyStorageKey;
import 'package:prism_plurality/core/services/build_info.dart';
import 'package:prism_plurality/core/services/runtime_dek_store.dart';
import 'package:prism_plurality/core/services/secure_storage.dart';

/// One row per `prism_sync.*` key at snapshot time.
@immutable
class CryptoBootKeyEntry {
  const CryptoBootKeyEntry({
    required this.bareKey,
    required this.present,
    this.decodedLength,
  });

  final String bareKey;
  final bool present;

  /// Length in bytes after base64-decoding the stored value. `null` when
  /// the key is missing OR when the value didn't decode as base64 (the
  /// keychain holds raw strings for some legacy slots).
  final int? decodedLength;

  Map<String, dynamic> toJson() => {
        'k': bareKey,
        'p': present,
        if (decodedLength != null) 'l': decodedLength,
      };

  factory CryptoBootKeyEntry.fromJson(Map<String, dynamic> json) {
    return CryptoBootKeyEntry(
      bareKey: json['k'] as String,
      present: json['p'] as bool? ?? false,
      decodedLength: json['l'] as int?,
    );
  }
}

/// One full snapshot taken at app boot (or on user-driven capture).
@immutable
class CryptoBootSnapshot {
  const CryptoBootSnapshot({
    required this.timestamp,
    required this.appVersion,
    required this.platform,
    required this.syncHealth,
    required this.handlePresent,
    required this.engineUnlocked,
    required this.keys,
    required this.trigger,
    this.unwrapFailure,
    this.platformDiagnostics,
  });

  final DateTime timestamp;
  final String appVersion;
  final String platform;
  final String syncHealth;
  final bool handlePresent;
  final bool? engineUnlocked;
  final List<CryptoBootKeyEntry> keys;

  /// What caused this snapshot. `'boot'` for the auto-capture during
  /// `createHandle`; `'manual'` when the user tapped the capture button
  /// in the debug screen.
  final String trigger;

  /// Most recent runtime-DEK unwrap failure observed during the cache
  /// restore that immediately preceded this snapshot. Null when the
  /// unwrap succeeded (or wasn't attempted because the cache was empty).
  final RuntimeDekUnwrapFailure? unwrapFailure;

  /// Platform-side diagnostic blob (Keystore alias presence, security
  /// level, device-lock state, OEM/build info). Shape is platform-defined
  /// — see `MainActivity.kt#collectRuntimeDekDiagnostics` and the iOS
  /// twin in `AppDelegate.swift`.
  final Map<String, dynamic>? platformDiagnostics;

  Map<String, dynamic> toJson() => {
        'ts': timestamp.toIso8601String(),
        'v': appVersion,
        'p': platform,
        'h': syncHealth,
        'hp': handlePresent,
        if (engineUnlocked != null) 'u': engineUnlocked,
        't': trigger,
        'k': keys.map((e) => e.toJson()).toList(),
        if (unwrapFailure != null) 'uf': unwrapFailure!.toJson(),
        if (platformDiagnostics != null) 'pd': platformDiagnostics,
      };

  factory CryptoBootSnapshot.fromJson(Map<String, dynamic> json) {
    return CryptoBootSnapshot(
      timestamp: DateTime.parse(json['ts'] as String),
      appVersion: json['v'] as String? ?? 'unknown',
      platform: json['p'] as String? ?? 'unknown',
      syncHealth: json['h'] as String? ?? 'unknown',
      handlePresent: json['hp'] as bool? ?? false,
      engineUnlocked: json['u'] as bool?,
      trigger: json['t'] as String? ?? 'boot',
      keys: (json['k'] as List<dynamic>? ?? const [])
          .map((e) => CryptoBootKeyEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      unwrapFailure: json['uf'] is Map<String, dynamic>
          ? RuntimeDekUnwrapFailure.fromJson(
              json['uf'] as Map<String, dynamic>,
            )
          : null,
      platformDiagnostics: json['pd'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['pd'] as Map<String, dynamic>)
          : null,
    );
  }

  bool get hasKey => keys.isNotEmpty;

  bool keyPresent(String bareKey) =>
      keys.any((e) => e.bareKey == bareKey && e.present);

  int? keyLength(String bareKey) {
    for (final e in keys) {
      if (e.bareKey == bareKey) return e.decodedLength;
    }
    return null;
  }
}

/// Service: capture, persist, read.
class CryptoBootLog {
  CryptoBootLog._();
  static final CryptoBootLog instance = CryptoBootLog._();

  static const int _maxEntries = 50;
  static const String _fileName = 'crypto_boot_log.json';

  // Serialize append/read operations against the same on-disk file.
  Future<void>? _inflight;

  /// Take a fresh snapshot. Pure: doesn't touch the file.
  ///
  /// [engineUnlocked] is the result of `ffi.isUnlocked(handle)` if the
  /// caller has it on hand. Pass `null` if the handle is null or the
  /// FFI call wasn't attempted — the snapshot records that as `unknown`.
  Future<CryptoBootSnapshot> capture({
    required String syncHealth,
    required bool handlePresent,
    required bool? engineUnlocked,
    required String trigger,
  }) async {
    // Use the slot-probe variant so a cipher failure on top-level readAll
    // still surfaces per-slot diagnostic data for the known DB-key slots
    // (the ones we care about most for crash triage). When readAll succeeds,
    // the probe is skipped — entries is identical to the unwrapped readAll.
    // See `docs/0.9.2-secure-storage-remediation.md` §2 / §10.
    final readAll = await safeSecureReadAllWithSlotProbe(
      const <String>[
        kDatabaseKeyStorageKey,
        '${kDatabaseKeyStorageKey}_staging',
        kSyncDatabaseKeyStorageKey,
        '${kSyncDatabaseKeyStorageKey}_staging',
      ],
    );
    final all = readAll.entries;
    final entries = <CryptoBootKeyEntry>[];
    for (final fullKey in all.keys) {
      if (!fullKey.startsWith('prism_sync.')) continue;
      final bare = fullKey.substring('prism_sync.'.length);
      entries.add(
        CryptoBootKeyEntry(
          bareKey: bare,
          present: true,
          decodedLength: _safeDecodedLength(all[fullKey]),
        ),
      );
    }
    entries.sort((a, b) => a.bareKey.compareTo(b.bareKey));
    if (!readAll.ok) {
      debugPrint(
        '[CryptoBootLog] readAll failed (failure=${readAll.failure}, '
        'code=${readAll.code}); recovered ${entries.length} entries via slot probe',
      );
    }

    // Best-effort platform Keystore/Keychain introspection. Read-only —
    // never mutates platform state. Returns null on unsupported platforms
    // or older builds without the method handler.
    Map<String, dynamic>? platformDiagnostics;
    try {
      platformDiagnostics =
          await const DeviceBoundRuntimeDekStore().getDiagnostics();
    } catch (e) {
      debugPrint('[CryptoBootLog] platform diagnostics failed: $e');
    }

    return CryptoBootSnapshot(
      timestamp: DateTime.now().toUtc(),
      appVersion: BuildInfo.appVersion,
      platform: defaultTargetPlatform.name,
      syncHealth: syncHealth,
      handlePresent: handlePresent,
      engineUnlocked: engineUnlocked,
      trigger: trigger,
      keys: entries,
      unwrapFailure: RuntimeDekUnwrapFailureRegistry.last,
      platformDiagnostics: platformDiagnostics,
    );
  }

  /// Append a snapshot to the persistent log, capping at [_maxEntries].
  ///
  /// Failures are swallowed — the log is diagnostic; it must never break
  /// the boot path. Errors are logged via `debugPrint` for triage.
  Future<void> append(CryptoBootSnapshot snapshot) async {
    final pending = _inflight ?? Future<void>.value();
    final next = pending.then((_) => _appendUnsafe(snapshot));
    _inflight = next;
    try {
      await next;
    } finally {
      if (identical(_inflight, next)) _inflight = null;
    }
  }

  Future<void> _appendUnsafe(CryptoBootSnapshot snapshot) async {
    try {
      final file = await _file();
      final existing = await _readUnsafe(file);
      final updated = [...existing, snapshot];
      final overflow = updated.length - _maxEntries;
      final trimmed =
          overflow > 0 ? updated.sublist(overflow) : updated;
      final json = trimmed.map((s) => s.toJson()).toList();
      await file.writeAsString(jsonEncode(json), flush: true);
    } catch (e) {
      debugPrint('[CryptoBootLog] append failed: $e');
    }
  }

  /// Read all persisted snapshots, oldest first.
  Future<List<CryptoBootSnapshot>> readAll() async {
    final pending = _inflight;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
    }
    try {
      final file = await _file();
      return await _readUnsafe(file);
    } catch (e) {
      debugPrint('[CryptoBootLog] readAll failed: $e');
      return const [];
    }
  }

  Future<List<CryptoBootSnapshot>> _readUnsafe(File file) async {
    if (!await file.exists()) return const [];
    final raw = await file.readAsString();
    if (raw.isEmpty) return const [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => CryptoBootSnapshot.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Wipe the persistent log.
  Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('[CryptoBootLog] clear failed: $e');
    }
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  int? _safeDecodedLength(String? base64Value) {
    if (base64Value == null || base64Value.isEmpty) return null;
    try {
      return base64Decode(base64Value).length;
    } catch (_) {
      return null;
    }
  }
}
