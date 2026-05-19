/// Per-boot secure-storage diagnostic — §10 of
/// docs/0.9.2-secure-storage-remediation.md.
///
/// Lives in `lib/core/services/` so the app DB probe (§4), the sync DB
/// probe (§5), and the recovery UI (§7) can all reach it without circular
/// imports. The diagnostic is purely descriptive — it carries no secrets,
/// no key material, just the boot's classification of every slot it
/// touched and the platform metadata that helps diagnose why a slot
/// failed.
///
/// The diagnostic is built up incrementally by the probes and finalized
/// in `main.dart` before being passed into the recovery UI via
/// [bootSecureStorageDiagnosticProvider]. The "Save diagnostic report"
/// button on the keychainUnreadable recovery screen serializes the
/// merged diagnostic to a pretty-printed JSON file via `share_plus`.
///
/// **Privacy default**: this code never auto-uploads. Diagnostic data
/// only leaves the device when the user explicitly taps "Save diagnostic
/// report" and shares the resulting file themselves.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/services/keychain_degraded_state.dart';

/// Per-slot outcome from a probe attempt.
///
/// - [ok]            slot was read AND the value successfully opened (or
///                   was usable for) the resource being verified.
/// - [cipher]        classifier categorised the failure as `cipher` (the
///                   secure-storage backend reported it cannot decrypt
///                   the slot — typically because the wrapping key was
///                   rotated).
/// - [transient]     classifier categorised the failure as `transient`
///                   (lock-state race, secure-element flake).
/// - [unknown]       classifier had nothing to say. Probably a
///                   PlatformException with an unrecognised shape.
/// - [missing]       slot returned null with no failure — the keychain
///                   doesn't have the entry.
/// - [invalidHex]    slot returned a value but it failed hex validation
///                   (wrong length, non-hex characters).
/// - [threw]         the read or the open attempt threw an unclassified
///                   exception. The message is captured separately in
///                   [SecureStorageDiagnostic.slotOutcomes] via the
///                   serialized `threw: <message>` form.
enum SlotOutcome {
  ok,
  cipher,
  transient,
  unknown,
  missing,
  invalidHex,
  threw,
}

/// Canonical slot identifiers. The probe code populates these as
/// strings in [SecureStorageDiagnostic.slotOutcomes]; consumers can
/// look up the canonical names here.
class DiagnosticSlotIds {
  DiagnosticSlotIds._();

  // App DB probe (§4).
  static const String appDbPrimary = 'app_db_primary';
  static const String appDbSync = 'app_db_sync';
  static const String appDbStaging = 'app_db_staging';
  static const String appDbSyncStaging = 'app_db_sync_staging';
  static const String appDbFresh = 'app_db_fresh';
  static const String appDbPrimaryStaging = 'app_db_primary_staging';

  // Sync DB probe (§5).
  static const String syncDbPrimary = 'sync_db_primary';
  static const String syncDbSyncStaging = 'sync_db_sync_staging';
  static const String syncDbAppPrimaryCandidate =
      'sync_db_app_primary_candidate';
  static const String syncDbAppStagingCandidate =
      'sync_db_app_staging_candidate';
  static const String syncDbFresh = 'sync_db_fresh';
  static const String syncDbStagingPromote = 'sync_db_staging_promote';
}

/// Stringification of [DbStartupState] (referenced by probe callers).
/// Defined here so this file does not depend on the database layer.
enum DbStartupStateName { ready, unrecoverable }

/// Outcome of the keychain-repair write-back attempt that runs after
/// the app DB probe in `main.dart`. See
/// `database_provider.dart#attemptKeychainRepairWriteback`.
enum KeychainRepairWritebackResult {
  /// Write-back succeeded. The repair-pending flag was cleared.
  ok,

  /// Write-back was attempted but the underlying secure-storage write
  /// failed with a cipher / transient / unknown classification.
  cipherFailure,

  /// Write-back was skipped entirely (e.g. the repair-pending flag was
  /// not set, or the app DB probe didn't recover a key).
  noop,
}

/// One captured per-boot secure-storage diagnostic.
///
/// Field naming for the JSON wire form is **snake_case** so the file is
/// readable when users open it in a text editor.
@immutable
class SecureStorageDiagnostic {
  SecureStorageDiagnostic({
    this.recoveredVia,
    DateTime? capturedAt,
    Map<String, String>? slotOutcomes,
    this.appDbState,
    this.syncDbState,
    this.keychainRepairPendingBeforeBoot,
    this.keychainRepairWritebackAttemptedThisBoot,
    this.keychainRepairWritebackResult,
    this.keychainDegradedStateSnapshot,
    this.runtimeDekDeviceState,
    this.appBuild,
  })  : capturedAt = capturedAt ?? DateTime.now().toUtc(),
        slotOutcomes = Map<String, String>.unmodifiable(
          slotOutcomes ?? const <String, String>{},
        );

  /// Which slot ultimately produced the verified key, or null if the
  /// probe ran but did not recover. Values match the plan's enumeration:
  ///   `'fresh' | 'primary' | 'sync' | 'sync_staging' | 'app_primary' |
  ///    'app_staging'`.
  final String? recoveredVia;

  /// Per-slot outcome string. Keys are the canonical names from
  /// [DiagnosticSlotIds]; values are either the [SlotOutcome] name
  /// (e.g. `'ok'`, `'cipher'`, `'missing'`) or a `'threw: <message>'`
  /// form for unclassified throws.
  final Map<String, String> slotOutcomes;

  /// Stringified terminal state of the app DB probe (or null when the
  /// probe was not run — e.g. when building a sync-only diagnostic).
  final DbStartupStateName? appDbState;

  /// Stringified terminal state of the sync DB probe (or null when the
  /// probe was not run).
  final DbStartupStateName? syncDbState;

  /// Whether `keychain_repair_pending` was already set when boot
  /// started, i.e. whether a previous boot left the flag on. Null when
  /// the value wasn't captured.
  final bool? keychainRepairPendingBeforeBoot;

  /// Whether `attemptKeychainRepairWriteback` ran during this boot.
  /// Null when the value wasn't captured.
  final bool? keychainRepairWritebackAttemptedThisBoot;

  /// The terminal outcome of the keychain-repair write-back attempt
  /// this boot. Null when no attempt was made.
  final KeychainRepairWritebackResult? keychainRepairWritebackResult;

  /// Snapshot of [KeychainDegradedState] at capture time. May be null
  /// when the service isn't reachable (e.g. tests).
  final KeychainDegradedState? keychainDegradedStateSnapshot;

  /// Platform-side runtime DEK device-state map (Keystore alias
  /// presence, security level, KeyguardManager / UserManager flags).
  /// Shape is platform-defined — see
  /// `MainActivity.kt#collectRuntimeDekDeviceState` and the iOS twin.
  /// Null on unsupported platforms or when the platform handler is
  /// missing.
  final Map<String, dynamic>? runtimeDekDeviceState;

  /// App build metadata. Keys (best-effort, all string values):
  ///   * `flavor`           — `'production'` for now; reserved for
  ///                          future flavor wiring.
  ///   * `mode`             — `'debug' | 'profile' | 'release'`.
  ///   * `app_version`      — `pubspec.yaml` version (e.g. `0.9.2`).
  ///   * `app_build_number` — pubspec build number when present.
  ///   * `platform_version` — `Platform.operatingSystemVersion`.
  final Map<String, String>? appBuild;

  /// When the diagnostic was captured. UTC ISO-8601.
  final DateTime capturedAt;

  /// Copy with new values. Used by the probes to incrementally enrich
  /// the diagnostic as the boot path progresses.
  SecureStorageDiagnostic copyWith({
    String? recoveredVia,
    DateTime? capturedAt,
    Map<String, String>? slotOutcomes,
    DbStartupStateName? appDbState,
    DbStartupStateName? syncDbState,
    bool? keychainRepairPendingBeforeBoot,
    bool? keychainRepairWritebackAttemptedThisBoot,
    KeychainRepairWritebackResult? keychainRepairWritebackResult,
    KeychainDegradedState? keychainDegradedStateSnapshot,
    Map<String, dynamic>? runtimeDekDeviceState,
    Map<String, String>? appBuild,
  }) {
    return SecureStorageDiagnostic(
      recoveredVia: recoveredVia ?? this.recoveredVia,
      capturedAt: capturedAt ?? this.capturedAt,
      slotOutcomes: slotOutcomes ?? this.slotOutcomes,
      appDbState: appDbState ?? this.appDbState,
      syncDbState: syncDbState ?? this.syncDbState,
      keychainRepairPendingBeforeBoot: keychainRepairPendingBeforeBoot ??
          this.keychainRepairPendingBeforeBoot,
      keychainRepairWritebackAttemptedThisBoot:
          keychainRepairWritebackAttemptedThisBoot ??
              this.keychainRepairWritebackAttemptedThisBoot,
      keychainRepairWritebackResult: keychainRepairWritebackResult ??
          this.keychainRepairWritebackResult,
      keychainDegradedStateSnapshot:
          keychainDegradedStateSnapshot ?? this.keychainDegradedStateSnapshot,
      runtimeDekDeviceState:
          runtimeDekDeviceState ?? this.runtimeDekDeviceState,
      appBuild: appBuild ?? this.appBuild,
    );
  }

  /// Merge two diagnostics — typically the app DB probe diagnostic with
  /// the sync DB probe diagnostic. Slot outcomes are unioned; non-null
  /// fields from [other] take precedence; [other]'s [capturedAt] wins
  /// (we want the most recent capture point as the timestamp).
  SecureStorageDiagnostic mergeWith(SecureStorageDiagnostic other) {
    final merged = <String, String>{}
      ..addAll(slotOutcomes)
      ..addAll(other.slotOutcomes);
    return SecureStorageDiagnostic(
      // recoveredVia is per-probe; preserve `other`'s value when it
      // recovered, otherwise keep ours.
      recoveredVia: other.recoveredVia ?? recoveredVia,
      capturedAt: other.capturedAt,
      slotOutcomes: merged,
      appDbState: other.appDbState ?? appDbState,
      syncDbState: other.syncDbState ?? syncDbState,
      keychainRepairPendingBeforeBoot: other.keychainRepairPendingBeforeBoot ??
          keychainRepairPendingBeforeBoot,
      keychainRepairWritebackAttemptedThisBoot:
          other.keychainRepairWritebackAttemptedThisBoot ??
              keychainRepairWritebackAttemptedThisBoot,
      keychainRepairWritebackResult: other.keychainRepairWritebackResult ??
          keychainRepairWritebackResult,
      keychainDegradedStateSnapshot: other.keychainDegradedStateSnapshot ??
          keychainDegradedStateSnapshot,
      runtimeDekDeviceState:
          other.runtimeDekDeviceState ?? runtimeDekDeviceState,
      appBuild: other.appBuild ?? appBuild,
    );
  }

  /// Serialize to the JSON-friendly wire form. All keys are snake_case.
  /// Null fields are serialized explicitly as `null` so consumers can
  /// distinguish "field absent" from "field present but unknown".
  Map<String, dynamic> toJson() => <String, dynamic>{
        'recovered_via': recoveredVia,
        'slot_outcomes': Map<String, String>.from(slotOutcomes),
        'app_db_state': appDbState?.name,
        'sync_db_state': syncDbState?.name,
        'keychain_repair_pending_before_boot':
            keychainRepairPendingBeforeBoot,
        'keychain_repair_writeback_attempted_this_boot':
            keychainRepairWritebackAttemptedThisBoot,
        'keychain_repair_writeback_result':
            keychainRepairWritebackResult?.name,
        'keychain_degraded_state_snapshot':
            keychainDegradedStateSnapshot?.toJson(),
        'runtime_dek_device_state': runtimeDekDeviceState,
        'app_build': appBuild,
        'captured_at': capturedAt.toIso8601String(),
      };
}

/// Encode a [SlotOutcome] for use as the value in
/// [SecureStorageDiagnostic.slotOutcomes]. For [SlotOutcome.threw] the
/// caller should use [slotOutcomeThrewString] instead so the exception
/// message is preserved.
String slotOutcomeName(SlotOutcome outcome) {
  switch (outcome) {
    case SlotOutcome.ok:
      return 'ok';
    case SlotOutcome.cipher:
      return 'cipher';
    case SlotOutcome.transient:
      return 'transient';
    case SlotOutcome.unknown:
      return 'unknown';
    case SlotOutcome.missing:
      return 'missing';
    case SlotOutcome.invalidHex:
      return 'invalid_hex';
    case SlotOutcome.threw:
      return 'threw';
  }
}

/// Format the `threw: <message>` slot outcome string. The message is
/// truncated to keep diagnostic JSON readable.
String slotOutcomeThrewString(Object error) {
  final raw = error.toString();
  final trimmed = raw.length > 240 ? '${raw.substring(0, 240)}…' : raw;
  return 'threw: $trimmed';
}

/// Top-level Riverpod provider holding the diagnostic captured during
/// boot. Overridden in `main.dart`'s `ProviderScope.overrides` with the
/// real value. Default null — the recovery UI handles a null gracefully
/// (serializes to `null` in the JSON file).
final bootSecureStorageDiagnosticProvider =
    Provider<SecureStorageDiagnostic?>((ref) => null);
