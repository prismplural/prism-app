import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:prism_plurality/core/services/local_notification_service.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

class PermissionsStep extends ConsumerStatefulWidget {
  const PermissionsStep({super.key});

  @override
  ConsumerState<PermissionsStep> createState() => _PermissionsStepState();
}

class _PermissionsStepState extends ConsumerState<PermissionsStep> {
  bool _notificationsGranted = false;
  bool _notificationsDeniedPermanently = false;
  bool _micGranted = false;
  bool _micDeniedPermanently = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkCurrentStatus();
  }

  Future<void> _checkCurrentStatus() async {
    final notifStatus = await Permission.notification.status;
    final micStatus =
        kIsWeb ? PermissionStatus.denied : await Permission.microphone.status;
    if (!mounted) return;
    setState(() {
      _notificationsGranted = notifStatus.isGranted;
      _notificationsDeniedPermanently = notifStatus.isPermanentlyDenied;
      _micGranted = micStatus.isGranted;
      _micDeniedPermanently = micStatus.isPermanentlyDenied;
      _loading = false;
    });
  }

  Future<void> _requestNotifications() async {
    final service = ref.read(localNotificationServiceProvider);
    final granted = await service.requestPermission();
    if (!mounted) return;
    if (granted) {
      setState(() => _notificationsGranted = true);
    } else {
      final status = await Permission.notification.status;
      if (!mounted) return;
      setState(() {
        _notificationsDeniedPermanently = status.isPermanentlyDenied;
      });
    }
  }

  Future<void> _requestMicrophone() async {
    final status = await Permission.microphone.request();
    if (!mounted) return;
    setState(() {
      _micGranted = status.isGranted;
      _micDeniedPermanently = status.isPermanentlyDenied;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          _PermissionRow(
            icon: AppIcons.editNotificationsOutlined,
            title: l10n.onboardingPermissionsNotificationTitle,
            rationale: l10n.onboardingPermissionsNotificationRationale,
            isGranted: _notificationsGranted,
            isDeniedPermanently: _notificationsDeniedPermanently,
            onRequest: _requestNotifications,
            allowLabel: l10n.onboardingPermissionsAllow,
            allowedLabel: l10n.onboardingPermissionsAllowed,
            openSettingsLabel: l10n.onboardingPermissionsOpenSettings,
            theme: theme,
          ),
          const SizedBox(height: 16),
          if (!kIsWeb)
            _PermissionRow(
              icon: AppIcons.microphone,
              title: l10n.onboardingPermissionsMicrophoneTitle,
              rationale: l10n.onboardingPermissionsMicrophoneRationale,
              isGranted: _micGranted,
              isDeniedPermanently: _micDeniedPermanently,
              onRequest: _requestMicrophone,
              allowLabel: l10n.onboardingPermissionsAllow,
              allowedLabel: l10n.onboardingPermissionsAllowed,
              openSettingsLabel: l10n.onboardingPermissionsOpenSettings,
              theme: theme,
            ),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.rationale,
    required this.isGranted,
    required this.isDeniedPermanently,
    required this.onRequest,
    required this.allowLabel,
    required this.allowedLabel,
    required this.openSettingsLabel,
    required this.theme,
  });

  final IconData icon;
  final String title;
  final String rationale;
  final bool isGranted;
  final bool isDeniedPermanently;
  final VoidCallback onRequest;
  final String allowLabel;
  final String allowedLabel;
  final String openSettingsLabel;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$title: ${isGranted ? allowedLabel : "not granted"}',
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 28,
              color: isGranted
                  ? AppColors.success
                  : theme.colorScheme.primary,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    rationale,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (isGranted)
              Icon(
                Icons.check_circle_rounded,
                color: AppColors.success,
                size: 24,
              )
            else if (isDeniedPermanently)
              TextButton(
                onPressed: () => openAppSettings(),
                child: Text(
                  openSettingsLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              )
            else
              FilledButton.tonal(
                onPressed: onRequest,
                child: Text(allowLabel),
              ),
          ],
        ),
      ),
    );
  }
}
