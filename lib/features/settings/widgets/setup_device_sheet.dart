import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lite_camera/flutter_lite_camera.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/constants/app_constants.dart';
import 'package:prism_plurality/core/crypto/bip39_validate.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/security/pin_buffer.dart';
import 'package:prism_plurality/core/security/pin_lockout_state.dart';
import 'package:prism_plurality/core/security/secret_bytes.dart';
import 'package:prism_plurality/core/sync/pairing_ceremony_api.dart';
import 'package:prism_plurality/core/sync/pairing_paste_code.dart';
import 'package:prism_plurality/core/sync/pairing_sas_display.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_event_loop.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/utils/human_bytes.dart';
import 'package:prism_plurality/shared/widgets/numpad_keyboard_listener.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_mnemonic_field.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:prism_plurality/shared/widgets/pin_numpad_cell.dart';
import 'package:prism_plurality/shared/widgets/secure_scope.dart';

import 'setup_device_sheet_desktop_decoder_stub.dart'
    if (dart.library.io) 'setup_device_sheet_desktop_decoder.dart'
    as desktop_qr;

class SetupDeviceSheet {
  static Future<void> show(BuildContext context, WidgetRef ref) async {
    final handle = await _readOrRestoreHandle(ref);
    if (handle == null) {
      if (!context.mounted) return;
      PrismToast.error(context, message: context.l10n.syncEngineNotAvailable);
      return;
    }

    final deviceId = await ref.read(syncDeviceIdProvider.future);
    final hasDeviceSecret = await ref.read(
      syncDeviceSecretPresentProvider.future,
    );
    if (deviceId == null || deviceId.isEmpty || !hasDeviceSecret) {
      if (!context.mounted) return;
      PrismToast.error(
        context,
        message: context.l10n.syncEnginePartialIdentity,
      );
      return;
    }

    // Pair-readiness: `wrapped_dek` is required to derive the joiner
    // bundle during the inviter ceremony. If it is missing (rare iOS
    // keychain anomaly), nudge the health state into `needsRewrap` so
    // the recovery sheet surfaces, then show a toast and bail out of the
    // pairing entry. See pairing/service.rs:602.
    final hasWrappedDek = await ref.read(syncWrappedDekPresentProvider.future);
    if (!hasWrappedDek) {
      ref
          .read(syncHealthProvider.notifier)
          .setState(SyncHealthState.needsRewrap);
      if (!context.mounted) return;
      PrismToast.error(
        context,
        message: context.l10n.syncEngineNeedsPinReconfirm,
      );
      return;
    }

    final relayUrl =
        await ref.read(relayUrlProvider.future) ?? AppConstants.defaultRelayUrl;

    if (!context.mounted) return;

    unawaited(
      PrismSheet.showFullScreen(
        context: context,
        builder: (ctx, sc) => _SetupDeviceSheetContent(
          handle: handle,
          relayUrl: relayUrl,
          scrollController: sc,
        ),
      ),
    );
  }

  static Future<ffi.PrismSyncHandle?> _readOrRestoreHandle(
    WidgetRef ref,
  ) async {
    var handle = ref.read(prismSyncHandleProvider).value;
    if (handle != null) return handle;

    try {
      handle = await ref.read(prismSyncHandleProvider.future);
    } catch (_) {
      handle = null;
    }
    if (handle != null) return handle;

    if (!_syncDatabaseReadyForHandleRestore(ref)) {
      return null;
    }

    final relayUrl = await ref.read(relayUrlProvider.future);
    final syncId = await ref.read(syncIdProvider.future);
    final deviceId = await ref.read(syncDeviceIdProvider.future);
    final hasDeviceSecret = await ref.read(
      syncDeviceSecretPresentProvider.future,
    );
    if (!hasCompletePersistentSyncIdentity(
      relayUrl: relayUrl,
      syncId: syncId,
      deviceId: deviceId,
      hasDeviceSecret: hasDeviceSecret,
    )) {
      return null;
    }

    try {
      return await ref
          .read(prismSyncHandleProvider.notifier)
          .createHandle(relayUrl: relayUrl!);
    } catch (_) {
      return null;
    }
  }

  static bool _syncDatabaseReadyForHandleRestore(WidgetRef ref) {
    try {
      return ref.read(syncDatabaseStartupProvider).state ==
          DbStartupState.ready;
    } catch (_) {
      return true;
    }
  }
}

class _SetupDeviceSheetContent extends ConsumerStatefulWidget {
  const _SetupDeviceSheetContent({
    required this.handle,
    required this.relayUrl,
    this.scrollController,
  });

  final ffi.PrismSyncHandle handle;
  final String relayUrl;
  final ScrollController? scrollController;

  @override
  ConsumerState<_SetupDeviceSheetContent> createState() =>
      SetupDeviceSheetContentState();
}

enum _InitiatorStep {
  enterMnemonic,
  // Pre-flight PIN verification: confirm the typed phrase+PIN unlock this
  // device before proceeding to the joiner QR scan.
  pinPreflight,
  prompt,
  scanning,
  // Camera-less fallback for the scan step; same token-bytes handoff.
  pasteCode,
  connecting,
  sasVerification,
  passwordEntry,
  // Uploading the encrypted snapshot to the relay. Progress bar visible.
  uploading,
  // Snapshot upload finished; finishing the credential handshake.
  completing,
  // Snapshot uploaded and handshake done. Brief confirmation before we
  // reset back to the prompt so the user sees the pair succeeded.
  uploadComplete,
  done,
  error,
}

// State class is public so tests can access @visibleForTesting members.
class SetupDeviceSheetContentState
    extends ConsumerState<_SetupDeviceSheetContent>
    with WidgetsBindingObserver {
  _InitiatorStep _step = _InitiatorStep.enterMnemonic;
  bool _joinerScanned = false;
  List<String>? _sasWords;
  String? _error;
  MobileScannerController? _joinerScannerController;

  /// Joiner's device_id captured from `startInitiatorCeremony`'s return
  /// JSON so we can thread it into `uploadPairingSnapshot(forDeviceId:)`.
  /// The relay scopes the snapshot and ACK-DELETE to this device_id.
  String? _joinerDeviceId;

  /// Latest upload progress for the pair-time snapshot, in bytes.
  /// Reset each time `_completeInitiator` runs.
  int? _uploadBytesSent;
  int? _uploadBytesTotal;

  /// Set when a `SnapshotUploadFailed` event arrives during the upload
  /// phase. Drives the retry button in the progress card.
  String? _uploadFailureReason;

  ProviderSubscription<AsyncValue<SyncEvent>>? _uploadEventSubscription;

  // Recovery phrase typed by the user; required because the mnemonic is never
  // persisted in the keychain. Dart Strings cannot be zeroed, so this is kept
  // only until completeInitiatorCeremony returns, reset, or dispose.
  String? _mnemonic;

  /// The PIN that passed pre-flight verification. Held here from pinPreflight
  /// until _completeInitiator consumes it, so the user never has to re-enter it.
  /// Zeroed on dispose, reset, and app lifecycle pause.
  PinBuffer? _validatedPin;

  /// Whether [_validatedPin] is currently null.
  ///
  /// Exposed only for widget tests that need to verify lifecycle-pause zeroing
  /// without walking the full SAS → passwordEntry path.
  @visibleForTesting
  bool get validatedPinIsNull => _validatedPin == null;

  /// The current length of [_validatedPin], or -1 if null.
  ///
  /// Exposed for regression tests that verify the buffer is non-empty after
  /// the preflight view unmounts (guarding against the dispose-clears-parent
  /// buffer bug).
  @visibleForTesting
  int get validatedPinLength => _validatedPin?.length ?? -1;

  late final PairingCeremonyApi _pairingApi;

  @override
  void initState() {
    super.initState();
    _pairingApi = ref.read(pairingCeremonyApiProvider);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _validatedPin?.clear();
      _validatedPin = null;
    }
  }

  MobileScannerController _ensureJoinerScanner() {
    return _joinerScannerController ??= MobileScannerController();
  }

  bool get _scannerSupportedForPairing {
    if (kIsWeb) return true;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => true,
      TargetPlatform.fuchsia => false,
    };
  }

  bool get _useDesktopPairingScanner {
    if (kIsWeb) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.linux || TargetPlatform.windows => true,
      TargetPlatform.android ||
      TargetPlatform.fuchsia ||
      TargetPlatform.iOS ||
      TargetPlatform.macOS => false,
    };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_shouldCancelActiveCeremony()) {
      unawaited(_cancelActiveCeremony());
    }
    _joinerScannerController?.dispose();
    _uploadEventSubscription?.close();
    _uploadEventSubscription = null;
    _mnemonic = null;
    _validatedPin?.clear();
    _validatedPin = null;
    super.dispose();
  }

  void _reset() {
    if (_shouldCancelActiveCeremony()) {
      unawaited(_cancelActiveCeremony());
    }
    _joinerScannerController?.dispose();
    _joinerScannerController = null;
    _uploadEventSubscription?.close();
    _uploadEventSubscription = null;
    _validatedPin?.clear();
    _validatedPin = null;
    setState(() {
      _step = _InitiatorStep.enterMnemonic;
      _joinerScanned = false;
      _sasWords = null;
      _joinerDeviceId = null;
      _uploadBytesSent = null;
      _uploadBytesTotal = null;
      _uploadFailureReason = null;
      _error = null;
      _mnemonic = null;
    });
  }

  bool _shouldCancelActiveCeremony() {
    return switch (_step) {
      _InitiatorStep.scanning ||
      _InitiatorStep.connecting ||
      _InitiatorStep.sasVerification ||
      _InitiatorStep.passwordEntry ||
      _InitiatorStep.uploading ||
      _InitiatorStep.completing ||
      _InitiatorStep.error => true,
      _InitiatorStep.enterMnemonic ||
      _InitiatorStep.pinPreflight ||
      _InitiatorStep.prompt ||
      _InitiatorStep.pasteCode ||
      _InitiatorStep.uploadComplete ||
      _InitiatorStep.done => false,
    };
  }

  Future<void> _cancelActiveCeremony() async {
    try {
      await _pairingApi
          .cancelPairingCeremony(handle: widget.handle)
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[SYNC] Pairing ceremony cancel failed: $e');
    }
  }

  Future<void> _startInitiatorCeremony(Uint8List tokenBytes) async {
    setState(() {
      _step = _InitiatorStep.connecting;
      _error = null;
    });

    try {
      final pairingApi = ref.read(pairingCeremonyApiProvider);
      final jsonString = await pairingApi.startInitiatorCeremony(
        handle: widget.handle,
        tokenBytes: tokenBytes,
      );
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final sas = PairingSasDisplay.fromJson(json);
      // Captured for uploadPairingSnapshot(forDeviceId:) in _completeInitiator.
      // This must be present so the pair-time snapshot cannot accidentally
      // become a group-wide pruning snapshot.
      final rawJoinerDeviceId = json['joiner_device_id'];
      final joinerDeviceId = rawJoinerDeviceId is String
          ? rawJoinerDeviceId.trim()
          : null;
      if (joinerDeviceId == null || joinerDeviceId.isEmpty) {
        throw StateError(
          'Pairing response missing joiner device id; update the app and try again.',
        );
      }

      if (!mounted) return;
      setState(() {
        _sasWords = sas.words;
        _joinerDeviceId = joinerDeviceId;
        _step = _InitiatorStep.sasVerification;
      });
    } catch (e) {
      unawaited(_cancelActiveCeremony());
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _step = _InitiatorStep.error;
      });
    }
  }

  Future<void> _completeInitiator(PinBuffer pin) async {
    // Drain the buffer synchronously BEFORE any setState/await — once the
    // step changes the source view (_PreflightPinView or _InitiatorPinView)
    // unmounts and its dispose() clears the buffer. Same risk if the app
    // backgrounds mid-flight: the lifecycle hook clears _validatedPin.
    final pinBytes = pin.consumeBytesAndClear();

    try {
      setState(() {
        _step = _InitiatorStep.uploading;
        _error = null;
        _uploadBytesSent = null;
        _uploadBytesTotal = null;
        _uploadFailureReason = null;
      });

      // Subscribe to the sync event stream to drive the upload progress
      // bar. The stream emits SnapshotUploadProgress during the streamed
      // PUT and SnapshotUploadFailed if the relay rejects the body.
      _uploadEventSubscription?.close();
      _uploadEventSubscription = ref.listenManual<AsyncValue<SyncEvent>>(
        syncEventStreamProvider,
        (prev, next) {
          next.whenData((event) {
            if (!mounted) return;
            if (event.type == 'SnapshotUploadProgress') {
              final sent = _asInt(event.data['bytes_sent']);
              final total = _asInt(event.data['bytes_total']);
              if (sent != null && total != null) {
                setState(() {
                  _uploadBytesSent = sent;
                  _uploadBytesTotal = total;
                });
              }
            } else if (event.type == 'SnapshotUploadFailed') {
              setState(() {
                _uploadFailureReason =
                    (event.data['reason'] as String?) ?? 'Upload failed';
              });
            }
          });
        },
      );

      try {
        // Upload the ephemeral snapshot BEFORE sending credentials. The joiner
        // can't register or try to bootstrap until it receives the credentials
        // from completeInitiatorCeremony, so uploading first guarantees the
        // snapshot is on the relay by the time the joiner's bootstrap_from_snapshot
        // runs. Otherwise the joiner races ahead, finds no snapshot, and ends
        // up with zero records.
        //
        // The snapshot is encrypted with the current (pre-rekey) epoch key,
        // which matches what the credential bundle will ship to the joiner.
        //
        // Fatal on failure: if the snapshot doesn't land on the relay we must
        // NOT release credentials. Otherwise the joiner registers, finds no
        // snapshot, falls through to an empty syncNow (first-device data is
        // still local-only), and ends up with zero records — the exact bug
        // this fix is meant to prevent. Let the error propagate to the outer
        // catch so the initiator flow shows an error state instead of a
        // confusing "synced but empty" success.
        await ffi.uploadPairingSnapshot(
          handle: widget.handle,
          ttlSecs: BigInt.from(86400),
          forDeviceId: _joinerDeviceId,
        );

        if (!mounted) return;
        setState(() {
          _step = _InitiatorStep.completing;
        });

        final mnemonic = _mnemonic;
        if (mnemonic == null) {
          // Defensive: should be set by the enterMnemonic step before we arrive
          // here. Bail out and bounce the user back to re-enter it.
          throw StateError('Recovery phrase is missing.');
        }

        final pairingApi = ref.read(pairingCeremonyApiProvider);
        Uint8List? mnemonicBytes;
        try {
          mnemonicBytes = secretUtf8Bytes(mnemonic);
          await pairingApi.completeInitiatorCeremony(
            handle: widget.handle,
            password: pinBytes,
            mnemonic: mnemonicBytes,
          );
        } finally {
          zeroBytesBestEffort(mnemonicBytes);
          _mnemonic = null;
        }

        // Drain store after completion (may mutate epoch / credentials)
        await drainRustStore(widget.handle);
        try {
          await cacheRuntimeKeys(widget.handle, ref.read(databaseProvider));
        } catch (e) {
          debugPrint('[SYNC] Failed to refresh runtime keys after pairing: $e');
        }

        if (!mounted) return;
        // Brief confirmation so the user sees the upload actually finished
        // before we route forward.
        setState(() {
          _step = _InitiatorStep.uploadComplete;
        });
        _uploadEventSubscription?.close();
        _uploadEventSubscription = null;
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        setState(() {
          _step = _InitiatorStep.done;
        });
      } catch (e) {
        _uploadEventSubscription?.close();
        _uploadEventSubscription = null;
        debugPrint('[SYNC] Pairing initiator completion failed: $e');
        if (!mounted) return;
        setState(() {
          _error = e.toString();
          _step = _InitiatorStep.error;
        });
      } finally {
        // Drop the _validatedPin reference now that the buffer has been consumed
        // (success path: consumeBytesAndClear already zeroed it) or the ceremony
        // failed (error path: zero any remaining bytes and release the reference).
        // This prevents a dangling reference to a stale/consumed buffer after
        // _completeInitiator returns.
        _validatedPin?.clear();
        _validatedPin = null;
      }
    } finally {
      // Belt-and-suspenders: zero pinBytes on every path including early
      // throws from setState or pre-FFI setup code. The inner mnemonicBytes
      // finally block already handles the normal crypto path.
      zeroBytesBestEffort(pinBytes);
    }
  }

  static int? _asInt(Object? raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is BigInt) return raw.toInt();
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return SecureScope(
      allowAndroidScreenCapture: _step == _InitiatorStep.enterMnemonic,
      child: Column(
        children: [
          PrismSheetTopBar(title: context.l10n.syncSetUpAnotherDevice),
          Expanded(
            child: SingleChildScrollView(
              controller: widget.scrollController,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              child: _buildContent(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onMnemonicSubmitted(String mnemonic) async {
    final normalized = PrismMnemonicField.normalize(mnemonic);

    if (!validateBip39Mnemonic(normalized)) {
      if (!mounted) return;
      setState(() {
        _error = context.l10n.changePinMnemonicInvalid;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _mnemonic = normalized;
      _error = null;
      _step = _InitiatorStep.pinPreflight;
    });
  }

  void _onPreflightValid(PinBuffer pin) {
    _validatedPin = pin;
    setState(() => _step = _InitiatorStep.prompt);
  }

  void _onPreflightNeedsRewrap() {
    ref.read(syncHealthProvider.notifier).setState(SyncHealthState.needsRewrap);
    if (mounted) {
      PrismToast.error(
        context,
        message: context.l10n.syncEngineNeedsPinReconfirm,
      );
      Navigator.of(context).pop();
    }
  }

  void _onPreflightHandleUnavailable() {
    if (mounted) {
      PrismToast.error(context, message: context.l10n.syncEngineNotAvailable);
      Navigator.of(context).pop();
    }
  }

  Widget _buildContent() {
    return switch (_step) {
      _InitiatorStep.enterMnemonic => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _PreflightStepIndicator(currentStep: _PreflightStep.phrase),
          const SizedBox(height: 16),
          _MnemonicEntryView(
            initialError: _error,
            onSubmit: _onMnemonicSubmitted,
          ),
        ],
      ),
      _InitiatorStep.pinPreflight => _PreflightPinView(
        mnemonic: _mnemonic!,
        onValidated: _onPreflightValid,
        onBack: () => setState(() => _step = _InitiatorStep.enterMnemonic),
        onNeedsRewrap: _onPreflightNeedsRewrap,
        onHandleUnavailable: _onPreflightHandleUnavailable,
      ),
      _InitiatorStep.prompt => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _PreflightStepIndicator(currentStep: _PreflightStep.scan),
          const SizedBox(height: 16),
          _ScanJoinerPrompt(
            scannerSupported: _scannerSupportedForPairing,
            onStartScan: () => setState(
              () => _step = _scannerSupportedForPairing
                  ? _InitiatorStep.scanning
                  : _InitiatorStep.pasteCode,
            ),
          ),
        ],
      ),
      _InitiatorStep.scanning =>
        _useDesktopPairingScanner
            ? _DesktopJoinerQrScannerView(
                scanned: _joinerScanned,
                error: _error,
                onBack: _reset,
                onScanned: (bytes) {
                  setState(() => _joinerScanned = true);
                  _startInitiatorCeremony(bytes);
                },
                onPasteFallback: () =>
                    setState(() => _step = _InitiatorStep.pasteCode),
              )
            : _JoinerQrScannerView(
                ensureScanner: _ensureJoinerScanner,
                scanned: _joinerScanned,
                error: _error,
                onBack: _reset,
                onScanned: (bytes) {
                  setState(() => _joinerScanned = true);
                  _startInitiatorCeremony(bytes);
                },
                onPasteFallback: () =>
                    setState(() => _step = _InitiatorStep.pasteCode),
              ),
      _InitiatorStep.pasteCode => _PasteCodeView(
        onSubmit: _startInitiatorCeremony,
        onBackToCamera: () => setState(
          () => _step = _scannerSupportedForPairing
              ? _InitiatorStep.scanning
              : _InitiatorStep.prompt,
        ),
      ),
      _InitiatorStep.connecting => Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PrismSpinner(
                color: Theme.of(context).colorScheme.primary,
                size: 52,
                dotCount: 8,
                duration: const Duration(milliseconds: 3000),
              ),
              const SizedBox(height: 16),
              Text(context.l10n.syncSetupConnectingToJoiner),
            ],
          ),
        ),
      ),
      _InitiatorStep.sasVerification => _SasVerificationView(
        sasWords: _sasWords!,
        onConfirm: () {
          if (_validatedPin != null) {
            _completeInitiator(_validatedPin!);
          } else {
            setState(() => _step = _InitiatorStep.passwordEntry);
          }
        },
        onReject: _reset,
      ),
      _InitiatorStep.passwordEntry => _InitiatorPinView(
        onPinEntered: _completeInitiator,
        onBack: () => setState(() => _step = _InitiatorStep.sasVerification),
      ),
      _InitiatorStep.uploading => _InitiatorUploadingView(
        bytesSent: _uploadBytesSent,
        bytesTotal: _uploadBytesTotal,
        failureReason: _uploadFailureReason,
        // Re-run the upload + completion. PIN was consumed on the first
        // attempt, so bounce back to the start of the flow so the user
        // re-enters the mnemonic and PIN.
        onRetry: _reset,
      ),
      _InitiatorStep.uploadComplete => const _InitiatorUploadCompleteView(),
      _InitiatorStep.completing => Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PrismSpinner(
                color: Theme.of(context).colorScheme.primary,
                size: 52,
                dotCount: 8,
                duration: const Duration(milliseconds: 3000),
              ),
              const SizedBox(height: 16),
              Text(context.l10n.syncSetupCompletingPairing),
            ],
          ),
        ),
      ),
      _InitiatorStep.done => _InitiatorDoneView(onDone: _reset),
      _InitiatorStep.error => _InitiatorErrorView(
        message: _error ?? context.l10n.onboardingSyncUnknownError,
        onTryAgain: _reset,
      ),
    };
  }
}

enum _PreflightStep { phrase, pin, scan }

/// A compact "1 Phrase · 2 PIN · 3 Scan" row used across the preflight steps.
class _PreflightStepIndicator extends StatelessWidget {
  const _PreflightStepIndicator({required this.currentStep});

  final _PreflightStep currentStep;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    final steps = [
      (l10n.syncSetupStepPhrase, _PreflightStep.phrase),
      (l10n.syncSetupStepPin, _PreflightStep.pin),
      (l10n.syncSetupStepScan, _PreflightStep.scan),
    ];

    final currentIndex = steps.indexWhere((s) => s.$2 == currentStep);
    final stepNumber = currentIndex + 1;
    final stepName = steps[currentIndex].$1;

    return Semantics(
      container: true,
      liveRegion: true,
      label: l10n.syncSetupStepIndicatorLabel(stepNumber, stepName),
      child: ExcludeSemantics(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < steps.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    '·',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              Text(
                '${i + 1} ${steps[i].$1}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: steps[i].$2 == currentStep
                      ? FontWeight.w700
                      : FontWeight.w400,
                  color: steps[i].$2 == currentStep
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// PIN entry screen shown BEFORE scanning the joiner QR to verify the user's
/// phrase+PIN unlock the current install's wrapped_dek.
///
/// Reuses [PinNumpadCell] for numpad cells and mirrors the shake +
/// dot-scale-pulse animation pattern from [_SyncPinSheetState].
class _PreflightPinView extends ConsumerStatefulWidget {
  const _PreflightPinView({
    required this.mnemonic,
    required this.onValidated,
    required this.onBack,
    required this.onNeedsRewrap,
    required this.onHandleUnavailable,
  });

  final String mnemonic;
  final void Function(PinBuffer pin) onValidated;
  final VoidCallback onBack;
  final VoidCallback onNeedsRewrap;
  final VoidCallback onHandleUnavailable;

  @override
  ConsumerState<_PreflightPinView> createState() => _PreflightPinViewState();
}

class _PreflightPinViewState extends ConsumerState<_PreflightPinView>
    with TickerProviderStateMixin {
  static const _pinLength = 6;

  late final PinBuffer _pin = PinBuffer(length: _pinLength);
  late final PinLockoutState _lockout = PinLockoutState(
    prefsScope: 'prism.preflight',
  );

  bool _hasError = false;
  bool _checking = false;

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  late final AnimationController _dotController;
  late final Animation<double> _dotScaleAnim;
  int? _lastFilledDotIndex;

  @override
  void initState() {
    super.initState();

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 0, end: -12), weight: 1),
          TweenSequenceItem(tween: Tween(begin: -12, end: 12), weight: 2),
          TweenSequenceItem(tween: Tween(begin: 12, end: -8), weight: 2),
          TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
          TweenSequenceItem(tween: Tween(begin: 8, end: 0), weight: 1),
        ]).animate(
          CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut),
        );

    _dotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _dotScaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.2), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 1),
    ]).animate(_dotController);

    _lockout.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _pin.clear();
    _shakeController.dispose();
    _dotController.dispose();
    super.dispose();
  }

  void _onDigit(String digit) {
    if (_checking || _lockout.isLockedOut || !_pin.appendDigit(digit)) return;
    setState(() {
      _hasError = false;
      _lastFilledDotIndex = _pin.length - 1;
    });
    _dotController.forward(from: 0);
    if (_pin.isFull) {
      _onPinComplete();
    }
  }

  void _onBackspace() {
    if (_pin.isEmpty || _checking) return;
    setState(_pin.removeLast);
  }

  void _shake() {
    _shakeController.forward(from: 0);
    _pin.clear();
    setState(() => _lastFilledDotIndex = null);
  }

  // Pauses briefly after successful validation so the user sees the dots fill before advancing.
  Future<void> _pauseForFeedback() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  Future<void> _onPinComplete() async {
    if (_lockout.isLockedOut) {
      _shake();
      return;
    }
    setState(() => _checking = true);

    // Make a defensive copy — verifyMnemonicPin drains the buffer
    final pinCopy = PinBuffer(length: _pin.length)..replaceWith(_pin);

    try {
      final result = await ref
          .read(syncHealthProvider.notifier)
          .verifyMnemonicPin(pin: pinCopy, mnemonic: widget.mnemonic);

      if (!mounted) return;

      switch (result) {
        case VerifyMnemonicPinMatch():
          await _lockout.clear();
          await _pauseForFeedback();
          if (!mounted) return;
          // Create a defensive copy so the parent owns a separate buffer.
          // The view's _pin is cleared below; when dispose() clears it again
          // that is harmless — the parent's handoff buffer is independent.
          final handoff = PinBuffer(length: _pin.length)..replaceWith(_pin);
          _pin.clear(); // we are done with our copy
          widget.onValidated(handoff);
        case VerifyMnemonicPinNoMatch():
          await _lockout.recordFailure();
          if (!mounted) return;
          _pin.clear();
          setState(() {
            _checking = false;
            _hasError = true;
          });
          _shake();
        case VerifyMnemonicPinNeedsRewrap():
          widget.onNeedsRewrap();
        case VerifyMnemonicPinHandleUnavailable():
          widget.onHandleUnavailable();
        case VerifyMnemonicPinError():
          // Infrastructure error — do NOT increment lockout. Show a toast
          // and stay on this step so the user can retry.
          if (!mounted) return;
          _pin.clear();
          setState(() => _checking = false);
          _shake();
          PrismToast.show(
            context,
            message: context.l10n.syncSetupVerifyPinTransientError,
          );
      }
    } finally {
      pinCopy.clear();
    }
  }

  String _subtitle(BuildContext context) {
    if (_lockout.isLockedOut) {
      return context.l10n.syncSetupVerifyPinLockedOut(
        _lockout.secondsRemaining,
      );
    }
    if (_checking) return context.l10n.syncSetupVerifyPinChecking;
    if (_hasError) return context.l10n.syncSetupVerifyPinFailed;
    return context.l10n.syncSetupVerifyPinSubtitle;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _PreflightStepIndicator(currentStep: _PreflightStep.pin),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: PrismButton(
            label: context.l10n.back,
            onPressed: widget.onBack,
            icon: AppIcons.arrowBackIosNew,
            tone: PrismButtonTone.subtle,
          ),
        ),
        const SizedBox(height: 24),
        Icon(AppIcons.lockOutline, color: accentColor, size: 40),
        const SizedBox(height: 16),
        Text(
          context.l10n.syncSetupVerifyPinTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          _subtitle(context),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: _hasError
                ? theme.colorScheme.error
                : theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        // PIN dot indicators with shake animation
        AnimatedBuilder(
          animation: _shakeAnimation,
          builder: (context, child) => Transform.translate(
            offset: Offset(_shakeAnimation.value, 0),
            child: child,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_pinLength, (i) {
              final filled = i < _pin.length;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: AnimatedBuilder(
                  animation: _dotScaleAnim,
                  builder: (context, child) => Transform.scale(
                    scale: i == _lastFilledDotIndex ? _dotScaleAnim.value : 1.0,
                    child: child,
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled
                          ? accentColor
                          : accentColor.withValues(alpha: 0.15),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 32),
        // Numpad
        if (!_checking)
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 296),
              child: NumpadKeyboardListener(
                onDigit: _onDigit,
                onBackspace: _onBackspace,
                enabled: !_checking && !_lockout.isLockedOut,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var row = 0; row < 4; row++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: _buildRow(row, theme),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: _PreflightCheckingIndicator(),
          ),
        if (!_checking) ...[
          const SizedBox(height: 8),
          Center(
            child: GestureDetector(
              onTap: widget.onBack,
              child: Text(
                context.l10n.syncSetupTryDifferentPhrase,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: accentColor,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _buildRow(int row, ThemeData theme) {
    if (row < 3) {
      return List.generate(3, (col) {
        final digit = '${row * 3 + col + 1}';
        return PinNumpadCell(
          label: digit,
          onTap: () => _onDigit(digit),
          theme: theme,
        );
      });
    }
    return [
      const SizedBox(width: 72, height: 72),
      PinNumpadCell(label: '0', onTap: () => _onDigit('0'), theme: theme),
      PinNumpadCell(
        icon: AppIcons.backspaceOutlined,
        onTap: _onBackspace,
        theme: theme,
      ),
    ];
  }
}

/// Small spinner shown while the pre-flight PIN check is in progress.
class _PreflightCheckingIndicator extends StatelessWidget {
  const _PreflightCheckingIndicator();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: PrismSpinner(
        color: Theme.of(context).colorScheme.primary,
        size: 40,
        dotCount: 8,
        duration: const Duration(milliseconds: 2000),
      ),
    );
  }
}

/// Recovery phrase entry — required first step since the mnemonic is no
/// longer persisted in the keychain.
class _MnemonicEntryView extends StatefulWidget {
  const _MnemonicEntryView({
    required this.initialError,
    required this.onSubmit,
  });

  final String? initialError;
  final Future<void> Function(String mnemonic) onSubmit;

  @override
  State<_MnemonicEntryView> createState() => _MnemonicEntryViewState();
}

class _MnemonicEntryViewState extends State<_MnemonicEntryView> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _error = widget.initialError;
  }

  @override
  void dispose() {
    _controller.clear();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final normalized = PrismMnemonicField.normalize(_controller.text);
    if (normalized.isEmpty) {
      setState(() => _error = context.l10n.changePinMnemonicRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await widget.onSubmit(normalized);
    if (!mounted) return;
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.setupDeviceEnterMnemonicTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.setupDeviceEnterMnemonicSubtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        PrismMnemonicField(
          controller: _controller,
          hintText: context.l10n.changePinMnemonicHint,
          enabled: !_busy,
          autofocus: true,
          errorText: _error,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 20),
        PrismButton(
          label: context.l10n.setupDeviceMnemonicContinue,
          onPressed: _submit,
          isLoading: _busy,
        ),
      ],
    );
  }
}

/// Prompt for the "Scan Joiner's QR" flow before the camera opens.
class _ScanJoinerPrompt extends StatelessWidget {
  const _ScanJoinerPrompt({
    required this.scannerSupported,
    required this.onStartScan,
  });

  final bool scannerSupported;
  final VoidCallback onStartScan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          scannerSupported
              ? context.l10n.syncSetupScanJoinerPrompt
              : context.l10n.syncSetupPasteCodeDescription,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        PrismButton(
          label: scannerSupported
              ? context.l10n.syncSetupScanJoinerButton
              : context.l10n.syncSetupPasteCodeTitle,
          icon: scannerSupported ? AppIcons.qrCodeScanner : AppIcons.paste,
          onPressed: onStartScan,
        ),
      ],
    );
  }
}

/// Camera view for scanning the joiner's rendezvous token QR.
class _JoinerQrScannerView extends StatelessWidget {
  const _JoinerQrScannerView({
    required this.ensureScanner,
    required this.scanned,
    required this.error,
    required this.onBack,
    required this.onScanned,
    required this.onPasteFallback,
  });

  final MobileScannerController Function() ensureScanner;
  final bool scanned;
  final String? error;
  final VoidCallback onBack;
  final void Function(Uint8List bytes) onScanned;
  final VoidCallback onPasteFallback;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: PrismButton(
            label: context.l10n.back,
            onPressed: onBack,
            icon: AppIcons.arrowBackIosNew,
            tone: PrismButtonTone.subtle,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.syncSetupScanJoinerDescription,
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(
            PrismShapes.of(context).radius(16),
          ),
          child: SizedBox(
            height: 280,
            child: MobileScanner(
              controller: ensureScanner(),
              onDetect: (capture) {
                if (scanned) return;
                final barcode = capture.barcodes.firstOrNull;
                final raw = barcode?.rawValue;
                if (raw == null) return;
                try {
                  final bytes = Uint8List.fromList(base64Decode(raw));
                  onScanned(bytes);
                } catch (_) {
                  if (context.mounted) {
                    PrismToast.show(
                      context,
                      message: context.l10n.syncSetupInvalidPairingQr,
                    );
                  }
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Keep the paste path available when camera access fails.
        Center(
          child: Semantics(
            button: true,
            child: TextButton(
              onPressed: onPasteFallback,
              child: Text(context.l10n.syncSetupPasteCodeLink),
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(
            error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

/// Windows/Linux scanner backed by desktop camera frames plus a Dart QR decoder.
class _DesktopJoinerQrScannerView extends StatefulWidget {
  const _DesktopJoinerQrScannerView({
    required this.scanned,
    required this.error,
    required this.onBack,
    required this.onScanned,
    required this.onPasteFallback,
  });

  final bool scanned;
  final String? error;
  final VoidCallback onBack;
  final void Function(Uint8List bytes) onScanned;
  final VoidCallback onPasteFallback;

  @override
  State<_DesktopJoinerQrScannerView> createState() =>
      _DesktopJoinerQrScannerViewState();
}

class _DesktopJoinerQrScannerViewState
    extends State<_DesktopJoinerQrScannerView> {
  static const _captureDelay = Duration(milliseconds: 100);
  static const _decodeDelay = Duration(milliseconds: 350);

  final FlutterLiteCamera _camera = FlutterLiteCamera();
  bool _capturing = false;
  bool _reportedScan = false;
  bool _decoding = false;
  String? _status;
  String? _cameraError;
  DateTime _nextDecodeAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _lastInvalidToastAt;
  ui.Image? _latestFrame;

  @override
  void initState() {
    super.initState();
    unawaited(_startCamera());
  }

  @override
  void dispose() {
    _capturing = false;
    unawaited(_releaseCamera());
    _latestFrame?.dispose();
    super.dispose();
  }

  Future<void> _releaseCamera() async {
    try {
      await _camera.release();
    } catch (error) {
      debugPrint('[SYNC] Desktop pairing camera release failed: $error');
    }
  }

  Future<void> _startCamera() async {
    try {
      final devices = await _camera.getDeviceList();
      if (!mounted) return;
      if (devices.isEmpty) {
        setState(() {
          _status = null;
          _cameraError = 'No camera was found.';
        });
        return;
      }

      final opened = await _camera.open(0);
      if (!mounted) return;
      if (!opened) {
        setState(() {
          _status = null;
          _cameraError = 'Could not open the camera.';
        });
        return;
      }

      setState(() {
        _status = null;
        _cameraError = null;
      });
      _capturing = true;
      unawaited(_captureLoop());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = null;
        _cameraError = error.toString();
      });
    }
  }

  Future<void> _captureLoop() async {
    while (mounted && _capturing && !_reportedScan) {
      await _captureFrame();
      if (mounted && _capturing && !_reportedScan) {
        await Future<void>.delayed(_captureDelay);
      }
    }
  }

  Future<void> _captureFrame() async {
    try {
      final frame = await _camera.captureFrame();
      final data = frame['data'];
      final width = (frame['width'] as num?)?.toInt();
      final height = (frame['height'] as num?)?.toInt();
      if (data is! Uint8List || width == null || height == null) {
        return;
      }

      final rgba = _rgb888ToRgba8888(data, width, height);
      await _showPreview(rgba, width, height);

      final now = DateTime.now();
      if (!_decoding && now.isAfter(_nextDecodeAt)) {
        _nextDecodeAt = now.add(_decodeDelay);
        unawaited(_decodeFrame(rgba, width, height));
      }
    } catch (error) {
      debugPrint('[SYNC] Desktop pairing camera frame failed: $error');
    }
  }

  Future<void> _showPreview(Uint8List rgba, int width, int height) async {
    final image = await _decodeRgbaImage(rgba, width, height);
    if (!mounted) {
      image.dispose();
      return;
    }

    final previous = _latestFrame;
    setState(() => _latestFrame = image);
    previous?.dispose();
  }

  Future<void> _decodeFrame(Uint8List rgba, int width, int height) async {
    _decoding = true;
    try {
      final raw = await desktop_qr.decodePairingQr(rgba, width, height);
      if (!mounted || raw == null || raw.isEmpty) return;
      _handleRawQr(raw);
    } catch (error) {
      debugPrint('[SYNC] Desktop pairing QR decode failed: $error');
    } finally {
      _decoding = false;
    }
  }

  void _handleRawQr(String raw) {
    if (widget.scanned || _reportedScan) return;
    try {
      final bytes = Uint8List.fromList(base64Decode(raw));
      _reportedScan = true;
      _capturing = false;
      widget.onScanned(bytes);
    } catch (_) {
      final now = DateTime.now();
      final last = _lastInvalidToastAt;
      if (last != null && now.difference(last) < const Duration(seconds: 2)) {
        return;
      }
      _lastInvalidToastAt = now;
      if (mounted) {
        PrismToast.show(
          context,
          message: context.l10n.syncSetupInvalidPairingQr,
        );
      }
    }
  }

  Uint8List _rgb888ToRgba8888(Uint8List rgb, int width, int height) {
    final pixelCount = width * height;
    final rgba = Uint8List(pixelCount * 4);
    final availablePixels = (rgb.length ~/ 3).clamp(0, pixelCount).toInt();
    for (var pixel = 0; pixel < availablePixels; pixel++) {
      final src = pixel * 3;
      final dst = pixel * 4;
      rgba[dst] = rgb[src];
      rgba[dst + 1] = rgb[src + 1];
      rgba[dst + 2] = rgb[src + 2];
      rgba[dst + 3] = 0xff;
    }
    return rgba;
  }

  Future<ui.Image> _decodeRgbaImage(Uint8List rgba, int width, int height) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: PrismButton(
            label: context.l10n.back,
            onPressed: widget.onBack,
            icon: AppIcons.arrowBackIosNew,
            tone: PrismButtonTone.subtle,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.syncSetupScanJoinerDescription,
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(
            PrismShapes.of(context).radius(16),
          ),
          child: SizedBox(
            height: 280,
            child: ColoredBox(
              color: Colors.black,
              child: _latestFrame != null
                  ? RawImage(image: _latestFrame, fit: BoxFit.cover)
                  : Center(
                      child: Text(
                        _cameraError ?? _status ?? context.l10n.loading,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Semantics(
            button: true,
            child: TextButton(
              onPressed: widget.onPasteFallback,
              child: Text(context.l10n.syncSetupPasteCodeLink),
            ),
          ),
        ),
        if (widget.error != null) ...[
          const SizedBox(height: 12),
          Text(
            widget.error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

/// Pastes the joiner's pairing code and hands the decoded bytes to the
/// existing initiator ceremony — the camera-less twin of `_JoinerQrScannerView`.
class _PasteCodeView extends StatefulWidget {
  const _PasteCodeView({required this.onSubmit, required this.onBackToCamera});

  final void Function(Uint8List tokenBytes) onSubmit;
  final VoidCallback onBackToCamera;

  @override
  State<_PasteCodeView> createState() => _PasteCodeViewState();
}

class _PasteCodeViewState extends State<_PasteCodeView> {
  final _controller = TextEditingController();
  String? _error;
  bool _hadText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    // Best-effort scrub of the pasted token before release.
    _controller.clear();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    // Skip rebuilds on cursor/selection moves; only state-affecting changes.
    var dirty = false;
    if (_error != null) {
      _error = null;
      dirty = true;
    }
    final hasText = _hasTextToSubmit;
    if (hasText != _hadText) {
      _hadText = hasText;
      dirty = true;
    }
    if (dirty) setState(() {});
  }

  bool get _hasTextToSubmit => _controller.text.trim().isNotEmpty;

  void _submit() {
    final bytes = parsePastedPairingCode(_controller.text);
    if (bytes == null) {
      setState(() => _error = context.l10n.syncSetupPasteCodeInvalidFormat);
      return;
    }
    widget.onSubmit(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: PrismButton(
            label: context.l10n.back,
            onPressed: widget.onBackToCamera,
            icon: AppIcons.arrowBackIosNew,
            tone: PrismButtonTone.subtle,
          ),
        ),
        const SizedBox(height: 16),
        Icon(AppIcons.paste, color: theme.colorScheme.primary, size: 40),
        const SizedBox(height: 16),
        Text(
          context.l10n.syncSetupPasteCodeTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.syncSetupPasteCodeDescription,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        PrismTextField(
          controller: _controller,
          labelText: context.l10n.syncSetupPasteCodeLabel,
          hintText: context.l10n.syncSetupPasteCodeHint,
          minLines: 3,
          maxLines: 5,
          autofocus: true,
          errorText: _error,
          // Autocorrect/autocapitalize would corrupt base64.
          textCapitalization: TextCapitalization.none,
        ),
        const SizedBox(height: 20),
        PrismButton(
          label: context.l10n.syncSetupPasteCodeSubmit,
          icon: AppIcons.checkCircle,
          tone: PrismButtonTone.filled,
          enabled: _hasTextToSubmit,
          onPressed: _submit,
        ),
      ],
    );
  }
}

/// Shows SAS words for the initiator to verify with the joiner.
class _SasVerificationView extends StatelessWidget {
  const _SasVerificationView({
    required this.sasWords,
    required this.onConfirm,
    required this.onReject,
  });

  final List<String> sasWords;
  final VoidCallback onConfirm;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          AppIcons.shieldOutlined,
          color: theme.colorScheme.primary,
          size: 40,
        ),
        const SizedBox(height: 16),
        Text(
          context.l10n.onboardingSyncVerifySecurityCode,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.syncSetupVerifyDescription,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(
              PrismShapes.of(context).radius(16),
            ),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: sasWords
                    .map(
                      (word) => Text(
                        word,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        PrismButton(
          label: context.l10n.onboardingSyncTheyMatch,
          icon: AppIcons.checkCircle,
          onPressed: onConfirm,
        ),
        const SizedBox(height: 8),
        PrismButton(
          label: context.l10n.onboardingSyncTheyDontMatch,
          icon: AppIcons.close,
          tone: PrismButtonTone.subtle,
          onPressed: onReject,
        ),
      ],
    );
  }
}

/// PIN entry for the initiator after SAS verification.
class _InitiatorPinView extends StatefulWidget {
  const _InitiatorPinView({required this.onPinEntered, required this.onBack});

  final void Function(PinBuffer pin) onPinEntered;
  final VoidCallback onBack;

  @override
  State<_InitiatorPinView> createState() => _InitiatorPinViewState();
}

class _InitiatorPinViewState extends State<_InitiatorPinView> {
  static const _pinLength = 6;
  late final PinBuffer _pin = PinBuffer(length: _pinLength);

  @override
  void dispose() {
    _pin.clear();
    super.dispose();
  }

  void _onDigit(String digit) {
    if (!_pin.appendDigit(digit)) return;
    if (_pin.isFull) {
      setState(() {});
      widget.onPinEntered(_pin);
      return;
    }
    setState(() {});
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(_pin.removeLast);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: PrismButton(
            label: context.l10n.back,
            onPressed: widget.onBack,
            icon: AppIcons.arrowBackIosNew,
            tone: PrismButtonTone.subtle,
          ),
        ),
        const SizedBox(height: 24),
        Icon(AppIcons.lockOutline, color: theme.colorScheme.primary, size: 40),
        const SizedBox(height: 16),
        Text(
          context.l10n.onboardingSyncEnterPassword,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.onboardingSyncEnterPasswordDescription,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        // PIN dot indicators
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_pinLength, (i) {
            final filled = i < _pin.length;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: filled
                      ? theme.colorScheme.primary
                      : theme.colorScheme.primary.withValues(alpha: 0.2),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 32),
        // Numpad — capped width so it doesn't spread across wide desktop
        // sheets, and wrapped in a keyboard listener so desktop users can
        // type digits directly.
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 296),
            child: NumpadKeyboardListener(
              onDigit: _onDigit,
              onBackspace: _onBackspace,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var row = 0; row < 4; row++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: _buildRow(row, theme),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildRow(int row, ThemeData theme) {
    if (row < 3) {
      return List.generate(3, (col) {
        final digit = '${row * 3 + col + 1}';
        return PinNumpadCell(
          label: digit,
          onTap: () => _onDigit(digit),
          theme: theme,
        );
      });
    }
    return [
      const SizedBox(width: 72, height: 72),
      PinNumpadCell(label: '0', onTap: () => _onDigit('0'), theme: theme),
      PinNumpadCell(
        icon: AppIcons.backspaceOutlined,
        onTap: _onBackspace,
        theme: theme,
      ),
    ];
  }
}

/// Success view after initiator completes pairing.
class _InitiatorDoneView extends StatelessWidget {
  const _InitiatorDoneView({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(
              PrismShapes.of(context).radius(12),
            ),
          ),
          child: Row(
            children: [
              Icon(AppIcons.checkCircle, color: Colors.green, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.l10n.syncSetupPairingComplete,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.green,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(
              PrismShapes.of(context).radius(12),
            ),
          ),
          child: Row(
            children: [
              Icon(
                AppIcons.infoOutline,
                color: theme.colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.l10n.syncSetupSnapshotNotice,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        PrismButton(
          label: context.l10n.done,
          icon: AppIcons.check,
          onPressed: onDone,
        ),
      ],
    );
  }
}

/// Error view for the initiator flow.
class _InitiatorErrorView extends StatelessWidget {
  const _InitiatorErrorView({required this.message, required this.onTryAgain});

  final String message;
  final VoidCallback onTryAgain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(AppIcons.errorOutline, color: theme.colorScheme.error, size: 40),
        const SizedBox(height: 16),
        Text(
          context.l10n.syncSetupPairingFailed,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          message,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        PrismButton(
          label: context.l10n.tryAgain,
          icon: AppIcons.refresh,
          tone: PrismButtonTone.subtle,
          onPressed: onTryAgain,
        ),
      ],
    );
  }
}

/// Progress card while the encrypted pairing snapshot streams to the relay.
///
/// Shows a linear progress bar driven by `SnapshotUploadProgress` events and
/// a human-readable label ("Uploading X of Y"). On `SnapshotUploadFailed`,
/// swaps the progress bar for a retry button.
class _InitiatorUploadingView extends StatelessWidget {
  const _InitiatorUploadingView({
    required this.bytesSent,
    required this.bytesTotal,
    required this.failureReason,
    required this.onRetry,
  });

  final int? bytesSent;
  final int? bytesTotal;
  final String? failureReason;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sent = bytesSent ?? 0;
    final total = bytesTotal ?? 0;
    final progress = total > 0 ? (sent / total).clamp(0.0, 1.0) : null;

    if (failureReason != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              AppIcons.errorOutline,
              color: theme.colorScheme.error,
              size: 40,
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.syncSetupSnapshotUploadFailedTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              failureReason!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            PrismButton(
              label: context.l10n.syncSetupSnapshotUploadRetry,
              icon: AppIcons.refresh,
              onPressed: onRetry,
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.syncSetupSnapshotUploadingTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(
              PrismShapes.of(context).radius(8),
            ),
            child: LinearProgressIndicator(value: progress, minHeight: 8),
          ),
          const SizedBox(height: 12),
          Text(
            total > 0
                ? context.l10n.syncSetupSnapshotUploadProgress(
                    humanBytes(sent),
                    humanBytes(total),
                  )
                : context.l10n.syncSetupSnapshotUploadStarting,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Brief "pairing ready" confirmation shown after the snapshot has been
/// uploaded and credentials exchanged, before routing back out of the sheet.
class _InitiatorUploadCompleteView extends StatelessWidget {
  const _InitiatorUploadCompleteView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.checkCircle, color: Colors.green, size: 40),
          const SizedBox(height: 16),
          Text(
            context.l10n.syncSetupPairingReadyTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.syncSetupPairingReadyWaiting,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
