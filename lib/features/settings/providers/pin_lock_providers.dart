import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/core/services/pin_lock_service.dart';

/// Singleton PinLockService instance.
final pinLockServiceProvider = Provider<PinLockService>((ref) {
  return PinLockService();
});

/// Whether a PIN is currently stored in secure storage.
///
/// Evaluated once at boot (before the lock decision), so this is also where we
/// run the legacy-PIN force-migration guard: a lingering SHA-256 (version-1)
/// slot is invalidated after N boots without an unlock so the weak hash cannot
/// persist indefinitely. The guard runs before [PinLockService.isPinSet] so the
/// returned value reflects any force-invalidation that just happened.
final isPinSetProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(pinLockServiceProvider);
  await service.enforceLegacyPinMigrationPolicy();
  return service.isPinSet();
});

/// Whether biometric authentication is available on this device.
final isBiometricAvailableProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(pinLockServiceProvider);
  return service.isBiometricAvailable();
});
