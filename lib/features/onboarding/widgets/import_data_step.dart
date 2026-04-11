import 'dart:io';
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
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_field_icon_button.dart';

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
          onSyncDevice: () {
            ref.read(onboardingProvider.notifier).enterSyncDeviceFlow();
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
    required this.onSyncDevice,
  });

  final void Function(_ImportSource) onSelect;
  final VoidCallback onSyncDevice;

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
            'You can import your existing data or skip this step to start fresh.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDark
                  ? AppColors.mutedTextDark
                  : AppColors.mutedTextLight,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          _SourceCard(
            icon: AppIcons.devices,
            color: Colors.teal,
            title: 'Sync with Existing Device',
            description:
                'Scan a pairing QR code to sync data from another device',
            onTap: onSyncDevice,
          ),
          const SizedBox(height: 16),
          _SourceCard(
            icon: AppIcons.sync,
            color: Colors.cyan,
            title: 'PluralKit',
            description:
                'Import members and fronting history from PluralKit via API token',
            onTap: () => onSelect(_ImportSource.pluralKit),
          ),
          const SizedBox(height: 16),
          _SourceCard(
            icon: AppIcons.inventoryOutlined,
            color: Colors.green,
            title: 'Prism Export',
            description:
                'Import from a Prism .json or encrypted .prism export file',
            onTap: () => onSelect(_ImportSource.prismExport),
          ),
          const SizedBox(height: 16),
          _SourceCard(
            icon: AppIcons.fileUploadOutlined,
            color: Colors.deepPurple,
            title: 'Simply Plural',
            description: 'Import from a Simply Plural JSON export file',
            onTap: () => onSelect(_ImportSource.simplyPlural),
          ),
          const SizedBox(height: 32),
          Text(
            'You can always import data later from Settings.',
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
                  'How to get your token:',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.warmWhite.withValues(alpha: 0.9)
                        : AppColors.warmBlack.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 8),
                const _InstructionRow(number: '1', text: 'Open Discord'),
                const _InstructionRow(
                  number: '2',
                  text: 'DM PluralKit bot: pk;token',
                ),
                const _InstructionRow(
                  number: '3',
                  text: 'Copy the token and paste below',
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
              hintText: 'Paste your PluralKit token',
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
                tooltip: _obscureToken ? 'Show token' : 'Hide token',
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
                      'Imported $_importedCount members from PluralKit!',
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
              label: 'Import Members',
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
      setState(() => _errorMessage = 'Please enter your PluralKit token.');
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
          _errorMessage = 'Could not connect. Please check your token.';
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
        _errorMessage = 'Import failed: $e';
      });
    }
  }
}

// ---------------------------------------------------------------------------
// Prism export import flow
// ---------------------------------------------------------------------------

enum _PrismExportStep { idle, password, preview, importing, error }

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
      final result = await FilePicker.platform.pickFiles(
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
      final json = DataImportService.resolveBytes(bytes);
      final preview = service.parsePreview(json);

      setState(() {
        _step = _PrismExportStep.preview;
        _jsonContent = json;
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
        _errorMessage = 'Failed to read file: $e';
      });
    }
  }

  void _unlockFile() {
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
        _step = _PrismExportStep.preview;
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
    final jsonContent = _jsonContent;
    final preview = _preview;
    if (jsonContent == null) return;

    setState(() => _step = _PrismExportStep.importing);

    try {
      final service = ref.read(dataImportServiceProvider);
      await service.importData(
        jsonContent,
        preserveImportedOnboardingState: false,
      );
      if (!mounted) return;

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
        _errorMessage = 'Import failed: $e';
      });
    }
  }

  void _reset() {
    setState(() {
      _step = _PrismExportStep.idle;
      _errorMessage = null;
      _jsonContent = null;
      _fileBytes = null;
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
          if (_step != _PrismExportStep.importing)
            Align(
              alignment: Alignment.centerLeft,
              child: _BackLink(onTap: widget.onBack),
            ),
          const SizedBox(height: 16),
          switch (_step) {
            _PrismExportStep.idle => _buildIdle(),
            _PrismExportStep.password => _buildPassword(),
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
                'How to export from Prism:',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.warmWhite : AppColors.warmBlack,
                ),
              ),
              const SizedBox(height: 8),
              const _InstructionRow(
                number: '1',
                text: 'Open Prism on your other device',
              ),
              const _InstructionRow(
                number: '2',
                text: 'Go to Settings → Import & Export → Export Data',
              ),
              const _InstructionRow(
                number: '3',
                text: 'Save the .json or .prism file and select it below',
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _ActionButton(
          label: 'Select Export File',
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
          'Encrypted Export',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: isDark ? AppColors.warmWhite : AppColors.warmBlack,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Enter the export password to unlock this Prism backup.',
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
            hintText: 'Export password',
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
              tooltip: _obscurePassword ? 'Show password' : 'Hide password',
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        const SizedBox(height: 24),
        _ActionButton(
          label: 'Unlock Export',
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
                'Ready to import',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.warmWhite.withValues(alpha: 0.9)
                      : AppColors.warmBlack.withValues(alpha: 0.9),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This will restore your exported Prism system and finish setup on this device.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isDark
                      ? AppColors.mutedTextDark
                      : AppColors.mutedTextLight,
                ),
              ),
              const SizedBox(height: 12),
              _PreviewRow(label: 'Members', count: preview.headmates),
              _PreviewRow(
                label: 'Fronting sessions',
                count: preview.frontSessions,
              ),
              _PreviewRow(label: 'Conversations', count: preview.conversations),
              _PreviewRow(label: 'Messages', count: preview.messages),
              _PreviewRow(label: 'Habits', count: preview.habits),
              _PreviewRow(label: 'Notes', count: preview.notes),
              Divider(
                color: isDark
                    ? const Color(0x22FFFFFF)
                    : const Color(0x22000000),
                height: 24,
              ),
              _PreviewRow(label: 'Total records', count: preview.totalRecords),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _ActionButton(
          label: 'Import and Continue',
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
            CircularProgressIndicator(color: textColor),
            const SizedBox(height: 16),
            Text(
              'Importing your Prism export...',
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
          label: 'Try Again',
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
                    'How to export from Simply Plural:',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.warmWhite.withValues(alpha: 0.9)
                          : AppColors.warmBlack.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const _InstructionRow(
                    number: '1',
                    text: 'Open Simply Plural app',
                  ),
                  const _InstructionRow(
                    number: '2',
                    text: 'Go to Settings → Export Data',
                  ),
                  const _InstructionRow(
                    number: '3',
                    text: 'Save the JSON file and select it below',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _ActionButton(
              label: 'Select Export File',
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
                    CircularProgressIndicator(color: textColor),
                    const SizedBox(height: 16),
                    Text('Reading file...', style: TextStyle(color: textColor)),
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
                    'Found data:',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.warmWhite.withValues(alpha: 0.9)
                          : AppColors.warmBlack.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _PreviewRow(
                    label: 'Members',
                    count:
                        migration.exportData!.members.length +
                        migration.exportData!.customFronts.length,
                  ),
                  _PreviewRow(
                    label: 'Fronting sessions',
                    count: migration.exportData!.frontHistory.length,
                  ),
                  _PreviewRow(
                    label: 'Conversations',
                    count: migration.exportData!.channels.length,
                  ),
                  _PreviewRow(
                    label: 'Messages',
                    count: migration.exportData!.messages.length,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _ActionButton(
              label: 'Import Data',
              color: primary,
              onPressed: () {
                ref.read(importerProvider.notifier).executeImport();
              },
            ),
          ],

          // Importing / downloading avatars
          if (migration.step == sp_importer.ImportState.importing ||
              migration.step == sp_importer.ImportState.downloadingAvatars) ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    CircularProgressIndicator(color: textColor),
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
                      'Import complete! Your data is ready.',
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
              label: 'Try Again',
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
            'Other import options',
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
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: buttonTextColor,
                    ),
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
