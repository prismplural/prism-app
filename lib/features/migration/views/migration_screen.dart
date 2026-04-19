import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';

import 'package:prism_plurality/features/migration/providers/migration_providers.dart';
import 'package:prism_plurality/features/migration/services/sp_importer.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';
import 'package:prism_plurality/features/migration/widgets/custom_front_disposition_step.dart';
import 'package:prism_plurality/features/migration/widgets/import_preview_card.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_field_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
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
      topBar: PrismTopBar(title: context.l10n.migrationImportData, showBackButton: true),
      bodyPadding: EdgeInsets.zero,
      body: switch (migration.step) {
        ImportState.idle => _IdleView(ref: ref),
        ImportState.parsing => _LoadingView(message: context.l10n.migrationReadingFile),
        ImportState.verifying =>
          migration.spUsername != null
              ? _ConnectedView(username: migration.spUsername!, ref: ref)
              : _LoadingView(message: context.l10n.migrationVerifyingToken),
        ImportState.fetching => _FetchingView(state: migration),
        ImportState.previewing => _PreviewView(
          data: migration.exportData!,
          ref: ref,
        ),
        ImportState.chooseDispositions =>
          CustomFrontDispositionStep(data: migration.exportData!),
        ImportState.importing ||
        ImportState.downloadingAvatars => _ImportingView(state: migration),
        ImportState.complete => _CompleteView(
          result: migration.result!,
          ref: ref,
        ),
        ImportState.error => _ErrorView(
          message: migration.error ?? context.l10n.migrationUnknownError,
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
        Icon(AppIcons.swapHoriz, size: 48, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          context.l10n.migrationImportFromSimplyPlural,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.migrationImportDescription,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),

        // Option 1: API import
        _ImportMethodCard(
          icon: AppIcons.cloudDownloadOutlined,
          title: context.l10n.migrationConnectWithApi,
          subtitle: context.l10n.migrationConnectWithApiSubtitle,
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
          title: context.l10n.migrationImportFromFile,
          subtitle: context.l10n.migrationImportFromFileSubtitle,
          recommended: false,
          onTap: () {
            ref.read(importerProvider.notifier).selectAndParseFile();
          },
        ),
        const SizedBox(height: 16),

        // Reminders trade-off note — surfaced before the user picks a method
        // so reminder-heavy systems don't pick API and then realize too late.
        PrismSurface(
          fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.5,
          ),
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
                  context.l10n.migrationRemindersApiNote,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Supported data note
        PrismSectionCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.migrationSupportedDataTypes,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              _SupportedItem(icon: AppIcons.person, label: context.l10n.migrationSupportedMembers),
              _SupportedItem(
                icon: AppIcons.labelOutlined,
                label: context.l10n.migrationSupportedCustomFronts,
              ),
              _SupportedItem(
                icon: AppIcons.flashOn,
                label: context.l10n.migrationSupportedFrontingHistory,
              ),
              _SupportedItem(
                icon: AppIcons.chatBubbleOutline,
                label: context.l10n.migrationSupportedChatChannels,
              ),
              _SupportedItem(icon: AppIcons.pollOutlined, label: context.l10n.migrationSupportedPolls),
              _SupportedItem(
                icon: AppIcons.colorLens,
                label: context.l10n.migrationSupportedMemberColors,
              ),
              _SupportedItem(
                icon: AppIcons.notes,
                label: context.l10n.migrationSupportedMemberDescriptions,
              ),
              _SupportedItem(
                icon: AppIcons.imageOutlined,
                label: context.l10n.migrationSupportedAvatarImages,
              ),
              _SupportedItem(icon: AppIcons.noteOutlined, label: context.l10n.migrationSupportedNotes),
              _SupportedItem(
                icon: AppIcons.textFields,
                label: context.l10n.migrationSupportedCustomFields,
              ),
              _SupportedItem(icon: AppIcons.groupOutlined, label: context.l10n.migrationSupportedGroups),
              _SupportedItem(
                icon: AppIcons.commentOutlined,
                label: context.l10n.migrationSupportedComments,
              ),
              _SupportedItem(icon: AppIcons.alarm, label: context.l10n.migrationSupportedReminders),
            ],
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

    return PrismSurface(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 32, color: theme.colorScheme.primary),
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
                          context.l10n.migrationRecommended,
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
                        labelPadding: const EdgeInsets.symmetric(
                          horizontal: 6,
                        ),
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
      topBar: PrismTopBar(
        title: context.l10n.migrationConnectToSimplyPlural,
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
            context.l10n.migrationConnectToSimplyPlural,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.migrationEnterTokenDescription,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          // Token input
          PrismTextField(
            controller: _tokenController,
            obscureText: _obscured,
            labelText: context.l10n.migrationApiTokenLabel,
            hintText: context.l10n.migrationPasteTokenHint,
            suffix: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PrismFieldIconButton(
                  icon: _obscured
                      ? AppIcons.visibilityOff
                      : AppIcons.visibility,
                  tooltip: _obscured ? context.l10n.migrationShowToken : context.l10n.migrationHideToken,
                  onPressed: () {
                    setState(() => _obscured = !_obscured);
                  },
                ),
                PrismFieldIconButton(
                  icon: AppIcons.paste,
                  onPressed: () async {
                    final data = await Clipboard.getData('text/plain');
                    if (data?.text != null) {
                      _tokenController.text = data!.text!;
                    }
                  },
                  tooltip: context.l10n.migrationPasteFromClipboard,
                ),
              ],
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
                  context.l10n.migrationWhereDoIFindThis,
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
            PrismSurface(
              fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.5,
              ),
              padding: const EdgeInsets.all(12),
              child: Text(
                context.l10n.migrationTokenHelpText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
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
            label: context.l10n.migrationVerifyToken,
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
            label: context.l10n.back,
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
            Icon(AppIcons.checkCircle, size: 64, color: Colors.green.shade600),
            const SizedBox(height: 16),
            Text(
              context.l10n.migrationConnected,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.migrationSignedInAs(username),
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
              label: context.l10n.migrationContinue,
              tone: PrismButtonTone.filled,
              expanded: true,
            ),
            const SizedBox(height: 8),
            PrismButton(
              onPressed: () {
                ref.read(importerProvider.notifier).reset();
              },
              label: context.l10n.cancel,
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
            PrismSpinner(
              color: Theme.of(context).colorScheme.primary,
              size: 80,
              dotCount: 8,
              duration: const Duration(milliseconds: 3000),
            ),
            const SizedBox(height: 24),
            Text(
              context.l10n.migrationFetchingData,
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
          PrismSpinner(
            color: Theme.of(context).colorScheme.primary,
            size: 52,
            dotCount: 8,
            duration: const Duration(milliseconds: 3000),
          ),
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
        Icon(AppIcons.preview, size: 48, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          context.l10n.migrationPreviewImport,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.migrationPreviewDescription,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),

        ImportPreviewCard(data: data),

        const SizedBox(height: 16),

        // Info note
        PrismSurface(
          fillColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
          borderColor: theme.colorScheme.primary.withValues(alpha: 0.2),
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
                  context.l10n.migrationImportInfoNote,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),

        // API limitation note — reminders aren't available via the API
        if (ref.read(importerProvider).source == ImportSource.api &&
            data.automatedTimers.isEmpty &&
            data.repeatedTimers.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: PrismSurface(
              fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.5,
              ),
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
                      context.l10n.migrationRemindersApiNote,
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

        // Action buttons — show "Start fresh" option if previous import exists
        hasPreviousImport.when(
          data: (hasPrevious) {
            if (hasPrevious) {
              return Column(
                children: [
                  PrismButton(
                    onPressed: () {
                      ref
                          .read(importerProvider.notifier)
                          .proceedFromPreview();
                    },
                    icon: AppIcons.download,
                    label: context.l10n.migrationImportAllAddToExisting,
                    tone: PrismButtonTone.filled,
                    expanded: true,
                  ),
                  const SizedBox(height: 8),
                  PrismButton(
                    onPressed: () {
                      _showStartFreshDialog(context);
                    },
                    icon: AppIcons.refresh,
                    label: context.l10n.migrationStartFresh,
                    tone: PrismButtonTone.outlined,
                    expanded: true,
                  ),
                ],
              );
            }
            return PrismButton(
              onPressed: () {
                ref.read(importerProvider.notifier).proceedFromPreview();
              },
              icon: AppIcons.download,
              label: context.l10n.migrationImportAll,
              tone: PrismButtonTone.filled,
              expanded: true,
            );
          },
          loading: () => PrismButton(
            onPressed: () {
              ref.read(importerProvider.notifier).proceedFromPreview();
            },
            icon: AppIcons.download,
            label: context.l10n.migrationImportAll,
            tone: PrismButtonTone.filled,
            expanded: true,
          ),
          error: (_, _) => PrismButton(
            onPressed: () {
              ref.read(importerProvider.notifier).proceedFromPreview();
            },
            icon: AppIcons.download,
            label: context.l10n.migrationImportAll,
            tone: PrismButtonTone.filled,
            expanded: true,
          ),
        ),

        const SizedBox(height: 8),
        PrismButton(
          onPressed: () {
            ref.read(importerProvider.notifier).reset();
          },
          label: context.l10n.cancel,
          tone: PrismButtonTone.outlined,
          expanded: true,
        ),
      ],
    );
  }

  void _showStartFreshDialog(BuildContext context) {
    PrismDialog.confirm(
      context: context,
      title: context.l10n.migrationReplaceAllTitle,
      message: context.l10n.migrationReplaceAllMessage,
      confirmLabel: context.l10n.migrationReplaceAll,
      destructive: true,
    ).then((confirmed) {
      if (confirmed) {
        ref.read(importerProvider.notifier).proceedFromPreview(resetFirst: true);
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
            PrismSpinner(
              color: Theme.of(context).colorScheme.primary,
              size: 80,
              dotCount: 8,
              duration: const Duration(milliseconds: 3000),
            ),
            const SizedBox(height: 24),
            Text(
              context.l10n.migrationImporting,
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
                borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(4)),
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
        Icon(AppIcons.checkCircle, size: 64, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          context.l10n.migrationImportComplete,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.migrationImportSuccess(result.totalImported, result.duration.inSeconds),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),

        // Summary card
        PrismSectionCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.migrationSummary,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              _ResultRow(label: context.l10n.migrationResultMembers, count: result.membersImported),
              _ResultRow(
                label: context.l10n.migrationResultFrontSessions,
                count: result.sessionsImported,
              ),
              _ResultRow(
                label: context.l10n.migrationResultConversations,
                count: result.conversationsImported,
              ),
              _ResultRow(label: context.l10n.migrationResultMessages, count: result.messagesImported),
              _ResultRow(label: context.l10n.migrationResultPolls, count: result.pollsImported),
              if (result.notesImported > 0)
                _ResultRow(label: context.l10n.migrationResultNotes, count: result.notesImported),
              if (result.commentsImported > 0)
                _ResultRow(label: context.l10n.migrationResultComments, count: result.commentsImported),
              if (result.customFieldsImported > 0)
                _ResultRow(
                  label: context.l10n.migrationResultCustomFields,
                  count: result.customFieldsImported,
                ),
              if (result.groupsImported > 0)
                _ResultRow(label: context.l10n.migrationResultGroups, count: result.groupsImported),
              if (result.remindersImported > 0)
                _ResultRow(
                  label: context.l10n.migrationResultReminders,
                  count: result.remindersImported,
                ),
              if (result.avatarsDownloaded > 0)
                _ResultRow(
                  label: context.l10n.migrationResultAvatarsDownloaded,
                  count: result.avatarsDownloaded,
                ),
            ],
          ),
        ),

        if (result.warnings.isNotEmpty) ...[
          const SizedBox(height: 16),
          PrismSurface(
            fillColor: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
            borderColor: theme.colorScheme.error.withValues(alpha: 0.3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.migrationWarnings(result.warnings.length),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 8),
                ...result.warnings.map(
                  (w) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      w,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 16),

        // Disclosure card — what didn't come over
        PrismSectionCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.migrationNotImportedTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              _DisclosureRow(
                title: context.l10n.migrationNotImportedFriendsTitle,
                detail: context.l10n.migrationNotImportedFriendsDetail,
              ),
              _DisclosureRow(
                title: context.l10n.migrationNotImportedBoardMetaTitle,
                detail: context.l10n.migrationNotImportedBoardMetaDetail,
              ),
              _DisclosureRow(
                title: context.l10n.migrationNotImportedNotifTitle,
                detail: context.l10n.migrationNotImportedNotifDetail,
              ),
              _DisclosureRow(
                title: context.l10n.migrationNotImportedFrontRulesTitle,
                detail: context.l10n.migrationNotImportedFrontRulesDetail,
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        PrismButton(
          onPressed: () {
            ref.read(importerProvider.notifier).reset();
            Navigator.of(context).pop();
          },
          label: context.l10n.done,
          tone: PrismButtonTone.filled,
          expanded: true,
        ),
      ],
    );
  }
}

class _DisclosureRow extends StatelessWidget {
  const _DisclosureRow({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mutedColor = theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1, right: 8),
            child: Icon(Icons.info_outline, size: 16, color: mutedColor),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: mutedColor,
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
          Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
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
              context.l10n.migrationImportFailed,
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
              label: context.l10n.tryAgain,
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
                    ref.read(importerProvider.notifier).selectAndParseFile();
                  });
                },
                icon: AppIcons.fileUploadOutlined,
                label: context.l10n.migrationTryFileImport,
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
