import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/secure_scope.dart';

sealed class VerifyBackupResult {
  const VerifyBackupResult();
}

final class VerifyBackupMatchResult extends VerifyBackupResult {
  const VerifyBackupMatchResult({
    required this.mnemonic,
    required this.verifiedAt,
  });

  final String mnemonic;
  final DateTime verifiedAt;
}

final class VerifyBackupNoMatchResult extends VerifyBackupResult {
  const VerifyBackupNoMatchResult();
}

class VerifyBackupResultView extends StatefulWidget {
  const VerifyBackupResultView({
    super.key,
    required this.result,
    required this.onDone,
    required this.onTryDifferent,
    required this.onReenterPin,
  });

  final VerifyBackupResult result;
  final VoidCallback onDone;
  final VoidCallback onTryDifferent;
  final VoidCallback onReenterPin;

  @override
  State<VerifyBackupResultView> createState() => _VerifyBackupResultViewState();
}

class _VerifyBackupResultViewState extends State<VerifyBackupResultView> {
  String _formatDate(DateTime date) => DateFormat.yMMMd().format(date);

  String _maskedPhrase(String mnemonic) {
    final words = mnemonic.trim().split(RegExp(r'\s+'));
    if (words.length < 2) return mnemonic;
    return '${words.first} … ${words.last}';
  }

  Future<void> _onShareQr(VerifyBackupMatchResult matchResult) async {
    final l10n = context.l10n;
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: l10n.secretKeyShareDialogTitle,
      message: l10n.secretKeyShareDialogMessage,
      confirmLabel: l10n.secretKeyShareConfirm,
      destructive: true,
    );
    if (!confirmed) return;
    if (!mounted) return;

    final words = matchResult.mnemonic.trim().split(RegExp(r'\s+'));
    final numberedWords =
        words.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n');
    final backupText = l10n.secretKeyBackupFileText(
      numberedWords,
      DateTime.now().toIso8601String().split('T').first,
    );
    await SharePlus.instance.share(
      ShareParams(text: backupText, subject: l10n.secretKeyBackupSubject),
    );
  }

  @override
  Widget build(BuildContext context) {
    return switch (widget.result) {
      VerifyBackupMatchResult() =>
        _buildMatch(context, widget.result as VerifyBackupMatchResult),
      VerifyBackupNoMatchResult() => _buildNoMatch(context),
    };
  }

  Widget _buildMatch(BuildContext context, VerifyBackupMatchResult result) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final onSurface = theme.colorScheme.onSurface;

    return SecureScope(
      allowAndroidScreenCapture: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            label: '${l10n.verifyBackupSrAnnounceMatch}. ${l10n.verifyBackupMatchHeadline}',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  AppIcons.checkCircle,
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.verifyBackupMatchHeadline,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.verifyBackupMatchBody,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Text(
            _maskedPhrase(result.mnemonic),
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.verifyBackupVerifiedOn(_formatDate(result.verifiedAt)),
            style: theme.textTheme.bodySmall?.copyWith(
              color: onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Semantics(
              label: l10n.verifyBackupNoQrSemanticLabel,
              container: true,
              child: ExcludeSemantics(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.warmWhite,
                    borderRadius: BorderRadius.circular(
                      PrismShapes.of(context).radius(12),
                    ),
                  ),
                  child: QrImageView(
                    data: result.mnemonic,
                    version: QrVersions.auto,
                    size: 200,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: PrismButton(
                  label: l10n.verifyBackupDoneButton,
                  onPressed: widget.onDone,
                  tone: PrismButtonTone.filled,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PrismButton(
                  label: l10n.verifyBackupShareQrButton,
                  onPressed: () => _onShareQr(result),
                  tone: PrismButtonTone.subtle,
                  icon: AppIcons.share,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNoMatch(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return SecureScope(
      allowAndroidScreenCapture: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            label: '${l10n.verifyBackupSrAnnounceNoMatch}. ${l10n.verifyBackupNoMatchHeadline}',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  AppIcons.errorOutlineRounded,
                  color: theme.colorScheme.error,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.verifyBackupNoMatchHeadline,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.verifyBackupNoMatchBody,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          PrismButton(
            label: l10n.verifyBackupTryDifferentBackup,
            onPressed: widget.onTryDifferent,
            tone: PrismButtonTone.filled,
          ),
          const SizedBox(height: 12),
          PrismButton(
            label: l10n.verifyBackupReenterPin,
            onPressed: widget.onReenterPin,
            tone: PrismButtonTone.subtle,
          ),
        ],
      ),
    );
  }
}
