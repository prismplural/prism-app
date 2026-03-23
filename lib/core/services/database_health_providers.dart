import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/services/database_health_service.dart';

/// Provides a [DatabaseHealthService] singleton.
final databaseHealthServiceProvider = Provider<DatabaseHealthService>((ref) {
  return const DatabaseHealthService();
});

/// Runs a health check and returns a [HealthReport].
///
/// Invalidate this provider to re-run the check.
final healthReportProvider = FutureProvider<HealthReport>((ref) async {
  final service = ref.watch(databaseHealthServiceProvider);
  final members = ref.watch(memberRepositoryProvider);
  final sessions = ref.watch(frontingSessionRepositoryProvider);
  final conversations = ref.watch(conversationRepositoryProvider);
  final messages = ref.watch(chatMessageRepositoryProvider);

  return service.runHealthCheck(
    members: members,
    sessions: sessions,
    conversations: conversations,
    messages: messages,
  );
});
