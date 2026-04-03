import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/migration/providers/migration_providers.dart';
import 'package:prism_plurality/features/migration/services/sp_importer.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';
import 'package:prism_plurality/features/migration/widgets/import_preview_card.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

/// Migration screen for importing data from Simply Plural.
///
/// Guides the user through a multi-step flow:
/// 1. Choose import method (API or file)
/// 2. (API) Enter token -> verify -> fetch
/// 3. Preview detected data
/// 4. Import progress
/// 5. Completion summary
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
        ImportState.verifying => migration.spUsername != null
            ? _ConnectedView(username: migration.spUsername!, ref: ref)
            : const _LoadingView(message: 'Verifying token...'),
        ImportState.fetching => _FetchingView(state: migration),
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
            source: migration.source,
          ),
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Step 1: Idle / Method selection
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
          AppIcons.swapHoriz,
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
          'Bring your existing data into Prism. Choose how you would '
          'like to import your Simply Plural data.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),

        // Option 1: API import
        _ImportMethodCard(
          icon: AppIcons.cloudDownloadOutlined,
          title: 'Connect with API',
          subtitle: 'No file export needed — imports directly from your account',
          recommended: true,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => _TokenInputScreen(ref: ref),
              ),
            );
          },
        ),
        const SizedBox(height: 12),

        // Option 2: File import
        _ImportMethodCard(
          icon: AppIcons.fileUploadOutlined,
          title: 'Import from file',
          subtitle: 'Use a JSON export file from Simply Plural',
          recommended: false,
          onTap: () {
            ref.read(importerProvider.notifier).selectAndParseFile();
          },
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
                _SupportedItem(icon: AppIcons.person, label: 'Members'),
                _SupportedItem(
                    icon: AppIcons.labelOutlined, label: 'Custom fronts'),
                _SupportedItem(
                    icon: AppIcons.flashOn, label: 'Fronting history'),
                _SupportedItem(
                    icon: AppIcons.chatBubbleOutline,
                    label: 'Chat channels & messages'),
                _SupportedItem(
                    icon: AppIcons.pollOutlined, label: 'Polls'),
                _SupportedItem(
                    icon: AppIcons.colorLens, label: 'Member colors'),
                _SupportedItem(
                    icon: AppIcons.notes, label: 'Member descriptions'),
                _SupportedItem(
                    icon: AppIcons.imageOutlined, label: 'Avatar images'),
                _SupportedItem(
                    icon: AppIcons.noteOutlined, label: 'Notes'),
                _SupportedItem(
                    icon: AppIcons.textFields, label: 'Custom fields'),
                _SupportedItem(
                    icon: AppIcons.groupOutlined, label: 'Groups'),
                _SupportedItem(
                    icon: AppIcons.commentOutlined,
                    label: 'Comments on front sessions'),
                _SupportedItem(
                    icon: AppIcons.alarm, label: 'Reminders'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Import method card
// ---------------------------------------------------------------------------

class _ImportMethodCard extends StatelessWidget {
  const _ImportMethodCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.recommended,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool recommended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                icon,
                size: 32,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (recommended) ...[
                          const SizedBox(width: 8),
                          Chip(
                            label: Text(
                              'Recommended',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSecondaryContainer,
                              ),
                            ),
                            backgroundColor:
                                theme.colorScheme.secondaryContainer,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            labelPadding:
                                const EdgeInsets.symmetric(horizontal: 6),
                          ),
                        ],
                      ],
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
              Icon(
                AppIcons.chevronRight,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Token input (API flow)
// ---------------------------------------------------------------------------

class _TokenInputScreen extends ConsumerStatefulWidget {
  const _TokenInputScreen({required this.ref});

  final WidgetRef ref;

  @override
  ConsumerState<_TokenInputScreen> createState() => _TokenInputScreenState();
}

class _TokenInputScreenState extends ConsumerState<_TokenInputScreen> {
  final _tokenController = TextEditingController();
  bool _obscured = true;
  bool _showHelp = false;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Listen for state changes to pop back when verification succeeds or
    // transitions to a non-idle state that the main screen handles.
    final migration = ref.watch(importerProvider);
    if (migration.step != ImportState.idle &&
        migration.step != ImportState.verifying) {
      // Pop after build completes so we don't interfere with the widget tree.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    }
    // If verification succeeded and username is set, pop to show _ConnectedView.
    if (migration.step == ImportState.verifying &&
        migration.spUsername != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    }

    final isVerifying =
        migration.step == ImportState.verifying && migration.spUsername == null;

    return PrismPageScaffold(
      topBar: const PrismTopBar(
        title: 'Connect to Simply Plural',
        showBackButton: true,
      ),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Icon(
            AppIcons.cloudDownloadOutlined,
            size: 48,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Connect to Simply Plural',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Enter your API token to import data directly.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          // Token input
          TextField(
            controller: _tokenController,
            obscureText: _obscured,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'API Token',
              hintText: 'Paste your token here',
              border: const OutlineInputBorder(),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      _obscured ? AppIcons.visibilityOff : AppIcons.visibility,
                    ),
                    onPressed: () {
                      setState(() => _obscured = !_obscured);
                    },
                    tooltip: _obscured ? 'Show token' : 'Hide token',
                  ),
                  IconButton(
                    icon: Icon(AppIcons.paste),
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null) {
                        _tokenController.text = data!.text!;
                      }
                    },
                    tooltip: 'Paste from clipboard',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Help expandable
          GestureDetector(
            onTap: () {
              setState(() => _showHelp = !_showHelp);
            },
            child: Row(
              children: [
                Icon(
                  _showHelp ? AppIcons.expandLess : AppIcons.expandMore,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  'Where do I find this?',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (_showHelp) ...[
            const SizedBox(height: 8),
            Card(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'In Simply Plural, go to Settings \u2192 Account \u2192 '
                  'Tokens. Create a new token with Read permission and '
                  'copy it.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),

          // Verify button
          PrismButton(
            onPressed: () {
              ref
                  .read(importerProvider.notifier)
                  .verifyToken(_tokenController.text);
            },
            icon: AppIcons.verifiedOutlined,
            label: 'Verify Token',
            tone: PrismButtonTone.filled,
            expanded: true,
            isLoading: isVerifying,
            enabled: !isVerifying,
          ),
          const SizedBox(height: 8),

          // Back button
          PrismButton(
            onPressed: () {
              ref.read(importerProvider.notifier).reset();
              Navigator.of(context).pop();
            },
            label: 'Back',
            tone: PrismButtonTone.outlined,
            expanded: true,
            enabled: !isVerifying,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Connected view (after token verification)
// ---------------------------------------------------------------------------

class _ConnectedView extends StatelessWidget {
  const _ConnectedView({required this.username, required this.ref});

  final String username;
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
              AppIcons.checkCircle,
              size: 64,
              color: Colors.green.shade600,
            ),
            const SizedBox(height: 16),
            Text(
              'Connected',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Signed in as $username',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            PrismButton(
              onPressed: () {
                ref.read(importerProvider.notifier).fetchFromApi();
              },
              icon: AppIcons.download,
              label: 'Continue',
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
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Fetching view (API data download)
// ---------------------------------------------------------------------------

class _FetchingView extends StatelessWidget {
  const _FetchingView({required this.state});

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
            const SizedBox(
              width: 80,
              height: 80,
              child: CircularProgressIndicator(
                strokeWidth: 6,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Fetching data from Simply Plural...',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              state.progressLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
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
    final hasPreviousImport = ref.watch(hasPreviousSpImportProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Icon(
          AppIcons.preview,
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
          'Review what was found before importing.',
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
                  AppIcons.infoOutline,
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

        // API limitation note — reminders aren't available via the API
        if (ref.read(importerProvider).source == ImportSource.api &&
            data.automatedTimers.isEmpty &&
            data.repeatedTimers.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Card(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      AppIcons.infoOutline,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Reminders are not available via the API. '
                        'To import reminders, use a file export instead.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        const SizedBox(height: 24),

        // Action buttons — show "Start fresh" option if previous import exists
        hasPreviousImport.when(
          data: (hasPrevious) {
            if (hasPrevious) {
              return Column(
                children: [
                  PrismButton(
                    onPressed: () {
                      ref.read(importerProvider.notifier).executeImport();
                    },
                    icon: AppIcons.download,
                    label: 'Import All (add to existing)',
                    tone: PrismButtonTone.filled,
                    expanded: true,
                  ),
                  const SizedBox(height: 8),
                  PrismButton(
                    onPressed: () {
                      _showStartFreshDialog(context);
                    },
                    icon: AppIcons.refresh,
                    label: 'Start Fresh (replace all data)',
                    tone: PrismButtonTone.outlined,
                    expanded: true,
                  ),
                ],
              );
            }
            return PrismButton(
              onPressed: () {
                ref.read(importerProvider.notifier).executeImport();
              },
              icon: AppIcons.download,
              label: 'Import All',
              tone: PrismButtonTone.filled,
              expanded: true,
            );
          },
          loading: () => PrismButton(
            onPressed: () {
              ref.read(importerProvider.notifier).executeImport();
            },
            icon: AppIcons.download,
            label: 'Import All',
            tone: PrismButtonTone.filled,
            expanded: true,
          ),
          error: (_, _) => PrismButton(
            onPressed: () {
              ref.read(importerProvider.notifier).executeImport();
            },
            icon: AppIcons.download,
            label: 'Import All',
            tone: PrismButtonTone.filled,
            expanded: true,
          ),
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

  void _showStartFreshDialog(BuildContext context) {
    PrismDialog.confirm(
      context: context,
      title: 'Replace all data?',
      message: 'This will delete all existing members, front history, '
          'conversations, and other data before importing. '
          'This action cannot be undone.\n\n'
          'If you have sync set up, other paired devices should '
          'also be reset to avoid conflicts.',
      confirmLabel: 'Replace All',
      destructive: true,
    ).then((confirmed) {
      if (confirmed) {
        ref
            .read(importerProvider.notifier)
            .executeImport(resetFirst: true);
      }
    });
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
          AppIcons.checkCircle,
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
                if (result.notesImported > 0)
                  _ResultRow(label: 'Notes', count: result.notesImported),
                if (result.commentsImported > 0)
                  _ResultRow(
                      label: 'Comments', count: result.commentsImported),
                if (result.customFieldsImported > 0)
                  _ResultRow(
                      label: 'Custom fields',
                      count: result.customFieldsImported),
                if (result.groupsImported > 0)
                  _ResultRow(label: 'Groups', count: result.groupsImported),
                if (result.remindersImported > 0)
                  _ResultRow(
                      label: 'Reminders', count: result.remindersImported),
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
  const _ErrorView({
    required this.message,
    required this.ref,
    required this.source,
  });

  final String message;
  final WidgetRef ref;
  final ImportSource source;

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
              AppIcons.errorOutline,
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
            if (source == ImportSource.api) ...[
              const SizedBox(height: 8),
              PrismButton(
                onPressed: () {
                  ref.read(importerProvider.notifier).reset();
                  // After resetting, the idle view will show with both options.
                  // The user can then tap "Import from file".
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    ref
                        .read(importerProvider.notifier)
                        .selectAndParseFile();
                  });
                },
                icon: AppIcons.fileUploadOutlined,
                label: 'Try file import instead',
                tone: PrismButtonTone.outlined,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------

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
