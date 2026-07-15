import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/services/files/prism_file_dialog_service.dart';
import 'package:prism_plurality/domain/repositories/normalized_avatar_batch_writer.dart';
import 'package:prism_plurality/features/migration/services/sp_avatar_zip_importer.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';

final spAvatarZipImporterProvider = Provider<SpAvatarZipImporter>(
  (ref) => SpAvatarZipImporter(),
);

enum _AvatarZipSheetState { idle, importing, complete, partial, error }

class SpAvatarZipImportSheet extends ConsumerStatefulWidget {
  const SpAvatarZipImportSheet({super.key, this.scrollController});

  final ScrollController? scrollController;

  @override
  ConsumerState<SpAvatarZipImportSheet> createState() =>
      _SpAvatarZipImportSheetState();
}

class _SpAvatarZipImportSheetState
    extends ConsumerState<SpAvatarZipImportSheet> {
  _AvatarZipSheetState _state = _AvatarZipSheetState.idle;
  SpAvatarZipImportResult? _result;
  SpAvatarZipProgress? _progress;
  String? _error;

  Future<void> _pickAndImport() async {
    final handle = await ref
        .read(prismFileDialogServiceProvider)
        .pickFile(allowedExtensions: const ['zip']);
    if (handle == null) return;

    setState(() {
      _state = _AvatarZipSheetState.importing;
      _result = null;
      _progress = null;
      _error = null;
    });

    try {
      final importer = ref.read(spAvatarZipImporterProvider);
      final memberRepo = ref.read(memberRepositoryProvider);
      if (memberRepo is! NormalizedAvatarBatchWriter) {
        throw StateError(
          'Avatar ZIP imports require the Drift member repository.',
        );
      }
      final avatarBatchWriter = memberRepo as NormalizedAvatarBatchWriter;
      void onProgress(SpAvatarZipProgress progress) {
        if (!mounted) return;
        setState(() => _progress = progress);
      }

      final result = handle.path == null
          ? await importer.importZipFileBytes(
              bytes: await handle.readAsBytes(),
              memberRepo: memberRepo,
              avatarBatchWriter: avatarBatchWriter,
              settingsRepo: ref.read(systemSettingsRepositoryProvider),
              spImportDao: ref.read(databaseProvider).spImportDao,
              onProgress: onProgress,
            )
          : await importer.importZipFile(
              filePath: handle.path!,
              memberRepo: memberRepo,
              avatarBatchWriter: avatarBatchWriter,
              settingsRepo: ref.read(systemSettingsRepositoryProvider),
              spImportDao: ref.read(databaseProvider).spImportDao,
              onProgress: onProgress,
            );
      if (!mounted) return;
      setState(() {
        _state = result.completion == SpAvatarZipImportCompletion.complete
            ? _AvatarZipSheetState.complete
            : _AvatarZipSheetState.partial;
        _result = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _AvatarZipSheetState.error;
        _error = e is FormatException ? e.message : e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        PrismSheetTopBar(title: context.l10n.spAvatarZipSheetTitle),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: switch (_state) {
              _AvatarZipSheetState.idle => _buildIdle(theme),
              _AvatarZipSheetState.importing => _buildImporting(theme),
              _AvatarZipSheetState.complete => _buildComplete(
                theme,
                partial: false,
              ),
              _AvatarZipSheetState.partial => _buildComplete(
                theme,
                partial: true,
              ),
              _AvatarZipSheetState.error => _buildError(theme),
            },
          ),
        ),
      ],
    );
  }

  Widget _buildIdle(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _IconCircle(theme, icon: AppIcons.photoLibrary),
        const SizedBox(height: 16),
        Text(
          context.l10n.spAvatarZipUpdateTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.spAvatarZipDescription,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        PrismButton(
          onPressed: _pickAndImport,
          icon: AppIcons.folderOpen,
          label: context.l10n.spAvatarZipSelect,
          tone: PrismButtonTone.filled,
          expanded: true,
        ),
      ],
    );
  }

  Widget _buildImporting(ThemeData theme) {
    final progress = _progress;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        const PrismLoadingState(),
        const SizedBox(height: 24),
        Text(
          context.l10n.spAvatarZipImporting,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          progress != null && progress.totalCandidates > 0
              ? context.l10n.spAvatarZipProgress(
                  progress.processedCandidates,
                  progress.totalCandidates,
                )
              : context.l10n.spAvatarZipImportingDescription,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildComplete(ThemeData theme, {required bool partial}) {
    final result = _result!;
    final noUpdates = result.totalUpdated == 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(AppIcons.checkCircleOutline, size: 48, color: Colors.green),
        const SizedBox(height: 16),
        Text(
          partial
              ? context.l10n.spAvatarZipPartialTitle
              : noUpdates
              ? context.l10n.spAvatarZipNoMatchesTitle
              : context.l10n.spAvatarZipCompleteTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          partial
              ? context.l10n.spAvatarZipPartialMessage
              : noUpdates
              ? context.l10n.spAvatarZipNoMatchesMessage
              : context.l10n.spAvatarZipUpdatedMessage(
                  result.memberAvatarsUpdated,
                ),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
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
            children: [
              _summaryRow(
                context.l10n.spAvatarZipImagesFound,
                result.imagesFound,
              ),
              _summaryRow(
                context.l10n.spAvatarZipMemberPhotosUpdated,
                result.memberAvatarsUpdated,
              ),
              if (result.systemAvatarUpdated)
                _summaryRow(context.l10n.spAvatarZipSystemPhotoUpdated, 1),
              if (result.unmatchedImages > 0)
                _summaryRow(
                  context.l10n.spAvatarZipUnmatchedImages,
                  result.unmatchedImages,
                ),
            ],
          ),
        ),
        if (result.warnings.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...result.warnings.map(
            (warning) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                warning,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        if (partial) ...[
          PrismButton(
            onPressed: _pickAndImport,
            icon: AppIcons.refresh,
            label: context.l10n.tryAgain,
            tone: PrismButtonTone.outlined,
            expanded: true,
          ),
          const SizedBox(height: 12),
        ],
        PrismButton(
          onPressed: () => Navigator.of(context).maybePop(),
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
        Icon(AppIcons.errorOutline, size: 48, color: theme.colorScheme.error),
        const SizedBox(height: 16),
        Text(
          context.l10n.spAvatarZipFailedTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _error ?? 'Unknown error',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        PrismButton(
          onPressed: _pickAndImport,
          icon: AppIcons.refresh,
          label: context.l10n.tryAgain,
          tone: PrismButtonTone.filled,
          expanded: true,
        ),
      ],
    );
  }

  Widget _summaryRow(String label, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            count.toString(),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _IconCircle extends StatelessWidget {
  const _IconCircle(this.theme, {required this.icon});

  final ThemeData theme;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.primary.withValues(alpha: 0.15),
      ),
      child: Icon(icon, size: 40, color: theme.colorScheme.primary),
    );
  }
}
