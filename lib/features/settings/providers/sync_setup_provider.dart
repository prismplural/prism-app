import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/core/constants/app_constants.dart';
import 'package:prism_plurality/core/crypto/bip39_english_wordlist.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/security/secret_bytes.dart';
import 'package:prism_plurality/core/services/build_info.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/core/services/secure_storage.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter_bootstrap.dart';
import 'package:prism_plurality/core/sync/first_device_admission_service.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/relay_cleanup.dart';
import 'package:prism_plurality/core/sync/sync_disconnect_marker.dart';
import 'package:prism_plurality/core/sync/sync_runtime_state.dart';
import 'package:prism_plurality/shared/widgets/prism_mnemonic_field.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

enum SyncSetupStep { intro, enterPhrase }

enum SyncSetupProgress {
  creatingGroup,
  configuringEngine,
  cachingKeys,
  bootstrappingData,
  measuringSnapshot,
}

const _sentinel = Object();
const _syncDatabaseRepairRequiredMessage =
    'Sync database needs repair before setup can continue. Open Sync '
    'troubleshooting, reset sync, then pair again.';

/// Shown for a permanently-unreadable keychain (cipher/entitlement failure),
/// where retrying re-runs the same failing `readAll` forever — so it points at
/// the reset that clears it instead of inviting a futile retry.
const _secureStorageUnreadableMessage =
    "This device's secure storage can't be read, so sync setup can't "
    'continue — retrying will keep failing. Go to Settings → Reset Data to '
    'clear it, then enter your recovery phrase again.';

/// Keychain enumeration failure during the pre-setup snapshot. Carries the
/// classified [failure] so the guard can split transient (retry) from permanent
/// (reset), plus the raw platform [code]/[message] — the only diagnostic we can
/// get off a release device, where the in-app keychain tools are debug-gated.
class _KeychainSnapshotException implements Exception {
  const _KeychainSnapshotException(this.failure, {this.code, this.message});
  final SecureStorageFailure? failure;
  final String? code;
  final String? message;
}

class SyncSetupState {
  final SyncSetupStep step;
  final String relayUrl;
  final String? registrationToken;
  final bool isProcessing;
  final SyncSetupProgress? currentProgress;
  final String? error;

  const SyncSetupState({
    this.step = SyncSetupStep.intro,
    this.relayUrl = AppConstants.defaultRelayUrl,
    this.registrationToken,
    this.isProcessing = false,
    this.currentProgress,
    this.error,
  });

  SyncSetupState copyWith({
    SyncSetupStep? step,
    String? relayUrl,
    Object? registrationToken = _sentinel,
    bool? isProcessing,
    Object? currentProgress = _sentinel,
    Object? error = _sentinel,
  }) => SyncSetupState(
    step: step ?? this.step,
    relayUrl: relayUrl ?? this.relayUrl,
    registrationToken: registrationToken == _sentinel
        ? this.registrationToken
        : registrationToken as String?,
    isProcessing: isProcessing ?? this.isProcessing,
    currentProgress: currentProgress == _sentinel
        ? this.currentProgress
        : currentProgress as SyncSetupProgress?,
    error: error == _sentinel ? this.error : error as String?,
  );
}

class SyncSetupNotifier extends Notifier<SyncSetupState> {
  /// Read the current sync handle from [prismSyncHandleProvider] at every
  /// use site rather than caching it in a field. The cached field used to
  /// outlive the underlying Rust handle if the provider was invalidated
  /// mid-setup (Bug B7); reading on demand surfaces a clean error instead.
  ffi.PrismSyncHandle? get _handle => ref.read(prismSyncHandleProvider).value;

  /// Indirection so tests can drive the catch path without binding the
  /// real FFI rollback. Production code uses the default null and falls
  /// through to `ffi.rollbackFirstDeviceRegistration` inside
  /// `rollbackFirstDeviceRegistration`.
  @visibleForTesting
  Future<String> Function({required ffi.PrismSyncHandle handle})?
  rollbackFirstDeviceRegistrationFnForTest;

  @override
  SyncSetupState build() {
    const bakedToken = BuildInfo.betaRegistrationToken;
    return SyncSetupState(
      registrationToken: bakedToken.isEmpty ? null : bakedToken,
    );
  }

  void setRelayUrl(String url) {
    state = state.copyWith(relayUrl: url);
  }

  void setRegistrationToken(String? token) {
    state = state.copyWith(registrationToken: token);
  }

  /// Validate the relay URL, create the sync handle, and proceed to the
  /// enter-phrase step.
  Future<void> proceedToEnterPhrase() async {
    // Validate relay URL before proceeding. Match the joiner flow
    // (SyncDeviceStep): require https:// unless the host is a loopback
    // address, in which case plain http:// is allowed for local dev.
    final uri = Uri.tryParse(state.relayUrl);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      state = state.copyWith(
        error: 'Invalid relay URL. Must be a valid http or https URL.',
      );
      return;
    }
    if (uri.scheme == 'http' && !_isLoopbackHost(uri.host)) {
      state = state.copyWith(error: 'Relay URL must use https://.');
      return;
    }

    // Create the handle now so the phrase-verification step can use it.
    // The handle is read back from `prismSyncHandleProvider` at each use
    // site via the `_handle` getter, so we don't cache the return value.
    if (!_syncDatabaseReadyForSetup()) {
      state = state.copyWith(error: _syncDatabaseRepairRequiredMessage);
      return;
    }
    final handleNotifier = ref.read(prismSyncHandleProvider.notifier);
    try {
      await handleNotifier.createHandle(relayUrl: state.relayUrl);
    } on SyncDbUnrecoverableException {
      state = state.copyWith(error: _syncDatabaseRepairRequiredMessage);
      return;
    }

    state = state.copyWith(step: SyncSetupStep.enterPhrase, error: null);
  }

  bool _syncDatabaseReadyForSetup() {
    try {
      return ref.read(syncDatabaseStartupProvider).state ==
          DbStartupState.ready;
    } catch (_) {
      return true;
    }
  }

  void goBack() {
    switch (state.step) {
      case SyncSetupStep.intro:
        break;
      case SyncSetupStep.enterPhrase:
        state = state.copyWith(step: SyncSetupStep.intro, error: null);
    }
  }

  /// Validate and submit the recovery phrase together with the user's PIN.
  ///
  /// Normalizes the mnemonic, checks that all 12 words are valid BIP39 words,
  /// then calls [ffi.unlock] to verify the phrase matches this account's key
  /// hierarchy. On success, proceeds to complete sync group creation.
  Future<bool> submitPhrase(String mnemonic, String pin) async {
    final normalized = PrismMnemonicField.normalize(mnemonic);
    final words = normalized.split(' ');

    // Validate 12 words, all in BIP39 wordlist.
    if (words.length != 12 || !words.every(bip39EnglishWordlistSet.contains)) {
      state = state.copyWith(error: 'Check that all 12 words are correct.');
      return false;
    }

    final handle = _handle;
    if (handle == null) {
      state = state.copyWith(
        error: 'Setup handle no longer available, please retry.',
      );
      return false;
    }

    state = state.copyWith(isProcessing: true, error: null);

    // Derive secret key bytes from mnemonic and verify against this account.
    Uint8List? mnemonicBytes;
    Uint8List? pinBytes;
    Uint8List? secretKeyBytes;
    try {
      mnemonicBytes = secretUtf8Bytes(normalized);
      secretKeyBytes = await ffi.mnemonicToBytes(mnemonic: mnemonicBytes);
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        error: 'Check that all 12 words are correct.',
      );
      return false;
    } finally {
      zeroBytesBestEffort(mnemonicBytes);
      mnemonicBytes = null;
    }

    try {
      // If wrapped_dek exists, verify the phrase unlocks the existing key
      // hierarchy before creating a new sync group. After a sync reset,
      // wrapped_dek is gone — skip verification and go straight to
      // createSyncGroup.
      // Probe wrapped_dek to decide whether this is a fresh setup or a
      // verify-then-create flow. Cipher failure surfaces as null (the blob
      // is effectively gone for this device) — fall through into the
      // createSyncGroup path without attempting unlock.
      final wrappedDek = (await safeSecureRead('prism_sync.wrapped_dek')).value;
      if (wrappedDek != null) {
        pinBytes = secretUtf8Bytes(pin);
        await ffi.unlock(
          handle: handle,
          password: pinBytes,
          secretKey: secretKeyBytes,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        error:
            'Incorrect PIN or recovery phrase. Check each word and try again.',
      );
      return false;
    } finally {
      zeroBytesBestEffort(pinBytes);
      zeroBytesBestEffort(secretKeyBytes);
      pinBytes = null;
      secretKeyBytes = null;
    }

    return _complete(pin, normalized);
  }

  /// Complete sync group creation. Called from [submitPhrase] after the phrase
  /// has been verified.
  Future<bool> _complete(String pin, String mnemonic) async {
    final handle = _handle;
    if (handle == null) {
      state = state.copyWith(
        error: 'Setup handle no longer available, please retry.',
      );
      return false;
    }

    // Snapshot the entire `prism_sync.*` namespace so a mid-setup failure
    // can roll back any partial writes without leaving orphaned keys
    // behind. The earlier static allow-list silently missed keys that
    // `createSyncGroup` + `drainRustStore` wrote (e.g. `sync_id`,
    // `relay_url`, `session_token`, `epoch`); a restart in that mixed
    // state would make the relay reject every authenticated request.
    //
    // The DB-encryption slots in `kProtectedFromReset` are deliberately
    // EXCLUDED from both the snapshot and the rollback wipe:
    // `cacheRuntimeKeys` may rotate them forward late in `_complete`, and
    // restoring the pre-setup value over a freshly-rekeyed DB would
    // orphan the file on disk. Reuses the same set as
    // `_resetSyncSystem` (Phase 1B) — both paths agree on which slots
    // are sacred.
    //
    // A keychain read failure here must surface a recoverable error
    // instead of escaping past the setup screen's error handler — without
    // the snapshot we cannot safely proceed (there is no way to roll
    // back partial writes), but the sheet must come out of "processing"
    // so the user can retry.
    final snapshot = await _snapshotPrismSyncKeychainWithSetupGuard();
    if (snapshot == null) return false;

    state = state.copyWith(
      isProcessing: true,
      currentProgress: SyncSetupProgress.creatingGroup,
      error: null,
    );

    try {
      final admissionService = FirstDeviceAdmissionService();
      await admissionService.preparePendingRegistration(
        handle: handle,
        relayUrl: state.relayUrl,
        registrationToken: state.registrationToken,
      );

      // createSyncGroup handles key hierarchy creation internally. Pass
      // byte buffers so the FFI input copies can be scrubbed immediately
      // after the call returns.
      Uint8List? pinBytes;
      Uint8List? mnemonicBytes;
      String inviteJson;
      try {
        pinBytes = secretUtf8Bytes(pin);
        mnemonicBytes = secretUtf8Bytes(mnemonic);
        inviteJson = await ffi.createSyncGroup(
          handle: handle,
          password: pinBytes,
          relayUrl: state.relayUrl,
          mnemonic: mnemonicBytes,
        );
      } finally {
        zeroBytesBestEffort(pinBytes);
        zeroBytesBestEffort(mnemonicBytes);
      }

      // Parse the invite to extract sync_id and relay_url, then persist both
      // after the Rust secure store has been drained. Publishing these
      // keychain gate keys before device_id/device_secret are durable can make
      // a killed setup look configured but unable to pair another device.
      final invite = jsonDecode(inviteJson) as Map<String, dynamic>;
      final syncId = invite['sync_id'] as String;
      final persistedRelayUrl =
          (invite['relay_url'] as String?) ?? state.relayUrl;

      state = state.copyWith(
        currentProgress: SyncSetupProgress.configuringEngine,
      );
      await ffi.configureEngine(handle: handle);
      await ffi.setAutoSync(
        handle: handle,
        enabled: true,
        debounceMs: BigInt.from(300),
        retryDelayMs: BigInt.from(30000),
        maxRetries: 3,
      );

      // Drain Rust SecureStore back to platform keychain. Use the
      // snapshot-aware variant: a thrown delete/write mid-mirror would
      // otherwise leave the keychain straddling pre- and post-setup
      // state. The drain-internal rollback restores `snapshot` exactly
      // even if the post-drain catch logic crashes for an unrelated
      // reason; the catch's own `_restoreKeychainSnapshot` below remains
      // as defense in depth.
      state = state.copyWith(currentProgress: SyncSetupProgress.cachingKeys);
      await drainRustStoreWithSnapshotRollback(
        handle,
        rollbackSnapshot: snapshot,
      );
      // `drainRustStore` is a delete-then-write mirror of Rust's secure store.
      // Keep the user-facing identity slots authoritative even if an older or
      // partially upgraded Rust layer omits them from the drained snapshot.
      await _persistSyncIdentity(relayUrl: persistedRelayUrl, syncId: syncId);

      // Cache a device-bound wrapped DEK so launches bypass Argon2id.
      await cacheRuntimeKeys(handle, ref.read(databaseProvider));

      // Bootstrap: seed the Rust engine's field_versions from existing Drift
      // state so the snapshot export has everything it needs. No relay
      // traffic here — bulk data only moves across the network at pair time.
      state = state.copyWith(
        currentProgress: SyncSetupProgress.bootstrappingData,
      );
      await _bootstrapExistingData(handle);
      await _finishSuccessfulSetup(handle);

      state = state.copyWith(isProcessing: false, currentProgress: null);
      return true;
    } catch (e) {
      final structuredError = PrismSyncStructuredError.tryParse(e);
      // Restore the platform keychain snapshot BEFORE the relay rollback.
      // If the process dies between the relay-rollback success and the
      // keychain restore, the platform keychain would otherwise still
      // hold the post-`drainRustStore` credentials for a relay
      // registration that was just deleted — next launch would see ghost
      // credentials and fail to sync. The rollback FFI reads its inputs
      // from the Rust `MemorySecureStore` (see
      // `rollback_first_device_registration` in `crates/prism-sync-ffi/src/api.rs`),
      // not the platform keychain, so swapping the order does not break
      // its ability to find the credentials it needs.
      await _restoreKeychainSnapshot(snapshot);
      // Best-effort: tell the relay to forget the registration
      // `create_sync_group` just made. The new FFI bypasses the local
      // registry seeding step that the existing `deregisterDevice`
      // requires (and which has not run yet at this failure window). The
      // rollback never throws — failures are reported via the result
      // envelope and logged as a warning, not surfaced to the user.
      await _runRelayRollbackForFailedSetup(e);
      state = state.copyWith(
        isProcessing: false,
        currentProgress: null,
        error: 'Setup failed: ${_friendlySetupError(structuredError, e)}',
      );
      return false;
    }
  }

  /// Invoke the FFI rollback that deregisters the just-created relay-side
  /// device record. Wraps every exception so the original setup error
  /// remains the user-facing failure mode. See `relay_cleanup.dart` and the
  /// Rust FFI doc on `rollback_first_device_registration` for the
  /// outcome shape.
  Future<void> _runRelayRollbackForFailedSetup(
    Object originalSetupError,
  ) async {
    final handle = _handle;
    if (handle == null) {
      // Without a live handle there is nothing to call. The Rust
      // `MemorySecureStore` is gone with the handle, so the relay-side row
      // cannot be deregistered locally. Block 5 covers the joiner-side
      // analog of this residual.
      return;
    }
    try {
      final result = await rollbackFirstDeviceRegistration(
        handle: handle,
        rollbackFn: rollbackFirstDeviceRegistrationFnForTest,
      );
      if (result == null) {
        ErrorReportingService.instance.report(
          'Setup-failure relay rollback: FFI threw or returned non-JSON',
          severity: ErrorSeverity.warning,
        );
        return;
      }
      // Report the warning for any outcome other than the silent no-op so
      // diagnostics show whether the relay-side registration was cleaned
      // up, deleted as a sole-device group, or left behind.
      if (!result.isNoOp) {
        ErrorReportingService.instance.report(
          'Setup failure (${originalSetupError.runtimeType}); '
          '${result.toLogLine()}',
          severity: ErrorSeverity.warning,
        );
      }
    } catch (e, st) {
      // Defensive: parsing is guarded inside `rollbackFirstDeviceRegistration`,
      // but anything thrown out here would otherwise replace the original
      // setup error in the catch block.
      ErrorReportingService.instance.report(
        'Setup-failure relay rollback threw: $e',
        severity: ErrorSeverity.warning,
        stackTrace: st,
      );
    }
  }

  /// Snapshot every `prism_sync.*` keychain entry except the protected
  /// DB-encryption slots in [kProtectedFromReset].
  ///
  /// The exclusion is critical: `cacheRuntimeKeys` rotates the DB key slots
  /// forward late in [_complete], so if we snapshotted the pre-rotation
  /// values and a later step failed, the rollback would write the OLD key
  /// back over a freshly-rekeyed DB, leaving the file unreadable.
  @visibleForTesting
  Future<Map<String, String>> snapshotPrismSyncKeychainForTest() =>
      _snapshotPrismSyncKeychain();

  /// Test seam for `_complete`'s guarded snapshot step. The full `_complete`
  /// path is gated behind FFI, but the snapshot guard is load-bearing: if
  /// keychain enumeration fails while setup is processing, the UI must stop
  /// spinning and show a retryable error.
  @visibleForTesting
  Future<Map<String, String>?> snapshotPrismSyncKeychainWithSetupGuardForTest({
    SyncSetupProgress? initialProgress,
  }) {
    state = state.copyWith(
      isProcessing: true,
      currentProgress: initialProgress,
      error: null,
    );
    return _snapshotPrismSyncKeychainWithSetupGuard();
  }

  /// Test-only entry point for the rollback path. The production code only
  /// reaches `_restoreKeychainSnapshot` from inside `_complete`'s catch
  /// block, which is hard to drive from pure-Dart tests because it sits
  /// behind several FFI calls. Tests use this seam together with
  /// [snapshotPrismSyncKeychainForTest] to exercise the rollback contract
  /// directly.
  @visibleForTesting
  Future<void> restoreKeychainSnapshotForTest(Map<String, String> snapshot) =>
      _restoreKeychainSnapshot(snapshot);

  @visibleForTesting
  Future<void> persistSyncIdentityForTest({
    required String relayUrl,
    required String syncId,
  }) => _persistSyncIdentity(relayUrl: relayUrl, syncId: syncId);

  /// Test seam for the catch-path rollback. Production code only reaches
  /// `_runRelayRollbackForFailedSetup` from inside `_complete`'s catch
  /// block, behind a chain of FFI calls (`createSyncGroup`,
  /// `configureEngine`, `drainRustStore`, `cacheRuntimeKeys`) that can't
  /// run in pure-Dart tests. Tests inject a fake `rollbackFn` via
  /// [rollbackFirstDeviceRegistrationFnForTest] and call this seam to
  /// assert the contract directly.
  @visibleForTesting
  Future<void> runRelayRollbackForFailedSetupForTest(
    Object originalSetupError,
  ) => _runRelayRollbackForFailedSetup(originalSetupError);

  @visibleForTesting
  Future<void> finishSuccessfulSetupForTest({
    required ffi.PrismSyncHandle handle,
    Future<void> Function()? postHealthyCatchUp,
  }) => _finishSuccessfulSetup(handle, postHealthyCatchUp: postHealthyCatchUp);

  Future<void> _finishSuccessfulSetup(
    ffi.PrismSyncHandle handle, {
    Future<void> Function()? postHealthyCatchUp,
  }) async {
    ref.read(syncHealthProvider.notifier).setState(SyncHealthState.healthy);
    // Credentials are now persisted, so subsequent live edits enqueue
    // durably into the outbox instead of taking the never-paired no-op path.
    syncCredentialsPersisted.value = true;
    await (postHealthyCatchUp ??
        () => runPostHealthySyncCatchUp(
          handle: handle,
          db: ref.read(databaseProvider),
          failureLabel: 'Post-setup catch-up sync failed',
        ))();
    try {
      await ref.read(syncDisconnectMarkerStoreProvider).delete();
      ref.invalidate(syncDisconnectMarkerProvider);
    } catch (e, st) {
      ErrorReportingService.instance.report(
        'Sync disconnect marker cleanup failed after setup: $e',
        severity: ErrorSeverity.warning,
        stackTrace: st,
      );
    }
  }

  Future<void> _persistSyncIdentity({
    required String relayUrl,
    required String syncId,
  }) async {
    // Base64-encode before storing — seedRustStore expects base64.
    //
    // Writes go through [safeSecureWrite]; classified failures throw a
    // non-PlatformException so the caller's rollback path still runs.
    await _checkedSecureWrite(
      kSyncRelayUrlKey,
      base64Encode(utf8.encode(relayUrl)),
    );
    await _checkedSecureWrite(kSyncIdKey, base64Encode(utf8.encode(syncId)));
    ref.invalidate(relayUrlProvider);
    ref.invalidate(syncIdProvider);
    ref.invalidate(syncDeviceIdProvider);
    ref.invalidate(syncDeviceSecretPresentProvider);
    ref.invalidate(syncWrappedDekPresentProvider);
  }

  Future<void> _checkedSecureWrite(String key, String value) async {
    final result = await safeSecureWrite(key, value);
    if (!result.ok) {
      throw StateError(
        'secure storage write failed for $key '
        '(failure=${result.failure?.name ?? 'unknown'}, code=${result.code}, '
        'message=${result.message})',
      );
    }
  }

  Future<Map<String, String>> _snapshotPrismSyncKeychain() async {
    // Enumerate directly (not via readPrefixed) so the classified failure
    // survives to the guard — a thrown StateError would erase transient-ness.
    final result = await safeSecureReadAll();
    if (!result.ok) {
      throw _KeychainSnapshotException(
        result.failure,
        code: result.code,
        message: result.message,
      );
    }
    return Map.fromEntries(
      result.entries.entries.where(
        (e) =>
            e.key.startsWith('prism_sync.') &&
            !kProtectedFromReset.contains(e.key),
      ),
    );
  }

  Future<Map<String, String>?>
  _snapshotPrismSyncKeychainWithSetupGuard() async {
    try {
      return await _snapshotPrismSyncKeychain();
    } on _KeychainSnapshotException catch (e) {
      // Release-build observability: keychain diagnostics are debug-gated, so
      // capture the raw platform fields here and (via the token below) on the
      // error itself, where a screenshot can carry the OSStatus to support.
      ErrorReportingService.instance.report(
        'Sync setup keychain snapshot failed: '
        'failure=${e.failure?.name ?? 'unknown'} code=${e.code} '
        'message=${e.message}',
      );
      // Transient (e.g. device not yet unlocked) can succeed on retry; a
      // cipher/unknown failure is permanent, so route to the reset instead.
      final retryable = e.failure == SecureStorageFailure.transient;
      state = state.copyWith(
        isProcessing: false,
        currentProgress: null,
        error: retryable
            ? 'Could not read secure storage. Please retry.'
            : _withDiagnosticToken(_secureStorageUnreadableMessage, e),
      );
      return null;
    } catch (e, st) {
      // Defensive: unexpected throw keeps the retry copy, still captured.
      ErrorReportingService.instance.report(
        'Sync setup keychain snapshot failed (unexpected): $e',
        stackTrace: st,
      );
      state = state.copyWith(
        isProcessing: false,
        currentProgress: null,
        error: 'Could not read secure storage. Please retry.',
      );
      return null;
    }
  }

  /// Append a copyable diagnostic token so a release user's screenshot carries
  /// the OSStatus. iOS may put it at either end of [message], so a long message
  /// keeps both ends.
  String _withDiagnosticToken(
    String baseMessage,
    _KeychainSnapshotException e,
  ) {
    final parts = <String>[e.failure?.name ?? 'error'];
    if (e.code != null && e.code!.isNotEmpty) parts.add(e.code!);
    final msg = e.message;
    if (msg != null && msg.isNotEmpty) {
      parts.add(
        msg.length > 100
            ? '${msg.substring(0, 60)}…${msg.substring(msg.length - 40)}'
            : msg,
      );
    }
    return '$baseMessage\n\nDiagnostic code: ${parts.join(' · ')} — '
        'include this if you contact support.';
  }

  /// Roll back the `prism_sync.*` namespace to a previously captured
  /// [snapshot] from [_snapshotPrismSyncKeychain].
  ///
  /// 1. Delete every current `prism_sync.*` key that is not in the snapshot
  ///    AND not in [kProtectedFromReset]. This catches keys that
  ///    `createSyncGroup` / `drainRustStore` wrote during setup.
  /// 2. Restore each snapshotted key to its captured value. Any key absent
  ///    from the snapshot has already been deleted in step 1.
  /// 3. Never touch [kProtectedFromReset] — see the doc on the snapshot
  ///    helper for why.
  Future<void> _restoreKeychainSnapshot(Map<String, String> snapshot) async {
    try {
      final current = await readPrefixed('prism_sync.');
      for (final key in current.keys) {
        if (kProtectedFromReset.contains(key)) continue;
        if (snapshot.containsKey(key)) continue;
        // Best-effort delete — failures from the classified wrapper are
        // returned as a result; the rollback path swallows them.
        await safeSecureDelete(key);
      }
    } catch (_) {
      // Best-effort scan — don't propagate errors.
    }

    for (final entry in snapshot.entries) {
      if (kProtectedFromReset.contains(entry.key)) continue;
      // Best-effort restore — classified wrapper returns a result we
      // intentionally ignore. Mid-rollback failure leaves the keychain
      // straddling pre/post-setup state; the snapshot caller treats that
      // as still-recoverable on the next attempt.
      await safeSecureWrite(entry.key, entry.value);
    }
  }

  /// Map structured sync errors to user-friendly messages for the setup flow.
  String _friendlySetupError(
    PrismSyncStructuredError? structured,
    Object rawError,
  ) => friendlySyncSetupError(structured, rawError);

  /// Seed the Rust sync engine with every existing Drift row so first-device
  /// setup finishes with a fully-populated `field_versions` table ready for
  /// snapshot export. This is offline-only: no `syncNow`, no `record_create`,
  /// no relay traffic. Bulk data only moves across the network at pair time.
  Future<void> _bootstrapExistingData(ffi.PrismSyncHandle handle) async {
    final db = ref.read(databaseProvider);

    // First-device setup seeds the entire Drift store directly into
    // field_versions, so any rows enqueued into the durable outbox before
    // pairing are redundant. Clear them so they don't replay as duplicate
    // (same-value LWW) ops after setup completes.
    await db.syncOutboxDao.clearAll();

    final adapter = ref.read(driftSyncAdapterProvider).adapter;
    final fetchers = bootstrapFetchersFor(adapter, db);

    final records = await buildBootstrapRecords(fetchers);

    if (kDebugMode) {
      debugPrint(
        '[BOOTSTRAP] Seeding ${records.length} records across '
        '${fetchers.length} tables',
      );
    }

    // Flip to the measuring-snapshot stage before calling FFI: the Rust side
    // upserts field_versions, computes the HLC watermark, then exports the
    // zstd snapshot and checks its size.
    state = state.copyWith(
      currentProgress: SyncSetupProgress.measuringSnapshot,
    );

    // Errors propagate to the outer try/catch in `_complete`, which restores
    // the keychain snapshot. Structured errors (`snapshot_too_large`,
    // `bootstrap_not_allowed`) are translated to friendly copy by
    // `_friendlySetupError`.
    final resultJson = await ffi.bootstrapExistingState(
      handle: handle,
      recordsJson: jsonEncode(records),
    );

    if (kDebugMode) {
      try {
        final result = jsonDecode(resultJson) as Map<String, dynamic>;
        debugPrint(
          '[BOOTSTRAP] seeded ${result['entity_count']} entities, '
          'snapshot size ${result['snapshot_bytes']} bytes',
        );
      } catch (_) {
        debugPrint('[BOOTSTRAP] seeded (unparsed result): $resultJson');
      }
    }
  }
}

/// Top-level version of [SyncSetupNotifier._friendlySetupError] so tests can
/// exercise the error-translation matrix without spinning up a full Riverpod
/// + FFI graph.
@visibleForTesting
String friendlySyncSetupError(
  PrismSyncStructuredError? structured,
  Object rawError,
) {
  if (structured != null) {
    final msg = structured.message.toLowerCase();

    // Bootstrap-specific structured errors surfaced by the new offline
    // bootstrap primitive. These come from `bootstrap_existing_state` in
    // the Rust sync core.
    if (structured.code == 'snapshot_too_large') {
      final parsed = _parseSnapshotTooLarge(rawError);
      if (parsed != null) {
        return 'Your system is ${_humanBytes(parsed.bytes)} of data, '
            'which exceeds the current sync limit of '
            '${_humanBytes(parsed.limitBytes)}. Please reach out to '
            "support — we're working on larger systems.";
      }
      return 'Your system exceeds the current sync data limit. Please '
          "reach out to support — we're working on larger systems.";
    }
    if (structured.code == 'bootstrap_not_allowed') {
      final reason =
          _parseBootstrapNotAllowedReason(rawError) ?? structured.message;
      return "Couldn't prepare sync on this device. Details: $reason. "
          'Please report this with logs.';
    }

    // Unsupported first-device admission challenge (e.g., PoW version mismatch)
    if (msg.contains('unsupported') && msg.contains('first-device admission')) {
      return "Your app version doesn't support this relay's security "
          'requirements. Please update the app.';
    }

    // Rate limiting on registration
    if (msg.contains('registration failed') &&
        (msg.contains('rate limit') || structured.status == 429)) {
      return 'Too many registration attempts. Please wait and try again.';
    }

    // Generic relay / network errors
    if (structured.errorType == 'relay' || structured.relayKind != null) {
      return 'Could not connect to relay server. Check your internet '
          'connection and relay URL.';
    }

    // Fall back to the structured user message
    return structured.userMessage;
  }

  // No structured error — check for common network patterns
  final raw = rawError.toString().toLowerCase();
  if (raw.contains('socketexception') ||
      raw.contains('connection refused') ||
      raw.contains('timed out')) {
    return 'Could not connect to relay server. Check your internet '
        'connection and relay URL.';
  }

  return rawError.toString();
}

/// Parsed payload of a `SnapshotTooLarge` structured error, surfaced by
/// `bootstrap_existing_state` when the local zstd blob exceeds the cap.
class _SnapshotTooLargeInfo {
  const _SnapshotTooLargeInfo({required this.bytes, required this.limitBytes});

  final int bytes;
  final int limitBytes;
}

_SnapshotTooLargeInfo? _parseSnapshotTooLarge(Object rawError) {
  final payload = _extractStructuredErrorPayload(rawError);
  if (payload == null) return null;
  final bytes = (payload['bytes'] as num?)?.toInt();
  final limit = (payload['limit_bytes'] as num?)?.toInt();
  if (bytes == null || limit == null) return null;
  return _SnapshotTooLargeInfo(bytes: bytes, limitBytes: limit);
}

String? _parseBootstrapNotAllowedReason(Object rawError) {
  final payload = _extractStructuredErrorPayload(rawError);
  if (payload == null) return null;
  return payload['reason'] as String?;
}

/// Decode the inline JSON payload that follows the `PRISM_SYNC_ERROR_JSON:`
/// marker when structured errors cross the FFI boundary.
Map<String, dynamic>? _extractStructuredErrorPayload(Object rawError) {
  final raw = rawError.toString();
  const marker = 'PRISM_SYNC_ERROR_JSON:';
  final idx = raw.indexOf(marker);
  if (idx == -1) return null;
  final payload = raw.substring(idx + marker.length).trim();
  try {
    final decoded = jsonDecode(payload);
    if (decoded is Map<String, dynamic>) return decoded;
  } catch (_) {
    return null;
  }
  return null;
}

String _humanBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final rounded = value >= 10 || unit == 0
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$rounded ${units[unit]}';
}

final syncSetupProvider = NotifierProvider<SyncSetupNotifier, SyncSetupState>(
  SyncSetupNotifier.new,
);

/// Returns true if [host] names a loopback address suitable for allowing
/// plain `http://` during first-device relay setup. Matches the joiner
/// flow's scheme rule with a carve-out for local dev relays.
bool _isLoopbackHost(String host) {
  if (host.isEmpty) return false;
  // Uri.host strips IPv6 brackets, so compare against the raw address form.
  return host == 'localhost' || host == '127.0.0.1' || host == '::1';
}
