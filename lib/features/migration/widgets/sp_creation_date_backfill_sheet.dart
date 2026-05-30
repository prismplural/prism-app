import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/services/files/prism_file_dialog_service.dart';
import 'package:prism_plurality/features/migration/services/sp_creation_date_backfill_service.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';

// Top-level function required for compute() — SpExportData is plain Dart data
// and SpParser.parse has no isolate-unsafe state.
SpExportData _parseJson(String jsonString) => SpParser.parse(jsonString);

enum _BackfillState { idle, parsing, preview, applying, complete, error }

class SpCreationDateBackfillSheet extends ConsumerStatefulWidget {
  const SpCreationDateBackfillSheet({super.key, this.scrollController});

  final ScrollController? scrollController;

  @override
  ConsumerState<SpCreationDateBackfillSheet> createState() =>
      _SpCreationDateBackfillSheetState();
}

class _SpCreationDateBackfillSheetState
    extends ConsumerState<SpCreationDateBackfillSheet> {
  _BackfillState _state = _BackfillState.idle;
  SpCreationDateBackfillPreview? _preview;
  SpCreationDateBackfillService? _service;
  int? _appliedCount;
  String? _error;

  Future<void> _pickAndProcess() async {
    final handle = await ref
        .read(prismFileDialogServiceProvider)
        .pickFile(allowedExtensions: const ['json']);
    if (handle == null) return;

    setState(() {
      _state = _BackfillState.parsing;
      _error = null;
    });

    try {
      // Parse the SP export on a background isolate.
      final jsonString = utf8.decode(await handle.readAsBytes());
      final export = await compute(_parseJson, jsonString);

      // Check that the user has previously done an SP import (mappings exist).
      final db = ref.read(databaseProvider);
      final allMappings = await db.spImportDao.getAllMappings();
      if (allMappings.isEmpty) {
        if (!mounted) return;
        setState(() {
          _state = _BackfillState.error;
          _error = context.l10n.spCreationDateBackfillNoMapping;
        });
        return;
      }

      // Build the service and compute the preview.
      final service = SpCreationDateBackfillService(
        db: db,
        spImportDao: db.spImportDao,
        memberRepo: ref.read(memberRepositoryProvider),
      );
      final preview = await service.preview(export);

      if (!mounted) return;

      if (preview.matches.isEmpty) {
        setState(() {
          _state = _BackfillState.error;
          _error = context.l10n.spCreationDateBackfillNoMatches;
        });
        return;
      }

      setState(() {
        _service = service;
        _preview = preview;
        _state = _BackfillState.preview;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _BackfillState.error;
        _error = e is FormatException ? e.message : e.toString();
      });
    }
  }

  Future<void> _applyBackfill() async {
    setState(() => _state = _BackfillState.applying);
    try {
      final count = await _service!.apply(_preview!);
      if (!mounted) return;
      setState(() {
        _appliedCount = count;
        _state = _BackfillState.complete;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _BackfillState.error;
        _error = e is FormatException ? e.message : e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        PrismSheetTopBar(title: context.l10n.spCreationDateBackfillTitle),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: switch (_state) {
              _BackfillState.idle => _buildIdle(theme),
              _BackfillState.parsing => _buildParsing(theme),
              _BackfillState.preview => _buildPreview(theme),
              _BackfillState.applying => _buildApplying(theme),
              _BackfillState.complete => _buildComplete(theme),
              _BackfillState.error => _buildError(theme),
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
        _IconCircle(theme, icon: AppIcons.history),
        const SizedBox(height: 16),
        Text(
          context.l10n.spCreationDateBackfillTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.spCreationDateBackfillDescription,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        PrismButton(
          onPressed: _pickAndProcess,
          icon: AppIcons.folderOpen,
          label: context.l10n.spAvatarZipSelect,
          tone: PrismButtonTone.filled,
          expanded: true,
        ),
      ],
    );
  }

  Widget _buildParsing(ThemeData theme) {
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
      ],
    );
  }

  Widget _buildPreview(ThemeData theme) {
    final preview = _preview!;
    final locale = Localizations.localeOf(context).toString();
    final dateFormat = DateFormat.yMMMd(locale);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.spCreationDateBackfillPreviewTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(
              PrismShapes.of(context).radius(12),
            ),
          ),
          child: Column(
            children: [
              for (int i = 0; i < preview.matches.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _buildMatchRow(preview.matches[i], theme, dateFormat),
              ],
            ],
          ),
        ),
        if (preview.unmatchedCount > 0) ...[
          const SizedBox(height: 8),
          Text(
            context.l10n.spCreationDateBackfillUnmatched(
              preview.unmatchedCount,
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 24),
        PrismButton(
          onPressed: _applyBackfill,
          label: context.l10n.spCreationDateBackfillApply,
          tone: PrismButtonTone.filled,
          expanded: true,
        ),
      ],
    );
  }

  Widget _buildMatchRow(
    SpCreationDateMatch match,
    ThemeData theme,
    DateFormat dateFormat,
  ) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            match.memberName,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            context.l10n.spCreationDateBackfillCurrent(
              dateFormat.format(match.currentCreatedAt.toLocal()),
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            context.l10n.spCreationDateBackfillNew(
              dateFormat.format(match.newCreatedAt.toLocal()),
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApplying(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        const PrismLoadingState(),
        const SizedBox(height: 24),
        Text(
          context.l10n.spCreationDateBackfillApply,
          style: theme.textTheme.titleMedium,
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
          context.l10n.spCreationDateBackfillSuccess(_appliedCount!),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 24),
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
          _error ?? 'Unknown error',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        PrismButton(
          onPressed: () => setState(() {
            _state = _BackfillState.idle;
            _error = null;
          }),
          icon: AppIcons.refresh,
          label: context.l10n.tryAgain,
          tone: PrismButtonTone.filled,
          expanded: true,
        ),
      ],
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
