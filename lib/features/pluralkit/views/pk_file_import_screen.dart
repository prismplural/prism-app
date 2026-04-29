import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/pluralkit/providers/pk_file_import_provider.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_file_parser.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_field_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
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
        PkFileImportStep.complete => _CompleteView(
          result: state.result!,
          mode: state.completionMode,
          switchesFound: state.export?.switches.length ?? 0,
          frontingResult: state.frontingResult,
        ),
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
          'Use a pk;export JSON plus a PluralKit token to recover fronting '
          'history. You can still import members and groups from the file only.',
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

class _PreviewView extends ConsumerStatefulWidget {
  const _PreviewView({required this.export});
  final PkFileExport export;

  @override
  ConsumerState<_PreviewView> createState() => _PreviewViewState();
}

class _PreviewViewState extends ConsumerState<_PreviewView> {
  final _tokenController = TextEditingController();
  bool _obscureToken = true;
  String? _tokenError;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _runFrontingRecovery() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _tokenError = 'Enter a PluralKit token first.');
      return;
    }
    setState(() => _tokenError = null);
    await ref
        .read(pkFileImportProvider.notifier)
        .runImport(frontingToken: token);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final terms = watchTerminology(context, ref);
    final hasSwitches = widget.export.switches.isNotEmpty;
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
              _PreviewRow(
                label: context.l10n.pkFileImportMembersLabel(terms.plural),
                count: widget.export.members.length,
              ),
              if (widget.export.groups.isNotEmpty)
                _PreviewRow(
                  label: context.l10n.pkFileImportGroupsLabel,
                  count: widget.export.groups.length,
                ),
              _PreviewRow(
                label: context.l10n.pkFileImportSwitchesFoundLabel,
                count: widget.export.switches.length,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        PrismSurface(
          fillColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
          padding: const EdgeInsets.all(12),
          child: Text(
            hasSwitches
                ? context.l10n.pkFileImportPreviewNote(terms.pluralLower)
                : 'Existing ${terms.pluralLower} with the same PluralKit ID '
                      'will be updated.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (hasSwitches) ...[
          PrismSectionCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recover fronting history',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'The file gives Prism your historical switches. The token '
                  'lets Prism match them to PluralKit switch IDs before '
                  'importing fronts.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                PrismTextField(
                  controller: _tokenController,
                  obscureText: _obscureToken,
                  labelText: context.l10n.pluralkitTokenLabel,
                  hintText: context.l10n.pluralkitPasteTokenHint,
                  isDense: true,
                  onSubmitted: (_) => _runFrontingRecovery(),
                  suffix: PrismFieldIconButton(
                    icon: _obscureToken
                        ? AppIcons.visibilityOff
                        : AppIcons.visibility,
                    tooltip: _obscureToken
                        ? context.l10n.showToken
                        : context.l10n.hideToken,
                    onPressed: () =>
                        setState(() => _obscureToken = !_obscureToken),
                  ),
                ),
                if (_tokenError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _tokenError!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                PrismButton(
                  onPressed: _runFrontingRecovery,
                  icon: AppIcons.link,
                  label: 'Match & import fronting history',
                  tone: PrismButtonTone.filled,
                  expanded: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        PrismButton(
          onPressed: () {
            ref.read(pkFileImportProvider.notifier).runImport();
          },
          icon: hasSwitches ? null : AppIcons.download,
          label: hasSwitches
              ? 'Import members/groups only'
              : context.l10n.pkFileImportImportButton,
          tone: hasSwitches ? PrismButtonTone.outlined : PrismButtonTone.filled,
          expanded: true,
        ),
        const SizedBox(height: 8),
        PrismButton(
          onPressed: () {
            ref.read(pkFileImportProvider.notifier).reset();
          },
          label: context.l10n.pkFileImportPickDifferentButton,
          tone: PrismButtonTone.outlined,
          expanded: true,
        ),
      ],
    );
  }
}

class _CompleteView extends ConsumerWidget {
  const _CompleteView({
    required this.result,
    required this.mode,
    required this.switchesFound,
    required this.frontingResult,
  });
  final PkFileImportResult result;
  final PkFileImportCompletionMode mode;
  final int switchesFound;
  final PkFileTokenFrontingImportResult? frontingResult;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final terms = watchTerminology(context, ref);
    final recoveredFronting =
        mode == PkFileImportCompletionMode.fileAndToken &&
        frontingResult?.frontingImported == true;
    final attemptedFronting = frontingResult != null;
    final newerSwitches = frontingResult?.apiOnlyOutsideRangeCount ?? 0;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 16),
        Icon(AppIcons.checkCircle, size: 64, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          context.l10n.pkFileImportCompleteHeading,
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
              _PreviewRow(
                label: context.l10n.pkFileImportMembersLabel(terms.plural),
                count: result.membersImported,
              ),
              if (result.groupsImported > 0)
                _PreviewRow(
                  label: context.l10n.pkFileImportGroupsLabel,
                  count: result.groupsImported,
                ),
              if (recoveredFronting && switchesFound > 0)
                _PreviewRow(
                  label: 'Switches matched with token',
                  count: frontingResult?.exactImportedCount ?? switchesFound,
                )
              else if (result.switchesCreated > 0)
                _PreviewRow(
                  label: context.l10n.pkFileImportSwitchesCreatedLabel,
                  count: result.switchesCreated,
                ),
              if (recoveredFronting && newerSwitches > 0)
                _PreviewRow(
                  label: 'Newer switches from PluralKit',
                  count: newerSwitches,
                ),
              if (!recoveredFronting && result.switchesSkipped > 0)
                _PreviewRow(
                  label: context.l10n.pkFileImportSwitchesFoundLabel,
                  count: result.switchesSkipped,
                ),
            ],
          ),
        ),
        if (recoveredFronting || attemptedFronting) ...[
          const SizedBox(height: 16),
          PrismSurface(
            fillColor: theme.colorScheme.primaryContainer.withValues(
              alpha: 0.3,
            ),
            padding: const EdgeInsets.all(12),
            child: Text(
              recoveredFronting
                  ? 'Fronting history was imported through the token-backed '
                        'PluralKit path so Prism can keep using canonical '
                        'switch IDs.'
                        '${newerSwitches > 0 ? ' Prism also imported $newerSwitches newer switches from PluralKit that were not in the export.' : ''}'
                  : 'Fronting history was not imported because the export and '
                        'PluralKit API did not match safely.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
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
