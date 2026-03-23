import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';

void main() {
  test('syncStatusAfterCompleted keeps last successful sync on sync error', () {
    final previousSyncAt = DateTime.utc(2026, 3, 18, 12, 0, 0);
    final completedAt = DateTime.utc(2026, 3, 18, 12, 5, 0);

    final next = syncStatusAfterCompleted(
      previous: SyncStatus(
        isSyncing: true,
        lastSyncAt: previousSyncAt,
        pendingOps: 4,
      ),
      rawResultError: 'push rejected by relay',
      pendingOps: 2,
      hasQuarantinedItems: false,
      completedAt: completedAt,
    );

    expect(next.isSyncing, isFalse);
    expect(next.lastSyncAt, previousSyncAt);
    expect(next.lastError, 'push rejected by relay');
    expect(next.pendingOps, 2);
  });

  test('syncStatusAfterCompleted records a new sync time on success', () {
    final completedAt = DateTime.utc(2026, 3, 18, 12, 5, 0);

    final next = syncStatusAfterCompleted(
      previous: const SyncStatus(isSyncing: true, lastError: 'old error'),
      rawResultError: null,
      pendingOps: 0,
      hasQuarantinedItems: true,
      completedAt: completedAt,
    );

    expect(next.isSyncing, isFalse);
    expect(next.lastSyncAt, completedAt);
    expect(next.lastError, isNull);
    expect(next.hasQuarantinedItems, isTrue);
  });

  test('syncStatusAfterCompleted treats empty-string error as success', () {
    final completedAt = DateTime.utc(2026, 3, 18, 12, 10, 0);

    final next = syncStatusAfterCompleted(
      previous: const SyncStatus(isSyncing: true),
      rawResultError: '',
      pendingOps: 0,
      hasQuarantinedItems: false,
      completedAt: completedAt,
    );

    expect(next.isSyncing, isFalse);
    expect(next.lastSyncAt, completedAt);
    expect(next.lastError, isNull);
  });
}
