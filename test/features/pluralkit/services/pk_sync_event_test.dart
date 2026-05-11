import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/features/pluralkit/services/pk_sync_event.dart';

void main() {
  group('PkTokenSet', () {
    test('toJson includes kind, system_name, system_id', () {
      const event = PkTokenSet(systemName: 'Foo', systemId: 'abc');
      expect(event.toJson(), {
        'kind': 'pkTokenSet',
        'system_name': 'Foo',
        'system_id': 'abc',
      });
    });

    test('summary names the system', () {
      const event = PkTokenSet(systemName: 'Foo', systemId: 'abc');
      expect(event.summary, 'PluralKit token set (Foo)');
    });

    test('isError is false', () {
      const event = PkTokenSet(systemName: 'Foo', systemId: 'abc');
      expect(event.isError, isFalse);
    });
  });

  group('PkTokenCleared', () {
    test('toJson contains only kind', () {
      expect(const PkTokenCleared().toJson(), {'kind': 'pkTokenCleared'});
    });

    test('summary', () {
      expect(const PkTokenCleared().summary, 'PluralKit token cleared');
    });

    test('isError is false', () {
      expect(const PkTokenCleared().isError, isFalse);
    });
  });

  group('PkTokenAuthFailed', () {
    test('toJson includes error_kind: auth', () {
      expect(const PkTokenAuthFailed().toJson(), {
        'kind': 'pkTokenAuthFailed',
        'error_kind': 'auth',
      });
    });

    test('isError is true', () {
      expect(const PkTokenAuthFailed().isError, isTrue);
    });

    test('summary', () {
      expect(
        const PkTokenAuthFailed().summary,
        'PluralKit token rejected (auth)',
      );
    });
  });

  group('PkSyncStarted', () {
    test('toJson includes trigger, direction, mode', () {
      const event = PkSyncStarted(
        trigger: 'manual',
        direction: 'pull',
        mode: 'live',
      );
      expect(event.toJson(), {
        'kind': 'pkSyncStarted',
        'trigger': 'manual',
        'direction': 'pull',
        'mode': 'live',
      });
    });

    test('summary lists trigger, direction, mode', () {
      const event = PkSyncStarted(
        trigger: 'manual',
        direction: 'pull',
        mode: 'live',
      );
      expect(event.summary, 'Sync started (manual, pull, live)');
    });
  });

  group('PkSyncCompleted', () {
    test('toJson omits error when null', () {
      const event = PkSyncCompleted(
        durationMs: 1234,
        pulled: 5,
        pushed: 0,
      );
      expect(event.toJson(), {
        'kind': 'pkSyncCompleted',
        'duration_ms': 1234,
        'pulled': 5,
        'pushed': 0,
      });
    });

    test('summary on success', () {
      const event = PkSyncCompleted(durationMs: 1234, pulled: 5, pushed: 0);
      expect(event.summary, 'Sync completed in 1234ms (pulled 5, pushed 0)');
    });

    test('toJson includes error when present', () {
      const event = PkSyncCompleted(
        durationMs: 1234,
        pulled: 5,
        pushed: 0,
        error: 'boom',
      );
      expect(event.toJson()['error'], 'boom');
    });

    test('isError is true with non-empty error', () {
      const event = PkSyncCompleted(
        durationMs: 1234,
        pulled: 5,
        pushed: 0,
        error: 'boom',
      );
      expect(event.isError, isTrue);
    });

    test('isError is false without error', () {
      const event = PkSyncCompleted(durationMs: 1234, pulled: 5, pushed: 0);
      expect(event.isError, isFalse);
    });

    test('summary on failure', () {
      const event = PkSyncCompleted(
        durationMs: 1234,
        pulled: 5,
        pushed: 0,
        error: 'boom',
      );
      expect(event.summary, 'Sync failed: boom');
    });
  });

  group('PkMembersImported', () {
    test('toJson', () {
      expect(const PkMembersImported(count: 12).toJson(), {
        'kind': 'pkMembersImported',
        'count': 12,
      });
    });

    test('summary', () {
      expect(const PkMembersImported(count: 12).summary, 'Imported 12 members');
    });
  });

  group('PkSyncPullCompleted', () {
    test('toJson', () {
      const event = PkSyncPullCompleted(
        pages: 3,
        fetched: 297,
        applied: 12,
        durationMs: 5000,
      );
      expect(event.toJson(), {
        'kind': 'pkSyncPullCompleted',
        'pages': 3,
        'fetched': 297,
        'applied': 12,
        'duration_ms': 5000,
      });
    });

    test('summary', () {
      const event = PkSyncPullCompleted(
        pages: 3,
        fetched: 297,
        applied: 12,
        durationMs: 5000,
      );
      expect(
        event.summary,
        'Pull completed: 297 fetched, 12 applied (3 pages, 5000ms)',
      );
    });
  });

  group('PkSwitchPushed', () {
    test('toJson', () {
      expect(const PkSwitchPushed(pushed: 2, deleted: 0).toJson(), {
        'kind': 'pkSwitchPushed',
        'pushed': 2,
        'deleted': 0,
      });
    });

    test('summary with only pushes', () {
      expect(
        const PkSwitchPushed(pushed: 2, deleted: 0).summary,
        'Pushed 2 switches',
      );
    });

    test('summary with only deletions', () {
      expect(
        const PkSwitchPushed(pushed: 0, deleted: 3).summary,
        'Pushed 3 switch deletions',
      );
    });

    test('summary with both', () {
      expect(
        const PkSwitchPushed(pushed: 2, deleted: 3).summary,
        'Pushed 2 switches, 3 deletions',
      );
    });
  });

  group('PkLiveFronterApplied', () {
    test('toJson', () {
      expect(const PkLiveFronterApplied(memberCount: 1).toJson(), {
        'kind': 'pkLiveFronterApplied',
        'member_count': 1,
      });
    });

    test('summary', () {
      expect(
        const PkLiveFronterApplied(memberCount: 1).summary,
        'Live fronter updated (1 member)',
      );
    });
  });

  group('PkLiveFronterSkipped', () {
    test('toJson', () {
      expect(const PkLiveFronterSkipped(reason: 'unmapped').toJson(), {
        'kind': 'pkLiveFronterSkipped',
        'reason': 'unmapped',
      });
    });

    test('summary', () {
      expect(
        const PkLiveFronterSkipped(reason: 'unmapped').summary,
        'Live fronter skipped: unmapped',
      );
    });
  });

  group('PkMappingDecisionApplied', () {
    test('toJson', () {
      expect(
        const PkMappingDecisionApplied(
          decisionId: 'link:abc',
          decisionKind: 'link',
        ).toJson(),
        {
          'kind': 'pkMappingDecisionApplied',
          'decision_id': 'link:abc',
          'decision_kind': 'link',
        },
      );
    });

    test('summary', () {
      expect(
        const PkMappingDecisionApplied(
          decisionId: 'link:abc',
          decisionKind: 'link',
        ).summary,
        'Mapping decision applied: link (link:abc)',
      );
    });
  });

  group('PkMappingDecisionFailed', () {
    test('toJson', () {
      expect(
        const PkMappingDecisionFailed(
          decisionId: 'push:def',
          decisionKind: 'push',
          error: 'stale link',
        ).toJson(),
        {
          'kind': 'pkMappingDecisionFailed',
          'decision_id': 'push:def',
          'decision_kind': 'push',
          'error': 'stale link',
        },
      );
    });

    test('isError is true', () {
      expect(
        const PkMappingDecisionFailed(
          decisionId: 'push:def',
          decisionKind: 'push',
          error: 'stale link',
        ).isError,
        isTrue,
      );
    });

    test('summary', () {
      expect(
        const PkMappingDecisionFailed(
          decisionId: 'push:def',
          decisionKind: 'push',
          error: 'stale link',
        ).summary,
        'Mapping decision failed: push (push:def) — stale link',
      );
    });
  });

  group('PkRateLimitHit', () {
    test('toJson', () {
      expect(
        const PkRateLimitHit(attempt: 2, backoffSeconds: 4).toJson(),
        {
          'kind': 'pkRateLimitHit',
          'attempt': 2,
          'backoff_secs': 4,
        },
      );
    });

    test('summary', () {
      expect(
        const PkRateLimitHit(attempt: 2, backoffSeconds: 4).summary,
        'Rate limit hit (attempt 2, backoff 4s)',
      );
    });

    test('isError is true', () {
      expect(
        const PkRateLimitHit(attempt: 2, backoffSeconds: 4).isError,
        isTrue,
      );
    });
  });

  group('PkRequestFailed', () {
    test('toJson', () {
      expect(
        const PkRequestFailed(
          stage: 'getMembers',
          errorKind: 'network',
          message: 'No internet',
        ).toJson(),
        {
          'kind': 'pkRequestFailed',
          'stage': 'getMembers',
          'error_kind': 'network',
          'message': 'No internet',
        },
      );
    });

    test('summary', () {
      expect(
        const PkRequestFailed(
          stage: 'getMembers',
          errorKind: 'network',
          message: 'No internet',
        ).summary,
        'Request failed: getMembers — No internet',
      );
    });

    test('isError is true', () {
      expect(
        const PkRequestFailed(
          stage: 'getMembers',
          errorKind: 'network',
          message: 'No internet',
        ).isError,
        isTrue,
      );
    });
  });

  group('PkAutoPollTick', () {
    test('toJson ok omits reason and error', () {
      expect(const PkAutoPollTick(outcome: 'ok').toJson(), {
        'kind': 'pkAutoPollTick',
        'outcome': 'ok',
      });
    });

    test('summary ok', () {
      expect(const PkAutoPollTick(outcome: 'ok').summary, 'Auto-poll tick: ok');
    });

    test('isError is false for ok', () {
      expect(const PkAutoPollTick(outcome: 'ok').isError, isFalse);
    });

    test('toJson failed includes error', () {
      expect(
        const PkAutoPollTick(outcome: 'failed', error: 'timeout').toJson()['error'],
        'timeout',
      );
    });

    test('summary failed', () {
      expect(
        const PkAutoPollTick(outcome: 'failed', error: 'timeout').summary,
        'Auto-poll tick failed: timeout',
      );
    });

    test('isError is true for failed', () {
      expect(
        const PkAutoPollTick(outcome: 'failed', error: 'timeout').isError,
        isTrue,
      );
    });

    test('toJson skipped includes reason', () {
      expect(
        const PkAutoPollTick(outcome: 'skipped', reason: 'recent_push')
            .toJson()['reason'],
        'recent_push',
      );
    });

    test('summary skipped', () {
      expect(
        const PkAutoPollTick(outcome: 'skipped', reason: 'recent_push').summary,
        'Auto-poll tick skipped: recent_push',
      );
    });

    test('isError is false for skipped (routine)', () {
      expect(
        const PkAutoPollTick(outcome: 'skipped', reason: 'recent_push').isError,
        isFalse,
      );
    });
  });

  group('PkBackgroundSyncTick', () {
    test('toJson', () {
      expect(
        const PkBackgroundSyncTick(taskName: 'com.prism.backgroundSync')
            .toJson(),
        {
          'kind': 'pkBackgroundSyncTick',
          'task_name': 'com.prism.backgroundSync',
        },
      );
    });

    test('summary', () {
      expect(
        const PkBackgroundSyncTick(taskName: 'com.prism.backgroundSync').summary,
        'Background sync tick: com.prism.backgroundSync',
      );
    });
  });

  group('PkSyncEvent.redact', () {
    test('replaces token occurrences', () {
      expect(
        PkSyncEvent.redact('Failed: abc123tok', 'abc123tok'),
        'Failed: [REDACTED]',
      );
    });

    test('returns message unchanged when token is null', () {
      expect(
        PkSyncEvent.redact('Failed: abc123tok', null),
        'Failed: abc123tok',
      );
    });

    test('returns message unchanged when token is empty', () {
      expect(
        PkSyncEvent.redact('Failed: abc123tok', ''),
        'Failed: abc123tok',
      );
    });

    test('returns message unchanged when token is not present', () {
      expect(
        PkSyncEvent.redact('No token in here', 'abc123tok'),
        'No token in here',
      );
    });
  });
}
