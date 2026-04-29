import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:share_plus/share_plus.dart';

import 'package:prism_plurality/features/data_management/providers/data_management_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_field_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

enum _ExportState { idle, password, exporting, error, complete }

class DataExportSheet extends ConsumerStatefulWidget {
  const DataExportSheet({super.key, this.scrollController});

  final ScrollController? scrollController;

  @override
  ConsumerState<DataExportSheet> createState() => _DataExportSheetState();
}

class _DataExportSheetState extends ConsumerState<DataExportSheet> {
  _ExportState _state = _ExportState.idle;
  String? _errorMessage;
  File? _exportedFile;

  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _passwordError;

  @override
  void dispose() {
    _deleteFile(_exportedFile);
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
    File? file;
    setState(() => _state = _ExportState.exporting);
    try {
      final service = ref.read(dataExportServiceProvider);
      file = await service.exportEncryptedData(password: password);
      if (!mounted) return;
      _passwordController.clear();
      _confirmController.clear();
      setState(() {
        _state = _ExportState.complete;
        _exportedFile = file;
      });
      // Trigger share sheet
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Prism Plurality Export',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _ExportState.error;
        _errorMessage = e.toString();
      });
    } finally {
      await _deleteFile(file);
      if (identical(_exportedFile, file)) {
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

    return Column(
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
              24 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                switch (_state) {
                  _ExportState.idle => _buildIdle(theme),
                  _ExportState.password => _buildPassword(theme),
                  _ExportState.exporting => _buildExporting(theme),
                  _ExportState.error => _buildError(theme),
                  _ExportState.complete => _buildComplete(theme),
                },
              ],
            ),
          ),
        ),
      ],
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
        if (_exportedFile != null)
          Text(
            _exportedFile!.path.split('/').last,
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
