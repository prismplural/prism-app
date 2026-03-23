import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/core/services/pin_lock_service.dart';

/// Singleton PinLockService instance.
final pinLockServiceProvider = Provider<PinLockService>((ref) {
  return PinLockService();
});

/// Whether a PIN is currently stored in secure storage.
final isPinSetProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(pinLockServiceProvider);
  return service.isPinSet();
});

/// Whether biometric authentication is available on this device.
final isBiometricAvailableProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(pinLockServiceProvider);
  return service.isBiometricAvailable();
});
