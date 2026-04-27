/// Codex P1 #3 — `SyncRecordMixin.suppress` tests.
///
/// Pins the suppression contract used by the per-member fronting
/// migration:
///   - [SyncRecordMixin.suppress] short-circuits every `syncRecord*`
///     call so the FFI never runs while the body executes.
///   - Outside `suppress`, the mixin behaves as before.
///   - The flag clears even if the body throws (verified via a probe
///     repository that records every FFI invocation).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';

void main() {
  group('SyncRecordMixin.suppress', () {
    test('short-circuits syncRecordCreate / Update / Delete inside body',
        () async {
      final repo = _ProbeRepository();

      // Sanity: outside `suppress`, the calls flow through the
      // _runWithConfiguredRetry wrapper. We can't actually hit the FFI
      // in tests (no Rust handle), but we can prove the suppression
      // gate by asserting that the per-call entry point ran or didn't.
      // Pre-suppression: a call with a null handle returns silently
      // but never sets `_probeMarker` because we never reach inside
      // the function body. Replace the marker assertion with a counter
      // tracked via the wrapper — see _ProbeRepository.

      expect(SyncRecordMixin.isSuppressed, isFalse, reason: 'pre-suppress');

      await SyncRecordMixin.suppress(() async {
        expect(SyncRecordMixin.isSuppressed, isTrue, reason: 'inside suppress');
        await repo.syncRecordCreate('members', 'm1', {'name': 'A'});
        await repo.syncRecordUpdate('members', 'm1', {'name': 'B'});
        await repo.syncRecordDelete('members', 'm1');
      });

      expect(SyncRecordMixin.isSuppressed, isFalse, reason: 'post-suppress');

      // Probe repo had a non-null handle stub but the mixin's early
      // return prevented it from being read. The probe asserts via
      // `handleAccessCount` how many times the wrapper got past the
      // suppression gate.
      expect(
        repo.handleAccessCount,
        0,
        reason: 'no syncRecord* call should reach the FFI gate while suppressed',
      );
    });

    test('flag clears after body throws', () async {
      expect(SyncRecordMixin.isSuppressed, isFalse);

      Object? caught;
      try {
        await SyncRecordMixin.suppress<void>(() async {
          throw StateError('boom');
        });
      } catch (e) {
        caught = e;
      }

      expect(caught, isA<StateError>());
      expect(
        SyncRecordMixin.isSuppressed,
        isFalse,
        reason: 'finally block must reset the flag even on throw',
      );
    });

    test('nested suppress blocks restore the previous value', () async {
      // Outer suppress → inner suppress → inner exits → outer still
      // suppressed → outer exits → flag clears.
      await SyncRecordMixin.suppress(() async {
        expect(SyncRecordMixin.isSuppressed, isTrue);
        await SyncRecordMixin.suppress(() async {
          expect(SyncRecordMixin.isSuppressed, isTrue);
        });
        expect(
          SyncRecordMixin.isSuppressed,
          isTrue,
          reason: 'inner suppress exit must not clear outer flag',
        );
      });
      expect(SyncRecordMixin.isSuppressed, isFalse);
    });

    test('passes calls through when not suppressed (handle = null branch)',
        () async {
      final repo = _ProbeRepository();
      // Outside suppress: the wrapper calls the syncHandle getter
      // exactly once per record method. With a null handle the wrapper
      // returns early — that's the historical "skip quietly" behavior
      // we keep alongside the new suppression gate.
      await repo.syncRecordCreate('members', 'm1', {'name': 'A'});
      await repo.syncRecordUpdate('members', 'm1', {'name': 'B'});
      await repo.syncRecordDelete('members', 'm1');
      expect(
        repo.handleAccessCount,
        3,
        reason: 'unsuppressed calls reach the FFI gate (and exit early '
            'on null handle)',
      );
    });
  });
}

/// Test double that exposes a counter on the syncHandle getter so we
/// can prove the suppression gate fires before the wrapper starts
/// inspecting the handle.
class _ProbeRepository with SyncRecordMixin {
  int handleAccessCount = 0;

  @override
  ffi.PrismSyncHandle? get syncHandle {
    handleAccessCount++;
    return null;
  }
}
