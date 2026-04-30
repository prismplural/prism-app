/// Phase 5C — multi-step upgrade modal for the per-member fronting
/// refactor.
///
/// State machine:
///   intro → role (skipped when solo) → mode (skipped on secondary) →
///   password → exporting → backupReady → running → success | failure
///
/// Drives [FrontingMigrationService] from 5B.  Don't put migration
/// logic here — only UX glue.
///
/// Mirror conventions from `data_export_sheet.dart`:
///   - Single sheet host, internal enum-driven state machine.
///   - 12+ char password gate with confirm field, show/hide toggles.
///   - Same headline + icon pattern per step.
///
/// The `backupReady` step is a hard gate before any destructive work —
/// the user must save the PRISM1 backup somewhere durable (file
/// picker), share it, or tick the manual "I saved this" checkbox
/// before the Continue button enables. Dismissing from this step
/// leaves settings at `'notStarted'` so the destructive phase never
/// runs.
library;

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'package:prism_plurality/features/fronting/migration/fronting_migration_service.dart';
import 'package:prism_plurality/features/fronting/migration/providers/fronting_migration_providers.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
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

  /// PRISM1 export is being built (between password submission and the
  /// durable-save gate). Renders a spinner. On success, transitions to
  /// [backupReady]; on failure, transitions to [failure].
  exporting,

  /// Durable-save gate. Renders the freshly-built backup file with
  /// three actions (save to file, share, manual checkbox) and a
  /// Continue button that's disabled until the user confirms they have
  /// saved the file somewhere recoverable. Dismissing from this step
  /// leaves settings at `'notStarted'`; the destructive phase never
  /// runs.
  backupReady,

  /// The destructive Drift transaction + post-tx cleanup is running.
  running,
  success,
  failure,

  /// Entered when the modal opens to mode == 'inProgress' (Drift
  /// transaction committed but a post-tx step like the FFI engine
  /// reset or keychain wipe failed). Renders a streamlined "Finish
  /// migration" screen that calls `resumeCleanup()` on tap. No
  /// password, no role, no destructive DB work — just the post-tx
  /// idempotent cleanup.
  resumeCleanup,
}

enum _PostMigrationPkImportStatus {
  idle,
  running,
  imported,
  needsToken,
  failed,
}

/// Result of the share-or-save callback. `true` means the user
/// committed to a destination (selected a save location, completed a
/// share); `false` means they cancelled or dismissed without saving.
typedef BackupHandoffCallback = Future<bool> Function(File file);

/// Show the upgrade modal.
///
/// [isDismissible] — `false` for the `'notStarted'` first-time prompt
/// (user must pick something; "Not now" is the dismissal that writes
/// `'deferred'`).  `true` for the deferred-banner re-entry, where the
/// user already chose to defer once.
Future<void> showFrontingUpgradeSheet(
  BuildContext context, {
  required bool isDismissible,
  BackupHandoffCallback? shareBackup,
  BackupHandoffCallback? saveBackup,
  bool autoRunPluralKitImport = true,
}) {
  return PrismSheet.showFullScreen(
    context: context,
    isDismissible: isDismissible,
    builder: (sheetContext, scrollController) => FrontingUpgradeSheet(
      scrollController: scrollController,
      isDismissible: isDismissible,
      shareBackup: shareBackup,
      saveBackup: saveBackup,
      autoRunPluralKitImport: autoRunPluralKitImport,
    ),
  );
}

class FrontingUpgradeSheet extends ConsumerStatefulWidget {
  const FrontingUpgradeSheet({
    super.key,
    this.scrollController,
    this.isDismissible = true,
    this.shareBackup,
    this.saveBackup,
    this.autoRunPluralKitImport = true,
  });

  final ScrollController? scrollController;
  final bool isDismissible;

  /// Optional override for the share-sheet handoff used by the
  /// `backupReady` step. Production wiring uses `share_plus` and
  /// inspects `ShareResult.status`. Tests pass an in-process callback
  /// to avoid platform-channel calls. Returns `true` if the user
  /// completed the share (auto-ticks the acknowledgment checkbox);
  /// `false` if dismissed.
  final BackupHandoffCallback? shareBackup;

  /// Optional override for the save-as handoff used by the
  /// `backupReady` step. Production wiring uses
  /// `FilePicker.platform.saveFile`. Returns `true` if the user picked
  /// a destination (auto-ticks the acknowledgment checkbox); `false`
  /// if cancelled.
  final BackupHandoffCallback? saveBackup;

  /// When true, a successful migration that cleared PK rows attempts a
  /// one-time PK API re-import before prompting for a temporary token.
  /// Tests can disable this to keep the sheet hermetic.
  final bool autoRunPluralKitImport;

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

  /// Filled in by `prepareBackup`; cleared on retry. The destructive
  /// phase is gated on this being non-null AND [_backupAcknowledged].
  File? _backupFile;

  /// Tracks whether the user has confirmed they saved the backup
  /// somewhere durable. Auto-ticked on a successful save-as or share;
  /// also user-toggleable via the manual checkbox on the
  /// `backupReady` step.
  bool _backupAcknowledged = false;

  MigrationResult? _result;
  _PostMigrationPkImportStatus _pkImportStatus =
      _PostMigrationPkImportStatus.idle;
  String? _pkImportError;
  bool _pkTokenPromptShown = false;

  @override
  void initState() {
    super.initState();
    // If the migration is mid-cleanup (Drift tx committed but post-tx
    // step failed), advance to the resume-cleanup screen instead of
    // the normal intro. Try the cached value first; if not yet
    // available, listen for the first stream emission and advance
    // then. listenManual handles the disposal lifecycle so we don't
    // leak the subscription past widget unmount.
    final cached = ref.read(frontingMigrationModeProvider).value;
    if (cached == FrontingMigrationService.modeInProgress) {
      _step = FrontingUpgradeStep.resumeCleanup;
      return;
    }
    ref.listenManual<AsyncValue<String>>(frontingMigrationModeProvider, (
      prev,
      next,
    ) {
      if (!mounted) return;
      if (next.value == FrontingMigrationService.modeInProgress &&
          _step == FrontingUpgradeStep.intro) {
        setState(() => _step = FrontingUpgradeStep.resumeCleanup);
      }
    }, fireImmediately: true);
  }

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
    // any destructive work for `MigrationMode.notNow`. The settings
    // write can still fail (e.g. DAO storage error); inspect the
    // result so a silent failure doesn't pop the modal as if the
    // deferral landed — the user would just see the upgrade banner
    // again on next launch with no explanation.
    MigrationResult result;
    try {
      result = await runner.runMigration(
        mode: MigrationMode.notNow,
        role: DeviceRole.solo, // role is irrelevant for notNow
        shareFile: (_) async => null,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _result = MigrationResult(
          outcome: MigrationOutcome.failed,
          errorMessage: e.toString(),
        );
        _step = FrontingUpgradeStep.failure;
      });
      return;
    }
    if (!mounted) return;
    if (result.outcome == MigrationOutcome.failed) {
      // Keep the modal open on the failure step so the user can see
      // what went wrong and retry. Mirrors the destructive-path
      // failure handling in `_runDestructive`.
      setState(() {
        _result = result;
        _step = FrontingUpgradeStep.failure;
      });
      return;
    }
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

  /// Phase 1: invoke `prepareBackup`. On success, transitions to
  /// `backupReady` so the user can save / share / acknowledge before
  /// the destructive phase runs (codex P1 #8). On failure, transitions
  /// to `failure` with the export error.
  Future<void> _runMigration() async {
    setState(() {
      _step = FrontingUpgradeStep.exporting;
      _backupFile = null;
      _backupAcknowledged = false;
    });

    final password = _passwordController.text;
    _passwordController.clear();
    _confirmController.clear();

    final runner = ref.read(frontingMigrationRunnerProvider);
    try {
      final file = await runner.prepareBackup(mode: _mode, password: password);
      if (!mounted) return;
      setState(() {
        _backupFile = file;
        _step = FrontingUpgradeStep.backupReady;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _result = MigrationResult(
          outcome: MigrationOutcome.failed,
          errorMessage: 'PRISM1 export failed: $e',
        );
        _step = FrontingUpgradeStep.failure;
      });
    }
  }

  /// Phase 2: run the destructive transaction + post-tx cleanup. Only
  /// invoked from the `backupReady` step's Continue button after the
  /// user has acknowledged saving the backup.
  Future<void> _runDestructive() async {
    final file = _backupFile;
    if (file == null) {
      // Defensive: should be unreachable since the Continue button is
      // gated on _backupFile + _backupAcknowledged.
      return;
    }
    setState(() => _step = FrontingUpgradeStep.running);
    final runner = ref.read(frontingMigrationRunnerProvider);
    try {
      final result = await runner.runMigrationDestructive(
        mode: _mode,
        role: _role ?? DeviceRole.solo,
        exportFile: file,
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
          exportFile: file,
          errorMessage: e.toString(),
        );
        _step = FrontingUpgradeStep.failure;
      });
    }
  }

  /// Default share-sheet handoff. Inspects `ShareResult.status` so a
  /// dismissed share doesn't auto-tick the acknowledgment checkbox.
  /// Tests override via [FrontingUpgradeSheet.shareBackup].
  Future<bool> _defaultShareBackup(File file) async {
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Prism Fronting Backup',
        ),
      );
      return result.status == ShareResultStatus.success;
    } catch (_) {
      return false;
    }
  }

  /// Default save-as handoff. Uses `file_picker` to let the user pick
  /// a destination outside the app's documents directory. Returns
  /// `true` if the user confirmed a destination, `false` on cancel.
  /// Tests override via [FrontingUpgradeSheet.saveBackup].
  Future<bool> _defaultSaveBackup(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final fileName = file.path.split('/').last;
      final result = await FilePicker.saveFile(
        dialogTitle: 'Save Prism backup',
        fileName: fileName,
        bytes: bytes,
      );
      return result != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> _onShareTapped() async {
    final file = _backupFile;
    if (file == null) return;
    final handler = widget.shareBackup ?? _defaultShareBackup;
    final ok = await handler(file);
    if (!mounted) return;
    if (ok) {
      setState(() => _backupAcknowledged = true);
    }
  }

  Future<void> _onSaveTapped() async {
    final file = _backupFile;
    if (file == null) return;
    final handler = widget.saveBackup ?? _defaultSaveBackup;
    final ok = await handler(file);
    if (!mounted) return;
    if (ok) {
      setState(() => _backupAcknowledged = true);
    }
  }

  void _retry() {
    // Preserve `_backupFile` when the prior failure occurred AFTER the
    // backup was successfully written to disk (i.e. somewhere between
    // `backupReady` acknowledgement and the destructive transaction).
    // Re-running `prepareBackup` would force the user to redo the
    // expensive Argon2id pass and orphan a usable rescue file on disk
    // that the new attempt won't overwrite (filename collision
    // protection). Jumping directly to `backupReady` lets the user
    // re-acknowledge and proceed.
    //
    // When the prior failure happened in `prepareBackup` itself
    // (`_backupFile` is null), drop back to the password step so the
    // user can retry export.
    final preservedBackup = _backupFile;
    final hasPreservedBackup =
        preservedBackup != null && preservedBackup.existsSync();
    setState(() {
      _result = null;
      _backupAcknowledged = false;
      _pkImportStatus = _PostMigrationPkImportStatus.idle;
      _pkImportError = null;
      _pkTokenPromptShown = false;
      if (hasPreservedBackup) {
        // Keep _backupFile; resume at the durable-save gate. The user
        // re-confirms saving (or trusts their previous save) and the
        // destructive phase reuses the existing rescue file.
        _step = FrontingUpgradeStep.backupReady;
      } else {
        _backupFile = null;
        _step = FrontingUpgradeStep.password;
      }
    });
  }

  /// Runs the idempotent post-tx cleanup when the modal opens to the
  /// `inProgress` state. No password / role / mode picker needed: the
  /// destructive Drift work already committed; only the engine reset +
  /// keychain wipe + quarantine clear + mark-complete remain.
  Future<void> _runResumeCleanup() async {
    setState(() => _step = FrontingUpgradeStep.running);
    final runner = ref.read(frontingMigrationRunnerProvider);
    try {
      final result = await runner.resumeCleanup();
      if (!mounted) return;
      setState(() {
        _result = result;
        _step = result.outcome == MigrationOutcome.success
            ? FrontingUpgradeStep.success
            : FrontingUpgradeStep.failure;
      });
      if (result.outcome == MigrationOutcome.success) {
        await _maybeAutoRunPluralKitImport(result);
      }
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

  bool _shouldHandlePluralKitImport(MigrationResult result) {
    return result.pkRowsDeleted > 0 && _role != DeviceRole.secondary;
  }

  Future<void> _maybeAutoRunPluralKitImport(MigrationResult result) async {
    if (!widget.autoRunPluralKitImport) return;
    if (!_shouldHandlePluralKitImport(result)) return;

    final notifier = ref.read(pluralKitSyncProvider.notifier);
    bool hasToken;
    try {
      hasToken = await notifier.hasRepairToken();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pkImportStatus = _PostMigrationPkImportStatus.failed;
        _pkImportError = e.toString();
      });
      return;
    }

    if (!mounted) return;
    if (!hasToken) {
      setState(() {
        _pkImportStatus = _PostMigrationPkImportStatus.needsToken;
        _pkImportError = null;
      });
      _schedulePluralKitTokenPrompt();
      return;
    }

    await _runOneTimePluralKitImport();
  }

  void _schedulePluralKitTokenPrompt() {
    if (_pkTokenPromptShown) return;
    _pkTokenPromptShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_step != FrontingUpgradeStep.success) return;
      if (_pkImportStatus != _PostMigrationPkImportStatus.needsToken) return;
      unawaited(_promptForPluralKitTokenAndImport());
    });
  }

  Future<void> _runOneTimePluralKitImport({String? token}) async {
    setState(() {
      _pkImportStatus = _PostMigrationPkImportStatus.running;
      _pkImportError = null;
    });
    try {
      await ref
          .read(pluralKitSyncProvider.notifier)
          .performOneTimeFullImport(token: token);
      if (!mounted) return;
      setState(() => _pkImportStatus = _PostMigrationPkImportStatus.imported);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pkImportStatus = _PostMigrationPkImportStatus.failed;
        _pkImportError = e.toString();
      });
    }
  }

  Future<void> _promptForPluralKitTokenAndImport() async {
    final controller = TextEditingController();
    try {
      final token = await PrismDialog.show<String>(
        context: context,
        title: 'PluralKit token',
        message:
            'Import PluralKit fronting history now. This uses the token once '
            'and does not turn on PluralKit sync.',
        builder: (dialogContext) => PrismTextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          labelText: 'PluralKit token',
          hintText: 'Paste your PluralKit token',
          onSubmitted: (_) {
            final trimmed = controller.text.trim();
            if (trimmed.isEmpty) return;
            Navigator.of(dialogContext).pop(trimmed);
          },
        ),
        actions: [
          PrismButton(
            label: context.l10n.cancel,
            tone: PrismButtonTone.outlined,
            onPressed: () => Navigator.of(context).pop(),
          ),
          PrismButton(
            label: 'Import',
            tone: PrismButtonTone.filled,
            onPressed: () {
              final trimmed = controller.text.trim();
              if (trimmed.isEmpty) return;
              Navigator.of(context).pop(trimmed);
            },
          ),
        ],
      );
      if (!mounted || token == null || token.trim().isEmpty) return;
      await _runOneTimePluralKitImport(token: token.trim());
    } finally {
      controller.dispose();
    }
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
                  FrontingUpgradeStep.exporting => _buildExporting(theme),
                  FrontingUpgradeStep.backupReady => _buildBackupReady(theme),
                  FrontingUpgradeStep.running => _buildRunning(theme),
                  FrontingUpgradeStep.success => _buildSuccess(theme),
                  FrontingUpgradeStep.failure => _buildFailure(theme),
                  FrontingUpgradeStep.resumeCleanup => _buildResumeCleanup(
                    theme,
                  ),
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
    final terms = readTerminology(context, ref);
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
          context.l10n.frontingUpgradeIntroBody(terms.singularLower),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        // Pre-migration `pending_ops` loss warning. The migration's
        // sync state wipe clears `pending_ops`, so any local writes
        // that haven't been pushed yet exist only on this device. Set
        // expectations early so the user can sync first.
        Text(
          context.l10n.frontingUpgradeIntroPendingSyncWarning,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
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

  Widget _buildResumeCleanup(ThemeData theme) {
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
            AppIcons.warningAmberRounded,
            size: 40,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          // Localized strings ship with the modal but the resume-cleanup
          // path is new in this PR — fall back to literal copy until the
          // l10n strings land. Intentionally minimal so the user
          // understands "previous attempt left the device in a partial
          // state; tap to finish."
          'Finish migration',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'A previous upgrade attempt finished the data migration but '
          "couldn't complete the sync reset. Tap below to finish — no "
          'data will be touched, only the sync credentials.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        PrismButton(
          onPressed: _runResumeCleanup,
          label: 'Finish migration',
          tone: PrismButtonTone.filled,
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
            onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
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

  Widget _buildExporting(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        const PrismLoadingState(),
        const SizedBox(height: 24),
        Text(
          context.l10n.frontingUpgradeExporting,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.frontingUpgradeExportingSubtitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildBackupReady(ThemeData theme) {
    final file = _backupFile;
    final fileName = file?.path.split('/').last ?? '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Icon(
            AppIcons.checkCircleOutline,
            size: 48,
            color: Colors.green,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          context.l10n.frontingUpgradeBackupReadyHeadline,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          context.l10n.frontingUpgradeBackupReadyBody,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (fileName.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            fileName,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
          ),
        ],
        const SizedBox(height: 20),
        PrismButton(
          onPressed: _onSaveTapped,
          icon: AppIcons.checkCircleOutline,
          label: context.l10n.frontingUpgradeBackupSaveAs,
          tone: PrismButtonTone.filled,
          expanded: true,
        ),
        const SizedBox(height: 8),
        PrismButton(
          onPressed: _onShareTapped,
          label: context.l10n.frontingUpgradeBackupShare,
          tone: PrismButtonTone.outlined,
          expanded: true,
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          value: _backupAcknowledged,
          onChanged: (v) => setState(() => _backupAcknowledged = v ?? false),
          title: Text(
            context.l10n.frontingUpgradeBackupAcknowledge,
            style: theme.textTheme.bodyMedium,
          ),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
        ),
        const SizedBox(height: 8),
        PrismButton(
          onPressed: _runDestructive,
          enabled: _backupAcknowledged,
          label: context.l10n.frontingUpgradeBackupContinue,
          tone: PrismButtonTone.filled,
          expanded: true,
        ),
      ],
    );
  }

  Widget _buildSuccess(ThemeData theme) {
    final result = _result;
    final showPluralKitImportCta =
        result != null &&
        result.pkRowsDeleted > 0 &&
        _role != DeviceRole.secondary;
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
        const SizedBox(height: 12),
        // §4.3 FYI: analytics relabel ("fronting time" → "{term}-minutes").
        // Same arithmetic as before; honest framing for co-fronting.
        Text(
          context.l10n.frontingUpgradeAnalyticsNote(
            watchTerminology(context, ref).singularLower,
          ),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (showPluralKitImportCta) ...[
          const SizedBox(height: 16),
          _buildPluralKitImportStatus(theme),
          if (_pkImportStatus == _PostMigrationPkImportStatus.idle ||
              _pkImportStatus == _PostMigrationPkImportStatus.needsToken ||
              _pkImportStatus == _PostMigrationPkImportStatus.failed) ...[
            const SizedBox(height: 8),
            PrismButton(
              onPressed: _promptForPluralKitTokenAndImport,
              icon: AppIcons.cloudSync,
              label: 'Import with PluralKit token',
              tone: PrismButtonTone.filled,
              expanded: true,
            ),
          ],
        ],
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

  Widget _buildPluralKitImportStatus(ThemeData theme) {
    switch (_pkImportStatus) {
      case _PostMigrationPkImportStatus.idle:
        return Text(
          'PluralKit history can be re-imported here with a temporary '
          'token. The token is used once and PluralKit sync stays off.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        );
      case _PostMigrationPkImportStatus.running:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PrismLoadingState(),
            const SizedBox(height: 8),
            Text(
              'Re-importing PluralKit history...',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      case _PostMigrationPkImportStatus.imported:
        return Text(
          'PluralKit history was re-imported.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        );
      case _PostMigrationPkImportStatus.needsToken:
        return Text(
          'No stored PluralKit token was found. You can import with a '
          'temporary token here without turning on PluralKit sync.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        );
      case _PostMigrationPkImportStatus.failed:
        return Text(
          'PluralKit re-import failed: ${_pkImportError ?? 'unknown error'}',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        );
    }
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
    final terms = readTerminology(context, ref);
    final lines = <String>[];
    if (r.spRowsMigrated > 0) {
      lines.add(l10n.frontingUpgradeCountSpMigrated(r.spRowsMigrated));
    }
    if (r.nativeRowsMigrated > 0) {
      lines.add(l10n.frontingUpgradeCountNativeMigrated(r.nativeRowsMigrated));
    }
    if (r.nativeRowsExpanded > 0) {
      lines.add(
        l10n.frontingUpgradeCountNativeExpanded(
          r.nativeRowsExpanded,
          terms.singularLower,
        ),
      );
    }
    if (r.pkRowsDeleted > 0) {
      lines.add(l10n.frontingUpgradeCountPkDeleted(r.pkRowsDeleted));
    }
    if (r.commentsMigrated > 0) {
      lines.add(l10n.frontingUpgradeCountCommentsMigrated(r.commentsMigrated));
    }
    if (r.orphanRowsAssignedToSentinel > 0) {
      lines.add(
        l10n.frontingUpgradeCountOrphansAssigned(
          r.orphanRowsAssignedToSentinel,
          terms.singularLower,
        ),
      );
    }
    if (r.unknownSentinelCreated) {
      lines.add(l10n.frontingUpgradeCountSentinelCreated(terms.singularLower));
    }
    // Surface corrupt-JSON fallback rows. The service falls back to
    // single-member migration when a row's `co_fronter_ids` JSON fails
    // to parse; without this counter the user silently loses
    // co-fronter relationships on those rows.
    if (r.corruptCoFronterRowIds.isNotEmpty) {
      lines.add(
        l10n.frontingUpgradeCountCorruptCoFronters(
          r.corruptCoFronterRowIds.length,
          terms.singularLower,
        ),
      );
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
                : theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.4,
                  ),
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
