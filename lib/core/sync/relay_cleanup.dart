import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

/// Shared relay-side cleanup helpers used by both setup-failure rollback
/// (`SyncSetupNotifier._complete` catch path) and the explicit reset
/// (`ResetDataNotifier._resetSyncSystem`).
///
/// Both paths need the same two-step "deregister then `deleteSyncGroup` on
/// last-active-device 403" semantics. Centralising them here keeps the
/// last-device fallback in one place — adding it to one path and forgetting
/// the other is exactly the drift this helper exists to prevent.

/// Result of a [cleanupRelayRegistration] call. Production callers log the
/// result but never branch on it for control flow — the existing setup
/// error (or reset progress) is what the user sees.
enum RelayCleanupOutcome {
  /// Self-deregister returned 2xx.
  deregistered,

  /// Deregister was rejected with the relay's "last active device" 403 and
  /// `deleteSyncGroup` succeeded.
  groupDeleted,

  /// Deregister was rejected with the relay's "last active device" 403 and
  /// the `deleteSyncGroup` fallback also failed.
  fallbackFailed,

  /// Deregister failed with something other than the sole-device 403.
  /// (No fallback is attempted — `deleteSyncGroup` is destructive and must
  /// not run when the failure mode is auth/revocation/network.)
  failed,
}

/// Detect the relay's "last active device" 403 the same way the Rust
/// rollback path does (`is_last_active_device_error` in
/// `crates/prism-sync-ffi/src/api.rs`): substring match against the
/// literal emitted by `do_self_deregister` in
/// `prism-sync-relay/src/routes/devices.rs`, AND a 403 marker. The two
/// conditions must BOTH hold — a generic 403 ("auth token rejected")
/// must not trigger the destructive `deleteSyncGroup` fallback, and a
/// 500 carrying the substring in some unrelated context must not either.
@visibleForTesting
bool isLastActiveDeviceError(Object error) {
  final msg = error.toString().toLowerCase();
  final hasNeedle = msg.contains('last active device');
  // Match either an explicit "HTTP 403"/"403:" prefix from the FFI's
  // structured error format, or a bare "403" token surrounded by
  // non-digits so we don't trip on substrings like "1403" inside an
  // unrelated id. The FFI emits both `HTTP 403: ...` (auth bucket) and
  // `Forbidden { ... }` shapes, so cover both.
  final has403 =
      msg.contains('http 403') ||
      msg.contains('403:') ||
      msg.contains('status: 403') ||
      msg.contains('forbidden');
  return hasNeedle && has403;
}

/// Try `deregisterDevice`; if the relay rejects with the sole-device 403,
/// fall back to `deleteSyncGroup`. Mirrors the policy in
/// `_resetSyncSystem` (`reset_data_provider.dart:461-503`).
///
/// `log` is invoked with single-line breadcrumbs so callers can surface them
/// via `ErrorReportingService` (info for reset, warning for setup-failure
/// rollback). The returned [RelayCleanupOutcome] is intended for diagnostics
/// — neither caller branches on it.
///
/// `fallbackOnAnyDeregisterFailure` controls when the destructive
/// `deleteSyncGroup` step runs after a `deregister` failure:
///
/// - `false` (default, used by setup-failure rollback): only attempt
///   `deleteSyncGroup` when the deregister failure matches the relay's
///   sole-device 403. A transient network blip during setup must NOT
///   nuke the entire sync group.
/// - `true` (used by full reset): attempt `deleteSyncGroup` after ANY
///   deregister failure (network 5xx, auth, last-active, anything). The
///   user is wiping the device and wants the relay-side group gone too;
///   leaving it behind on a transient deregister failure is the worse
///   outcome there.
Future<RelayCleanupOutcome> cleanupRelayRegistration({
  required ffi.PrismSyncHandle handle,
  required String syncId,
  required String deviceId,
  required String sessionToken,
  required Future<void> Function({
    required ffi.PrismSyncHandle handle,
    required String syncId,
    required String deviceId,
    required String sessionToken,
  })
  deregister,
  required Future<void> Function({
    required ffi.PrismSyncHandle handle,
    required String syncId,
    required String deviceId,
    required String sessionToken,
  })
  deleteSyncGroup,
  void Function(String message)? log,
  bool fallbackOnAnyDeregisterFailure = false,
}) async {
  try {
    await deregister(
      handle: handle,
      syncId: syncId,
      deviceId: deviceId,
      sessionToken: sessionToken,
    );
    return RelayCleanupOutcome.deregistered;
  } catch (e) {
    if (isLastActiveDeviceError(e)) {
      log?.call('Last device; attempting sync group deletion: $e');
    } else if (fallbackOnAnyDeregisterFailure) {
      log?.call(
        'Relay deregister failed; reset path forcing sync group '
        'deletion: $e',
      );
    } else {
      log?.call('Relay deregister failed (non-fatal): $e');
      return RelayCleanupOutcome.failed;
    }
  }

  try {
    await deleteSyncGroup(
      handle: handle,
      syncId: syncId,
      deviceId: deviceId,
      sessionToken: sessionToken,
    );
    return RelayCleanupOutcome.groupDeleted;
  } catch (e) {
    log?.call('Relay sync group delete failed (non-fatal): $e');
    return RelayCleanupOutcome.fallbackFailed;
  }
}

/// Outcome of a [rollbackFirstDeviceRegistration] call. Mirrors the JSON
/// shape returned by the FFI of the same name in
/// `crates/prism-sync-ffi/src/api.rs` so the Dart caller can log the
/// distinction without re-deriving it from the raw payload.
class FirstDeviceRollbackResult {
  const FirstDeviceRollbackResult({
    required this.outcome,
    this.reason,
    this.stage,
    this.fallbackFrom,
  });

  /// One of: `no_op`, `deregistered`, `group_deleted`, `failed`. Kept as a
  /// raw string rather than an enum so a future `outcome` value added on
  /// the Rust side surfaces directly in logs without an upgrade gate.
  final String outcome;

  /// For `no_op`: which credential was missing. For `failed`: the underlying
  /// error string from the relay/network.
  final String? reason;

  /// For `failed`: which stage failed (`build_relay`, `deregister`,
  /// `delete_sync_group`).
  final String? stage;

  /// For `group_deleted`: the trigger that caused the fallback. Today this
  /// is always `last_active_device`.
  final String? fallbackFrom;

  bool get isNoOp => outcome == 'no_op';
  bool get isDeregistered => outcome == 'deregistered';
  bool get isGroupDeleted => outcome == 'group_deleted';
  bool get isFailed => outcome == 'failed';

  /// Single-line summary suitable for `ErrorReportingService.report`.
  String toLogLine() {
    final buffer = StringBuffer('relay rollback: $outcome');
    if (stage != null) buffer.write(' stage=$stage');
    if (fallbackFrom != null) buffer.write(' fallback_from=$fallbackFrom');
    if (reason != null) buffer.write(' reason=$reason');
    return buffer.toString();
  }
}

/// Parse the JSON envelope returned by the Rust FFI
/// `rollback_first_device_registration`. Returns a [FirstDeviceRollbackResult]
/// or `null` if the payload didn't match the expected shape (treat that as a
/// silent no-op: the FFI is contractually supposed to return JSON, and a
/// schema mismatch is itself a non-fatal warning, not a setup-blocking
/// failure).
FirstDeviceRollbackResult? parseFirstDeviceRollbackResult(String raw) {
  Map<String, dynamic> map;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    map = decoded;
  } catch (_) {
    return null;
  }
  final outcome = map['outcome'];
  if (outcome is! String) return null;
  return FirstDeviceRollbackResult(
    outcome: outcome,
    reason: map['reason'] as String?,
    stage: map['stage'] as String?,
    fallbackFrom: map['fallback_from'] as String?,
  );
}

/// Invoke the Rust FFI `rollback_first_device_registration` and parse the
/// result. Wraps every error so the caller can keep its original setup
/// failure as the user-visible message — the rollback is best-effort.
///
/// Returns `null` if the FFI itself threw (network glitch in the FFI layer,
/// handle disposed, etc.). Callers should log the `null` case as a warning
/// but never propagate it.
Future<FirstDeviceRollbackResult?> rollbackFirstDeviceRegistration({
  required ffi.PrismSyncHandle handle,
  Future<String> Function({required ffi.PrismSyncHandle handle})? rollbackFn,
}) async {
  final fn = rollbackFn ?? ffi.rollbackFirstDeviceRegistration;
  try {
    final raw = await fn(handle: handle);
    return parseFirstDeviceRollbackResult(raw);
  } catch (_) {
    return null;
  }
}
