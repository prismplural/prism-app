/// Phase 5C — multi-step upgrade modal for the per-member fronting
/// refactor.
///
/// State machine:
///   intro → role (skipped when solo) → mode (skipped on secondary) →
///   password → running → success | failure
///
/// Drives [FrontingMigrationService] from 5B.  Don't put migration
/// logic here — only UX glue.
///
/// Mirror conventions from `data_export_sheet.dart`:
///   - Single sheet host, internal enum-driven state machine.
///   - 12+ char password gate with confirm field, show/hide toggles.
///   - Same headline + icon pattern per step.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'package:prism_plurality/features/fronting/migration/fronting_migration_service.dart';
import 'package:prism_plurality/features/fronting/migration/providers/fronting_migration_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_field_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';

/// Steps in the upgrade flow.  See file-level docstring for the
/// transitions.
enum FrontingUpgradeStep {
  intro,
  role,
  mode,
  password,
  running,
  success,
  failure,
}

/// Show the upgrade modal.
///
/// [isDismissible] — `false` for the `'notStarted'` first-time prompt
/// (user must pick something; "Not now" is the dismissal that writes
/// `'deferred'`).  `true` for the deferred-banner re-entry, where the
/// user already chose to defer once.
Future<void> showFrontingUpgradeSheet(
  BuildContext context, {
  required bool isDismissible,
}) {
  return PrismSheet.showFullScreen(
    context: context,
    isDismissible: isDismissible,
    builder: (sheetContext, scrollController) => FrontingUpgradeSheet(
      scrollController: scrollController,
      isDismissible: isDismissible,
    ),
  );
}

class FrontingUpgradeSheet extends ConsumerStatefulWidget {
  const FrontingUpgradeSheet({
    super.key,
    this.scrollController,
    this.isDismissible = true,
  });

  final ScrollController? scrollController;
  final bool isDismissible;

  @override
  ConsumerState<FrontingUpgradeSheet> createState() =>
      _FrontingUpgradeSheetState();
}

class _FrontingUpgradeSheetState extends ConsumerState<FrontingUpgradeSheet> {
  FrontingUpgradeStep _step = FrontingUpgradeStep.intro;

  // Filled in as the user progresses.  Persist across retry so the
  // failure → password → run loop doesn't force the user to redo the
  // mode/role choice.
  DeviceRole? _role;
  MigrationMode _mode = MigrationMode.upgradeAndKeep;

  // Password fields — cleared after each submit per data-export sheet
  // pattern, never retained in state across the running step.
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _passwordError;

  MigrationResult? _result;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------
  // Step transitions
  // -------------------------------------------------------------------

  Future<void> _onContinueFromIntro() async {
    // Decide whether to ask the role question.  Solo users (no peers)
    // skip straight to the mode picker.  Await the future explicitly
    // so we don't race a still-loading FutureProvider — the user may
    // tap Continue immediately after the sheet appears.
    int pairedCount;
    try {
      pairedCount = await ref.read(pairedDeviceCountProvider.future);
    } catch (_) {
      // Treat lookup failure as "assume paired" — safer to ask than
      // to silently default a multi-device user into solo mode.
      pairedCount = 1;
    }
    if (!mounted) return;
    if (pairedCount == 0) {
      // Solo path.
      setState(() {
        _role = DeviceRole.solo;
        _step = FrontingUpgradeStep.mode;
      });
      return;
    }
    setState(() => _step = FrontingUpgradeStep.role);
  }

  Future<void> _onNotNow() async {
    final runner = ref.read(frontingMigrationRunnerProvider);
    // The service writes 'deferred' to settings and returns without
    // any destructive work for `MigrationMode.notNow`.
    await runner.runMigration(
      mode: MigrationMode.notNow,
      role: DeviceRole.solo, // role is irrelevant for notNow
      shareFile: (_) async => null,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _onRoleChosen(DeviceRole role) {
    setState(() {
      _role = role;
      // Secondaries skip the mode picker — they always wipe local
      // tables and rely on re-pairing per §4.1 secondary path.  We
      // pass `upgradeAndKeep` to the service since secondary paths
      // ignore the mode value but require a non-notNow mode.
      if (role == DeviceRole.secondary) {
        _mode = MigrationMode.upgradeAndKeep;
        _step = FrontingUpgradeStep.password;
      } else {
        _step = FrontingUpgradeStep.mode;
      }
    });
  }

  void _onModeChosen(MigrationMode mode) {
    setState(() {
      _mode = mode;
      _step = FrontingUpgradeStep.password;
    });
  }

  void _onPasswordSubmit() {
    final password = _passwordController.text;
    final confirm = _confirmController.text;
    if (password.isEmpty) {
      setState(() => _passwordError = context.l10n.dataManagementPasswordEmpty);
      return;
    }
    if (password.length < 12) {
      setState(
        () => _passwordError = context.l10n.dataManagementPasswordTooShort,
      );
      return;
    }
    if (password != confirm) {
      setState(
        () => _passwordError = context.l10n.dataManagementPasswordMismatch,
      );
      return;
    }
    setState(() => _passwordError = null);
    _runMigration();
  }

  Future<void> _runMigration() async {
    setState(() => _step = FrontingUpgradeStep.running);

    final password = _passwordController.text;
    _passwordController.clear();
    _confirmController.clear();

    final runner = ref.read(frontingMigrationRunnerProvider);
    try {
      final result = await runner.runMigration(
        mode: _mode,
        role: _role ?? DeviceRole.solo,
        shareFile: _shareFile,
        password: password,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _step = result.outcome == MigrationOutcome.success
            ? FrontingUpgradeStep.success
            : FrontingUpgradeStep.failure;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _result = MigrationResult(
          outcome: MigrationOutcome.failed,
          errorMessage: e.toString(),
        );
        _step = FrontingUpgradeStep.failure;
      });
    }
  }

  /// Share-file callback handed to the migration service.  Pops the
  /// system share sheet so the user can save the PRISM1 backup
  /// somewhere durable.  Returning null aborts migration per the
  /// service's contract — but the sheet swallows the cancellation and
  /// returns null itself, which the service treats as "user backed
  /// out, keep local file but don't proceed."  We treat the share
  /// dismissal as a soft success (proceed) so users on platforms
  /// without a real share-receiver don't get blocked.
  Future<Uri?> _shareFile(File file) async {
    try {
      // We don't inspect the result — even a dismissed share is a
      // valid outcome (the file is on disk and the user can re-share
      // later).  Return a non-null Uri so the migration service
      // interprets this as success and proceeds.
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Prism Fronting Backup',
        ),
      );
      return Uri.file(file.path);
    } catch (_) {
      // Bubble the failure to the migration service so it returns a
      // failure result with a meaningful error message.
      rethrow;
    }
  }

  void _retry() {
    setState(() {
      _result = null;
      _step = FrontingUpgradeStep.password;
    });
  }

  // -------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        PrismSheetTopBar(title: context.l10n.frontingUpgradeTitle),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            controller: widget.scrollController,
            padding: EdgeInsets.fromLTRB(
              24,
              24,
              24,
              24 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                switch (_step) {
                  FrontingUpgradeStep.intro => _buildIntro(theme),
                  FrontingUpgradeStep.role => _buildRole(theme),
                  FrontingUpgradeStep.mode => _buildMode(theme),
                  FrontingUpgradeStep.password => _buildPassword(theme),
                  FrontingUpgradeStep.running => _buildRunning(theme),
                  FrontingUpgradeStep.success => _buildSuccess(theme),
                  FrontingUpgradeStep.failure => _buildFailure(theme),
                },
              ],
            ),
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------
  // Step bodies
  // -------------------------------------------------------------------

  Widget _buildIntro(ThemeData theme) {
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
            AppIcons.personOutline,
            size: 40,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          context.l10n.frontingUpgradeIntroHeadline,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          context.l10n.frontingUpgradeIntroBody,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        PrismButton(
          onPressed: _onContinueFromIntro,
          label: context.l10n.frontingUpgradeContinue,
          tone: PrismButtonTone.filled,
          expanded: true,
        ),
        const SizedBox(height: 8),
        PrismButton(
          onPressed: _onNotNow,
          label: context.l10n.frontingUpgradeNotNow,
          tone: PrismButtonTone.subtle,
          expanded: true,
        ),
      ],
    );
  }

  Widget _buildRole(ThemeData theme) {
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
            AppIcons.checkCircleOutline,
            size: 40,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          context.l10n.frontingUpgradeRoleHeadline,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          context.l10n.frontingUpgradeRoleBody,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        PrismButton(
          onPressed: () => _onRoleChosen(DeviceRole.primary),
          label: context.l10n.frontingUpgradeRolePrimary,
          tone: PrismButtonTone.filled,
          expanded: true,
        ),
        const SizedBox(height: 8),
        PrismButton(
          onPressed: () => _onRoleChosen(DeviceRole.secondary),
          label: context.l10n.frontingUpgradeRoleSecondary,
          tone: PrismButtonTone.outlined,
          expanded: true,
        ),
      ],
    );
  }

  Widget _buildMode(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.frontingUpgradeModeHeadline,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        _ModeCard(
          icon: AppIcons.checkCircleOutline,
          title: context.l10n.frontingUpgradeModeKeepTitle,
          description: context.l10n.frontingUpgradeModeKeepBody,
          recommended: true,
          recommendedLabel: context.l10n.frontingUpgradeRecommended,
          onTap: () => _onModeChosen(MigrationMode.upgradeAndKeep),
        ),
        const SizedBox(height: 12),
        _ModeCard(
          icon: AppIcons.warningAmberRounded,
          title: context.l10n.frontingUpgradeModeFreshTitle,
          description: context.l10n.frontingUpgradeModeFreshBody,
          onTap: () => _onModeChosen(MigrationMode.startFresh),
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
          context.l10n.frontingUpgradePasswordHeadline,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.frontingUpgradePasswordBody,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          context.l10n.frontingUpgradePasswordNote,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 20),
        PrismTextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          autofocus: true,
          labelText: context.l10n.dataManagementPasswordLabel,
          hintText: context.l10n.dataManagementPasswordHint,
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
        ),
        const SizedBox(height: 12),
        PrismTextField(
          controller: _confirmController,
          obscureText: _obscureConfirm,
          labelText: context.l10n.dataManagementConfirmPasswordLabel,
          errorText: _passwordError,
          suffix: PrismFieldIconButton(
            icon: _obscureConfirm
                ? AppIcons.visibilityOff
                : AppIcons.visibility,
            tooltip: _obscureConfirm
                ? context.l10n.dataManagementShowPassword
                : context.l10n.dataManagementHidePassword,
            onPressed: () =>
                setState(() => _obscureConfirm = !_obscureConfirm),
          ),
          onSubmitted: (_) => _onPasswordSubmit(),
        ),
        const SizedBox(height: 20),
        PrismButton(
          onPressed: _onPasswordSubmit,
          icon: AppIcons.lock,
          label: context.l10n.frontingUpgradePasswordSubmit,
          tone: PrismButtonTone.filled,
          expanded: true,
        ),
      ],
    );
  }

  Widget _buildRunning(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        const PrismLoadingState(),
        const SizedBox(height: 24),
        Text(
          context.l10n.frontingUpgradeRunning,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.frontingUpgradeRunningSubtitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSuccess(ThemeData theme) {
    final result = _result;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(AppIcons.checkCircleOutline, size: 48, color: Colors.green),
        const SizedBox(height: 16),
        Text(
          context.l10n.frontingUpgradeSuccessHeadline,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        if (result != null) ...[
          ..._buildResultCounts(theme, result),
          if (result.exportFile != null) ...[
            const SizedBox(height: 8),
            Text(
              result.exportFile!.path.split('/').last,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
        const SizedBox(height: 16),
        // Re-pair guidance — primary, secondary, or solo.
        Text(
          _rePairCopy(context),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        PrismButton(
          onPressed: () => Navigator.of(context).pop(),
          label: context.l10n.done,
          tone: PrismButtonTone.filled,
          expanded: true,
        ),
      ],
    );
  }

  Widget _buildFailure(ThemeData theme) {
    final result = _result;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(AppIcons.errorOutline, size: 48, color: Colors.red),
        const SizedBox(height: 16),
        Text(
          context.l10n.frontingUpgradeFailureHeadline,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          result?.errorMessage ?? context.l10n.migrationUnknownError,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
        const SizedBox(height: 12),
        if (result?.exportFile != null)
          Text(
            context.l10n.frontingUpgradeFailureBackupNote,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: PrismButton(
                onPressed: () => Navigator.of(context).pop(),
                label: context.l10n.close,
                tone: PrismButtonTone.outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PrismButton(
                onPressed: _retry,
                label: context.l10n.dataManagementRetry,
                tone: PrismButtonTone.filled,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // -------------------------------------------------------------------
  // Result-screen helpers
  // -------------------------------------------------------------------

  /// One Text per nonzero counter so the success screen feels concrete
  /// without being noisy.  Order matches the spec's natural reading
  /// flow: rows preserved → fan-out → cleanup → sentinel.
  List<Widget> _buildResultCounts(ThemeData theme, MigrationResult r) {
    final l10n = context.l10n;
    final lines = <String>[];
    if (r.spRowsMigrated > 0) {
      lines.add(l10n.frontingUpgradeCountSpMigrated(r.spRowsMigrated));
    }
    if (r.nativeRowsMigrated > 0) {
      lines.add(l10n.frontingUpgradeCountNativeMigrated(r.nativeRowsMigrated));
    }
    if (r.nativeRowsExpanded > 0) {
      lines.add(l10n.frontingUpgradeCountNativeExpanded(r.nativeRowsExpanded));
    }
    if (r.pkRowsDeleted > 0) {
      lines.add(l10n.frontingUpgradeCountPkDeleted(r.pkRowsDeleted));
    }
    if (r.commentsMigrated > 0) {
      lines.add(l10n.frontingUpgradeCountCommentsMigrated(r.commentsMigrated));
    }
    if (r.orphanRowsAssignedToSentinel > 0) {
      lines.add(
        l10n.frontingUpgradeCountOrphansAssigned(r.orphanRowsAssignedToSentinel),
      );
    }
    if (r.unknownSentinelCreated) {
      lines.add(l10n.frontingUpgradeCountSentinelCreated);
    }
    if (lines.isEmpty) return const [];
    return [
      for (final line in lines) ...[
        Text(
          line,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
      ],
    ];
  }

  String _rePairCopy(BuildContext context) {
    switch (_role) {
      case DeviceRole.primary:
        return context.l10n.frontingUpgradeRepairPrimary;
      case DeviceRole.secondary:
        return context.l10n.frontingUpgradeRepairSecondary;
      case DeviceRole.solo:
      case null:
        return context.l10n.frontingUpgradeRepairSolo;
    }
  }
}

// ---------------------------------------------------------------------
// Mode picker card
// ---------------------------------------------------------------------

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.recommended = false,
    this.recommendedLabel,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;
  final bool recommended;
  final String? recommendedLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: recommended
                ? accent.withValues(alpha: 0.08)
                : theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: recommended
                  ? accent.withValues(alpha: 0.4)
                  : theme.colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 28, color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (recommended && recommendedLabel != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              recommendedLabel!,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
