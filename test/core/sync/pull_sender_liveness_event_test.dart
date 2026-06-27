import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_event_loop.dart';

/// The one-way-sync-liveness events (`PullSenderStalled` / `PullSenderRecovered`)
/// arrive from Rust as additive JSON over the sync-event stream. These assert the
/// Dart getters decode them so support diagnostics can distinguish "a peer's
/// inbound changes aren't applying" from ordinary sync success.
void main() {
  group('PullSenderStalled / PullSenderRecovered SyncEvent getters', () {
    test('decodes a PullSenderStalled payload', () {
      final e = SyncEvent.fromJson({
        'type': 'PullSenderStalled',
        'sender_device_id': 'device-bbb',
        'reason': 'sender_unresolved',
        'live_stall_count': 3,
        'quarantined_batch_count': 1,
        'last_error': 'no signed registry artifact available',
      });
      expect(e.isPullSenderStalled, isTrue);
      expect(e.isPullSenderRecovered, isFalse);
      expect(e.pullSenderId, 'device-bbb');
      expect(e.pullSenderReason, 'sender_unresolved');
      expect(e.pullSenderLiveStallCount, 3);
      expect(e.pullSenderQuarantinedBatchCount, 1);
    });

    test('decodes a PullSenderRecovered payload', () {
      final e = SyncEvent.fromJson({
        'type': 'PullSenderRecovered',
        'sender_device_id': 'device-bbb',
        'reason': 'stale_key_generation',
        'replayed_batch_count': 2,
      });
      expect(e.isPullSenderRecovered, isTrue);
      expect(e.isPullSenderStalled, isFalse);
      expect(e.pullSenderId, 'device-bbb');
      expect(e.pullSenderReason, 'stale_key_generation');
      expect(e.pullSenderReplayedBatchCount, 2);
    });

    test('getters default safely for unrelated / malformed events', () {
      final e = SyncEvent.fromJson({'type': 'SyncStarted'});
      expect(e.isPullSenderStalled, isFalse);
      expect(e.isPullSenderRecovered, isFalse);
      expect(e.pullSenderId, '');
      expect(e.pullSenderReason, '');
      expect(e.pullSenderLiveStallCount, 0);
      expect(e.pullSenderQuarantinedBatchCount, 0);
      expect(e.pullSenderReplayedBatchCount, 0);
    });
  });

  group('debug-log summary lines', () {
    SyncEventLogEntry entry(Map<String, dynamic> json) =>
        SyncEventLogEntry(timestamp: DateTime(2026), event: SyncEvent.fromJson(json));

    test('PullSenderStalled summary names the peer, reason, and counts', () {
      final summary = entry({
        'type': 'PullSenderStalled',
        'sender_device_id': 'device-bbb',
        'reason': 'sender_unresolved',
        'live_stall_count': 3,
        'quarantined_batch_count': 1,
        'last_error': 'x',
      }).summary;
      expect(summary, contains('device-bbb'));
      expect(summary, contains('sender_unresolved'));
      expect(summary, contains('3 live stalls'));
      expect(summary, contains('1 quarantined'));
    });

    test('PullSenderRecovered summary names the peer and replay count', () {
      final summary = entry({
        'type': 'PullSenderRecovered',
        'sender_device_id': 'device-bbb',
        'reason': 'stale_key_generation',
        'replayed_batch_count': 2,
      }).summary;
      expect(summary, contains('recovered'));
      expect(summary, contains('device-bbb'));
      expect(summary, contains('replayed 2'));
    });
  });
}
