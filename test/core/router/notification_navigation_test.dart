import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/router/notification_navigation.dart';

void main() {
  test(
    'allowlists scheduled, immediate, legacy delayed and fronting targets',
    () {
      for (final payload in [
        'prism:reminder:scheduled:synthetic-id',
        'prism:reminder:immediate:synthetic-id',
        'prism:reminder:front-change-delayed:synthetic-id:["name","body:private",1,null]',
      ]) {
        expect(NotificationIntent.parse(payload)?.reminderId, 'synthetic-id');
      }
      expect(NotificationIntent.parse('prism:fronting:v1')?.isFronting, isTrue);
    },
  );

  test(
    'legacy delayed envelope uses reminder ID, never fingerprint member ID',
    () {
      final intent = NotificationIntent.parse(
        'prism:reminder:front-change-delayed:reminder-id:'
        '["Private synthetic name","Private synthetic body",2,"different-member-id"]',
      );
      expect(intent?.reminderId, 'reminder-id');
      expect(intent, const NotificationIntent.reminder('reminder-id'));
      expect(intent?.toString(), isNot(contains('Private synthetic')));
      expect(intent?.toString(), isNot(contains('different-member-id')));
      // The producer has an explicit envelope ID; a bare private fingerprint
      // cannot authorize entity selection or substitute a target member ID.
      expect(NotificationIntent.parse('["name","body",2,"member-id"]'), isNull);
    },
  );

  test(
    'rejects malformed, arbitrary routes, versions, IDs and oversized data',
    () {
      for (final payload in <String?>[
        null,
        '',
        '/',
        '/reminders',
        'prism:fronting:v2',
        'prism:reminder:unknown:id',
        'prism:reminder:scheduled:',
        'prism:reminder:scheduled:../private',
        'prism:reminder:scheduled:id?route=/members',
        'prism:reminder:scheduled:id\n',
        'prism:reminder:front-change-delayed:id:not-json',
        'prism:reminder:front-change-delayed:id:{}',
        'prism:reminder:front-change-delayed:id:["a","b",{},null]',
        'prism:reminder:front-change-delayed:id:["a","b",1,null,"extra"]',
        'prism:reminder:scheduled:${'a' * 129}',
        'prism:reminder:front-change-delayed:id:["${'a' * 8192}","b",1,null]',
      ]) {
        expect(NotificationIntent.parse(payload), isNull);
      }
    },
  );

  test('latest distinct target wins and cannot be claimed twice', () {
    final pending = PendingNotificationIntents();
    expect(pending.receive('prism:reminder:scheduled:first'), isTrue);
    final first = pending.claim()!;
    expect(pending.claim(), isNull);
    expect(pending.receive('prism:reminder:scheduled:first'), isFalse);
    expect(pending.receive('prism:reminder:scheduled:second'), isTrue);
    expect(pending.complete(first), isFalse);
    final second = pending.claim()!;
    expect(second.intent.reminderId, 'second');
    expect(pending.complete(second), isTrue);
    expect(pending.complete(second), isFalse);
    expect(pending.pending, isNull);
    // A later occurrence of an identical reminder is not permanently deduped.
    expect(pending.receive('prism:reminder:scheduled:second'), isTrue);
  });

  test('relock releases; reset invalidates even an identical new target', () {
    final pending = PendingNotificationIntents();
    pending.receive('prism:fronting:v1');
    final beforeRelock = pending.claim()!;
    pending.release(beforeRelock);
    final afterRelock = pending.claim()!;
    expect(pending.complete(beforeRelock), isFalse);
    pending.clear();
    pending.receive('prism:fronting:v1');
    expect(pending.complete(afterRelock), isFalse);
    final afterReset = pending.claim()!;
    expect(pending.complete(afterReset), isTrue);
  });

  test('unknown payload does not displace the pending protected target', () {
    final pending = PendingNotificationIntents();
    pending.receive('prism:reminder:scheduled:synthetic-id');
    expect(pending.receive('/members'), isFalse);
    expect(pending.claim()!.intent.reminderId, 'synthetic-id');
  });
}
