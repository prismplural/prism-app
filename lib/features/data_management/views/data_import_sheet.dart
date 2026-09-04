import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/services/files/prism_file_dialog_service.dart';
import 'package:prism_plurality/features/data_management/providers/data_management_providers.dart';
import 'package:prism_plurality/features/data_management/services/data_import_service.dart';
import 'package:prism_plurality/features/data_management/services/export_crypto.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_field_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/unsaved_changes_guard.dart';

enum _ImportState {
  idle,
  password,
  decrypting,
  preview,
  importing,
  complete,
  error,
}

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
  List<({String mediaId, Uint8List blob})> _mediaBlobs = const [];
  Uint8List? _fileBytes;
  ImportPreview? _preview;
  ImportResult? _result;

  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String? _passwordError;

  bool get _isDirty =>
      _state == _ImportState.password && _passwordController.text.isNotEmpty;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final handle = await ref
          .read(prismFileDialogServiceProvider)
          .pickFile(allowedExtensions: const ['json', 'prism']);
      if (handle == null) return;

      final bytes = await handle.readAsBytes();

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

  Future<void> _onPasswordSubmit() async {
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(
        () => _passwordError = context.l10n.dataManagementPasswordEmptyImport,
      );
      return;
    }
    setState(() {
      _state = _ImportState.decrypting;
      _passwordError = null;
    });
    final bytes = _fileBytes!;
    final pass = password;
    try {
      final resolved = await compute(DataImportService.resolveForCompute, (
        bytes: bytes,
        password: pass,
      ));
      final service = ref.read(dataImportServiceProvider);
      final preview = service.parsePreview(resolved.json);
      if (!mounted) return;
      setState(() {
        _state = _ImportState.preview;
        _jsonContent = resolved.json;
        _mediaBlobs = resolved.mediaBlobs;
        _preview = preview;
      });
    } on FormatException catch (e) {
      if (!mounted) return;
      final msg = e.message;
      setState(() {
        _state = _ImportState.password;
        _passwordError = msg == 'unencrypted-prism-backup'
            ? context.l10n.dataManagementUnencryptedBackup
            : msg.contains('mac check') || msg.contains('wrong')
            ? context.l10n.dataManagementIncorrectPassword
            : context.l10n.dataManagementDecryptionFailed(msg);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _ImportState.password;
        _passwordError = context.l10n.dataManagementDecryptionFailed(
          e.toString(),
        );
      });
    }
  }

  Future<void> _startImport() async {
    if (_jsonContent == null) return;
    setState(() => _state = _ImportState.importing);

    try {
      final service = ref.read(dataImportServiceProvider);
      final result = await service.importData(
        _jsonContent!,
        mediaBlobs: _mediaBlobs,
      );
      if (!mounted) return;
      setState(() {
        _state = _ImportState.complete;
        _result = result;
        _fileBytes = null;
        _jsonContent = null;
        _mediaBlobs = const [];
        _passwordController.clear();
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

    return ListenableBuilder(
      listenable: _passwordController,
      builder: (context, _) => UnsavedChangesGuard<void>(
        hasUnsavedChanges: _isDirty,
        child: Column(
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
                      _ImportState.decrypting => _buildImporting(theme),
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
        ),
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
          onSubmitted: (_) => _onPasswordSubmit(),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: PrismButton(
                onPressed: () => Navigator.of(context).maybePop(),
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
    final terms = readTerminology(context, ref);
    final frontingTerms = readFrontingTerms(context, ref);
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
            borderRadius: BorderRadius.circular(
              PrismShapes.of(context).radius(12),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final row in _previewCountRows(
                p,
                terms.plural,
                frontingTerms.sessionPlural,
                frontingTerms.sessionSingularLower,
              ))
                _previewRow(row.label, row.count),
              const Divider(),
              _previewRow(
                context.l10n.dataManagementPreviewTotal,
                p.totalRecords,
                bold: true,
              ),
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

  List<({String label, int count})> _previewCountRows(
    ImportPreview p,
    String membersPlural,
    String sessionPlural,
    String sessionSingularLower,
  ) => [
    (
      label: context.l10n.dataManagementPreviewMembers(membersPlural),
      count: p.headmates,
    ),
    (label: sessionPlural, count: p.frontSessions),
    (
      label: context.l10n.dataManagementPreviewSleepSessions,
      count: p.sleepSessions,
    ),
    (
      label: context.l10n.dataManagementPreviewConversations,
      count: p.conversations,
    ),
    (label: context.l10n.dataManagementPreviewMessages, count: p.messages),
    (label: context.l10n.dataManagementPreviewPolls, count: p.polls),
    (
      label: context.l10n.dataManagementPreviewPollOptions,
      count: p.pollOptions,
    ),
    (
      label: context.l10n.dataManagementPreviewSettings,
      count: p.systemSettings,
    ),
    (label: context.l10n.dataManagementPreviewHabits, count: p.habits),
    (
      label: context.l10n.dataManagementPreviewHabitCompletions,
      count: p.habitCompletions,
    ),
    (
      label: context.l10n.dataManagementPreviewMemberGroups,
      count: p.memberGroups,
    ),
    (
      label: context.l10n.dataManagementPreviewMemberGroupEntries,
      count: p.memberGroupEntries,
    ),
    (
      label: context.l10n.dataManagementPreviewCustomFields,
      count: p.customFields,
    ),
    (
      label: context.l10n.dataManagementPreviewCustomFieldValues,
      count: p.customFieldValues,
    ),
    (label: context.l10n.dataManagementPreviewNotes, count: p.notes),
    (
      label: context.l10n.dataManagementPreviewFrontSessionComments(
        sessionSingularLower,
      ),
      count: p.frontSessionComments,
    ),
    (
      label: context.l10n.dataManagementPreviewConversationCategories,
      count: p.conversationCategories,
    ),
    (label: context.l10n.dataManagementPreviewReminders, count: p.reminders),
    (label: context.l10n.dataManagementPreviewFriends, count: p.friends),
    (
      label: context.l10n.dataManagementPreviewMediaAttachments,
      count: p.mediaAttachments,
    ),
    (
      label: context.l10n.dataManagementPreviewMemberBoardPosts,
      count: p.memberBoardPosts,
    ),
    (
      label: context.l10n.dataManagementPreviewAppPreferences,
      count: p.appPreferences,
    ),
  ];

  Widget _previewRow(String label, int count, {bool bold = false}) {
    final style = bold ? const TextStyle(fontWeight: FontWeight.bold) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: 16),
          Text(count.toString(), textAlign: TextAlign.end, style: style),
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
        Text(
          context.l10n.dataManagementImporting,
          style: theme.textTheme.titleMedium,
        ),
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
    final terms = readTerminology(context, ref);
    final frontingTerms = readFrontingTerms(context, ref);
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
            borderRadius: BorderRadius.circular(
              PrismShapes.of(context).radius(12),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final row in _resultCountRows(
                r,
                terms.plural,
                frontingTerms.sessionPlural,
                frontingTerms.sessionSingularLower,
              ))
                _previewRow(row.label, row.count),
              const Divider(),
              _previewRow(
                context.l10n.dataManagementPreviewTotalCreated,
                r.totalRecordsCreated,
                bold: true,
              ),
            ],
          ),
        ),
        if (r.timestampOnlyFrontSessionCommentsDropped > 0) ...[
          const SizedBox(height: 12),
          _importWarning(
            theme,
            context.l10n.dataImportTimestampOnlyCommentsDropped(
              r.timestampOnlyFrontSessionCommentsDropped,
            ),
          ),
        ],
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

  List<({String label, int count})> _resultCountRows(
    ImportResult r,
    String membersPlural,
    String sessionPlural,
    String sessionSingularLower,
  ) => [
    (
      label: context.l10n.dataManagementPreviewMembers(membersPlural),
      count: r.membersCreated,
    ),
    (label: sessionPlural, count: r.frontSessionsCreated),
    (
      label: context.l10n.dataManagementPreviewSleepSessions,
      count: r.sleepSessionsCreated,
    ),
    (
      label: context.l10n.dataManagementPreviewConversations,
      count: r.conversationsCreated,
    ),
    (
      label: context.l10n.dataManagementPreviewMessages,
      count: r.messagesCreated,
    ),
    (label: context.l10n.dataManagementPreviewPolls, count: r.pollsCreated),
    (
      label: context.l10n.dataManagementPreviewPollOptions,
      count: r.pollOptionsCreated,
    ),
    (
      label: context.l10n.dataManagementPreviewSettings,
      count: r.settingsUpdated ? 1 : 0,
    ),
    (label: context.l10n.dataManagementPreviewHabits, count: r.habitsCreated),
    (
      label: context.l10n.dataManagementPreviewHabitCompletions,
      count: r.habitCompletionsCreated,
    ),
    (
      label: context.l10n.dataManagementPreviewMemberGroups,
      count: r.memberGroupsCreated,
    ),
    (
      label: context.l10n.dataManagementPreviewMemberGroupEntries,
      count: r.memberGroupEntriesCreated,
    ),
    (
      label: context.l10n.dataManagementPreviewCustomFields,
      count: r.customFieldsCreated,
    ),
    (
      label: context.l10n.dataManagementPreviewCustomFieldValues,
      count: r.customFieldValuesCreated,
    ),
    (label: context.l10n.dataManagementPreviewNotes, count: r.notesCreated),
    (
      label: context.l10n.dataManagementPreviewFrontSessionComments(
        sessionSingularLower,
      ),
      count: r.frontSessionCommentsCreated,
    ),
    (
      label: context.l10n.dataManagementPreviewConversationCategories,
      count: r.conversationCategoriesCreated,
    ),
    (
      label: context.l10n.dataManagementPreviewReminders,
      count: r.remindersCreated,
    ),
    (label: context.l10n.dataManagementPreviewFriends, count: r.friendsCreated),
    (
      label: context.l10n.dataManagementPreviewMediaAttachments,
      count: r.mediaAttachmentsCreated,
    ),
    (
      label: context.l10n.dataManagementPreviewMemberBoardPosts,
      count: r.memberBoardPostsCreated,
    ),
    (
      label: context.l10n.dataManagementPreviewAppPreferences,
      count: r.appPreferencesCreated,
    ),
  ];

  Widget _importWarning(ThemeData theme, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(8)),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
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
              _mediaBlobs = const [];
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
