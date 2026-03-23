import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/constants/app_constants.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/shared/utils/sensitive_clipboard.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

/// Parsed result of a `createInvite` FFI call.
class _SyncInvite {
  const _SyncInvite({
    required this.qrPayload,
    required this.url,
    required this.words,
    required this.syncId,
    required this.relayUrl,
  });

  final Uint8List qrPayload;
  final String url;
  final List<String> words;
  final String syncId;
  final String relayUrl;

  factory _SyncInvite.fromJson(Map<String, dynamic> json) {
    final rawBytes = (json['qr_payload'] as List<dynamic>).cast<int>();
    return _SyncInvite(
      qrPayload: Uint8List.fromList(rawBytes),
      url: json['url'] as String,
      words: (json['words'] as List<dynamic>).cast<String>(),
      syncId: json['sync_id'] as String,
      relayUrl: json['relay_url'] as String,
    );
  }
}

class SetupDeviceSheet {
  static Future<void> show(BuildContext context, WidgetRef ref) async {
    final handle = ref.read(prismSyncHandleProvider).value;
    if (handle == null) {
      if (!context.mounted) return;
      PrismToast.error(context, message: 'Sync engine not available');
      return;
    }

    final relayUrl =
        await ref.read(relayUrlProvider.future) ?? AppConstants.defaultRelayUrl;

    if (!context.mounted) return;

    PrismSheet.showFullScreen(
      context: context,
      builder: (ctx, sc) => _SetupDeviceSheetContent(
        handle: handle,
        relayUrl: relayUrl,
        scrollController: sc,
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

class _SetupDeviceSheetContentState
    extends ConsumerState<_SetupDeviceSheetContent> {
  _SyncInvite? _invite;
  String? _error;
  bool _building = false;
  bool _showDetails = false;
  final _passwordController = TextEditingController();
  bool _passwordVisible = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _createInvite() async {
    final password = _passwordController.text.trim();
    if (password.isEmpty) {
      setState(() => _error = 'Please enter a sync password');
      return;
    }
    if (_building) return;

    setState(() {
      _building = true;
      _error = null;
    });

    try {
      // Use createInvite (NOT createSyncGroup) — this generates an invite
      // for the EXISTING sync group so the new device joins the same group.
      final jsonString = await ffi.createInvite(
        handle: widget.handle,
        password: password,
      );
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final joinerDeviceId = json['joiner_device_id'] as String?;
      final invite = _SyncInvite.fromJson(json);

      // createInvite may mutate Rust secure store state (e.g. epoch);
      // drain back to platform keychain to avoid credential loss.
      await drainRustStore(widget.handle);

      // Upload ephemeral snapshot for the new device to bootstrap from
      try {
        await ffi.uploadPairingSnapshot(
          handle: widget.handle,
          ttlSecs: BigInt.from(86400), // 24 hours
          forDeviceId: joinerDeviceId,
        );
      } catch (e) {
        // Non-fatal — new device can still sync incrementally
        debugPrint('[PAIRING] Snapshot upload failed (non-fatal): $e');
      }

      if (!mounted) return;
      setState(() {
        _invite = invite;
        _building = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _building = false;
      });
    }
  }

  void _reset() {
    setState(() {
      _invite = null;
      _error = null;
      _building = false;
      _showDetails = false;
      _passwordController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const PrismSheetTopBar(title: 'Set Up Another Device'),
        Expanded(
          child: SingleChildScrollView(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            child: _invite == null
                ? _PasswordPrompt(
                    controller: _passwordController,
                    passwordVisible: _passwordVisible,
                    onToggleVisibility: () =>
                        setState(() => _passwordVisible = !_passwordVisible),
                    isLoading: _building,
                    error: _error,
                    onSubmit: _createInvite,
                  )
                : _SetupResponseView(
                    invite: _invite!,
                    showDetails: _showDetails,
                    onToggleDetails: () =>
                        setState(() => _showDetails = !_showDetails),
                    onPairAnother: _reset,
                  ),
          ),
        ),
      ],
    );
  }
}

/// Simple password prompt — Device A enters the sync password,
/// then we create the invite and show the QR code.
class _PasswordPrompt extends StatelessWidget {
  const _PasswordPrompt({
    required this.controller,
    required this.passwordVisible,
    required this.onToggleVisibility,
    required this.isLoading,
    required this.error,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool passwordVisible;
  final VoidCallback onToggleVisibility;
  final bool isLoading;
  final String? error;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Enter a sync password for the new device. '
          'The other device will need this same password to join.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: controller,
          obscureText: !passwordVisible,
          decoration: InputDecoration(
            labelText: 'Sync password',
            suffixIcon: IconButton(
              icon: Icon(
                passwordVisible ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: onToggleVisibility,
            ),
          ),
          onSubmitted: (_) => onSubmit(),
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          Text(
            error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (isLoading)
          const Center(child: CircularProgressIndicator())
        else
          PrismButton(
            label: 'Generate QR Code',
            icon: Icons.qr_code,
            onPressed: onSubmit,
          ),
      ],
    );
  }
}

class _SetupResponseView extends StatelessWidget {
  const _SetupResponseView({
    required this.invite,
    required this.showDetails,
    required this.onToggleDetails,
    required this.onPairAnother,
  });

  final _SyncInvite invite;
  final bool showDetails;
  final VoidCallback onToggleDetails;
  final VoidCallback onPairAnother;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber, color: Colors.orange, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Anyone with this invite QR and your password can join the sync group.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.orange,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: QrImageView(
            data: invite.url,
            size: 220,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Scan this invite on the new device to finish pairing.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: theme.colorScheme.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'An encrypted snapshot will be temporarily uploaded and '
                  'automatically deleted after your new device connects '
                  '(or after 24 hours).',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        PrismButton(
          label: 'Copy Invite Link',
          icon: Icons.copy,
          onPressed: () async {
            await SensitiveClipboard.copy(invite.url);
            if (!context.mounted) return;
            PrismToast.show(
              context,
              message: 'Copied — clipboard will be cleared in 15 seconds',
            );
          },
        ),
        const SizedBox(height: 12),
        PrismButton(
          label: showDetails ? 'Hide Details' : 'Show Details',
          icon: showDetails ? Icons.visibility_off : Icons.visibility,
          onPressed: onToggleDetails,
        ),
        const SizedBox(height: 12),
        PrismButton(
          label: 'Pair Another Device',
          icon: Icons.qr_code_scanner,
          onPressed: onPairAnother,
        ),
        if (showDetails) ...[
          const SizedBox(height: 16),
          _CopiableField(label: 'Invite link', value: invite.url),
          const SizedBox(height: 12),
          _WordListField(words: invite.words),
          const SizedBox(height: 12),
          _CopiableField(label: 'Sync ID', value: invite.syncId),
        ],
      ],
    );
  }
}

class _WordListField extends StatelessWidget {
  const _WordListField({required this.words});

  final List<String> words;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wordString = words.join(' ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recovery words',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (int i = 0; i < words.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${i + 1}. ${words[i]}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () async {
            await SensitiveClipboard.copy(wordString);
            if (!context.mounted) return;
            PrismToast.show(
              context,
              message: 'Copied — clipboard will be cleared in 15 seconds',
            );
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.copy,
                size: 14,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 4),
              Text(
                'Copy all words',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CopiableField extends StatelessWidget {
  const _CopiableField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () async {
            await SensitiveClipboard.copy(value);
            if (!context.mounted) return;
            PrismToast.show(
              context,
              message: 'Copied — clipboard will be cleared in 15 seconds',
            );
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.5,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                Icon(
                  Icons.copy,
                  size: 16,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
