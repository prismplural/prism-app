import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/core/services/biometric_service.dart';

/// Singleton [BiometricService] instance.
final biometricServiceProvider = Provider<BiometricService>((ref) {
  return BiometricService();
});
