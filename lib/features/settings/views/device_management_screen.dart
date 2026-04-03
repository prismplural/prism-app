import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/settings/providers/device_management_provider.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

class DeviceManagementScreen extends ConsumerWidget {
  const DeviceManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesAsync = ref.watch(deviceListProvider);
    final currentDeviceId = ref.watch(nodeIdProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Devices')),
      body: devicesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(AppIcons.errorOutline,
                    size: 48, color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 16),
                Text(
                  'Failed to load devices',
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
                  const _SectionHeader(title: 'This Device'),
                  _DeviceTile(
                    device: currentDevice,
                    isCurrent: true,
                    onRevoke: null,
                  ),
                  const SizedBox(height: 16),
                ],
                _SectionHeader(
                  title: 'Other Devices',
                  trailing: Text(
                    '${otherDevices.length}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5),
                        ),
                  ),
                ),
                if (otherDevices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 32),
                    child: EmptyState(
                      icon: Icon(AppIcons.devices, size: 48),
                      title: 'No other devices',
                      subtitle:
                          'Only this device is registered in the sync group.',
                    ),
                  )
                else
                  ...otherDevices.map(
                    (device) => _DeviceTile(
                      device: device,
                      isCurrent: false,
                      onRevoke: () =>
                          _confirmRevoke(context, ref, device),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmRevoke(
    BuildContext context,
    WidgetRef ref,
    Device device,
  ) async {
    final result = await PrismDialog.show<({bool confirmed, bool wipe})>(
      context: context,
      title: 'Revoke Device?',
      message: 'Device ${device.shortId} will be removed from the sync '
          'group and can no longer sync. This cannot be undone.',
      builder: (dialogContext) {
        var requestWipe = false;

        return StatefulBuilder(
          builder: (builderContext, setState) {
            final theme = Theme.of(builderContext);

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Request remote data wipe',
                    style: theme.textTheme.bodyMedium,
                  ),
                  subtitle: Text(
                    'Asks the device to erase its sync data. This is a '
                    'request \u2014 if the device is offline or '
                    'compromised, it may not be honored.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.5),
                    ),
                  ),
                  value: requestWipe,
                  onChanged: (value) => setState(() {
                    requestWipe = value;
                  }),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    PrismButton(
                      label: 'Cancel',
                      onPressed: () =>
                          Navigator.of(dialogContext).pop(null),
                    ),
                    const SizedBox(width: 8),
                    PrismButton(
                      label: 'Revoke',
                      onPressed: () => Navigator.of(dialogContext)
                          .pop((confirmed: true, wipe: requestWipe)),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Device ${device.shortId} revoked')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to revoke: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
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
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                  fontWeight: FontWeight.w600,
                ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
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
  });

  final Device device;
  final bool isCurrent;
  final VoidCallback? onRevoke;

  Color _statusColor(BuildContext context) {
    if (device.isActive) return Colors.green;
    if (device.isStale) return Colors.amber;
    return Theme.of(context).colorScheme.outline;
  }

  String _statusLabel() {
    if (device.isActive) return 'Active';
    if (device.isStale) return 'Stale';
    if (device.isRevoked) return 'Revoked';
    return device.status;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColor(context);

    return Semantics(
      label:
          'Device ${device.shortId}, ${_statusLabel()}${isCurrent ? ', this device' : ''}',
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: ListTile(
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
                Chip(
                  label: const Text('This Device'),
                  labelStyle: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimary,
                  ),
                  backgroundColor: theme.colorScheme.primary,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                )
              else
                Chip(
                  label: Text(_statusLabel()),
                  labelStyle: theme.textTheme.labelSmall?.copyWith(
                    color: statusColor,
                  ),
                  side: BorderSide(color: statusColor.withValues(alpha: 0.3)),
                  backgroundColor:
                      statusColor.withValues(alpha: 0.1),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
            ],
          ),
          subtitle: Text('Epoch ${device.epoch}'),
          trailing: isCurrent
              ? null
              : IconButton(
                  icon: const Icon(AppIcons.removeCircleOutline),
                  tooltip: 'Revoke device',
                  color: theme.colorScheme.error,
                  onPressed: onRevoke,
                ),
          onLongPress: () {
            Clipboard.setData(ClipboardData(text: device.deviceId));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Device ID copied')),
            );
          },
        ),
      ),
    );
  }
}
