import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';

import 'package:prism_plurality/features/migration/providers/migration_providers.dart';
import 'package:prism_plurality/features/migration/services/sp_importer.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';
import 'package:prism_plurality/features/migration/widgets/custom_front_disposition_step.dart';
import 'package:prism_plurality/features/migration/widgets/import_preview_card.dart';
import 'package:prism_plurality/features/migration/widgets/sp_member_mapping_step.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/sp_import_warning_summary.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

/// Migration screen for importing data from Simply Plural.
///
/// Guides the user through a multi-step flow:
/// 1. Select a JSON export file
/// 2. Preview detected data
/// 3. Import progress
/// 4. Completion summary
class MigrationScreen extends ConsumerWidget {
  const MigrationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final migration = ref.watch(importerProvider);

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: context.l10n.migrationImportData,
        showBackButton: true,
      ),
      bodyPadding: EdgeInsets.zero,
      body: switch (migration.step) {
        ImportState.idle => _IdleView(ref: ref),
        ImportState.parsing => _LoadingView(
          message: context.l10n.migrationReadingFile,
        ),
        ImportState.encryptedChatsDetected => _EncryptedChatWarningView(
          data: migration.exportData!,
          ref: ref,
        ),
        ImportState.previewing => _PreviewView(
          data: migration.exportData!,
          ref: ref,
        ),
        ImportState.matchMembers => SpMemberMappingStep(
          data: migration.exportData!,
        ),
        ImportState.chooseDispositions => CustomFrontDispositionStep(
          data: migration.exportData!,
        ),
        ImportState.importing ||
        ImportState.downloadingAvatars => _ImportingView(state: migration),
        ImportState.complete => _CompleteView(
          result: migration.result!,
          ref: ref,
        ),
        ImportState.error => _ErrorView(
          message: migration.error ?? context.l10n.migrationUnknownError,
          ref: ref,
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
    final terms = watchTerminology(context, ref);

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

        _ImportMethodCard(
          icon: AppIcons.fileUploadOutlined,
          title: context.l10n.migrationImportFromFile,
          subtitle: context.l10n.migrationImportFromFileSubtitle,
          recommended: true,
          onTap: () {
            ref.read(importerProvider.notifier).selectAndParseFile();
          },
        ),
        const SizedBox(height: 16),

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
              _SupportedItem(
                icon: AppIcons.person,
                label: context.l10n.migrationSupportedMembers(terms.plural),
              ),
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
              _SupportedItem(
                icon: AppIcons.pollOutlined,
                label: context.l10n.migrationSupportedPolls,
              ),
              _SupportedItem(
                icon: AppIcons.colorLens,
                label: context.l10n.migrationSupportedMemberColors(
                  terms.singular,
                ),
              ),
              _SupportedItem(
                icon: AppIcons.notes,
                label: context.l10n.migrationSupportedMemberDescriptions(
                  terms.singular,
                ),
              ),
              _SupportedItem(
                icon: AppIcons.imageOutlined,
                label: context.l10n.migrationSupportedAvatarImages,
              ),
              _SupportedItem(
                icon: AppIcons.noteOutlined,
                label: context.l10n.migrationSupportedNotes,
              ),
              _SupportedItem(
                icon: AppIcons.textFields,
                label: context.l10n.migrationSupportedCustomFields,
              ),
              _SupportedItem(
                icon: AppIcons.groupOutlined,
                label: context.l10n.migrationSupportedGroups,
              ),
              _SupportedItem(
                icon: AppIcons.commentOutlined,
                label: context.l10n.migrationSupportedComments,
              ),
              _SupportedItem(
                icon: AppIcons.alarm,
                label: context.l10n.migrationSupportedReminders,
              ),
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
                        backgroundColor: theme.colorScheme.secondaryContainer,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
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
// Encrypted chat warning
// ---------------------------------------------------------------------------

class _EncryptedChatWarningView extends StatelessWidget {
  const _EncryptedChatWarningView({required this.data, required this.ref});

  final SpExportData data;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = data.encryptedChatMessageCount;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Icon(
          AppIcons.warningAmberRounded,
          size: 48,
          color: theme.colorScheme.error,
        ),
        const SizedBox(height: 16),
        Text(
          context.l10n.migrationEncryptedChatsTitle,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.migrationEncryptedChatsDescription(count),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        PrismSurface(
          fillColor: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
          borderColor: theme.colorScheme.error.withValues(alpha: 0.2),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                AppIcons.infoOutline,
                size: 20,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.l10n.migrationEncryptedChatsNote,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        PrismButton(
          onPressed: () {
            ref.read(importerProvider.notifier).skipEncryptedChatsAndPreview();
          },
          icon: AppIcons.skipNext,
          label: context.l10n.migrationEncryptedChatsSkip,
          tone: PrismButtonTone.filled,
          expanded: true,
        ),
        const SizedBox(height: 8),
        PrismButton(
          onPressed: () {
            ref.read(importerProvider.notifier).chooseFreshFileImport();
          },
          icon: AppIcons.fileUploadOutlined,
          label: context.l10n.migrationEncryptedChatsFresh,
          tone: PrismButtonTone.outlined,
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
    final migration = ref.watch(importerProvider);
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

        _AvatarZipPickerCard(
          avatarZipPath: migration.avatarZipPath,
          avatarZipName: migration.avatarZipName,
          onTap: () {
            ref.read(importerProvider.notifier).selectAvatarZipFile();
          },
          onClear: migration.avatarZipName == null
              ? null
              : () {
                  ref.read(importerProvider.notifier).clearAvatarZipFile();
                },
        ),

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

        const SizedBox(height: 24),

        // Action buttons — show "Start fresh" option if previous import exists
        hasPreviousImport.when(
          data: (hasPrevious) {
            if (hasPrevious) {
              return Column(
                children: [
                  PrismButton(
                    onPressed: () {
                      ref.read(importerProvider.notifier).proceedFromPreview();
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
    final terms = readTerminology(context, ref);
    PrismDialog.confirm(
      context: context,
      title: context.l10n.migrationReplaceAllTitle,
      message: context.l10n.migrationReplaceAllMessage(terms.pluralLower),
      confirmLabel: context.l10n.migrationReplaceAll,
      destructive: true,
    ).then((confirmed) {
      if (confirmed) {
        ref
            .read(importerProvider.notifier)
            .proceedFromPreview(resetFirst: true);
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
                borderRadius: BorderRadius.circular(
                  PrismShapes.of(context).radius(4),
                ),
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
    final terms = watchTerminology(context, ref);

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
          context.l10n.migrationImportSuccess(
            result.totalImported,
            result.duration.inSeconds,
          ),
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
              _ResultRow(
                label: context.l10n.migrationResultMembers(terms.plural),
                count: result.membersImported,
              ),
              if (result.membersLinked > 0)
                _ResultRow(
                  label: context.l10n.migrationResultMembersLinked(
                    terms.plural,
                  ),
                  count: result.membersLinked,
                ),
              _ResultRow(
                label: context.l10n.migrationResultFrontSessions,
                count: result.sessionsImported,
              ),
              _ResultRow(
                label: context.l10n.migrationResultConversations,
                count: result.conversationsImported,
              ),
              _ResultRow(
                label: context.l10n.migrationResultMessages,
                count: result.messagesImported,
              ),
              _ResultRow(
                label: context.l10n.migrationResultPolls,
                count: result.pollsImported,
              ),
              if (result.notesImported > 0)
                _ResultRow(
                  label: context.l10n.migrationResultNotes,
                  count: result.notesImported,
                ),
              if (result.commentsImported > 0)
                _ResultRow(
                  label: context.l10n.migrationResultComments,
                  count: result.commentsImported,
                ),
              if (result.customFieldsImported > 0)
                _ResultRow(
                  label: context.l10n.migrationResultCustomFields,
                  count: result.customFieldsImported,
                ),
              if (result.groupsImported > 0)
                _ResultRow(
                  label: context.l10n.migrationResultGroups,
                  count: result.groupsImported,
                ),
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
              if (result.avatarsImportedFromZip > 0)
                _ResultRow(
                  label: context.l10n.migrationResultAvatarZipImported,
                  count: result.avatarsImportedFromZip,
                ),
            ],
          ),
        ),

        if (result.warnings.isNotEmpty) ...[
          const SizedBox(height: 16),
          SpImportWarningSummary(
            warnings: result.warnings,
            onRetryAvatars: result.hasAvatarDownloadFailures
                ? () =>
                      ref.read(importerProvider.notifier).retryAvatarDownloads()
                : null,
            retryInProgress:
                ref.watch(importerProvider).step ==
                ImportState.downloadingAvatars,
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
                  style: theme.textTheme.bodySmall?.copyWith(color: mutedColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarZipPickerCard extends StatelessWidget {
  const _AvatarZipPickerCard({
    required this.avatarZipPath,
    required this.avatarZipName,
    required this.onTap,
    this.onClear,
  });

  final String? avatarZipPath;
  final String? avatarZipName;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedFileName = avatarZipPath == null
        ? avatarZipName
        : p.basename(avatarZipPath!);

    return PrismSurface(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(AppIcons.photoLibrary, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.migrationAvatarZipTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  selectedFileName == null
                      ? context.l10n.migrationAvatarZipSubtitle
                      : context.l10n.migrationAvatarZipSelected(
                          selectedFileName,
                        ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (onClear != null)
            IconButton(
              tooltip: context.l10n.migrationAvatarZipRemove,
              icon: Icon(AppIcons.close),
              color: theme.colorScheme.onSurfaceVariant,
              onPressed: onClear,
            )
          else
            Icon(
              AppIcons.chevronRight,
              color: theme.colorScheme.onSurfaceVariant,
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
