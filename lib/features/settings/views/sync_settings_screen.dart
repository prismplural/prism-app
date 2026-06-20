import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:prism_plurality/core/reset/reset_recovery_app.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_disconnect_marker.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/settings/providers/reset_data_provider.dart';
import 'package:prism_plurality/features/settings/views/device_management_screen.dart';
import 'package:prism_plurality/features/settings/views/sync_troubleshooting_screen.dart';
import 'package:prism_plurality/features/settings/views/verify_backup_screen.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/adaptive_detail_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_grouped_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_settings_row.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/features/settings/widgets/sync_toast_listener.dart';
import 'package:prism_plurality/features/settings/widgets/change_pin_sheet.dart';
import 'package:prism_plurality/features/settings/widgets/setup_device_sheet.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/glass_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

// ---------------------------------------------------------------------------
// Sync entity counts provider
// ---------------------------------------------------------------------------

@visibleForTesting
bool canTriggerManualSync({
  required bool hasHandle,
  required bool hasRelayUrl,
  required bool isSyncActive,
  required bool isHandleLoading,
  required bool syncDatabaseReady,
}) {
  if (!syncDatabaseReady) return false;
  if (isSyncActive || isHandleLoading) return false;
  return hasHandle || hasRelayUrl;
}

enum SyncSummaryHeadline { connected, reconnecting, needsAttention, offline }

enum SyncSummaryTone { healthy, warning, error }

enum SyncSummaryActivity {
  checkingForChanges,
  syncing,
  pendingUploads,
  reconnecting,
  needsRepair,
  none,
}

class SyncSummaryPresentation {
  const SyncSummaryPresentation({
    required this.headline,
    required this.tone,
    required this.activity,
    required this.pendingUploads,
  });

  final SyncSummaryHeadline headline;
  final SyncSummaryTone tone;
  final SyncSummaryActivity activity;
  final int pendingUploads;
}

@visibleForTesting
SyncSummaryPresentation buildSyncSummaryPresentation({
  required SyncStatus syncStatus,
  required bool hasActiveHandle,
  required bool handleIsLoading,
  required bool canAttemptReconnect,
  required bool wsConnected,
  required bool syncDatabaseReady,
}) {
  final SyncSummaryHeadline headline;
  final SyncSummaryTone tone;

  if (!syncDatabaseReady) {
    headline = SyncSummaryHeadline.needsAttention;
    tone = SyncSummaryTone.error;
  } else if (syncStatus.lastError != null) {
    headline = SyncSummaryHeadline.needsAttention;
    tone = SyncSummaryTone.error;
  } else if (syncStatus.hasSyncIssues) {
    headline = SyncSummaryHeadline.needsAttention;
    tone = SyncSummaryTone.warning;
  } else if (handleIsLoading || (hasActiveHandle && !wsConnected)) {
    headline = SyncSummaryHeadline.reconnecting;
    tone = SyncSummaryTone.warning;
  } else if (hasActiveHandle) {
    headline = SyncSummaryHeadline.connected;
    tone = SyncSummaryTone.healthy;
  } else if (canAttemptReconnect) {
    headline = SyncSummaryHeadline.offline;
    tone = SyncSummaryTone.error;
  } else {
    headline = SyncSummaryHeadline.offline;
    tone = SyncSummaryTone.error;
  }

  final SyncSummaryActivity activity;
  if (!syncDatabaseReady) {
    activity = SyncSummaryActivity.needsRepair;
  } else if (syncStatus.isSyncing) {
    activity = SyncSummaryActivity.syncing;
  } else if (syncStatus.pendingOps > 0) {
    activity = SyncSummaryActivity.pendingUploads;
  } else {
    activity = switch (headline) {
      SyncSummaryHeadline.connected => SyncSummaryActivity.checkingForChanges,
      SyncSummaryHeadline.reconnecting => SyncSummaryActivity.reconnecting,
      SyncSummaryHeadline.needsAttention ||
      SyncSummaryHeadline.offline => SyncSummaryActivity.none,
    };
  }

  return SyncSummaryPresentation(
    headline: headline,
    tone: tone,
    activity: activity,
    pendingUploads: syncStatus.pendingOps,
  );
}

@visibleForTesting
bool isSyncSettingsConfigured({
  required bool hasActiveHandle,
  required SyncHealthState syncHealth,
  required String? relayUrl,
  required String? syncId,
  required String? deviceId,
  required bool hasDeviceSecret,
  bool identityLoadComplete = true,
}) {
  if (hasCompletePersistentSyncIdentity(
    relayUrl: relayUrl,
    syncId: syncId,
    deviceId: deviceId,
    hasDeviceSecret: hasDeviceSecret,
  )) {
    return true;
  }
  if (identityLoadComplete) return false;
  return hasActiveHandle && syncHealth != SyncHealthState.unpaired;
}

/// Whether the "Set up another device" row should appear in sync settings.
///
/// All three conditions must hold; otherwise the row is hidden so users
/// don't tap into a sheet that fires error toasts when the keychain is in
/// a partial state:
///   1. FFI handle is alive.
///   2. Persistent sync identity is complete (relay URL, sync ID, device
///      ID, device secret).
///   3. `wrapped_dek` is present, because the inviter ceremony needs it
///      to derive the joiner bundle.
@visibleForTesting
bool canSetUpAnotherDeviceRow({
  required bool hasActiveHandle,
  required String? relayUrl,
  required String? syncId,
  required String? deviceId,
  required bool hasDeviceSecret,
  required bool hasWrappedDek,
}) {
  if (!hasActiveHandle) return false;
  if (!hasCompletePersistentSyncIdentity(
    relayUrl: relayUrl,
    syncId: syncId,
    deviceId: deviceId,
    hasDeviceSecret: hasDeviceSecret,
  )) {
    return false;
  }
  return hasWrappedDek;
}

@visibleForTesting
bool shouldShowLocalDisconnectState(SyncDisconnectMarker? marker) {
  return marker != null &&
      marker.localAppDataOutcome == LocalAppDataOutcome.preserved &&
      marker.nextSetupConstraint == SyncSetupConstraint.localOnly;
}

@visibleForTesting
bool shouldShowJoinOnlyReplaceState(SyncDisconnectMarker? marker) {
  return marker != null &&
      marker.localAppDataOutcome == LocalAppDataOutcome.wiped &&
      marker.nextSetupConstraint ==
          SyncSetupConstraint.joinOnlyReplaceLocalData;
}

class SyncSettingsScreen extends ConsumerWidget {
  const SyncSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final relayUrlAsync = ref.watch(relayUrlProvider);
    final syncIdAsync = ref.watch(syncIdProvider);
    final deviceIdAsync = ref.watch(syncDeviceIdProvider);
    final deviceSecretAsync = ref.watch(syncDeviceSecretPresentProvider);
    final relayUrl = relayUrlAsync.value;
    final syncId = syncIdAsync.value;
    final deviceId = deviceIdAsync.value;
    final hasDeviceSecret = deviceSecretAsync.value ?? false;
    // A complete keychain identity is the durable "configured" signal.
    // While those FutureProviders are resolving or revalidating, an active
    // handle can temporarily bridge the state so the setup view does not
    // flash during provider invalidation.
    final handleAsyncForGate = ref.watch(prismSyncHandleProvider);
    final hasActiveHandle = handleAsyncForGate.value != null;
    final syncHealth = ref.watch(syncHealthProvider);
    final identityLoadComplete =
        relayUrlAsync.hasValue &&
        syncIdAsync.hasValue &&
        deviceIdAsync.hasValue &&
        deviceSecretAsync.hasValue;
    final isConfigured = isSyncSettingsConfigured(
      hasActiveHandle: hasActiveHandle,
      syncHealth: syncHealth,
      relayUrl: relayUrl,
      syncId: syncId,
      deviceId: deviceId,
      hasDeviceSecret: hasDeviceSecret,
      identityLoadComplete: identityLoadComplete,
    );

    if (syncHealth == SyncHealthState.disconnected) {
      return PrismPageScaffold(
        topBar: PrismTopBar(
          title: context.l10n.syncTitle,
          showBackButton: true,
        ),
        body: _StateMessageView(
          icon: AppIcons.syncDisabled,
          title: context.l10n.syncDisconnectedTitle,
          message: context.l10n.syncDisconnectedMessage,
          actionLabel: context.l10n.syncSetUpSyncButton,
          onAction: () => context.push(AppRoutePaths.syncSetup),
        ),
      );
    }

    if ((relayUrlAsync.isLoading ||
            syncIdAsync.isLoading ||
            deviceIdAsync.isLoading ||
            deviceSecretAsync.isLoading) &&
        !relayUrlAsync.hasValue &&
        !syncIdAsync.hasValue &&
        !deviceIdAsync.hasValue &&
        !deviceSecretAsync.hasValue &&
        !isConfigured) {
      return PrismPageScaffold(
        topBar: PrismTopBar(
          title: context.l10n.syncTitle,
          showBackButton: true,
        ),
        body: const PrismLoadingState(),
      );
    }

    final loadError = relayUrlAsync.hasError
        ? relayUrlAsync.error
        : syncIdAsync.hasError
        ? syncIdAsync.error
        : deviceIdAsync.hasError
        ? deviceIdAsync.error
        : deviceSecretAsync.hasError
        ? deviceSecretAsync.error
        : null;

    if (loadError != null && !isConfigured) {
      return PrismPageScaffold(
        topBar: PrismTopBar(
          title: context.l10n.syncTitle,
          showBackButton: true,
        ),
        body: _StateMessageView(
          icon: AppIcons.syncProblem,
          title: context.l10n.syncUnableToLoad,
          message: '$loadError',
          actionLabel: context.l10n.tryAgain,
          onAction: () {
            ref.invalidate(relayUrlProvider);
            ref.invalidate(syncIdProvider);
          },
        ),
      );
    }

    return PrismPageScaffold(
      topBar: PrismTopBar(title: context.l10n.syncTitle, showBackButton: true),
      bodyPadding: EdgeInsets.zero,
      body: isConfigured
          ? SyncToastListener(
              child: _ConfiguredView(
                relayUrl: relayUrl ?? '',
                syncId: syncId ?? '',
              ),
            )
          : const _SetupView(),
    );
  }
}

class _SetupView extends ConsumerWidget {
  const _SetupView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final shapes = PrismShapes.of(context);
    final accent = theme.colorScheme.primary;
    final markerAsync = ref.watch(syncDisconnectMarkerProvider);
    if (markerAsync.isLoading && !markerAsync.hasValue) {
      return const PrismLoadingState();
    }
    final marker = markerAsync.whenOrNull(data: (value) => value);

    if (shouldShowLocalDisconnectState(marker)) {
      return _LocalDisconnectSetupView(marker: marker!);
    }
    if (shouldShowJoinOnlyReplaceState(marker)) {
      return const _JoinOnlyReplaceSetupView();
    }

    final radius = BorderRadius.circular(
      shapes.radius(PrismTokens.radiusLarge),
    );

    return SafeArea(
      top: false,
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            PrismTokens.pageHorizontalPadding,
            28,
            PrismTokens.pageHorizontalPadding,
            28 + NavBarInset.of(context),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: GlassSurface(
              borderRadius: radius,
              tint: accent,
              backgroundColor: _setupCardFill(theme, accent),
              borderColor: accent.withValues(alpha: 0.16),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.18),
                            blurRadius: 28,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: GlassSurface.circle(
                        size: 82,
                        tint: accent,
                        backgroundColor: accent.withValues(alpha: 0.08),
                        borderColor: accent.withValues(alpha: 0.24),
                        child: PhosphorIcon(
                          AppIcons.duotoneSync,
                          size: 48,
                          color: accent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    context.l10n.syncNotSetUp,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    context.l10n.syncNotSetUpDescription,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  _SetupBenefitPoint(
                    icon: AppIcons.duotoneLock,
                    title: 'Private by design',
                    subtitle: 'The server cannot read your Prism data.',
                    tint: accent,
                  ),
                  const SizedBox(height: 12),
                  _SetupBenefitPoint(
                    icon: AppIcons.duotoneDevices,
                    title: 'Keeps devices current',
                    subtitle:
                        'Changes you make here show up on your other devices.',
                    tint: accent,
                  ),
                  const SizedBox(height: 12),
                  _SetupBenefitPoint(
                    icon: AppIcons.duotoneKey,
                    title: 'Use your recovery phrase',
                    subtitle:
                        'The 12 words and PIN you set up when you installed Prism.',
                    tint: accent,
                  ),
                  const SizedBox(height: 26),
                  PrismButton(
                    label: context.l10n.syncSetupButton,
                    icon: AppIcons.lockOutline,
                    tone: PrismButtonTone.filled,
                    expanded: true,
                    onPressed: () => context.push(AppRoutePaths.syncSetup),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SetupBenefitPoint extends StatelessWidget {
  const _SetupBenefitPoint({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tint,
  });

  final PhosphorIconData icon;
  final String title;
  final String subtitle;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        TintedGlassSurface.circle(
          size: 42,
          tint: tint,
          tintStrength: 0.12,
          borderColor: tint.withValues(alpha: 0.14),
          child: PhosphorIcon(icon, size: 24, color: tint),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Color _setupCardFill(ThemeData theme, Color accent) {
  final isDark = theme.brightness == Brightness.dark;
  final surface = isDark
      ? theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.34)
      : theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.70);
  return Color.alphaBlend(
    accent.withValues(alpha: isDark ? 0.035 : 0.025),
    surface,
  );
}

class _JoinOnlyReplaceSetupView extends ConsumerWidget {
  const _JoinOnlyReplaceSetupView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              AppIcons.devices,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.72),
            ),
            const SizedBox(height: 24),
            Text(
              'Ready to pair this device',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'This device was wiped so it can replace its local data by joining an existing sync group.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            PrismButton(
              label: 'Continue Pairing',
              icon: AppIcons.devices,
              tone: PrismButtonTone.filled,
              expanded: true,
              onPressed: () {
                ref
                    .read(onboardingProvider.notifier)
                    .enterSyncDeviceFlowFromWelcome();
                context.go(AppRoutePaths.onboarding);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalDisconnectSetupView extends ConsumerWidget {
  const _LocalDisconnectSetupView({required this.marker});

  final SyncDisconnectMarker marker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final previousSyncId = marker.hasPreviousSyncId
        ? _shortSyncId(marker.previousSyncId!)
        : null;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              AppIcons.syncDisabled,
              size: 64,
              color: theme.colorScheme.error.withValues(alpha: 0.72),
            ),
            const SizedBox(height: 24),
            Text(
              'Sync is off on this device',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              previousSyncId == null
                  ? 'Your data is still here, but it is no longer syncing with other devices.'
                  : 'Your data is still here, but it is no longer syncing with the previous group $previousSyncId.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            PrismButton(
              label: 'Start a New Sync Group',
              icon: AppIcons.addCircle,
              tone: PrismButtonTone.filled,
              expanded: true,
              onPressed: () => _confirmCreateNewGroup(context),
            ),
            const SizedBox(height: 12),
            PrismButton(
              label: 'Replace Local Data and Pair',
              icon: AppIcons.devices,
              tone: PrismButtonTone.destructive,
              expanded: true,
              onPressed: () => _confirmReplaceAndPair(context, ref),
            ),
            const SizedBox(height: 16),
            Text(
              'Pairing with another device replaces this device. It does not merge local-only changes into the other group.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmCreateNewGroup(BuildContext context) async {
    final previousSyncId = marker.hasPreviousSyncId
        ? ' Devices still using ${_shortSyncId(marker.previousSyncId!)} will not join automatically.'
        : '';
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: 'Start a new sync group?',
      message:
          'This creates a brand-new sync group from the data on this device.'
          '$previousSyncId To join an existing group, replace local data and pair instead.',
      confirmLabel: 'Start New Group',
      destructive: false,
    );
    if (confirmed && context.mounted) {
      await context.push(AppRoutePaths.syncSetup);
    }
  }

  Future<void> _confirmReplaceAndPair(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: 'Replace this device by pairing?',
      message:
          'This permanently wipes the data stored on this device, then opens the pairing flow. '
          'Make sure another device has the data you want. Prism will not merge this device into the other group.',
      confirmLabel: 'Wipe This Device and Pair',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    try {
      await ref
          .read(resetDataNotifierProvider.notifier)
          .replaceLocalDataAndPrepareForPairing();
      if (!context.mounted) return;
      final restartRequired = await ref
          .read(fullResetServiceProvider)
          .isRestartRequired();
      if (!context.mounted) return;
      if (restartRequired) {
        await Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute<void>(
            builder: (_) => const ResetRecoveryScreen(
              mode: ResetRecoveryScreenMode.restartRequired,
            ),
          ),
          (_) => false,
        );
        return;
      }
      ref.read(onboardingProvider.notifier).enterSyncDeviceFlowFromWelcome();
      context.go(AppRoutePaths.onboarding);
    } catch (e) {
      if (!context.mounted) return;
      PrismToast.error(context, message: 'Could not prepare pairing: $e');
    }
  }
}

String _shortSyncId(String syncId) {
  final compact = syncId.replaceAll(RegExp(r'\s+'), '');
  if (compact.length <= 12) return compact;
  return '${compact.substring(0, 6)}...${compact.substring(compact.length - 6)}';
}

class _StateMessageView extends StatelessWidget {
  const _StateMessageView({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

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
              icon,
              size: 64,
              color: theme.colorScheme.error.withValues(alpha: 0.8),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            PrismButton(
              label: actionLabel,
              icon: AppIcons.refresh,
              tone: PrismButtonTone.filled,
              onPressed: onAction,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfiguredView extends ConsumerWidget {
  const _ConfiguredView({required this.relayUrl, required this.syncId});

  final String relayUrl;
  final String syncId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncStatus = ref.watch(syncStatusProvider);
    final syncHealth = ref.watch(syncHealthProvider);
    final handleAsync = ref.watch(prismSyncHandleProvider);
    final handle = handleAsync.value;
    final isHandleLoading = handleAsync.isLoading && handle == null;
    final syncDatabaseReady = _watchSyncDatabaseReadyForUi(ref);
    final nodeId = ref.watch(nodeIdProvider).value;
    final wsConnected = ref.watch(websocketConnectedProvider);

    // Pairing entry-point gating: hide "Set up another device" unless this
    // device has a complete persistent sync identity AND a wrapped DEK on
    // hand. Without all three the inviter ceremony would either fail to
    // derive the joiner bundle (missing wrapped_dek) or trip a partial-
    // identity guard inside `SetupDeviceSheet.show`. Use `.value ?? false`
    // so the row stays hidden during async loads rather than briefly
    // visible on a stale truthy state.
    final pairingDeviceIdAsync = ref.watch(syncDeviceIdProvider);
    final pairingDeviceSecretAsync = ref.watch(syncDeviceSecretPresentProvider);
    final pairingWrappedDekAsync = ref.watch(syncWrappedDekPresentProvider);
    final canSetUpAnotherDevice = canSetUpAnotherDeviceRow(
      hasActiveHandle: handle != null,
      relayUrl: relayUrl,
      syncId: syncId,
      deviceId: pairingDeviceIdAsync.value,
      hasDeviceSecret: pairingDeviceSecretAsync.value ?? false,
      hasWrappedDek: pairingWrappedDekAsync.value ?? false,
    );
    final canVerifySavedBackup =
        canSetUpAnotherDevice && nodeId != null && nodeId.isNotEmpty;
    final canChangePin = syncHealth == SyncHealthState.healthy;

    final quarantinedAsync = ref.watch(quarantinedItemsProvider);

    final isSyncActive = syncStatus.isSyncing;
    final hasRelayUrl = relayUrl.isNotEmpty;
    final canSyncNow = canTriggerManualSync(
      hasHandle: handle != null,
      hasRelayUrl: hasRelayUrl,
      isSyncActive: isSyncActive,
      isHandleLoading: isHandleLoading,
      syncDatabaseReady: syncDatabaseReady,
    );

    return ListView(
      padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            PrismTokens.pageHorizontalPadding,
            PrismTokens.sectionSpacing,
            PrismTokens.pageHorizontalPadding,
            0,
          ),
          child: _SyncSummaryPanel(
            syncStatus: syncStatus,
            hasActiveHandle: handle != null,
            handleIsLoading: isHandleLoading,
            canAttemptReconnect: hasRelayUrl,
            wsConnected: wsConnected,
            syncDatabaseReady: syncDatabaseReady,
            canSyncNow: canSyncNow,
            onSyncNow: () => _syncNow(context, ref, handle, relayUrl),
          ),
        ),

        // Some local changes couldn't fit one sync envelope and were
        // quarantined (e.g. an oversized avatar). Surface it up top — not just
        // buried in Troubleshooting — and route there to repair.
        if (syncStatus.quarantinedBatchCount > 0)
          _QuarantineMainBanner(count: syncStatus.quarantinedBatchCount),

        PrismSection(
          title: context.l10n.syncDevicesSectionTitle,
          child: PrismGroupedSectionCard(
            child: Column(
              children: [
                if (syncHealth ==
                    SyncHealthState.runtimeDekRestoreDeferred) ...[
                  PrismSettingsRow(
                    icon: AppIcons.passwordOutlined,
                    title: 'Recover sync access',
                    subtitle:
                        'Use your PIN and recovery phrase if the device key '
                        'cannot be restored.',
                    onTap: () {
                      if (ref.read(syncHealthProvider) ==
                          SyncHealthState.runtimeDekRestoreDeferred) {
                        ref
                            .read(syncHealthProvider.notifier)
                            .setState(SyncHealthState.needsPassword);
                      }
                    },
                  ),
                ],
                if (handle != null) ...[
                  if (syncHealth == SyncHealthState.runtimeDekRestoreDeferred)
                    const Divider(height: 1, indent: 60, endIndent: 12),
                  if (canSetUpAnotherDevice &&
                      nodeId != null &&
                      nodeId.isNotEmpty) ...[
                    PrismSettingsRow(
                      icon: AppIcons.devices,
                      title: context.l10n.syncSetUpAnotherDevice,
                      subtitle: context.l10n.syncSetUpAnotherDeviceSubtitle,
                      onTap: () => SetupDeviceSheet.show(context, ref),
                    ),
                    const Divider(height: 1, indent: 60, endIndent: 12),
                  ],
                  PrismSettingsRow(
                    icon: AppIcons.devicesOther,
                    title: context.l10n.syncManageDevices,
                    subtitle: context.l10n.syncManageDevicesSubtitle,
                    onTap: () {
                      showAdaptiveDetailSurface<void>(
                        context: context,
                        builder: (_) => const DeviceManagementScreen(),
                        route: (context) =>
                            context.push(AppRoutePaths.settingsDevices),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),

        if (canChangePin || canVerifySavedBackup)
          PrismSection(
            title: context.l10n.syncSecuritySectionTitle,
            child: PrismGroupedSectionCard(
              child: Column(
                children: [
                  if (canChangePin)
                    PrismSettingsRow(
                      icon: AppIcons.passwordOutlined,
                      title: context.l10n.syncChangePassword,
                      subtitle: context.l10n.syncChangePasswordSubtitle,
                      enabled: !isSyncActive,
                      onTap: () => ChangePinSheet.show(context),
                    ),
                  if (canChangePin && canVerifySavedBackup)
                    const Divider(height: 1, indent: 60, endIndent: 12),
                  if (canVerifySavedBackup)
                    PrismSettingsRow(
                      icon: AppIcons.shieldOutlined,
                      title: context.l10n.verifyBackupRowTitle,
                      subtitle: context.l10n.verifyBackupRowSubtitle,
                      onTap: () {
                        showAdaptiveDetailSurface<void>(
                          context: context,
                          builder: (_) => const VerifyBackupScreen(),
                          route: (context) => context.push(
                            AppRoutePaths.settingsSyncVerifyBackup,
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),

        // Sync preferences — centralises sync-behaviour toggles from other screens
        PrismSection(
          title: context.l10n.syncPreferencesSection,
          child: PrismGroupedSectionCard(
            child: Column(
              children: [
                _SyncAppearanceToggle(),
                const Divider(height: 1, indent: 60, endIndent: 12),
                _IgnoreSyncedAppearanceToggle(),
                const Divider(height: 1, indent: 60, endIndent: 12),
                _SyncNavigationToggle(),
              ],
            ),
          ),
        ),

        if (syncStatus.hasSyncIssues)
          PrismSection(
            title: context.l10n.syncIssuesSection,
            description: context.l10n.syncIssuesDescription,
            child: PrismGroupedSectionCard(
              child: Column(
                children: [
                  if (syncStatus.quarantinedBatchCount > 0)
                    PrismSettingsRow(
                      icon: AppIcons.warningAmberRounded,
                      iconColor: Colors.amber.shade700,
                      title: context.l10n.syncQuarantinedBatchBannerTitle(
                        syncStatus.quarantinedBatchCount,
                      ),
                      subtitle: context.l10n.syncQuarantinedBatchBannerBody,
                      onTap: () => context.push(
                        AppRoutePaths.settingsSyncTroubleshooting,
                      ),
                    ),
                  if (syncStatus.quarantinedBatchCount > 0 &&
                      syncStatus.hasQuarantinedItems)
                    const Divider(height: 1),
                  if (syncStatus.hasQuarantinedItems) ...[
                    ...quarantinedAsync.whenOrNull(
                          data: (items) => items
                              .map((item) => _QuarantineItemTile(item: item))
                              .toList(),
                        ) ??
                        [],
                    if (quarantinedAsync.hasValue &&
                        quarantinedAsync.value!.isNotEmpty)
                      const Divider(height: 1),
                    PrismListRow(
                      title: Text(context.l10n.syncClearAll),
                      destructive: true,
                      onTap: () async {
                        await ref
                            .read(syncQuarantineServiceProvider)
                            .clearAll();
                        ref.invalidate(quarantinedItemsProvider);
                        ref
                            .read(syncStatusProvider.notifier)
                            .clearQuarantineFlag();
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),

        Padding(
          padding: const EdgeInsets.fromLTRB(
            PrismTokens.pageHorizontalPadding,
            PrismTokens.sectionSpacing,
            PrismTokens.pageHorizontalPadding,
            PrismTokens.sectionSpacing,
          ),
          child: PrismGroupedSectionCard(
            child: PrismSettingsRow(
              icon: AppIcons.buildCircleOutlined,
              title: context.l10n.syncTroubleshootingLink,
              onTap: () {
                showAdaptiveDetailSurface<void>(
                  context: context,
                  builder: (_) => const SyncTroubleshootingScreen(),
                  route: (context) =>
                      context.push(AppRoutePaths.settingsSyncTroubleshooting),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _syncNow(
    BuildContext context,
    WidgetRef ref,
    ffi.PrismSyncHandle? currentHandle,
    String relayUrl,
  ) async {
    try {
      if (!_readSyncDatabaseReadyForAction(ref)) {
        if (context.mounted) {
          PrismToast.error(context, message: _syncDatabaseNeedsRepairMessage);
        }
        return;
      }

      var handle = currentHandle;
      if (handle == null) {
        if (relayUrl.isEmpty) {
          throw StateError('Sync relay URL is missing.');
        }
        handle = await ref
            .read(prismSyncHandleProvider.notifier)
            .createHandle(relayUrl: relayUrl);
      }

      final health = await ref
          .read(prismSyncHandleProvider.notifier)
          .ensureConfigured(handle);
      if (health != SyncHealthState.healthy) {
        if (context.mounted) {
          PrismToast.error(
            context,
            message: _manualSyncUnavailableMessage(health),
          );
        }
        return;
      }

      await syncNowAfterOutboxDrain(
        db: ref.read(databaseProvider),
        handle: handle,
      );
      if (context.mounted) {
        PrismToast.show(context, message: context.l10n.syncFinished);
      }
    } catch (e) {
      if (context.mounted) {
        final message = e is SyncDbKeychainUnavailableException
            ? _syncTemporarilyUnavailableMessage
            : e is SyncDbUnrecoverableException
            ? _syncDatabaseNeedsRepairMessage
            : context.l10n.syncFailed(e);
        PrismToast.error(context, message: message);
      }
    }
  }

  String _manualSyncUnavailableMessage(SyncHealthState health) =>
      switch (health) {
        SyncHealthState.needsPassword =>
          'Sync needs your PIN and recovery phrase before it can reconnect.',
        SyncHealthState.needsRewrap =>
          'Re-enter your PIN and recovery phrase to restore your pairing key.',
        SyncHealthState.disconnected =>
          'Sync credentials are missing. Set up sync again to reconnect.',
        SyncHealthState.reconnecting =>
          'Sync is reconnecting — this should clear on its own in a moment.',
        SyncHealthState.unpaired => 'Sync is not set up on this device.',
        SyncHealthState.awaitingDeviceUnlock =>
          'Sync paused while the device was locked — it will reconnect '
              'once you bring the app to the foreground.',
        SyncHealthState.runtimeDekRestoreDeferred =>
          'Sync paused while the device key is being checked. Reopen Prism '
              'or unlock your device to retry.',
        SyncHealthState.healthy => 'Sync is not ready yet.',
      };
}

const _syncDatabaseNeedsRepairMessage =
    'Sync database needs repair. Open Advanced to reset sync and re-pair '
    'this device.';

const _syncTemporarilyUnavailableMessage =
    "Couldn't reach secure storage just now — your data is safe. Close and "
    'reopen Prism, then try syncing again.';

bool _watchSyncDatabaseReadyForUi(WidgetRef ref) {
  try {
    return ref.watch(syncDatabaseStartupProvider).state == DbStartupState.ready;
  } catch (_) {
    return true;
  }
}

bool _readSyncDatabaseReadyForAction(WidgetRef ref) {
  try {
    return ref.read(syncDatabaseStartupProvider).state == DbStartupState.ready;
  } catch (_) {
    return true;
  }
}

class _SyncAppearanceToggle extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(syncAppearanceEnabledProvider);

    return PrismSwitchRow(
      icon: AppIcons.paletteOutlined,
      iconColor: Colors.deepPurple,
      title: context.l10n.syncPreferenceAppearanceTitle,
      subtitle: context.l10n.syncPreferenceAppearanceSubtitle,
      value: value,
      onChanged: (v) =>
          ref.read(settingsNotifierProvider.notifier).updateSyncThemeEnabled(v),
    );
  }
}

class _IgnoreSyncedAppearanceToggle extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncValue = ref.watch(ignoreSyncedAppearanceProvider);
    final value = asyncValue.whenOrNull(data: (v) => v) ?? false;

    return PrismSwitchRow(
      icon: AppIcons.devicesOther,
      iconColor: Colors.blueGrey,
      title: context.l10n.syncPreferenceLocalAppearanceTitle,
      subtitle: context.l10n.syncPreferenceLocalAppearanceSubtitle,
      value: value,
      onChanged: (v) =>
          ref.read(ignoreSyncedAppearanceProvider.notifier).set(v),
    );
  }
}

class _SyncNavigationToggle extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(syncNavigationEnabledProvider);

    return PrismSwitchRow(
      icon: AppIcons.tabOutlined,
      iconColor: Colors.teal,
      title: context.l10n.syncPreferenceNavigationTitle,
      subtitle: context.l10n.syncPreferenceNavigationSubtitle,
      value: value,
      onChanged: (v) => ref
          .read(settingsNotifierProvider.notifier)
          .updateSyncNavigationEnabled(v),
    );
  }
}

/// Banner shown when local push batches were quarantined.
class _QuarantineMainBanner extends StatelessWidget {
  const _QuarantineMainBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.push(AppRoutePaths.settingsSyncTroubleshooting),
        child: PrismSurface(
          fillColor: theme.colorScheme.errorContainer,
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                AppIcons.warningAmberRounded,
                color: theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.l10n.syncQuarantinedBatchBannerTitle(count),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                AppIcons.chevronRight,
                size: 18,
                color: theme.colorScheme.onErrorContainer,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single quarantined record shown in the Sync Issues section.
class _QuarantineItemTile extends StatelessWidget {
  const _QuarantineItemTile({required this.item});

  final SyncQuarantineData item;

  @override
  Widget build(BuildContext context) {
    final field = item.fieldName ?? 'unknown field';
    return PrismListRow(
      dense: true,
      leading: Icon(
        AppIcons.warningAmberRounded,
        size: 20,
        color: Colors.amber.shade700,
      ),
      title: Text('${item.entityType} · $field'),
      subtitle: Text(
        item.errorMessage ??
            'Expected ${item.expectedType}, got ${item.receivedType}',
      ),
    );
  }
}

class _SyncSummaryPanel extends StatefulWidget {
  const _SyncSummaryPanel({
    required this.syncStatus,
    required this.hasActiveHandle,
    required this.handleIsLoading,
    required this.canAttemptReconnect,
    required this.wsConnected,
    required this.syncDatabaseReady,
    required this.canSyncNow,
    required this.onSyncNow,
  });

  final SyncStatus syncStatus;
  final bool hasActiveHandle;
  final bool handleIsLoading;
  final bool canAttemptReconnect;
  final bool wsConnected;
  final bool syncDatabaseReady;
  final bool canSyncNow;
  final VoidCallback onSyncNow;

  @override
  State<_SyncSummaryPanel> createState() => _SyncSummaryPanelState();
}

class _SyncSummaryPanelState extends State<_SyncSummaryPanel> {
  static const _syncingShowDelay = Duration(milliseconds: 350);
  static const _syncingMinVisible = Duration(milliseconds: 800);

  Timer? _syncingTimer;
  bool _showSyncing = false;
  DateTime? _syncingShownAt;

  @override
  void initState() {
    super.initState();
    _syncPresentationState();
  }

  @override
  void didUpdateWidget(_SyncSummaryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.syncStatus.isSyncing != widget.syncStatus.isSyncing) {
      _syncPresentationState();
    }
  }

  @override
  void dispose() {
    _syncingTimer?.cancel();
    super.dispose();
  }

  void _syncPresentationState() {
    _syncingTimer?.cancel();
    _syncingTimer = null;

    if (widget.syncStatus.isSyncing) {
      if (_showSyncing) return;
      _syncingTimer = Timer(_syncingShowDelay, () {
        if (!mounted || !widget.syncStatus.isSyncing) return;
        setState(() {
          _showSyncing = true;
          _syncingShownAt = DateTime.now();
        });
      });
      return;
    }

    if (!_showSyncing) return;
    final shownAt = _syncingShownAt;
    final visibleFor = shownAt == null
        ? _syncingMinVisible
        : DateTime.now().difference(shownAt);
    final remaining = _syncingMinVisible - visibleFor;
    if (remaining <= Duration.zero) {
      setState(() {
        _showSyncing = false;
        _syncingShownAt = null;
      });
      return;
    }

    _syncingTimer = Timer(remaining, () {
      if (!mounted || widget.syncStatus.isSyncing) return;
      setState(() {
        _showSyncing = false;
        _syncingShownAt = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final visibleStatus = _visibleSyncStatus(widget.syncStatus, _showSyncing);
    final buttonIsBusy = _showSyncing || widget.handleIsLoading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatusCard(
          syncStatus: visibleStatus,
          hasActiveHandle: widget.hasActiveHandle,
          handleIsLoading: widget.handleIsLoading,
          canAttemptReconnect: widget.canAttemptReconnect,
          wsConnected: widget.wsConnected,
          syncDatabaseReady: widget.syncDatabaseReady,
        ),
        const SizedBox(height: PrismTokens.sectionSpacing),
        PrismButton(
          label: _showSyncing
              ? context.l10n.syncSummaryActivitySyncing
              : context.l10n.syncNowTitle,
          icon: AppIcons.sync,
          tone: PrismButtonTone.outlined,
          density: PrismControlDensity.regular,
          expanded: true,
          enabled: widget.canSyncNow && !buttonIsBusy,
          isLoading: buttonIsBusy,
          semanticLabel: context.l10n.syncNowTitle,
          onPressed: widget.onSyncNow,
        ),
      ],
    );
  }

  SyncStatus _visibleSyncStatus(SyncStatus status, bool isSyncing) {
    return SyncStatus(
      isSyncing: isSyncing,
      lastSyncAt: status.lastSyncAt,
      pendingOps: status.pendingOps,
      lastError: status.lastError,
      hasQuarantinedItems: status.hasQuarantinedItems,
      quarantinedBatchCount: status.quarantinedBatchCount,
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.syncStatus,
    required this.hasActiveHandle,
    required this.handleIsLoading,
    required this.canAttemptReconnect,
    required this.wsConnected,
    required this.syncDatabaseReady,
  });

  final SyncStatus syncStatus;
  final bool hasActiveHandle;
  final bool handleIsLoading;
  final bool canAttemptReconnect;
  final bool wsConnected;
  final bool syncDatabaseReady;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shapes = PrismShapes.of(context);
    final summary = buildSyncSummaryPresentation(
      syncStatus: syncStatus,
      hasActiveHandle: hasActiveHandle,
      handleIsLoading: handleIsLoading,
      canAttemptReconnect: canAttemptReconnect,
      wsConnected: wsConnected,
      syncDatabaseReady: syncDatabaseReady,
    );
    final statusColor = _summaryColor(theme, summary.tone);
    final radius = BorderRadius.circular(
      shapes.radius(PrismTokens.radiusLarge),
    );
    final headline = _summaryHeadlineText(context, summary.headline);
    final detail = _summaryDetailText(context, summary);
    final error = syncStatus.lastError;
    final semanticParts = [headline, detail, ?error];

    return Semantics(
      container: true,
      label: semanticParts.join(', '),
      child: ClipRRect(
        borderRadius: radius,
        child: GlassSurface(
          borderRadius: radius,
          backgroundColor: _summaryCardFill(theme, statusColor),
          borderColor: statusColor.withValues(alpha: 0.18),
          padding: EdgeInsets.zero,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.transparent,
                        statusColor.withValues(
                          alpha: theme.brightness == Brightness.dark
                              ? 0.08
                              : 0.06,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: statusColor.withValues(alpha: 0.16),
                            blurRadius: 20,
                          ),
                        ],
                      ),
                      child: GlassSurface.circle(
                        size: 56,
                        tint: statusColor,
                        backgroundColor: statusColor.withValues(alpha: 0.08),
                        borderColor: statusColor.withValues(alpha: 0.22),
                        child: PhosphorIcon(
                          _summaryIcon(summary.headline),
                          color: statusColor,
                          size: 34,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            headline,
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            detail,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.25,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (error != null && error != detail) ...[
                            const SizedBox(height: 6),
                            Text(
                              error,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
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

  String _formatTime(DateTime time, BuildContext context) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return context.l10n.syncJustNow;
    if (diff.inMinutes < 60) return context.l10n.syncMinutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return context.l10n.syncHoursAgo(diff.inHours);
    return context.l10n.syncDaysAgo(diff.inDays);
  }

  String _summaryHeadlineText(
    BuildContext context,
    SyncSummaryHeadline headline,
  ) => switch (headline) {
    SyncSummaryHeadline.connected => context.l10n.syncSummaryConnected,
    SyncSummaryHeadline.reconnecting => context.l10n.syncSummaryReconnecting,
    SyncSummaryHeadline.needsAttention =>
      context.l10n.syncSummaryNeedsAttention,
    SyncSummaryHeadline.offline => context.l10n.syncSummaryOffline,
  };

  String? _summaryActivityText(
    BuildContext context,
    SyncSummaryPresentation summary,
  ) => switch (summary.activity) {
    SyncSummaryActivity.checkingForChanges =>
      context.l10n.syncSummaryActivityChecking,
    SyncSummaryActivity.syncing => context.l10n.syncSummaryActivitySyncing,
    SyncSummaryActivity.pendingUploads =>
      context.l10n.syncSummaryPendingUploads(summary.pendingUploads),
    SyncSummaryActivity.reconnecting =>
      context.l10n.syncSummaryActivityReconnecting,
    SyncSummaryActivity.needsRepair => context.l10n.syncSummaryNeedsRepair,
    SyncSummaryActivity.none => null,
  };

  String _summaryDetailText(
    BuildContext context,
    SyncSummaryPresentation summary,
  ) {
    final synced = _summarySyncedText(context);
    final activity = _summaryActivityText(context, summary);
    if (activity == null ||
        summary.activity == SyncSummaryActivity.checkingForChanges) {
      return synced;
    }
    return '$activity · $synced';
  }

  String _summarySyncedText(BuildContext context) {
    final lastSyncAt = syncStatus.lastSyncAt;
    if (lastSyncAt == null) return context.l10n.syncSummaryNeverSynced;
    final diff = DateTime.now().difference(lastSyncAt);
    if (diff.inSeconds < 60) return context.l10n.syncSummarySyncedJustNow;
    return context.l10n.syncSummarySyncedAt(_formatTime(lastSyncAt, context));
  }

  PhosphorIconData _summaryIcon(SyncSummaryHeadline headline) {
    return switch (headline) {
      SyncSummaryHeadline.connected => AppIcons.duotoneCloudCheck,
      SyncSummaryHeadline.reconnecting => AppIcons.duotoneSync,
      SyncSummaryHeadline.needsAttention => AppIcons.duotoneWarning,
      SyncSummaryHeadline.offline => AppIcons.duotoneCloudOff,
    };
  }

  Color _summaryColor(ThemeData theme, SyncSummaryTone tone) {
    final isDark = theme.brightness == Brightness.dark;
    return switch (tone) {
      SyncSummaryTone.healthy =>
        isDark ? const Color(0xFF78C99A) : const Color(0xFF287A52),
      SyncSummaryTone.warning =>
        isDark ? const Color(0xFFD6B65D) : const Color(0xFF8A6400),
      SyncSummaryTone.error => theme.colorScheme.error,
    };
  }

  Color _summaryCardFill(ThemeData theme, Color statusColor) {
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark
        ? theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.34)
        : theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.70);
    return Color.alphaBlend(
      statusColor.withValues(alpha: isDark ? 0.035 : 0.025),
      surface,
    );
  }
}
