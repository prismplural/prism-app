import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_provider.dart';

/// Debounce interval for the ticker. Untransacted bulk-write loops
/// (~1ms per insert) coalesce into one downstream emission per
/// ~debounce-window batch; transactional bulk imports (PK initial,
/// SP importer, sanitizer rewrites) coalesce into one emission via
/// Drift's own per-transaction notification.
const Duration _frontingTickerDebounce = Duration(milliseconds: 200);

/// Fires on every write to `fronting_sessions`.
///
/// Why this exists: FutureProviders (analytics, member stats, member
/// fronting counts) don't subscribe to Drift's stream queries the way
/// StreamProviders do, so they don't auto-rebuild when their backing
/// table changes. Pre-this-provider, every mutation site had to
/// remember to invalidate every dependent FutureProvider — a perpetual
/// whack-a-mole. Subscribing each FutureProvider to this ticker lets
/// Drift's existing table-update notification carry the rebuild signal
/// for free.
///
/// Bulk-import behavior:
///   * **Transactional bulk** (PK initial import, SP importer,
///     sanitizer batch): Drift emits one update notification per
///     transaction. We see one tick.
///   * **Untransacted loop** (worst-case path): each insert emits its
///     own notification. The 200ms debounce coalesces a burst into a
///     single trailing emission. A 1000-row loop running ~1ms per
///     insert produces ~5–6 emissions instead of 1000.
///
/// Lifecycle: NOT autoDispose. Analytics screens unmount/remount
/// during navigation; the ticker must keep running so the next mount
/// reads a fresh value rather than a stale cached one.
final frontingTableTickerProvider = StreamProvider<int>((ref) async* {
  final db = ref.watch(databaseProvider);
  var counter = 0;
  // Emit immediately so consumers don't block on first listen.
  yield counter;

  StreamSubscription<Set<TableUpdate>>? sub;
  Timer? debounceTimer;
  final controller = StreamController<int>();
  ref.onDispose(() {
    debounceTimer?.cancel();
    sub?.cancel();
    controller.close();
  });

  sub = db
      .tableUpdates(
        TableUpdateQuery.onTable(db.frontingSessions),
      )
      .listen((_) {
    debounceTimer?.cancel();
    debounceTimer = Timer(_frontingTickerDebounce, () {
      if (!controller.isClosed) controller.add(++counter);
    });
  });

  yield* controller.stream;
});
