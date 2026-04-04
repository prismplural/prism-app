import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/utils/sensitive_clipboard.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
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
  });

  final String mnemonic;
  final bool hasSaved;
  final ValueChanged<bool> onHasSavedChanged;

  /// Whether to show the "I have saved my Secret Key" checkbox.
  /// Set to false when viewing an existing key (not during initial setup).
  final bool showSaveConfirmation;

  @override
  State<SecretKeyRevealContent> createState() => _SecretKeyRevealContentState();
}

class _SecretKeyRevealContentState extends State<SecretKeyRevealContent> {
  bool _showQr = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final words = widget.mnemonic.split(' ');

    return SecureScope(child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(12),
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
                  'Save this key now. You\'ll need it to set up new devices. '
                  'Prism cannot recover it if lost.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        Text(
          'Your 12-word recovery phrase:',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < words.length; i++)
                Chip(
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
                tone: PrismButtonTone.outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PrismButton(
                onPressed: _shareBackup,
                icon: AppIcons.share,
                label: 'Save Backup',
                tone: PrismButtonTone.outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        PrismButton(
          onPressed: () => setState(() => _showQr = !_showQr),
          icon: _showQr ? AppIcons.visibilityOff : AppIcons.qrCode,
          label: _showQr ? 'Hide QR Code' : 'Show QR Code',
          tone: PrismButtonTone.outlined,
        ),
        if (_showQr) ...[
          const SizedBox(height: 16),
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.warmWhite,
                borderRadius: BorderRadius.circular(12),
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
          PrismListRow(
            leading: Checkbox(
              value: widget.hasSaved,
              onChanged: (v) => widget.onHasSavedChanged(v ?? false),
            ),
            title: const Text('I have saved my Secret Key'),
            padding: EdgeInsets.zero,
            onTap: () => widget.onHasSavedChanged(!widget.hasSaved),
          ),
        ],
      ],
    ));
  }

  Future<void> _copyToClipboard() async {
    await SensitiveClipboard.copy(widget.mnemonic);
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
      message: 'You are about to share your 12-word Secret Key using the system share sheet.\n\n'
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
    final backupText = '''Prism Secret Key Backup
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
    widget.onHasSavedChanged(true);
  }
}
