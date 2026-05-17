import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:share_plus/share_plus.dart';

import 'package:prism_plurality/core/services/files/prism_file_dialog_service.dart';
import 'package:prism_plurality/features/data_management/providers/data_management_providers.dart';
import 'package:prism_plurality/features/data_management/services/data_export_service.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/utils/modal_insets.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_field_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/unsaved_changes_guard.dart';

enum _ExportState { idle, password, exporting, error, readyToSave, complete }

class DataExportSheet extends ConsumerStatefulWidget {
  const DataExportSheet({super.key, this.scrollController});

  final ScrollController? scrollController;

  @override
  ConsumerState<DataExportSheet> createState() => _DataExportSheetState();
}

class _DataExportSheetState extends ConsumerState<DataExportSheet> {
  _ExportState _state = _ExportState.idle;
  String? _errorMessage;
  EncryptedExportFile? _exportedFile;
  String? _savedDisplayName;

  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _passwordError;
  bool _isSaving = false;
  bool _isSharing = false;

  bool get _isDirty =>
      _state == _ExportState.password &&
      (_passwordController.text.isNotEmpty ||
          _confirmController.text.isNotEmpty);

  @override
  void dispose() {
    _deleteFile(_exportedFile?.file);
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _onExportPressed() {
    setState(() => _state = _ExportState.password);
  }

  void _onPasswordSubmit() {
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (password.isEmpty) {
      setState(() => _passwordError = context.l10n.dataManagementPasswordEmpty);
      return;
    }
    if (password.length < 12) {
      setState(
        () => _passwordError = context.l10n.dataManagementPasswordTooShort,
      );
      return;
    }
    if (password != confirm) {
      setState(
        () => _passwordError = context.l10n.dataManagementPasswordMismatch,
      );
      return;
    }

    setState(() => _passwordError = null);
    _startExport(password: password);
  }

  Future<void> _startExport({required String password}) async {
    setState(() => _state = _ExportState.exporting);
    final EncryptedExportFile file;
    try {
      final service = ref.read(dataExportServiceProvider);
      file = await service.buildEncryptedExportFile(password: password);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _ExportState.error;
        _errorMessage = e.toString();
      });
      return;
    }
    if (!mounted) {
      await _deleteFile(file.file);
      return;
    }
    _passwordController.clear();
    _confirmController.clear();
    setState(() {
      _state = _ExportState.readyToSave;
      _exportedFile = file;
      _savedDisplayName = null;
    });
    await _saveExportedFile();
  }

  Future<void> _saveExportedFile() async {
    final export = _exportedFile;
    if (export == null || _isSaving) return;
    setState(() => _isSaving = true);
    final outcome = await ref
        .read(prismFileDialogServiceProvider)
        .saveExistingFile(
          ExistingFileSaveRequest(
            sourceFile: export.file,
            suggestedName: export.fileName,
            allowedExtensions: const ['prism'],
            sourceIsDurable: false,
            dialogTitle: 'Save Prism export',
            mimeType: 'application/octet-stream',
          ),
        );
    if (!mounted) return;
    setState(() => _isSaving = false);
    switch (outcome.status) {
      case SaveFileStatus.saved:
        setState(() {
          _state = _ExportState.complete;
          _savedDisplayName = outcome.savedDisplayName ?? export.fileName;
        });
        await _deleteFile(export.file);
        if (identical(_exportedFile, export)) {
          _exportedFile = null;
        }
        break;
      case SaveFileStatus.cancelled:
      case SaveFileStatus.alreadyActive:
        break;
      case SaveFileStatus.failed:
      case SaveFileStatus.unsupported:
      case SaveFileStatus.sourceNotReady:
        setState(() {
          _state = _ExportState.error;
          _errorMessage = outcome.error?.toString() ?? outcome.status.name;
        });
        break;
    }
  }

  Future<void> _shareExportedFile() async {
    final export = _exportedFile;
    if (export == null || _isSharing) return;
    setState(() => _isSharing = true);
    ShareResultStatus status = ShareResultStatus.dismissed;
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(export.file.path)],
          subject: 'Prism Plurality Export',
        ),
      );
      status = result.status;
    } catch (_) {
      status = ShareResultStatus.dismissed;
    }
    if (!mounted) return;
    setState(() => _isSharing = false);
    if (status == ShareResultStatus.success) {
      setState(() {
        _state = _ExportState.complete;
        _savedDisplayName = export.fileName;
      });
      await _deleteFile(export.file);
      if (identical(_exportedFile, export)) {
        _exportedFile = null;
      }
    }
  }

  Future<void> _deleteFile(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: Listenable.merge([_passwordController, _confirmController]),
      builder: (context, _) => UnsavedChangesGuard<void>(
        hasUnsavedChanges: _isDirty,
        child: Column(
          children: [
            PrismSheetTopBar(title: context.l10n.dataManagementExportTitle),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                controller: widget.scrollController,
                padding: EdgeInsets.fromLTRB(
                  24,
                  24,
                  24,
                  24 + modalBottomInsetOf(context),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    switch (_state) {
                      _ExportState.idle => _buildIdle(theme),
                      _ExportState.password => _buildPassword(theme),
                      _ExportState.exporting => _buildExporting(theme),
                      _ExportState.error => _buildError(theme),
                      _ExportState.readyToSave => _buildReadyToSave(theme),
                      _ExportState.complete => _buildComplete(theme),
                    },
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdle(ThemeData theme) {
    final terms = readTerminology(context, ref);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.blue.withValues(alpha: 0.15),
          ),
          child: Icon(AppIcons.uploadOutlined, size: 40, color: Colors.blue),
        ),
        const SizedBox(height: 16),
        Text(
          context.l10n.dataManagementExportYourData,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.dataManagementExportDescription(terms.pluralLower),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        PrismButton(
          onPressed: _onExportPressed,
          icon: AppIcons.download,
          label: context.l10n.dataManagementExportButton,
          tone: PrismButtonTone.filled,
          expanded: true,
        ),
      ],
    );
  }

  Widget _buildPassword(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.primary.withValues(alpha: 0.15),
          ),
          child: Icon(
            AppIcons.lockOutline,
            size: 40,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          context.l10n.dataManagementEncryptExport,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.dataManagementEncryptDescription,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        PrismTextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          autofocus: true,
          labelText: context.l10n.dataManagementPasswordLabel,
          hintText: context.l10n.dataManagementPasswordHint,
          suffix: PrismFieldIconButton(
            icon: _obscurePassword
                ? AppIcons.visibilityOff
                : AppIcons.visibility,
            tooltip: _obscurePassword
                ? context.l10n.dataManagementShowPassword
                : context.l10n.dataManagementHidePassword,
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
          ),
          onChanged: (_) {
            if (_passwordError != null) {
              setState(() => _passwordError = null);
            }
          },
        ),
        const SizedBox(height: 12),
        PrismTextField(
          controller: _confirmController,
          obscureText: _obscureConfirm,
          labelText: context.l10n.dataManagementConfirmPasswordLabel,
          errorText: _passwordError,
          suffix: PrismFieldIconButton(
            icon: _obscureConfirm
                ? AppIcons.visibilityOff
                : AppIcons.visibility,
            tooltip: _obscureConfirm
                ? context.l10n.dataManagementShowPassword
                : context.l10n.dataManagementHidePassword,
            onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
          ),
          onSubmitted: (_) => _onPasswordSubmit(),
        ),
        const SizedBox(height: 20),
        PrismButton(
          onPressed: _onPasswordSubmit,
          icon: AppIcons.lock,
          label: context.l10n.dataManagementEncrypt,
          tone: PrismButtonTone.filled,
        ),
      ],
    );
  }

  Widget _buildExporting(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        const PrismLoadingState(),
        const SizedBox(height: 24),
        Text(
          context.l10n.dataManagementExporting,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.dataManagementMayTakeMoment,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildError(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(AppIcons.errorOutline, size: 48, color: Colors.red),
        const SizedBox(height: 16),
        Text(
          context.l10n.dataManagementExportFailed,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _errorMessage ?? context.l10n.migrationUnknownError,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: PrismButton(
                onPressed: () => Navigator.pop(context),
                label: context.l10n.close,
                tone: PrismButtonTone.outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PrismButton(
                onPressed: () => setState(() {
                  _state = _ExportState.idle;
                  _errorMessage = null;
                }),
                label: context.l10n.dataManagementRetry,
                tone: PrismButtonTone.filled,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReadyToSave(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          AppIcons.uploadOutlined,
          size: 48,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          context.l10n.dataManagementExportReadyTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.dataManagementExportReadyDescription,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (_exportedFile != null) ...[
          const SizedBox(height: 8),
          Text(
            _exportedFile!.fileName,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: PrismButton(
                onPressed: _shareExportedFile,
                enabled: !_isSharing,
                icon: AppIcons.share,
                label: context.l10n.dataManagementShareExport,
                tone: PrismButtonTone.outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PrismButton(
                onPressed: _saveExportedFile,
                enabled: !_isSaving,
                icon: AppIcons.download,
                label: context.l10n.save,
                tone: PrismButtonTone.filled,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildComplete(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(AppIcons.checkCircleOutline, size: 48, color: Colors.green),
        const SizedBox(height: 16),
        Text(
          context.l10n.dataManagementExportComplete,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        if (_savedDisplayName != null)
          Text(
            _savedDisplayName!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 24),
        PrismButton(
          onPressed: () => Navigator.pop(context),
          label: context.l10n.done,
          tone: PrismButtonTone.filled,
          expanded: true,
        ),
      ],
    );
  }
}
