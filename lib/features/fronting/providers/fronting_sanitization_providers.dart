import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/fronting/sanitization/fronting_sanitizer_service.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_editing_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_validation_providers.dart';

/// Tracks the count of unresolved timeline issues found after sync or edits.
/// Displayed as a banner on the fronting tab.
///
/// Post-sync rescans are driven by [syncEventStreamProvider]: whenever a
/// RemoteChanges event includes fronting_sessions rows, a broad rescan over
/// the last 30 days is triggered automatically. No explicit wiring needed at
/// call sites — the listener activates as soon as this provider is first
/// watched (e.g. when the fronting-tab banner widget builds).
final frontingIssueCountProvider =
    NotifierProvider<FrontingIssueCountNotifier, int>(
      FrontingIssueCountNotifier.new,
    );

class FrontingIssueCountNotifier extends Notifier<int> {
  @override
  int build() {
    if (kReleaseMode) {
      return 0;
    }

    // Listen for remote fronting_sessions changes and trigger a broad rescan.
    // RemoteChanges events fire after Drift rows are already written, so the
    // repository will return the updated data when the scan runs.
    ref.listen(syncEventStreamProvider, (previous, next) {
      next.whenData((event) {
        if (!event.isRemoteChanges) return;
        final hasFrontingChanges = event.changes.any(
          (c) => c['table'] == 'fronting_sessions',
        );
        if (hasFrontingChanges) {
          _triggerBroadRescan();
        }
      });
    });
    return 0;
  }

  void setCount(int count) => state = count;

  /// Rescans the last 30 days of sessions. Called after remote fronting_sessions
  /// changes land in Drift so the banner count stays accurate across devices.
  void _triggerBroadRescan() {
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 30));
    final sanitizer = ref.read(frontingSanitizerServiceProvider);
    unawaited(
      sanitizer
          .scan(from: from, to: now)
          .then((issues) {
            state = issues.length;
          })
          .catchError((Object e, StackTrace st) {
            debugPrint('[FrontingRescan] Post-sync rescan failed: $e\n$st');
          }),
    );
  }
}

/// Provides a [FrontingSanitizerService] wired to the repository, validator,
/// planner, and executor layers.
final frontingSanitizerServiceProvider = Provider<FrontingSanitizerService>((
  ref,
) {
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
  if (kReleaseMode) return;

  const padding = Duration(hours: 1);
  final from = sessionStart.subtract(padding);
  final to = (sessionEnd ?? sessionStart).add(padding);

  final sanitizer = ref.read(frontingSanitizerServiceProvider);

  // Fire-and-forget: errors are swallowed to avoid disrupting the UI.
  unawaited(
    sanitizer
        .scan(from: from, to: to)
        .then((issues) {
          ref.read(frontingIssueCountProvider.notifier).setCount(issues.length);
        })
        .catchError((Object e, StackTrace st) {
          debugPrint('[FrontingRescan] Post-edit rescan failed: $e\n$st');
        }),
  );
}
