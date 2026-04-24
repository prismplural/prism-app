import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/pluralkit/providers/pk_file_import_provider.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_file_parser.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

/// Standalone screen for importing PluralKit data from a `pk;export` JSON file.
///
/// Reuses [pkFileImportProvider] so the state machine matches the onboarding
/// file flow — just rendered without onboarding-specific wiring.
class PkFileImportScreen extends ConsumerStatefulWidget {
  const PkFileImportScreen({super.key});

  @override
  ConsumerState<PkFileImportScreen> createState() => _PkFileImportScreenState();
}

class _PkFileImportScreenState extends ConsumerState<PkFileImportScreen> {
  @override
  void initState() {
    super.initState();
    // Reset any prior state so opening the screen always starts fresh.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(pkFileImportProvider.notifier).reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pkFileImportProvider);

    return PrismPageScaffold(
      topBar: const PrismTopBar(
        title: 'Import from PluralKit file',
        showBackButton: true,
      ),
      bodyPadding: EdgeInsets.zero,
      body: switch (state.step) {
        PkFileImportStep.idle => const _IdleView(),
        PkFileImportStep.parsing => const _BusyView(label: 'Reading file…'),
        PkFileImportStep.previewing => _PreviewView(export: state.export!),
        PkFileImportStep.importing => _BusyView(
          label: state.progressLabel.isNotEmpty
              ? state.progressLabel
              : 'Importing…',
          progress: state.progress,
        ),
        PkFileImportStep.complete => _CompleteView(result: state.result!),
        PkFileImportStep.error => _ErrorView(
          message: state.error ?? 'Import failed.',
        ),
      },
    );
  }
}

class _IdleView extends ConsumerWidget {
  const _IdleView();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Icon(
          AppIcons.fileUploadOutlined,
          size: 48,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'Import from a pk;export file',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Faster than the API for large systems. In Discord, DM PluralKit '
          'with pk;export, download the JSON, then pick it below.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        PrismButton(
          onPressed: () {
            ref.read(pkFileImportProvider.notifier).selectAndParseFile();
          },
          icon: AppIcons.fileUploadOutlined,
          label: 'Select file',
          tone: PrismButtonTone.filled,
          expanded: true,
        ),
      ],
    );
  }
}

class _BusyView extends StatelessWidget {
  const _BusyView({required this.label, this.progress});
  final String label;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PrismSpinner(
              color: theme.colorScheme.primary,
              size: 80,
              dotCount: 8,
              duration: const Duration(milliseconds: 3000),
            ),
            const SizedBox(height: 24),
            Text(
              label,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (progress != null && progress! > 0) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: progress,
                borderRadius: BorderRadius.circular(
                  PrismShapes.of(context).radius(4),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PreviewView extends ConsumerWidget {
  const _PreviewView({required this.export});
  final PkFileExport export;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Icon(AppIcons.preview, size: 48, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          'Ready to import',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        PrismSectionCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PreviewRow(label: 'Members', count: export.members.length),
              if (export.groups.isNotEmpty)
                _PreviewRow(label: 'Groups', count: export.groups.length),
              _PreviewRow(
                label: 'Fronting sessions',
                count: export.switches.length,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        PrismSurface(
          fillColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
          padding: const EdgeInsets.all(12),
          child: Text(
            'Existing members with the same PluralKit ID will be updated. '
            'Duplicate switches are skipped.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 24),
        PrismButton(
          onPressed: () {
            ref.read(pkFileImportProvider.notifier).runImport();
          },
          icon: AppIcons.download,
          label: 'Import',
          tone: PrismButtonTone.filled,
          expanded: true,
        ),
        const SizedBox(height: 8),
        PrismButton(
          onPressed: () {
            ref.read(pkFileImportProvider.notifier).reset();
          },
          label: 'Pick a different file',
          tone: PrismButtonTone.outlined,
          expanded: true,
        ),
      ],
    );
  }
}

class _CompleteView extends ConsumerWidget {
  const _CompleteView({required this.result});
  final PkFileImportResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 16),
        Icon(AppIcons.checkCircle, size: 64, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          'Import complete',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        PrismSectionCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PreviewRow(label: 'Members', count: result.membersImported),
              if (result.groupsImported > 0)
                _PreviewRow(label: 'Groups', count: result.groupsImported),
              _PreviewRow(
                label: 'Switches created',
                count: result.switchesCreated,
              ),
              if (result.switchesSkipped > 0)
                _PreviewRow(
                  label: 'Switches skipped (already present)',
                  count: result.switchesSkipped,
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        PrismButton(
          onPressed: () {
            ref.read(pkFileImportProvider.notifier).reset();
            Navigator.of(context).pop();
          },
          label: 'Done',
          tone: PrismButtonTone.filled,
          expanded: true,
        ),
      ],
    );
  }
}

class _ErrorView extends ConsumerWidget {
  const _ErrorView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              AppIcons.errorOutline,
              size: 64,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Import failed',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            PrismButton(
              onPressed: () {
                ref.read(pkFileImportProvider.notifier).reset();
              },
              label: 'Try again',
              tone: PrismButtonTone.filled,
            ),
          ],
        ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(
            count.toString(),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
