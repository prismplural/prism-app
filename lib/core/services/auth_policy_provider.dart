import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/core/services/auth_policy_service.dart';

/// Singleton [AuthPolicyService] instance.
final authPolicyServiceProvider = Provider<AuthPolicyService>((ref) {
  return AuthPolicyService();
});

/// Whether the user is due for a periodic PIN verification (every 30 days).
final pinVerificationDueProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(authPolicyServiceProvider);
  return service.isPinVerificationDue();
});

/// Whether the user is due for a recovery-phrase backup reminder (every 30 days).
final backupReminderDueProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(authPolicyServiceProvider);
  return service.isBackupReminderDue();
});
