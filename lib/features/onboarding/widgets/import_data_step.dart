import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/features/data_management/providers/data_management_providers.dart';
import 'package:prism_plurality/features/data_management/services/data_import_service.dart';
import 'package:prism_plurality/features/data_management/services/export_crypto.dart';
import 'package:prism_plurality/features/onboarding/models/onboarding_data_counts.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/migration/providers/migration_providers.dart';
import 'package:prism_plurality/features/migration/services/sp_importer.dart'
    as sp_importer;
import 'package:prism_plurality/features/migration/widgets/custom_front_disposition_step.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_field_icon_button.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';

/// Import Data step — lets user choose between PluralKit, Simply Plural,
/// or skipping entirely (default: no import selected).
class ImportDataStep extends ConsumerStatefulWidget {
  const ImportDataStep({super.key});

  @override
  ConsumerState<ImportDataStep> createState() => _ImportDataStepState();
}

enum _ImportSource { none, pluralKit, prismExport, simplyPlural }

class _ImportDataStepState extends ConsumerState<ImportDataStep> {
  _ImportSource _selected = _ImportSource.none;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: switch (_selected) {
        _ImportSource.none => _SourcePicker(
          key: const ValueKey('picker'),
          onSelect: (source) {
            setState(() => _selected = source);
          },
        ),
        _ImportSource.pluralKit => _PluralKitImportFlow(
          key: const ValueKey('pk'),
          onBack: () => setState(() => _selected = _ImportSource.none),
        ),
        _ImportSource.prismExport => _PrismExportImportFlow(
          key: const ValueKey('prism-export'),
          onBack: () => setState(() => _selected = _ImportSource.none),
        ),
        _ImportSource.simplyPlural => _SimplyPluralImportFlow(
          key: const ValueKey('sp'),
          onBack: () => setState(() => _selected = _ImportSource.none),
        ),
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Source picker (default view)
// ---------------------------------------------------------------------------

class _SourcePicker extends StatelessWidget {
  const _SourcePicker({
    super.key,
    required this.onSelect,
  });

  final void Function(_ImportSource) onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Text(
            context.l10n.onboardingImportDataSourcePickerIntro,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDark
                  ? AppColors.mutedTextDark
                  : AppColors.mutedTextLight,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          _SourceCard(
            icon: AppIcons.sync,
            color: Colors.cyan,
            title: context.l10n.onboardingImportPluralKit,
            description: context.l10n.onboardingImportPluralKitDescription,
            onTap: () => onSelect(_ImportSource.pluralKit),
          ),
          const SizedBox(height: 16),
          _SourceCard(
            icon: AppIcons.inventoryOutlined,
            color: Colors.green,
            title: context.l10n.onboardingImportPrismExport,
            description: context.l10n.onboardingImportPrismExportDescription,
            onTap: () => onSelect(_ImportSource.prismExport),
          ),
          const SizedBox(height: 16),
          _SourceCard(
            icon: AppIcons.fileUploadOutlined,
            color: Colors.deepPurple,
            title: context.l10n.onboardingImportSimplyPlural,
            description: context.l10n.onboardingImportSimplyPluralDescription,
            onTap: () => onSelect(_ImportSource.simplyPlural),
          ),
          const SizedBox(height: 32),
          Text(
            context.l10n.onboardingImportLaterHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: isDark
                  ? AppColors.warmWhite.withValues(alpha: 0.5)
                  : AppColors.warmBlack.withValues(alpha: 0.5),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SourceCard extends StatefulWidget {
  const _SourceCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  State<_SourceCard> createState() => _SourceCardState();
}

class _SourceCardState extends State<_SourceCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _pressed
                ? (isDark
                      ? AppColors.warmWhite.withValues(alpha: 0.25)
                      : AppColors.warmBlack.withValues(alpha: 0.12))
                : (isDark
                      ? AppColors.warmWhite.withValues(alpha: 0.12)
                      : AppColors.parchmentElevated),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _pressed
                  ? primary.withValues(alpha: 0.5)
                  : (isDark
                        ? AppColors.warmWhite.withValues(alpha: 0.1)
                        : AppColors.warmBlack.withValues(alpha: 0.1)),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: primary.withValues(alpha: 0.15),
                ),
                child: Icon(widget.icon, color: primary, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppColors.warmWhite
                            : AppColors.warmBlack,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.mutedTextDark
                            : AppColors.mutedTextLight,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                AppIcons.chevronRight,
                color: isDark
                    ? AppColors.warmWhite.withValues(alpha: 0.4)
                    : AppColors.warmBlack.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PluralKit import flow
// ---------------------------------------------------------------------------

class _PluralKitImportFlow extends ConsumerStatefulWidget {
  const _PluralKitImportFlow({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  ConsumerState<_PluralKitImportFlow> createState() =>
      _PluralKitImportFlowState();
}

class _PluralKitImportFlowState extends ConsumerState<_PluralKitImportFlow> {
  final _tokenController = TextEditingController();
  bool _obscureToken = true;
  bool _isImporting = false;
  bool _importSuccess = false;
  String? _errorMessage;
  int _importedCount = 0;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Back to source picker
          Align(
            alignment: Alignment.centerLeft,
            child: _BackLink(onTap: widget.onBack),
          ),
          const SizedBox(height: 16),

          // Instructions
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.warmWhite.withValues(alpha: 0.1)
                  : AppColors.parchmentElevated,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.onboardingPluralKitHowToGetToken,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.warmWhite.withValues(alpha: 0.9)
                        : AppColors.warmBlack.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 8),
                _InstructionRow(number: '1', text: context.l10n.onboardingPluralKitStep1),
                _InstructionRow(
                  number: '2',
                  text: context.l10n.onboardingPluralKitStep2,
                ),
                _InstructionRow(
                  number: '3',
                  text: context.l10n.onboardingPluralKitStep3,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Token field
          Container(
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.warmWhite.withValues(alpha: 0.1)
                  : AppColors.parchmentElevated,
              borderRadius: BorderRadius.circular(12),
            ),
            child: PrismTextField(
              controller: _tokenController,
              obscureText: _obscureToken,
              style: TextStyle(
                color: isDark ? AppColors.warmWhite : AppColors.warmBlack,
              ),
              hintText: context.l10n.onboardingPluralKitTokenHint,
              hintStyle: TextStyle(
                color: isDark
                    ? AppColors.warmWhite.withValues(alpha: 0.35)
                    : AppColors.warmBlack.withValues(alpha: 0.35),
              ),
              fieldStyle: PrismTextFieldStyle.borderless,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              suffix: PrismFieldIconButton(
                icon: _obscureToken
                    ? AppIcons.visibilityOff
                    : AppIcons.visibility,
                color: isDark
                    ? AppColors.warmWhite.withValues(alpha: 0.75)
                    : AppColors.warmBlack.withValues(alpha: 0.75),
                tooltip: _obscureToken ? context.l10n.showToken : context.l10n.hideToken,
                onPressed: () => setState(() => _obscureToken = !_obscureToken),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Import button or success
          if (_importSuccess)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(AppIcons.checkCircle, color: Colors.green),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.l10n.onboardingPluralKitImportSuccess(_importedCount),
                      style: TextStyle(
                        color: isDark
                            ? AppColors.warmWhite
                            : AppColors.warmBlack,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            _ActionButton(
              label: context.l10n.onboardingPluralKitImportButton,
              color: primary,
              isLoading: _isImporting,
              onPressed: _handleImport,
            ),

          // Error
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _handleImport() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _errorMessage = context.l10n.onboardingPluralKitErrorEnterToken);
      return;
    }

    setState(() {
      _isImporting = true;
      _errorMessage = null;
    });

    try {
      final pkNotifier = ref.read(pluralKitSyncProvider.notifier);
      await pkNotifier.setToken(token);

      final connected = await pkNotifier.testConnection();
      if (!connected) {
        // Clear the invalid token so it doesn't persist
        await pkNotifier.clearToken();
        setState(() {
          _isImporting = false;
          _errorMessage = context.l10n.onboardingPluralKitErrorCouldNotConnect;
        });
        return;
      }

      // importMembersOnly() already creates/updates members in the DB via the
      // sync service's _importMembers helper (which deduplicates by PK UUID).
      // We intentionally do NOT create members again here — the previous code
      // duplicated every PK member on each import because createMember() does
      // not set pluralkitUuid, so the service's dedup couldn't catch them.
      final (systemName, importedMembers) = await pkNotifier
          .importMembersOnly();

      if (systemName != null && systemName.isNotEmpty) {
        ref.read(onboardingProvider.notifier).setSystemName(systemName);
      }
      ref.read(onboardingProvider.notifier).setWasImportedFromPluralKit(true);

      setState(() {
        _isImporting = false;
        _importSuccess = true;
        _importedCount = importedMembers.length;
      });
    } catch (e) {
      setState(() {
        _isImporting = false;
        _errorMessage = context.l10n.onboardingImportError(e);
      });
    }
  }
}

// ---------------------------------------------------------------------------
// Prism export import flow
// ---------------------------------------------------------------------------

enum _PrismExportStep { idle, password, decrypting, preview, importing, error }

class _PrismExportImportFlow extends ConsumerStatefulWidget {
  const _PrismExportImportFlow({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  ConsumerState<_PrismExportImportFlow> createState() =>
      _PrismExportImportFlowState();
}

class _PrismExportImportFlowState
    extends ConsumerState<_PrismExportImportFlow> {
  _PrismExportStep _step = _PrismExportStep.idle;
  String? _errorMessage;
  String? _jsonContent;
  List<({String mediaId, Uint8List blob})> _mediaBlobs = const [];
  Uint8List? _fileBytes;
  ImportPreview? _preview;

  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String? _passwordError;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'prism'],
        withData: false,
        withReadStream: false,
      );
      if (result == null || result.files.isEmpty) return;

      final path = result.files.single.path;
      if (path == null) return;

      final bytes = await File(path).readAsBytes();
      if (!mounted) return;

      if (ExportCrypto.isEncrypted(bytes)) {
        setState(() {
          _step = _PrismExportStep.password;
          _fileBytes = bytes;
          _passwordError = null;
          _errorMessage = null;
        });
        return;
      }

      final service = ref.read(dataImportServiceProvider);
      final resolved = DataImportService.resolveBytes(bytes);
      final preview = service.parsePreview(resolved.json);

      setState(() {
        _step = _PrismExportStep.preview;
        _jsonContent = resolved.json;
        _mediaBlobs = resolved.mediaBlobs;
        _preview = preview;
        _errorMessage = null;
      });
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _PrismExportStep.error;
        _errorMessage = e.message.toString();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _PrismExportStep.error;
        _errorMessage = context.l10n.onboardingImportReadFileFailed(e);
      });
    }
  }

  Future<void> _unlockFile() async {
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _passwordError = context.l10n.onboardingImportPasswordEmpty);
      return;
    }
    setState(() {
      _step = _PrismExportStep.decrypting;
      _passwordError = null;
    });
    final bytes = _fileBytes!;
    final pass = password;
    try {
      final resolved = await Isolate.run(
        () => DataImportService.resolveBytes(bytes, password: pass),
      );
      final service = ref.read(dataImportServiceProvider);
      final preview = service.parsePreview(resolved.json);
      if (!mounted) return;
      setState(() {
        _step = _PrismExportStep.preview;
        _jsonContent = resolved.json;
        _mediaBlobs = resolved.mediaBlobs;
        _preview = preview;
        _passwordError = null;
      });
    } on FormatException catch (e) {
      if (!mounted) return;
      final msg = e.message;
      setState(() {
        _step = _PrismExportStep.password;
        _passwordError = msg == 'unencrypted-prism-backup'
            ? context.l10n.onboardingImportUnencryptedBackup
            : msg.contains('mac check') || msg.contains('wrong')
                ? context.l10n.onboardingImportIncorrectPassword
                : context.l10n.onboardingImportDecryptionFailed(msg);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _PrismExportStep.password;
        _passwordError = context.l10n.onboardingImportDecryptionFailed(e.toString());
      });
    }
  }

  Future<void> _startImport() async {
    final jsonContent = _jsonContent;
    final preview = _preview;
    if (jsonContent == null) return;

    setState(() => _step = _PrismExportStep.importing);

    try {
      final service = ref.read(dataImportServiceProvider);
      await service.importData(
        jsonContent,
        mediaBlobs: _mediaBlobs,
        preserveImportedOnboardingState: false,
      );
      if (!mounted) return;

      setState(() {
        _fileBytes = null;
        _jsonContent = null;
        _mediaBlobs = const [];
        _passwordController.clear();
      });
      ref
          .read(onboardingProvider.notifier)
          .showImportedDataReady(
            OnboardingDataCounts(
              members: preview?.headmates ?? 0,
              frontingSessions: preview?.frontSessions ?? 0,
              conversations: preview?.conversations ?? 0,
              messages: preview?.messages ?? 0,
              habits: preview?.habits ?? 0,
              notes: preview?.notes ?? 0,
            ),
          );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _PrismExportStep.error;
        _errorMessage = context.l10n.onboardingImportError(e);
      });
    }
  }

  void _reset() {
    setState(() {
      _step = _PrismExportStep.idle;
      _errorMessage = null;
      _jsonContent = null;
      _fileBytes = null;
      _mediaBlobs = const [];
      _preview = null;
      _passwordError = null;
      _passwordController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_step != _PrismExportStep.importing && _step != _PrismExportStep.decrypting)
            Align(
              alignment: Alignment.centerLeft,
              child: _BackLink(onTap: widget.onBack),
            ),
          const SizedBox(height: 16),
          switch (_step) {
            _PrismExportStep.idle => _buildIdle(),
            _PrismExportStep.password => _buildPassword(),
            _PrismExportStep.decrypting => _buildImporting(),
            _PrismExportStep.preview => _buildPreview(),
            _PrismExportStep.importing => _buildImporting(),
            _PrismExportStep.error => _buildError(),
          },
        ],
      ),
    );
  }

  Widget _buildIdle() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.warmWhite.withValues(alpha: 0.1)
                : AppColors.parchmentElevated,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.onboardingPrismExportHowToExport,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.warmWhite : AppColors.warmBlack,
                ),
              ),
              const SizedBox(height: 8),
              _InstructionRow(
                number: '1',
                text: context.l10n.onboardingPrismExportStep1,
              ),
              _InstructionRow(
                number: '2',
                text: context.l10n.onboardingPrismExportStep2,
              ),
              _InstructionRow(
                number: '3',
                text: context.l10n.onboardingPrismExportStep3,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _ActionButton(
          label: context.l10n.onboardingPrismExportSelectFile,
          color: primary,
          onPressed: _pickFile,
        ),
      ],
    );
  }

  Widget _buildPassword() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          AppIcons.lockOutline,
          color: isDark ? AppColors.warmWhite : AppColors.warmBlack,
          size: 48,
        ),
        const SizedBox(height: 16),
        Text(
          context.l10n.onboardingPrismExportEncryptedTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: isDark ? AppColors.warmWhite : AppColors.warmBlack,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.onboardingPrismExportEncryptedDescription,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: isDark ? AppColors.mutedTextDark : AppColors.mutedTextLight,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Container(
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.warmWhite.withValues(alpha: 0.1)
                : AppColors.parchmentElevated,
            borderRadius: BorderRadius.circular(12),
          ),
          child: PrismTextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            style: TextStyle(
              color: isDark ? AppColors.warmWhite : AppColors.warmBlack,
            ),
            autofocus: true,
            onSubmitted: (_) => _unlockFile(),
            hintText: context.l10n.onboardingPrismExportPasswordHint,
            hintStyle: TextStyle(
              color: isDark
                  ? AppColors.warmWhite.withValues(alpha: 0.35)
                  : AppColors.warmBlack.withValues(alpha: 0.35),
            ),
            errorText: _passwordError,
            fieldStyle: PrismTextFieldStyle.borderless,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            suffix: PrismFieldIconButton(
              icon: _obscurePassword
                  ? AppIcons.visibilityOff
                  : AppIcons.visibility,
              color: isDark
                  ? AppColors.warmWhite.withValues(alpha: 0.75)
                  : AppColors.warmBlack.withValues(alpha: 0.75),
              tooltip: _obscurePassword ? context.l10n.showPassword : context.l10n.hidePassword,
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        const SizedBox(height: 24),
        _ActionButton(
          label: context.l10n.onboardingPrismExportUnlockButton,
          color: primary,
          onPressed: _unlockFile,
        ),
      ],
    );
  }

  Widget _buildPreview() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    final preview = _preview!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.warmWhite.withValues(alpha: 0.1)
                : AppColors.parchmentElevated,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.onboardingPrismExportReadyToImport,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.warmWhite.withValues(alpha: 0.9)
                      : AppColors.warmBlack.withValues(alpha: 0.9),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.onboardingPrismExportPreviewDescription,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isDark
                      ? AppColors.mutedTextDark
                      : AppColors.mutedTextLight,
                ),
              ),
              const SizedBox(height: 12),
              _PreviewRow(label: context.l10n.onboardingImportPreviewMembers, count: preview.headmates),
              _PreviewRow(
                label: context.l10n.onboardingImportPreviewFrontingSessions,
                count: preview.frontSessions,
              ),
              _PreviewRow(label: context.l10n.onboardingImportPreviewConversations, count: preview.conversations),
              _PreviewRow(label: context.l10n.onboardingImportPreviewMessages, count: preview.messages),
              _PreviewRow(label: context.l10n.onboardingImportPreviewHabits, count: preview.habits),
              _PreviewRow(label: context.l10n.onboardingImportPreviewNotes, count: preview.notes),
              Divider(
                color: isDark
                    ? const Color(0x22FFFFFF)
                    : const Color(0x22000000),
                height: 24,
              ),
              _PreviewRow(label: context.l10n.onboardingImportPreviewTotalRecords, count: preview.totalRecords),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _ActionButton(
          label: context.l10n.onboardingPrismExportImportButton,
          color: primary,
          onPressed: _startImport,
        ),
      ],
    );
  }

  Widget _buildImporting() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppColors.warmWhite : AppColors.warmBlack;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            PrismSpinner(
              color: textColor,
              size: 52,
              dotCount: 8,
              duration: const Duration(milliseconds: 3000),
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.onboardingPrismExportImporting,
              style: TextStyle(color: textColor),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(AppIcons.errorOutline, color: Colors.red),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _errorMessage ?? 'Import failed.',
                  style: TextStyle(
                    color: isDark ? AppColors.warmWhite : AppColors.warmBlack,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ActionButton(
          label: context.l10n.tryAgain,
          color: Colors.redAccent,
          onPressed: _reset,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Simply Plural import flow
// ---------------------------------------------------------------------------

class _SimplyPluralImportFlow extends ConsumerStatefulWidget {
  const _SimplyPluralImportFlow({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  ConsumerState<_SimplyPluralImportFlow> createState() =>
      _SimplyPluralImportFlowState();
}

class _SimplyPluralImportFlowState
    extends ConsumerState<_SimplyPluralImportFlow> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    final textColor = isDark ? AppColors.warmWhite : AppColors.warmBlack;
    final migration = ref.watch(importerProvider);

    // When the SP import completes and the file carried a system name,
    // seed the onboarding system-name field so the user doesn't have to
    // retype something they already set in Simply Plural.
    ref.listen(importerProvider, (prev, next) {
      final justCompleted = prev?.step != sp_importer.ImportState.complete &&
          next.step == sp_importer.ImportState.complete;
      if (!justCompleted) return;
      final name = next.exportData?.systemName?.trim();
      if (name == null || name.isEmpty) return;
      ref.read(onboardingProvider.notifier).setSystemName(name);
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Back to source picker
          if (migration.step == sp_importer.ImportState.idle)
            Align(
              alignment: Alignment.centerLeft,
              child: _BackLink(onTap: widget.onBack),
            ),
          const SizedBox(height: 16),

          // Instructions
          if (migration.step == sp_importer.ImportState.idle) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.warmWhite.withValues(alpha: 0.1)
                    : AppColors.parchmentElevated,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.onboardingSimplyPluralHowToExport,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.warmWhite.withValues(alpha: 0.9)
                          : AppColors.warmBlack.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _InstructionRow(
                    number: '1',
                    text: context.l10n.onboardingSimplyPluralStep1,
                  ),
                  _InstructionRow(
                    number: '2',
                    text: context.l10n.onboardingSimplyPluralStep2,
                  ),
                  _InstructionRow(
                    number: '3',
                    text: context.l10n.onboardingSimplyPluralStep3,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _ActionButton(
              label: context.l10n.onboardingSimplyPluralSelectFile,
              color: primary,
              onPressed: () {
                ref.read(importerProvider.notifier).selectAndParseFile();
              },
            ),
          ],

          // Parsing
          if (migration.step == sp_importer.ImportState.parsing)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    PrismSpinner(
                      color: textColor,
                      size: 52,
                      dotCount: 8,
                      duration: const Duration(milliseconds: 3000),
                    ),
                    const SizedBox(height: 16),
                    Text(context.l10n.onboardingSimplyPluralReadingFile, style: TextStyle(color: textColor)),
                  ],
                ),
              ),
            ),

          // Preview
          if (migration.step == sp_importer.ImportState.previewing &&
              migration.exportData != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.warmWhite.withValues(alpha: 0.1)
                    : AppColors.parchmentElevated,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.onboardingSimplyPluralFoundData,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.warmWhite.withValues(alpha: 0.9)
                          : AppColors.warmBlack.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _PreviewRow(
                    label: context.l10n.onboardingImportPreviewMembers,
                    count:
                        migration.exportData!.members.length +
                        migration.exportData!.customFronts.length,
                  ),
                  _PreviewRow(
                    label: context.l10n.onboardingImportPreviewFrontingSessions,
                    count: migration.exportData!.frontHistory.length,
                  ),
                  _PreviewRow(
                    label: context.l10n.onboardingImportPreviewConversations,
                    count: migration.exportData!.channels.length,
                  ),
                  _PreviewRow(
                    label: context.l10n.onboardingImportPreviewMessages,
                    count: migration.exportData!.messages.length,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _ActionButton(
              label: context.l10n.onboardingSimplyPluralImportButton,
              color: primary,
              onPressed: () {
                ref.read(importerProvider.notifier).proceedFromPreview();
              },
            ),
          ],

          // Custom-front disposition step — lets the user pick per-CF how to
          // handle SP "custom fronts" (import as member, merge as note,
          // convert to sleep, skip). Only appears when the export has CFs.
          if (migration.step == sp_importer.ImportState.chooseDispositions &&
              migration.exportData != null)
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.75,
              child: CustomFrontDispositionStep(data: migration.exportData!),
            ),

          // Importing / downloading avatars
          if (migration.step == sp_importer.ImportState.importing ||
              migration.step == sp_importer.ImportState.downloadingAvatars) ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    PrismSpinner(
                      color: textColor,
                      size: 52,
                      dotCount: 8,
                      duration: const Duration(milliseconds: 3000),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      migration.progressLabel.isNotEmpty
                          ? migration.progressLabel
                          : 'Importing... ${(migration.progress * 100).toStringAsFixed(0)}%',
                      style: TextStyle(color: textColor),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Complete
          if (migration.step == sp_importer.ImportState.complete) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(AppIcons.checkCircle, color: Colors.green),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.l10n.onboardingSimplyPluralImportComplete,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Error
          if (migration.step == sp_importer.ImportState.error) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(AppIcons.errorOutline, color: Colors.red),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      migration.error ?? 'Import failed.',
                      style: TextStyle(color: textColor),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _ActionButton(
              label: context.l10n.tryAgain,
              color: primary,
              onPressed: () {
                ref.read(importerProvider.notifier).reset();
              },
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------

class _BackLink extends StatelessWidget {
  const _BackLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final linkColor = isDark
        ? AppColors.mutedTextDark
        : AppColors.mutedTextLight;
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.arrowBackIos, size: 14, color: linkColor),
          const SizedBox(width: 4),
          Text(
            context.l10n.onboardingImportOtherOptions,
            style: theme.textTheme.bodyMedium?.copyWith(color: linkColor),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.label,
    required this.color,
    this.isLoading = false,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final buttonTextColor = isDark ? AppColors.warmWhite : AppColors.warmBlack;
    return GestureDetector(
      onTapDown: widget.isLoading
          ? null
          : (_) => setState(() => _pressed = true),
      onTapUp: widget.isLoading
          ? null
          : (_) {
              setState(() => _pressed = false);
              widget.onPressed();
            },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: _pressed
                ? widget.color.withValues(alpha: 0.7)
                : widget.color.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: widget.isLoading
                ? PrismSpinner(
                    color: buttonTextColor,
                    size: 20,
                  )
                : Text(
                    widget.label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: buttonTextColor,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _InstructionRow extends StatelessWidget {
  const _InstructionRow({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primary.withValues(alpha: 0.3),
            ),
            child: Center(
              child: Text(
                number,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isDark
                    ? AppColors.warmWhite.withValues(alpha: 0.8)
                    : AppColors.warmBlack.withValues(alpha: 0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDark
                  ? AppColors.warmWhite.withValues(alpha: 0.8)
                  : AppColors.warmBlack.withValues(alpha: 0.8),
            ),
          ),
          Text(
            '$count',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDark ? AppColors.warmWhite : AppColors.warmBlack,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
