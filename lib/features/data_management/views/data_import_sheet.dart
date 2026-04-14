import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/data_management/providers/data_management_providers.dart';
import 'package:prism_plurality/features/data_management/services/data_import_service.dart';
import 'package:prism_plurality/features/data_management/services/export_crypto.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_field_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

enum _ImportState { idle, password, preview, importing, complete, error }

class DataImportSheet extends ConsumerStatefulWidget {
  const DataImportSheet({super.key, this.scrollController});

  final ScrollController? scrollController;

  @override
  ConsumerState<DataImportSheet> createState() => _DataImportSheetState();
}

class _DataImportSheetState extends ConsumerState<DataImportSheet> {
  _ImportState _state = _ImportState.idle;
  String? _errorMessage;
  String? _jsonContent;
  Uint8List? _fileBytes;
  ImportPreview? _preview;
  ImportResult? _result;

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
      );
      if (result == null || result.files.isEmpty) return;

      final path = result.files.single.path;
      if (path == null) return;

      final bytes = await File(path).readAsBytes();

      if (ExportCrypto.isEncrypted(bytes)) {
        // Encrypted file — need password before we can preview
        if (!mounted) return;
        setState(() {
          _state = _ImportState.password;
          _fileBytes = bytes;
        });
        return;
      }

      // Plain JSON file
      final content = String.fromCharCodes(bytes);
      final service = ref.read(dataImportServiceProvider);
      final preview = service.parsePreview(content);

      if (!mounted) return;
      setState(() {
        _state = _ImportState.preview;
        _jsonContent = content;
        _preview = preview;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _ImportState.error;
        _errorMessage = 'Failed to read file: $e';
      });
    }
  }

  void _onPasswordSubmit() {
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _passwordError = context.l10n.dataManagementPasswordEmptyImport);
      return;
    }

    try {
      final json = DataImportService.resolveBytes(
        _fileBytes!,
        password: password,
      );
      final service = ref.read(dataImportServiceProvider);
      final preview = service.parsePreview(json);

      if (!mounted) return;
      setState(() {
        _state = _ImportState.preview;
        _jsonContent = json;
        _preview = preview;
        _passwordError = null;
      });
    } catch (e) {
      if (!mounted) return;
      final message = e.toString();
      setState(() {
        _passwordError = message.contains('mac check')
            ? context.l10n.dataManagementIncorrectPassword
            : context.l10n.dataManagementDecryptionFailed(message);
      });
    }
  }

  Future<void> _startImport() async {
    if (_jsonContent == null) return;
    setState(() => _state = _ImportState.importing);

    try {
      final service = ref.read(dataImportServiceProvider);
      final result = await service.importData(_jsonContent!);
      if (!mounted) return;
      setState(() {
        _state = _ImportState.complete;
        _result = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _ImportState.error;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        PrismSheetTopBar(title: context.l10n.dataManagementImportTitle),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                switch (_state) {
                  _ImportState.idle => _buildIdle(theme),
                  _ImportState.password => _buildPassword(theme),
                  _ImportState.preview => _buildPreview(theme),
                  _ImportState.importing => _buildImporting(theme),
                  _ImportState.complete => _buildComplete(theme),
                  _ImportState.error => _buildError(theme),
                },
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIdle(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.green.withValues(alpha: 0.15),
          ),
          child: Icon(AppIcons.downloadOutlined, size: 40, color: Colors.green),
        ),
        const SizedBox(height: 16),
        Text(
          context.l10n.dataManagementImportTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.dataManagementImportFileDescription,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        PrismButton(
          onPressed: _pickFile,
          icon: AppIcons.folderOpen,
          label: context.l10n.dataManagementSelectFile,
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
          context.l10n.dataManagementEncryptedFile,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.dataManagementEncryptedFileDescription,
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
          errorText: _passwordError,
          suffix: PrismFieldIconButton(
            icon: _obscurePassword
                ? AppIcons.visibilityOff
                : AppIcons.visibility,
            tooltip: _obscurePassword ? context.l10n.dataManagementShowPassword : context.l10n.dataManagementHidePassword,
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
          ),
          onChanged: (_) {
            if (_passwordError != null) {
              setState(() => _passwordError = null);
            }
          },
          onSubmitted: (_) => _onPasswordSubmit(),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: PrismButton(
                onPressed: () => Navigator.pop(context),
                label: context.l10n.cancel,
                tone: PrismButtonTone.outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PrismButton(
                onPressed: _onPasswordSubmit,
                icon: AppIcons.lockOpen,
                label: context.l10n.dataManagementDecrypt,
                tone: PrismButtonTone.filled,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPreview(ThemeData theme) {
    final p = _preview!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          context.l10n.dataManagementImportPreview,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        if (p.exportDate.isNotEmpty)
          Text(
            context.l10n.dataManagementExportedDate(p.exportDate),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _previewRow(context.l10n.dataManagementPreviewMembers, p.headmates),
              _previewRow(context.l10n.dataManagementPreviewFrontSessions, p.frontSessions),
              _previewRow(context.l10n.dataManagementPreviewSleepSessions, p.sleepSessions),
              _previewRow(context.l10n.dataManagementPreviewConversations, p.conversations),
              _previewRow(context.l10n.dataManagementPreviewMessages, p.messages),
              _previewRow(context.l10n.dataManagementPreviewPolls, p.polls),
              _previewRow(context.l10n.dataManagementPreviewPollOptions, p.pollOptions),
              _previewRow(context.l10n.dataManagementPreviewSettings, p.systemSettings),
              _previewRow(context.l10n.dataManagementPreviewHabits, p.habits),
              _previewRow(context.l10n.dataManagementPreviewHabitCompletions, p.habitCompletions),
              const Divider(),
              _previewRow(context.l10n.dataManagementPreviewTotal, p.totalRecords, bold: true),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: PrismButton(
                onPressed: () => Navigator.pop(context),
                label: context.l10n.cancel,
                tone: PrismButtonTone.outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PrismButton(
                onPressed: _startImport,
                icon: AppIcons.download,
                label: context.l10n.dataManagementImport,
                tone: PrismButtonTone.filled,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _previewRow(String label, int count, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null,
          ),
          Text(
            count.toString(),
            style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null,
          ),
        ],
      ),
    );
  }

  Widget _buildImporting(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        const PrismLoadingState(),
        const SizedBox(height: 24),
        Text(context.l10n.dataManagementImporting, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          context.l10n.dataManagementImportingMessage,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildComplete(ThemeData theme) {
    final r = _result!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(AppIcons.checkCircleOutline, size: 48, color: Colors.green),
        const SizedBox(height: 16),
        Text(
          context.l10n.dataManagementImportComplete,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _previewRow(context.l10n.dataManagementPreviewMembers, r.membersCreated),
              _previewRow(context.l10n.dataManagementPreviewFrontSessions, r.frontSessionsCreated),
              _previewRow(context.l10n.dataManagementPreviewSleepSessions, r.sleepSessionsCreated),
              _previewRow(context.l10n.dataManagementPreviewConversations, r.conversationsCreated),
              _previewRow(context.l10n.dataManagementPreviewMessages, r.messagesCreated),
              _previewRow(context.l10n.dataManagementPreviewPolls, r.pollsCreated),
              _previewRow(context.l10n.dataManagementPreviewPollOptions, r.pollOptionsCreated),
              _previewRow(context.l10n.dataManagementPreviewSettings, r.settingsUpdated ? 1 : 0),
              _previewRow(context.l10n.dataManagementPreviewHabits, r.habitsCreated),
              _previewRow(context.l10n.dataManagementPreviewHabitCompletions, r.habitCompletionsCreated),
              const Divider(),
              _previewRow(context.l10n.dataManagementPreviewTotalCreated, r.totalRecordsCreated, bold: true),
            ],
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

  Widget _buildError(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(AppIcons.errorOutline, size: 48, color: Colors.red),
        const SizedBox(height: 16),
        Text(
          context.l10n.dataManagementImportFailed,
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
        const SizedBox(height: 4),
        Text(
          context.l10n.dataManagementImportFailedNote,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        PrismButton(
          onPressed: () {
            setState(() {
              _state = _ImportState.idle;
              _errorMessage = null;
              _fileBytes = null;
              _jsonContent = null;
              _passwordController.clear();
              _passwordError = null;
            });
          },
          label: context.l10n.tryAgain,
          tone: PrismButtonTone.filled,
          expanded: true,
        ),
      ],
    );
  }
}
