import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/utils/sensitive_clipboard.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_checkbox_row.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/secure_scope.dart';

class SecretKeyRevealContent extends StatefulWidget {
  const SecretKeyRevealContent({
    super.key,
    required this.mnemonic,
    required this.hasSaved,
    required this.onHasSavedChanged,
    this.showSaveConfirmation = true,
    this.requireInteraction = false,
  });

  final String mnemonic;
  final bool hasSaved;
  final ValueChanged<bool> onHasSavedChanged;

  /// Whether to show the "I have saved my Secret Key" checkbox.
  /// Set to false when viewing an existing key (not during initial setup).
  final bool showSaveConfirmation;

  /// When true, the "I have saved my Secret Key" checkbox is disabled until
  /// the user has interacted with at least one backup method (copy, share, or QR).
  final bool requireInteraction;

  @override
  State<SecretKeyRevealContent> createState() => _SecretKeyRevealContentState();
}

class _SecretKeyRevealContentState extends State<SecretKeyRevealContent> {
  bool _showQr = false;
  bool _hasInteracted = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final words = widget.mnemonic.split(' ');

    return SecureScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(12)),
            ),
            child: Row(
              children: [
                Icon(
                  AppIcons.warningRounded,
                  color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Save this now. This is the ONLY way to add new devices or '
                    'change your PIN. It is not stored on this phone and it '
                    'cannot be recovered if lost.\n\n'
                    'Save it to a password manager AND on paper — do not keep '
                    'the only copy on this phone.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(12)),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (var i = 0; i < words.length; i++)
                  Chip(
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      '${i + 1}. ${words[i]}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                      ),
                    ),
                    backgroundColor: theme.colorScheme.surfaceContainerLow,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: PrismButton(
                  onPressed: _copyToClipboard,
                  icon: AppIcons.copy,
                  label: 'Copy',
                  tone: PrismButtonTone.subtle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PrismButton(
                  onPressed: _shareBackup,
                  icon: AppIcons.share,
                  label: 'Save Backup',
                  tone: PrismButtonTone.subtle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          PrismButton(
            onPressed: () => setState(() {
              _showQr = !_showQr;
              if (_showQr && !_hasInteracted) _hasInteracted = true;
            }),
            icon: _showQr ? AppIcons.visibilityOff : AppIcons.qrCode,
            label: _showQr ? 'Hide QR Code' : 'Show QR Code',
            tone: PrismButtonTone.subtle,
          ),
          if (_showQr) ...[
            const SizedBox(height: 16),
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.warmWhite,
                  borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(12)),
                ),
                child: QrImageView(
                  data: widget.mnemonic,
                  version: QrVersions.auto,
                  size: 200,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Scan from another device to transfer your Secret Key',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (widget.showSaveConfirmation) ...[
            const SizedBox(height: 32),
            PrismCheckboxRow(
              checkboxAffinity: PrismCheckboxAffinity.leading,
              value: widget.hasSaved,
              onChanged: widget.onHasSavedChanged,
              enabled: !(widget.requireInteraction && !_hasInteracted),
              title: const Text('I have saved my Secret Key'),
              padding: EdgeInsets.zero,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _copyToClipboard() async {
    await SensitiveClipboard.copy(widget.mnemonic);
    if (!_hasInteracted) setState(() => _hasInteracted = true);
    if (mounted) {
      PrismToast.show(
        context,
        message: 'Copied — clipboard will be cleared in 15 seconds',
      );
    }
  }

  Future<void> _shareBackup() async {
    // Require explicit confirmation before exposing the key via the share sheet.
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: 'Share Secret Key?',
      message:
          'You are about to share your 12-word Secret Key using the system share sheet.\n\n'
          'Anyone who receives this text \u2014 including cloud storage apps, messaging '
          'apps, or clipboard sync services \u2014 can use it to access your data.\n\n'
          'Only share to a secure, private destination you control, such as a '
          'password manager or an encrypted notes app.',
      confirmLabel: 'Share Anyway',
      destructive: true,
    );

    if (!confirmed) return;

    final words = widget.mnemonic.split(' ');
    final numberedWords = words
        .asMap()
        .entries
        .map((e) => '${e.key + 1}. ${e.value}')
        .join('\n');
    final backupText =
        '''Prism Secret Key Backup
========================

Your Secret Key (12-word recovery phrase):

$numberedWords

IMPORTANT:
- Store this in a safe place — you will need it to set up new devices.
- Anyone with this phrase AND your password can access your data.
- Prism cannot recover this key if lost.

Generated: ${DateTime.now().toIso8601String().split('T').first}
''';
    await SharePlus.instance.share(
      ShareParams(text: backupText, subject: 'Prism Secret Key Backup'),
    );
    if (!_hasInteracted) setState(() => _hasInteracted = true);
    widget.onHasSavedChanged(true);
  }
}
