import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
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
      title: 'Disconnect PluralKit?',
      message: 'This will remove your token and disconnect from PluralKit. '
          'Your imported data will remain in the app.',
      confirmLabel: 'Disconnect',
      destructive: true,
    );
    if (confirmed) {
      await ref.read(pluralKitSyncProvider.notifier).clearToken();
    }
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
      topBar: const PrismTopBar(
        title: 'PluralKit',
        showBackButton: true,
      ),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // -- Section 1: PluralKit Account --
          const _SectionHeader(title: 'PluralKit Account'),
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

          // -- Section 2: Sync Direction --
          if (syncState.isConnected) ...[
            const SizedBox(height: 24),
            const _SectionHeader(title: 'Sync Direction'),
            const SizedBox(height: 8),
            _buildSyncDirectionSection(theme),
          ],

          // -- Section 3: Sync Actions --
          if (syncState.isConnected) ...[
            const SizedBox(height: 24),
            const _SectionHeader(title: 'Sync Actions'),
            const SizedBox(height: 8),
            if (syncState.isSyncing)
              _buildSyncProgress(syncState, theme)
            else
              _buildSyncActions(syncState, theme),
          ],

          // -- Section 4: Sync Summary --
          if (syncState.isConnected) ...[
            _buildSyncSummarySection(),
          ],

          // -- How It Works --
          const SizedBox(height: 24),
          const _SectionHeader(title: 'How It Works'),
          const SizedBox(height: 8),
          PrismSectionCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(
                  icon: AppIcons.sync,
                  text: 'Supports pull, push, or bidirectional sync. '
                      'Choose your preferred direction above.',
                ),
                const SizedBox(height: 12),
                _InfoRow(
                  icon: AppIcons.lockOutline,
                  text: 'Your token is stored securely in the device '
                      'keychain and never leaves your device.',
                ),
                const SizedBox(height: 12),
                _InfoRow(
                  icon: AppIcons.people,
                  text: 'Members are matched by PluralKit UUID. '
                      'Existing members are updated, new ones are created.',
                ),
                const SizedBox(height: 12),
                _InfoRow(
                  icon: AppIcons.swapVert,
                  text: 'Switches are imported as fronting sessions. '
                      'Duplicate switches are automatically skipped.',
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
                'Connected',
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
              'Last sync: ${_formatDate(syncState.lastSyncDate!)}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (syncState.lastManualSyncDate != null) ...[
            const SizedBox(height: 4),
            Text(
              'Last manual sync: ${_formatDate(syncState.lastManualSyncDate!)}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          PrismButton(
            onPressed: _disconnect,
            icon: AppIcons.linkOff,
            label: 'Disconnect',
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
            labelText: 'PluralKit Token',
            hintText: 'Paste your token here',
            isDense: true,
            onSubmitted: (_) => _connect(),
          ),
          const SizedBox(height: 12),
          PrismButton(
            onPressed: _connect,
            icon: AppIcons.link,
            label: 'Connect',
            tone: PrismButtonTone.filled,
            expanded: true,
          ),
          const SizedBox(height: 12),
          Text(
            'To get your token, DM the PluralKit bot on Discord with '
            '"pk;token" and paste the result here.',
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
          label: 'Import from PluralKit',
          tone: PrismButtonTone.filled,
          expanded: true,
          enabled: !syncState.isSyncing,
        ),
        const SizedBox(height: 8),
        PrismButton(
          onPressed: _syncRecent,
          icon: AppIcons.sync,
          label: _cooldownSeconds > 0
              ? 'Sync Recent Changes ($_cooldownSeconds s)'
              : 'Sync Recent Changes',
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

  Widget _buildSyncDirectionSection(ThemeData theme) {
    final direction = ref.watch(pkSyncDirectionProvider);
    return PrismSectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose how data flows between Prism and PluralKit.',
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
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
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
