import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/features/fronting/sanitization/fronting_sanitizer_service.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_editing_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_validation_providers.dart';

/// Tracks the count of unresolved timeline issues found after sync or edits.
/// Displayed as a banner on the fronting tab.
final frontingIssueCountProvider =
    NotifierProvider<FrontingIssueCountNotifier, int>(
      FrontingIssueCountNotifier.new,
    );

class FrontingIssueCountNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void setCount(int count) => state = count;
}

/// Provides a [FrontingSanitizerService] wired to the repository, validator,
/// planner, and executor layers.
final frontingSanitizerServiceProvider =
    Provider<FrontingSanitizerService>((ref) {
  return FrontingSanitizerService(
    repository: ref.watch(frontingSessionRepositoryProvider),
    validator: ref.watch(frontingValidatorProvider),
    planner: ref.watch(frontingFixPlannerProvider),
    executor: ref.watch(frontingChangeExecutorProvider),
  );
});

/// Runs a scoped rescan over the time range [sessionStart, sessionEnd] ± 1
/// hour and updates [frontingIssueCountProvider] with the number of issues
/// found. The scan is fire-and-forget — it does not block the caller.
///
/// Typical usage: call this after a session edit completes.
void triggerPostEditRescan(
  WidgetRef ref, {
  required DateTime sessionStart,
  DateTime? sessionEnd,
}) {
  const padding = Duration(hours: 1);
  final from = sessionStart.subtract(padding);
  final to = (sessionEnd ?? sessionStart).add(padding);

  final sanitizer = ref.read(frontingSanitizerServiceProvider);

  // Fire-and-forget: errors are swallowed to avoid disrupting the UI.
  sanitizer.scan(from: from, to: to).then((issues) {
    ref.read(frontingIssueCountProvider.notifier).setCount(issues.length);
  }).catchError((Object e, StackTrace st) {
    debugPrint('[FrontingRescan] Post-edit rescan failed: $e\n$st');
  });
}

// TODO(sync): Wire a post-sync rescan by listening to syncEventStreamProvider
// for SyncCompleted events (see lib/core/sync/prism_sync_providers.dart,
// SyncStatusNotifier.build() for the pattern). The challenge is that
// triggerPostEditRescan needs a time range (sessionStart/sessionEnd), but
// SyncCompleted events don't carry which fronting_sessions were affected.
//
// Approach: add a Riverpod provider that listens to syncEventStreamProvider,
// filters for isSyncCompleted with no error, and triggers a broad rescan
// (e.g. last 30 days). This provider would use Ref, not WidgetRef, so it
// needs a Ref-compatible variant of triggerPostEditRescan. Example:
//
//   ref.listen(syncEventStreamProvider, (prev, next) {
//     next.whenData((event) {
//       if (event.isSyncCompleted) {
//         triggerPostSyncRescan(ref, from: thirtyDaysAgo, to: now);
//       }
//     });
//   });
