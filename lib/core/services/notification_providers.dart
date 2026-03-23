import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/services/fronting_notification_service.dart';

/// Provides the [FrontingNotificationService] singleton instance.
final frontingNotificationServiceProvider =
    Provider<FrontingNotificationService>((ref) {
  return FrontingNotificationService();
});

/// Checks whether notification permissions are currently granted.
final notificationPermissionProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(frontingNotificationServiceProvider);
  await service.initialize();
  return service.isPermissionGranted();
});
