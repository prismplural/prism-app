import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/constants/app_constants.dart';
import 'package:prism_plurality/core/crypto/bip39_validate.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/security/pin_buffer.dart';
import 'package:prism_plurality/core/sync/pairing_ceremony_api.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_event_loop.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/utils/human_bytes.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_mnemonic_field.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:prism_plurality/shared/widgets/secure_scope.dart';

class SetupDeviceSheet {
  static Future<void> show(BuildContext context, WidgetRef ref) async {
    final handle = ref.read(prismSyncHandleProvider).value;
    if (handle == null) {
      if (!context.mounted) return;
      PrismToast.error(context, message: context.l10n.syncEngineNotAvailable);
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
      _SetupDeviceSheetContentState();
}

enum _InitiatorStep {
  enterMnemonic,
  prompt,
  scanning,
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

class _SetupDeviceSheetContentState
    extends ConsumerState<_SetupDeviceSheetContent> {
  _InitiatorStep _step = _InitiatorStep.enterMnemonic;
  bool _joinerScanned = false;
  String? _sasWords;
  String? _sasDecimal;
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

  // Recovery phrase typed by the user; required because the mnemonic is
  // never persisted in the keychain. Zeroed on dispose.
  String? _mnemonic;

  MobileScannerController _ensureJoinerScanner() {
    return _joinerScannerController ??= MobileScannerController();
  }

  @override
  void dispose() {
    _joinerScannerController?.dispose();
    _uploadEventSubscription?.close();
    _uploadEventSubscription = null;
    _mnemonic = null;
    super.dispose();
  }

  void _reset() {
    _joinerScannerController?.dispose();
    _joinerScannerController = null;
    _uploadEventSubscription?.close();
    _uploadEventSubscription = null;
    setState(() {
      _step = _InitiatorStep.enterMnemonic;
      _joinerScanned = false;
      _sasWords = null;
      _sasDecimal = null;
      _joinerDeviceId = null;
      _uploadBytesSent = null;
      _uploadBytesTotal = null;
      _uploadFailureReason = null;
      _error = null;
      _mnemonic = null;
    });
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
      final sasWords = json['sas_words'] as String;
      final sasDecimal = json['sas_decimal'] as String;
      // Captured for uploadPairingSnapshot(forDeviceId:) in _completeInitiator.
      // May be absent on older Rust builds; threading it through lets the
      // joiner DELETE the snapshot once it has applied the bootstrap.
      final joinerDeviceId = json['joiner_device_id'] as String?;

      if (!mounted) return;
      setState(() {
        _sasWords = sasWords;
        _sasDecimal = sasDecimal;
        _joinerDeviceId = joinerDeviceId;
        _step = _InitiatorStep.sasVerification;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _step = _InitiatorStep.error;
      });
    }
  }

  Future<void> _completeInitiator(String pin) async {
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
      await pairingApi.completeInitiatorCeremony(
        handle: widget.handle,
        password: pin,
        mnemonic: mnemonic,
      );

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
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _step = _InitiatorStep.error;
      });
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
      _step = _InitiatorStep.prompt;
    });
  }

  Widget _buildContent() {
    return switch (_step) {
      _InitiatorStep.enterMnemonic => _MnemonicEntryView(
        initialError: _error,
        onSubmit: _onMnemonicSubmitted,
      ),
      _InitiatorStep.prompt => _ScanJoinerPrompt(
        onStartScan: () => setState(() => _step = _InitiatorStep.scanning),
      ),
      _InitiatorStep.scanning => _JoinerQrScannerView(
        ensureScanner: _ensureJoinerScanner,
        scanned: _joinerScanned,
        error: _error,
        onBack: _reset,
        onScanned: (bytes) {
          setState(() => _joinerScanned = true);
          _startInitiatorCeremony(bytes);
        },
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
        sasDecimal: _sasDecimal!,
        onConfirm: () => setState(() => _step = _InitiatorStep.passwordEntry),
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
  const _ScanJoinerPrompt({required this.onStartScan});

  final VoidCallback onStartScan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.syncSetupScanJoinerPrompt,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        PrismButton(
          label: context.l10n.syncSetupScanJoinerButton,
          icon: AppIcons.qrCodeScanner,
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
  });

  final MobileScannerController Function() ensureScanner;
  final bool scanned;
  final String? error;
  final VoidCallback onBack;
  final void Function(Uint8List bytes) onScanned;

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

/// Shows SAS words for the initiator to verify with the joiner.
class _SasVerificationView extends StatelessWidget {
  const _SasVerificationView({
    required this.sasWords,
    required this.sasDecimal,
    required this.onConfirm,
    required this.onReject,
  });

  final String sasWords;
  final String sasDecimal;
  final VoidCallback onConfirm;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final words = sasWords.split(' ');

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
                children: words
                    .map(
                      (word) => Text(
                        word,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              Text(
                sasDecimal,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  fontFamily: 'monospace',
                  letterSpacing: 2,
                ),
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

  final void Function(String pin) onPinEntered;
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
      final pin = _pin.consumeStringAndClear();
      setState(() {});
      widget.onPinEntered(pin);
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
        // Numpad
        for (var row = 0; row < 4; row++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _buildRow(row, theme),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildRow(int row, ThemeData theme) {
    if (row < 3) {
      return List.generate(3, (col) {
        final digit = '${row * 3 + col + 1}';
        return _InitiatorNumpadButton(
          label: digit,
          onTap: () => _onDigit(digit),
          theme: theme,
        );
      });
    }
    return [
      const SizedBox(width: 72, height: 72),
      _InitiatorNumpadButton(
        label: '0',
        onTap: () => _onDigit('0'),
        theme: theme,
      ),
      _InitiatorNumpadButton(
        icon: AppIcons.backspaceOutlined,
        onTap: _onBackspace,
        theme: theme,
      ),
    ];
  }
}

class _InitiatorNumpadButton extends StatelessWidget {
  const _InitiatorNumpadButton({
    this.label,
    this.icon,
    required this.onTap,
    required this.theme,
  });

  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 72,
        height: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.colorScheme.primary.withValues(alpha: 0.08),
        ),
        child: label != null
            ? Text(
                label!,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                ),
              )
            : Icon(icon, size: 24, color: theme.colorScheme.onSurface),
      ),
    );
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
