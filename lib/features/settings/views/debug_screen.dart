import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/settings/providers/reset_data_provider.dart';
import 'package:prism_plurality/features/settings/services/stress_data_generator.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';

/// Placeholder — pending changes count (sync now managed by Rust layer).
final _pendingChangesCountProvider = FutureProvider<int>((ref) async {
  return 0;
});

/// Developer-oriented debug screen with database reset, sync info, and
/// build details.
class DebugScreen extends ConsumerStatefulWidget {
  const DebugScreen({super.key});

  @override
  ConsumerState<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends ConsumerState<DebugScreen> {
  StressProgress? _progress;
  bool _isGenerating = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nodeIdAsync = ref.watch(nodeIdProvider);
    final pendingAsync = ref.watch(_pendingChangesCountProvider);
    final lastSyncTime = ref.watch(lastSyncTimeProvider);

    return PrismPageScaffold(
      topBar: const PrismTopBar(title: 'Debug', showBackButton: true),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, NavBarInset.of(context)),
        children: [
          // ── Danger Zone ─────────────────────────────
          Card(
            color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Danger Zone',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: PrismButton(
                      label: 'Reset Database',
                      icon: AppIcons.deleteForever,
                      tone: PrismButtonTone.destructive,
                      expanded: true,
                      onPressed: () => _confirmReset(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: PrismButton(
                      label: 'Export Data',
                      icon: AppIcons.fileUploadOutlined,
                      tone: PrismButtonTone.outlined,
                      expanded: true,
                      onPressed: () {
                        PrismToast.show(context, message: 'Coming soon');
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Stress Testing ─────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Stress Testing',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Generate large datasets for performance testing',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_isGenerating && _progress != null) ...[
                    LinearProgressIndicator(value: _progress!.fraction),
                    const SizedBox(height: 4),
                    Text(
                      '${_progress!.phase}... ${_progress!.current}/${_progress!.total}',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: PrismButton(
                      label: 'Generate Stress Data',
                      icon: AppIcons.speed,
                      tone: PrismButtonTone.outlined,
                      expanded: true,
                      isLoading: _isGenerating,
                      enabled: !_isGenerating,
                      onPressed: () => _showPresetPicker(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: PrismButton(
                      label: 'Clear Stress Data',
                      icon: AppIcons.deleteForever,
                      tone: PrismButtonTone.destructive,
                      expanded: true,
                      enabled: !_isGenerating,
                      onPressed: () => _confirmClearStressData(context),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── CRDT Sync State ─────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sync State',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _DebugRow(
                    label: 'Pending changes',
                    value: pendingAsync.when(
                      loading: () => '...',
                      error: (e, _) => 'Error',
                      data: (count) => '$count',
                    ),
                  ),
                  const Divider(height: 16),
                  _DebugRow(
                    label: 'Last sync',
                    value: lastSyncTime != null
                        ? _formatDateTime(lastSyncTime)
                        : 'Never',
                  ),
                  const Divider(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: PrismButton(
                      label: 'Open Sync Debug Log',
                      icon: AppIcons.receiptLongOutlined,
                      tone: PrismButtonTone.outlined,
                      expanded: true,
                      onPressed: () =>
                          context.push(AppRoutePaths.settingsSyncDebug),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Build Info ──────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Build Info',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const _DebugRow(label: 'App version', value: '0.1.0'),
                  const Divider(height: 16),
                  const _DebugRow(label: 'Package', value: 'prism_plurality'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Tools ────────────────────────────────────
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Tools',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                PrismListRow(
                  leading: Icon(AppIcons.healing),
                  title: const Text('Timeline Sanitization'),
                  subtitle: const Text('Scan for and fix timeline issues'),
                  trailing: Icon(AppIcons.chevronRight),
                  onTap: () => context.push(
                    AppRoutePaths.settingsTimelineSanitization,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Node ID ─────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Device',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  nodeIdAsync.when(
                    loading: () => const PrismLoadingState(),
                    error: (e, _) => Text('Error: $e'),
                    data: (nodeId) {
                      final displayId =
                          nodeId ?? 'Unavailable — not yet paired';
                      return Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Node ID',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                SelectableText(
                                  displayId,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (nodeId != null)
                            IconButton(
                              icon: Icon(AppIcons.copy, size: 18),
                              tooltip: 'Copy Node ID',
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(text: nodeId),
                                );
                                PrismToast.show(
                                  context,
                                  message: 'Node ID copied to clipboard',
                                );
                              },
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _confirmReset(BuildContext context) async {
    // First confirmation.
    final first = await PrismDialog.confirm(
      context: context,
      title: 'Reset Database',
      message:
          'Are you sure you want to delete all data? '
          'This action cannot be undone.',
      confirmLabel: 'Continue',
      destructive: true,
    );

    if (!first || !context.mounted) return;

    // Second confirmation.
    final second = await PrismDialog.confirm(
      context: context,
      title: 'Really delete all data?',
      message:
          'This will permanently erase all members, sessions, '
          'conversations, messages, and polls. There is no undo.',
      confirmLabel: 'Delete Everything',
      destructive: true,
    );

    if (!second || !context.mounted) return;

    try {
      await ref
          .read(resetDataNotifierProvider.notifier)
          .reset(ResetCategory.all);
      if (!context.mounted) return;
      PrismToast.show(context, message: 'Database reset successfully');
    } catch (e) {
      if (!context.mounted) return;
      PrismToast.error(context, message: 'Failed to reset: $e');
    }
  }

  List<StressPreset> get _availablePresets {
    if (kIsWeb) return [StressPreset.medium];
    final isDesktop = defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
    if (isDesktop) {
      return [StressPreset.medium, StressPreset.large, StressPreset.extreme];
    }
    return [StressPreset.medium, StressPreset.large];
  }

  Future<void> _showPresetPicker(BuildContext context) async {
    final presets = _availablePresets;
    final preset = await showModalBottomSheet<StressPreset>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Select Preset',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ),
            for (final p in presets)
              ListTile(
                title: Text(p.label),
                subtitle: Text(
                  '${p.members} members, ${p.sessions} sessions '
                  '\u2022 ~${p.estimatedSizeMb}MB, ~${p.estimatedSeconds}s',
                ),
                onTap: () => Navigator.pop(context, p),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (preset == null || !mounted) return;

    final db = ref.read(databaseProvider);
    final generator = StressDataGenerator(db);
    final hasExisting = await generator.hasExistingData();

    if (hasExisting && mounted) {
      final confirmed = await PrismDialog.confirm(
        context: context,
        title: 'Database Not Empty',
        message:
            'Your database already has data. Stress data will be '
            'added alongside it. Continue?',
      );
      if (!confirmed || !mounted) return;
    }

    _runGeneration(preset);
  }

  Future<void> _runGeneration(StressPreset preset) async {
    setState(() {
      _isGenerating = true;
      _progress = null;
    });

    try {
      final db = ref.read(databaseProvider);
      final generator = StressDataGenerator(db);

      await for (final progress in generator.generate(preset)) {
        if (mounted) {
          setState(() => _progress = progress);
        }
      }

      if (mounted) {
        PrismToast.show(context, message: '${preset.label} stress data generated');
      }
    } catch (e) {
      if (mounted) {
        PrismToast.show(context, message: 'Generation failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _confirmClearStressData(BuildContext context) async {
    final db = ref.read(databaseProvider);
    final generator = StressDataGenerator(db);
    final hasStress = await generator.hasStressData();

    if (!hasStress) {
      if (mounted) PrismToast.show(context, message: 'No stress data to clear');
      return;
    }

    if (!mounted) return;

    final confirmed = await PrismDialog.confirm(
      context: context,
      title: 'Clear Stress Data',
      message:
          'This will delete all generated stress test data. '
          'Your real data will not be affected.',
    );

    if (!confirmed || !mounted) return;

    await generator.clearStressData();
    if (mounted) {
      PrismToast.show(context, message: 'Stress data cleared');
    }
  }
}

class _DebugRow extends StatelessWidget {
  const _DebugRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: theme.textTheme.bodyMedium),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontFamily: 'monospace',
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
