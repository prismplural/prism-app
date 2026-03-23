import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/data_management/providers/data_management_providers.dart';
import 'package:prism_plurality/features/data_management/services/data_import_service.dart';
import 'package:prism_plurality/features/data_management/services/export_crypto.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

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
      final result = await FilePicker.platform.pickFiles(
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
      setState(() => _passwordError = 'Password cannot be empty');
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
            ? 'Incorrect password'
            : 'Decryption failed: $message';
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

    return SingleChildScrollView(
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
          child: const Icon(Icons.download_outlined,
              size: 40, color: Colors.green),
        ),
        const SizedBox(height: 16),
        Text(
          'Import Data',
          style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Select a Prism export file (.json or .prism) to restore your data. Existing data will not be overwritten.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        PrismButton(
          onPressed: _pickFile,
          icon: Icons.folder_open,
          label: 'Select File',
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
            Icons.lock_outline,
            size: 40,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Encrypted File',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'This export file is encrypted. Enter the password that was used when the export was created.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Password',
            border: const OutlineInputBorder(),
            errorText: _passwordError,
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
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
                label: 'Cancel',
                tone: PrismButtonTone.outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PrismButton(
                onPressed: _onPasswordSubmit,
                icon: Icons.lock_open,
                label: 'Decrypt',
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
          'Import Preview',
          style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        if (p.exportDate.isNotEmpty)
          Text(
            'Exported: ${p.exportDate}',
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
              _previewRow('Members', p.headmates),
              _previewRow('Front Sessions', p.frontSessions),
              _previewRow('Sleep Sessions', p.sleepSessions),
              _previewRow('Conversations', p.conversations),
              _previewRow('Messages', p.messages),
              _previewRow('Polls', p.polls),
              _previewRow('Poll Options', p.pollOptions),
              _previewRow('Settings', p.systemSettings),
              _previewRow('Habits', p.habits),
              _previewRow('Habit Completions', p.habitCompletions),
              const Divider(),
              _previewRow('Total', p.totalRecords, bold: true),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: PrismButton(
                onPressed: () => Navigator.pop(context),
                label: 'Cancel',
                tone: PrismButtonTone.outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PrismButton(
                onPressed: _startImport,
                icon: Icons.download,
                label: 'Import',
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
            style: bold
                ? const TextStyle(fontWeight: FontWeight.bold)
                : null,
          ),
          Text(
            count.toString(),
            style: bold
                ? const TextStyle(fontWeight: FontWeight.bold)
                : null,
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
        const CircularProgressIndicator(),
        const SizedBox(height: 24),
        Text('Importing your data...', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'This may take a moment. Do not close the app.',
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
        const Icon(
          Icons.check_circle_outline,
          size: 48,
          color: Colors.green,
        ),
        const SizedBox(height: 16),
        Text(
          'Import Complete',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
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
              _previewRow('Members', r.membersCreated),
              _previewRow('Front Sessions', r.frontSessionsCreated),
              _previewRow('Sleep Sessions', r.sleepSessionsCreated),
              _previewRow('Conversations', r.conversationsCreated),
              _previewRow('Messages', r.messagesCreated),
              _previewRow('Polls', r.pollsCreated),
              _previewRow('Poll Options', r.pollOptionsCreated),
              _previewRow('Settings', r.settingsUpdated ? 1 : 0),
              _previewRow('Habits', r.habitsCreated),
              _previewRow('Habit Completions', r.habitCompletionsCreated),
              const Divider(),
              _previewRow('Total Created', r.totalRecordsCreated, bold: true),
            ],
          ),
        ),
        const SizedBox(height: 24),
        PrismButton(
          onPressed: () => Navigator.pop(context),
          label: 'Done',
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
        const Icon(Icons.error_outline, size: 48, color: Colors.red),
        const SizedBox(height: 16),
        Text(
          'Import Failed',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          _errorMessage ?? 'An unknown error occurred.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'No data was imported. The database was not modified.',
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
          label: 'Try Again',
          tone: PrismButtonTone.filled,
          expanded: true,
        ),
      ],
    );
  }
}
