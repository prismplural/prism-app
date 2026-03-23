import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/migration/providers/migration_providers.dart';
import 'package:prism_plurality/features/migration/services/sp_importer.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';
import 'package:prism_plurality/features/migration/widgets/import_preview_card.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

/// Migration screen for importing data from Simply Plural.
///
/// Guides the user through a multi-step flow:
/// 1. Select export file
/// 2. Preview detected data
/// 3. Import progress
/// 4. Completion summary
class MigrationScreen extends ConsumerWidget {
  const MigrationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final migration = ref.watch(importerProvider);

    return PrismPageScaffold(
      topBar: const PrismTopBar(
        title: 'Import Data',
        showBackButton: true,
      ),
      bodyPadding: EdgeInsets.zero,
      body: switch (migration.step) {
        ImportState.idle => _IdleView(ref: ref),
        ImportState.parsing => const _LoadingView(message: 'Reading file...'),
        ImportState.previewing => _PreviewView(
            data: migration.exportData!,
            ref: ref,
          ),
        ImportState.importing ||
        ImportState.downloadingAvatars =>
          _ImportingView(state: migration),
        ImportState.complete => _CompleteView(
            result: migration.result!,
            ref: ref,
          ),
        ImportState.error => _ErrorView(
            message: migration.error ?? 'An unknown error occurred.',
            ref: ref,
          ),
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Step 1: Idle / File selection
// ---------------------------------------------------------------------------

class _IdleView extends StatelessWidget {
  const _IdleView({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Icon(
          Icons.swap_horiz,
          size: 48,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'Import from Simply Plural',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Bring your existing data into Prism. Export your data from '
          'Simply Plural, then import it here to get started quickly.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 32),

        // Instructions
        const _StepTile(
          step: 1,
          title: 'Export from Simply Plural',
          subtitle: 'Go to Settings > Export in Simply Plural and '
              'save the JSON export file.',
        ),
        const _StepTile(
          step: 2,
          title: 'Select the file here',
          subtitle: 'Choose the exported JSON file from your device.',
        ),
        const _StepTile(
          step: 3,
          title: 'Review & confirm',
          subtitle: 'Preview what will be imported and confirm '
              'before any data is added.',
        ),
        const SizedBox(height: 24),

        // Select file button
        PrismButton(
          onPressed: () {
            ref.read(importerProvider.notifier).selectAndParseFile();
          },
          icon: Icons.file_upload_outlined,
          label: 'Select SP Export File',
          tone: PrismButtonTone.filled,
          expanded: true,
        ),
        const SizedBox(height: 24),

        // Supported data note
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Supported data types',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                const _SupportedItem(icon: Icons.person, label: 'Members'),
                const _SupportedItem(
                    icon: Icons.label_outlined, label: 'Custom fronts'),
                const _SupportedItem(
                    icon: Icons.flash_on, label: 'Fronting history'),
                const _SupportedItem(
                    icon: Icons.chat_bubble_outline, label: 'Chat channels & messages'),
                const _SupportedItem(
                    icon: Icons.poll_outlined, label: 'Polls'),
                const _SupportedItem(
                    icon: Icons.color_lens, label: 'Member colors'),
                const _SupportedItem(
                    icon: Icons.notes, label: 'Member descriptions'),
                const _SupportedItem(
                    icon: Icons.image_outlined, label: 'Avatar images'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Loading spinner
// ---------------------------------------------------------------------------

class _LoadingView extends StatelessWidget {
  const _LoadingView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(message),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2: Preview
// ---------------------------------------------------------------------------

class _PreviewView extends StatelessWidget {
  const _PreviewView({required this.data, required this.ref});

  final SpExportData data;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Icon(
          Icons.preview,
          size: 48,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'Preview Import',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Review what was found in your export file before importing.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),

        ImportPreviewCard(data: data),

        const SizedBox(height: 16),

        // Info note
        Card(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Imported data will be added alongside any existing data. '
                    'Nothing will be overwritten.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        // Action buttons
        PrismButton(
          onPressed: () {
            ref.read(importerProvider.notifier).executeImport();
          },
          icon: Icons.download,
          label: 'Import All',
          tone: PrismButtonTone.filled,
          expanded: true,
        ),
        const SizedBox(height: 8),
        PrismButton(
          onPressed: () {
            ref.read(importerProvider.notifier).reset();
          },
          label: 'Cancel',
          tone: PrismButtonTone.outlined,
          expanded: true,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 3: Importing
// ---------------------------------------------------------------------------

class _ImportingView extends StatelessWidget {
  const _ImportingView({required this.state});

  final MigrationState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 80,
              height: 80,
              child: CircularProgressIndicator(
                value: state.progress > 0 ? state.progress : null,
                strokeWidth: 6,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Importing...',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              state.progressLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (state.total > 0) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: state.progress,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 8),
              Text(
                '${state.current} / ${state.total}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 4: Complete
// ---------------------------------------------------------------------------

class _CompleteView extends StatelessWidget {
  const _CompleteView({required this.result, required this.ref});

  final ImportResult result;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 16),
        Icon(
          Icons.check_circle,
          size: 64,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'Import Complete',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Successfully imported ${result.totalImported} items '
          'in ${result.duration.inSeconds}s.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),

        // Summary card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Summary',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                _ResultRow(label: 'Members', count: result.membersImported),
                _ResultRow(
                    label: 'Front sessions', count: result.sessionsImported),
                _ResultRow(
                    label: 'Conversations',
                    count: result.conversationsImported),
                _ResultRow(label: 'Messages', count: result.messagesImported),
                _ResultRow(label: 'Polls', count: result.pollsImported),
                if (result.avatarsDownloaded > 0)
                  _ResultRow(
                      label: 'Avatars downloaded',
                      count: result.avatarsDownloaded),
              ],
            ),
          ),
        ),

        if (result.warnings.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${result.warnings.length} warning(s)',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...result.warnings.map((w) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          w,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      )),
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: 24),

        PrismButton(
          onPressed: () {
            ref.read(importerProvider.notifier).reset();
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

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Text(
            count.toString(),
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error view
// ---------------------------------------------------------------------------

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.ref});

  final String message;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Import Failed',
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
                ref.read(importerProvider.notifier).reset();
              },
              label: 'Try Again',
              tone: PrismButtonTone.filled,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.step,
    required this.title,
    required this.subtitle,
  });

  final int step;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              '$step',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SupportedItem extends StatelessWidget {
  const _SupportedItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
