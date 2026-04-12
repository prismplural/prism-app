import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/settings/providers/device_management_provider.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_pill.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

class DeviceManagementScreen extends ConsumerWidget {
  const DeviceManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesAsync = ref.watch(deviceListProvider);
    final currentDeviceId = ref.watch(nodeIdProvider).value;

    return PrismPageScaffold(
      topBar: PrismTopBar(title: context.l10n.devicesTitle, showBackButton: true),
      bodyPadding: EdgeInsets.zero,
      body: devicesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  AppIcons.errorOutline,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  context.l10n.devicesFailedToLoad,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        data: (devices) {
          final currentDevice = devices
              .where((d) => d.deviceId == currentDeviceId)
              .firstOrNull;
          final otherDevices = devices
              .where((d) => d.deviceId != currentDeviceId && !d.isRevoked)
              .toList();

          return RefreshIndicator(
            onRefresh: () => ref.refresh(deviceListProvider.future),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                if (currentDevice != null) ...[
                  _SectionHeader(title: context.l10n.devicesThisDevice),
                  _DeviceTile(
                    device: currentDevice,
                    isCurrent: true,
                    onRevoke: null,
                    onRotateKey: () =>
                        _confirmRotateKey(context, ref, currentDevice),
                  ),
                  const SizedBox(height: 16),
                ],
                _SectionHeader(
                  title: context.l10n.devicesOtherDevices,
                  trailing: Text(
                    '${otherDevices.length}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                if (otherDevices.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 32),
                    child: EmptyState(
                      icon: Icon(AppIcons.devices, size: 48),
                      title: context.l10n.devicesNoOtherDevices,
                      subtitle: context.l10n.devicesNoOtherDevicesSubtitle,
                    ),
                  )
                else
                  ...otherDevices.map(
                    (device) => _DeviceTile(
                      device: device,
                      isCurrent: false,
                      onRevoke: () => _confirmRevoke(context, ref, device),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmRotateKey(
    BuildContext context,
    WidgetRef ref,
    Device device,
  ) async {
    final confirmed = await PrismDialog.show<bool>(
      context: context,
      title: context.l10n.devicesRotateKeyTitle,
      message: context.l10n.devicesRotateKeyMessage,
      builder: (dialogContext) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            PrismButton(
              label: context.l10n.cancel,
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            const SizedBox(width: 8),
            PrismButton(
              label: context.l10n.devicesRotate,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) return;

    try {
      final newGen =
          await ref.read(deviceListProvider.notifier).rotateMlDsaKey();
      if (context.mounted) {
        PrismToast.success(
          context,
          message: context.l10n.devicesKeyRotated(newGen),
        );
      }
    } catch (e) {
      if (context.mounted) {
        PrismToast.error(context, message: context.l10n.devicesKeyRotationFailed(e));
      }
    }
  }

  Future<void> _confirmRevoke(
    BuildContext context,
    WidgetRef ref,
    Device device,
  ) async {
    final result = await PrismDialog.show<({bool confirmed, bool wipe})>(
      context: context,
      title: context.l10n.devicesRevokeTitle,
      message: context.l10n.devicesRevokeMessage(device.shortId),
      builder: (dialogContext) {
        var requestWipe = false;

        return StatefulBuilder(
          builder: (_, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PrismSwitchRow(
                  title: context.l10n.devicesRequestWipeTitle,
                  subtitle: context.l10n.devicesRequestWipeSubtitle,
                  value: requestWipe,
                  onChanged: (value) => setState(() => requestWipe = value),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    PrismButton(
                      label: context.l10n.cancel,
                      onPressed: () => Navigator.of(dialogContext).pop(null),
                    ),
                    const SizedBox(width: 8),
                    PrismButton(
                      label: context.l10n.devicesRevoke,
                      onPressed: () => Navigator.of(
                        dialogContext,
                      ).pop((confirmed: true, wipe: requestWipe)),
                      tone: PrismButtonTone.destructive,
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null || !result.confirmed || !context.mounted) return;

    try {
      await ref
          .read(deviceListProvider.notifier)
          .revoke(device.deviceId, remoteWipe: result.wipe);
      if (context.mounted) {
        PrismToast.success(
          context,
          message: context.l10n.devicesRevoked(device.shortId),
        );
      }
    } catch (e) {
      if (context.mounted) {
        PrismToast.error(context, message: context.l10n.devicesFailedToRevoke(e));
      }
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
              fontWeight: FontWeight.w600,
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.isCurrent,
    this.onRevoke,
    this.onRotateKey,
  });

  final Device device;
  final bool isCurrent;
  final VoidCallback? onRevoke;
  final VoidCallback? onRotateKey;

  Color _statusColor(BuildContext context) {
    if (device.isActive) return Colors.green;
    if (device.isStale) return Colors.amber;
    return Theme.of(context).colorScheme.outline;
  }

  String _statusLabel(BuildContext context) {
    if (device.isActive) return context.l10n.devicesStatusActive;
    if (device.isStale) return context.l10n.devicesStatusStale;
    if (device.isRevoked) return context.l10n.devicesStatusRevoked;
    return device.status;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColor(context);
    final statusLabel = _statusLabel(context);

    return Semantics(
      label: isCurrent
          ? context.l10n.devicesSemanticLabelCurrent(device.shortId, statusLabel, device.mlDsaKeyGeneration)
          : context.l10n.devicesSemanticLabel(device.shortId, statusLabel, device.mlDsaKeyGeneration),
      child: PrismSurface(
        padding: EdgeInsets.zero,
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: PrismListRow(
          leading: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          title: Row(
            children: [
              Text(
                device.shortId,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              if (isCurrent)
                PrismPill(
                  label: context.l10n.devicesThisDevice,
                  tone: PrismPillTone.accent,
                )
              else
                PrismPill(label: statusLabel, color: statusColor),
            ],
          ),
          subtitle: Text(
            context.l10n.devicesEpochKeyGen(device.epoch, device.mlDsaKeyGeneration),
          ),
          trailing: isCurrent
              ? (onRotateKey != null
                  ? PrismIconButton(
                      icon: AppIcons.refresh,
                      tooltip: context.l10n.devicesRotateKeyTooltip,
                      color: theme.colorScheme.primary,
                      size: 36,
                      iconSize: 18,
                      onPressed: onRotateKey!,
                    )
                  : null)
              : PrismIconButton(
                  icon: AppIcons.removeCircleOutline,
                  tooltip: context.l10n.devicesRevokeTooltip,
                  color: theme.colorScheme.error,
                  size: 36,
                  iconSize: 18,
                  onPressed: onRevoke!,
                ),
          onLongPress: () {
            Clipboard.setData(ClipboardData(text: device.deviceId));
            PrismToast.show(context, message: context.l10n.devicesIdCopied);
          },
        ),
      ),
    );
  }
}
