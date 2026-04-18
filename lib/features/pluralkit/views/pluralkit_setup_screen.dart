import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_mapping_controller.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/pluralkit/views/pk_mapping_screen.dart';
import 'package:prism_plurality/features/pluralkit/widgets/pk_sync_direction_picker.dart';
import 'package:prism_plurality/features/pluralkit/widgets/pk_sync_summary_card.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// PluralKit integration setup and sync management screen.
class PluralKitSetupScreen extends ConsumerStatefulWidget {
  const PluralKitSetupScreen({super.key});

  @override
  ConsumerState<PluralKitSetupScreen> createState() =>
      _PluralKitSetupScreenState();
}

class _PluralKitSetupScreenState extends ConsumerState<PluralKitSetupScreen> {
  final _tokenController = TextEditingController();
  Timer? _cooldownTimer;
  int _cooldownSeconds = 0;

  @override
  void dispose() {
    _tokenController.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldownTimer(PluralKitSyncState syncState) {
    _cooldownTimer?.cancel();
    if (syncState.lastManualSyncDate == null) return;

    final elapsed =
        DateTime.now().difference(syncState.lastManualSyncDate!).inSeconds;
    final remaining = 60 - elapsed;
    if (remaining <= 0) return;

    setState(() => _cooldownSeconds = remaining);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _cooldownSeconds--;
        if (_cooldownSeconds <= 0) {
          timer.cancel();
        }
      });
    });
  }

  Future<void> _connect() async {
    final token = _tokenController.text;
    if (token.trim().isEmpty) return;

    await ref.read(pluralKitSyncProvider.notifier).setToken(token);
    _tokenController.clear();
  }

  Future<void> _disconnect() async {
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: context.l10n.pluralkitDisconnectTitle,
      message: context.l10n.pluralkitDisconnectMessage,
      confirmLabel: context.l10n.pluralkitDisconnect,
      destructive: true,
    );
    if (confirmed) {
      await ref.read(pluralKitSyncProvider.notifier).clearToken();
    }
  }

  Future<void> _openMappingScreen() async {
    // Reset the controller so the mapping screen fetches fresh data.
    ref.invalidate(pkMappingControllerProvider);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const PkMappingScreen(),
      ),
    );
  }

  Future<void> _importFromPK() async {
    await ref.read(pluralKitSyncProvider.notifier).performFullImport();
  }

  Future<void> _syncRecent() async {
    final direction = ref.read(pkSyncDirectionProvider);
    final summary = await ref.read(pluralKitSyncProvider.notifier).syncRecentData(
          isManual: true,
          direction: direction,
        );
    if (summary != null) {
      ref.read(pkLastSyncSummaryProvider.notifier).set(summary);
    }
    final syncState = ref.read(pluralKitSyncProvider);
    _startCooldownTimer(syncState);
  }

  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(pluralKitSyncProvider);
    final theme = Theme.of(context);

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: context.l10n.pluralkitTitle,
        showBackButton: true,
      ),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // -- Section 1: PluralKit Account --
          _SectionHeader(title: context.l10n.pluralkitAccount),
          const SizedBox(height: 8),
          if (syncState.isConnected)
            _buildConnectedCard(syncState, theme)
          else
            _buildTokenInput(syncState, theme),

          if (syncState.syncError != null) ...[
            const SizedBox(height: 8),
            PrismSurface(
              fillColor: theme.colorScheme.errorContainer,
              borderColor: theme.colorScheme.error.withValues(alpha: 0.3),
              padding: const EdgeInsets.all(12),
              child: Row(
                  children: [
                    Icon(AppIcons.errorOutline,
                        color: theme.colorScheme.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        syncState.syncError!,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
            ),
          ],

          // -- Mapping gate banner --
          if (syncState.isConnected && syncState.needsMapping) ...[
            const SizedBox(height: 16),
            _buildMappingBanner(theme),
          ],

          // -- Section 2: Sync Direction --
          if (syncState.canAutoSync) ...[
            const SizedBox(height: 24),
            _SectionHeader(title: context.l10n.pluralkitSyncDirection),
            const SizedBox(height: 8),
            _buildSyncDirectionSection(theme),
          ],

          // -- Section 3: Sync Actions --
          if (syncState.canAutoSync) ...[
            const SizedBox(height: 24),
            _SectionHeader(title: context.l10n.pluralkitSyncActions),
            const SizedBox(height: 8),
            if (syncState.isSyncing)
              _buildSyncProgress(syncState, theme)
            else
              _buildSyncActions(syncState, theme),
            const SizedBox(height: 8),
            PrismButton(
              // TODO(l10n)
              label: 'Re-run member mapping',
              onPressed: _openMappingScreen,
              icon: AppIcons.people,
              tone: PrismButtonTone.outlined,
              expanded: true,
            ),
          ],

          // -- Section 4: Sync Summary --
          if (syncState.canAutoSync) ...[
            _buildSyncSummarySection(),
          ],

          // -- How It Works --
          const SizedBox(height: 24),
          _SectionHeader(title: context.l10n.pluralkitHowItWorks),
          const SizedBox(height: 8),
          PrismSectionCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(
                  icon: AppIcons.sync,
                  text: context.l10n.pluralkitInfoSync,
                ),
                const SizedBox(height: 12),
                _InfoRow(
                  icon: AppIcons.lockOutline,
                  text: context.l10n.pluralkitInfoToken,
                ),
                const SizedBox(height: 12),
                _InfoRow(
                  icon: AppIcons.people,
                  text: context.l10n.pluralkitInfoMembers,
                ),
                const SizedBox(height: 12),
                _InfoRow(
                  icon: AppIcons.swapVert,
                  text: context.l10n.pluralkitInfoSwitches,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildConnectedCard(PluralKitSyncState syncState, ThemeData theme) {
    return PrismSectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.checkCircle, color: Colors.green.shade600),
              const SizedBox(width: 8),
              Text(
                context.l10n.pluralkitConnected,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.green.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (syncState.lastSyncDate != null) ...[
            const SizedBox(height: 8),
            Text(
              context.l10n.pluralkitLastSync(_formatDate(syncState.lastSyncDate!)),
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (syncState.lastManualSyncDate != null) ...[
            const SizedBox(height: 4),
            Text(
              context.l10n.pluralkitLastManualSync(_formatDate(syncState.lastManualSyncDate!)),
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          PrismButton(
            onPressed: _disconnect,
            icon: AppIcons.linkOff,
            label: context.l10n.pluralkitDisconnect,
            tone: PrismButtonTone.destructive,
            expanded: true,
          ),
        ],
      ),
    );
  }

  Widget _buildTokenInput(PluralKitSyncState syncState, ThemeData theme) {
    return PrismSectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PrismTextField(
            controller: _tokenController,
            obscureText: true,
            labelText: context.l10n.pluralkitTokenLabel,
            hintText: context.l10n.pluralkitPasteTokenHint,
            isDense: true,
            onSubmitted: (_) => _connect(),
          ),
          const SizedBox(height: 12),
          PrismButton(
            onPressed: _connect,
            icon: AppIcons.link,
            label: context.l10n.pluralkitConnect,
            tone: PrismButtonTone.filled,
            expanded: true,
          ),
          const SizedBox(height: 12),
          Text(
            context.l10n.pluralkitTokenHelp,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncProgress(PluralKitSyncState syncState, ThemeData theme) {
    return PrismSectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            value: syncState.syncProgress > 0 ? syncState.syncProgress : null,
          ),
          const SizedBox(height: 12),
          Text(
            syncState.syncStatus,
            style: theme.textTheme.bodyMedium,
          ),
          if (syncState.syncProgress > 0) ...[
            const SizedBox(height: 4),
            Text(
              '${(syncState.syncProgress * 100).toInt()}%',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSyncActions(PluralKitSyncState syncState, ThemeData theme) {
    final canSync = syncState.canManualSync && _cooldownSeconds <= 0;

    return Column(
      children: [
        PrismButton(
          onPressed: _importFromPK,
          icon: AppIcons.cloudDownload,
          label: context.l10n.pluralkitImportButton,
          tone: PrismButtonTone.filled,
          expanded: true,
          enabled: !syncState.isSyncing,
        ),
        const SizedBox(height: 8),
        PrismButton(
          onPressed: _syncRecent,
          icon: AppIcons.sync,
          label: _cooldownSeconds > 0
              ? context.l10n.pluralkitSyncRecentCooldown(_cooldownSeconds)
              : context.l10n.pluralkitSyncRecent,
          tone: PrismButtonTone.outlined,
          expanded: true,
          enabled: canSync,
        ),
        if (syncState.syncStatus.isNotEmpty && !syncState.isSyncing) ...[
          const SizedBox(height: 8),
          Text(
            syncState.syncStatus,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMappingBanner(ThemeData theme) {
    return PrismSectionCard(
      padding: const EdgeInsets.all(16),
      accentColor: theme.colorScheme.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.people, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  // TODO(l10n)
                  'Link your PluralKit members to get started',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            // TODO(l10n)
            'Match PluralKit members to members in Prism (or import them as new) '
            'before syncing. This avoids duplicate members.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          PrismButton(
            onPressed: _openMappingScreen,
            icon: AppIcons.link,
            // TODO(l10n)
            label: 'Link members',
            tone: PrismButtonTone.filled,
            expanded: true,
          ),
        ],
      ),
    );
  }

  Widget _buildSyncDirectionSection(ThemeData theme) {
    final direction = ref.watch(pkSyncDirectionProvider);
    return PrismSectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.pluralkitSyncDirectionDescription,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: PkSyncDirectionPicker(
              selected: direction,
              onChanged: (d) {
                ref.read(pkSyncDirectionProvider.notifier).setDirection(d);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncSummarySection() {
    final summary = ref.watch(pkLastSyncSummaryProvider);
    if (summary == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: PkSyncSummaryCard(summary: summary),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return context.l10n.pluralkitJustNow;
    if (diff.inHours < 1) return context.l10n.pluralkitMinutesAgo(diff.inMinutes);
    if (diff.inDays < 1) return context.l10n.pluralkitHoursAgo(diff.inHours);
    return context.l10n.pluralkitDaysAgo(diff.inDays);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
