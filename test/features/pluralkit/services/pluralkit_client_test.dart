/// Unit tests for PluralKitClient — request shape, error mapping, and
/// rate-limit retry behavior.
///
/// These tests inject a mock http.Client and a zero-interval PkRequestQueue
/// so the suite stays fast while still exercising the real queue wiring.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:prism_plurality/features/pluralkit/services/pk_request_queue.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Build a client with a recording mock http.Client and a queue with zero
/// pacing / fast retries for tests.
({
  PluralKitClient client,
  List<http.Request> requests,
}) buildClient(
  Future<http.Response> Function(http.Request req, int callIndex) handler, {
  String token = 'test-token',
  int maxRetries = 3,
}) {
  final requests = <http.Request>[];
  var callIndex = 0;

  final mock = MockClient((req) async {
    requests.add(req);
    final resp = await handler(req, callIndex);
    callIndex++;
    return resp;
  });

  final client = PluralKitClient(
    token: token,
    httpClient: mock,
    queue: PkRequestQueue(
      minInterval: Duration.zero,
      maxRetries: maxRetries,
    ),
  );

  return (client: client, requests: requests);
}

http.Response jsonResponse(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PluralKitClient — request shape', () {
    test('getSystem hits /systems/@me with auth headers', () async {
      final h = buildClient((req, _) async {
        expect(req.url.toString(), 'https://api.pluralkit.me/v2/systems/@me');
        expect(req.method, 'GET');
        expect(req.headers['Authorization'], 'test-token');
        expect(req.headers['User-Agent'], contains('PrismPlurality'));
        return jsonResponse({'id': 'sysabc'});
      });

      final system = await h.client.getSystem();
      expect(system.id, 'sysabc');
      expect(h.requests, hasLength(1));
    });

    test('getMembers parses a list of PKMember', () async {
      final h = buildClient((req, _) async {
        expect(
          req.url.toString(),
          'https://api.pluralkit.me/v2/systems/@me/members',
        );
        return jsonResponse([
          {'id': 'aaaaa', 'uuid': 'u1', 'name': 'Alice'},
          {'id': 'bbbbb', 'uuid': 'u2', 'name': 'Bob'},
        ]);
      });

      final members = await h.client.getMembers();
      expect(members, hasLength(2));
      expect(members[0].name, 'Alice');
      expect(members[1].id, 'bbbbb');
    });

    test('getSwitches forwards before + limit as query params', () async {
      final before = DateTime.utc(2026, 4, 1, 12);
      final h = buildClient((req, _) async {
        expect(req.url.path, '/v2/systems/@me/switches');
        expect(req.url.queryParameters['limit'], '50');
        expect(
          req.url.queryParameters['before'],
          before.toIso8601String(),
        );
        return jsonResponse(<Map<String, dynamic>>[]);
      });

      final switches = await h.client.getSwitches(before: before, limit: 50);
      expect(switches, isEmpty);
    });

    test('createMember POSTs JSON body with Content-Type', () async {
      final h = buildClient((req, _) async {
        expect(req.method, 'POST');
        expect(req.headers['Content-Type'], startsWith('application/json'));
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['name'], 'NewMember');
        return jsonResponse({
          'id': 'xyz12',
          'uuid': 'uuid-xyz12',
          'name': 'NewMember',
        });
      });

      final m = await h.client.createMember({'name': 'NewMember'});
      expect(m.id, 'xyz12');
    });

    test('updateMember PATCHes to /members/{id}', () async {
      final h = buildClient((req, _) async {
        expect(req.method, 'PATCH');
        expect(req.url.path, '/v2/members/abcde');
        return jsonResponse({
          'id': 'abcde',
          'uuid': 'u-abcde',
          'name': 'Renamed',
        });
      });

      final m = await h.client.updateMember('abcde', {'name': 'Renamed'});
      expect(m.name, 'Renamed');
    });

    test('deleteMember sends DELETE and tolerates empty body', () async {
      final h = buildClient((req, _) async {
        expect(req.method, 'DELETE');
        expect(req.url.path, '/v2/members/abcde');
        return http.Response('', 204);
      });

      await h.client.deleteMember('abcde');
      expect(h.requests, hasLength(1));
    });

    test('createSwitch POSTs member IDs and optional timestamp', () async {
      final ts = DateTime.utc(2026, 4, 17, 18);
      final h = buildClient((req, _) async {
        expect(req.method, 'POST');
        expect(req.url.path, '/v2/systems/@me/switches');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['members'], ['aaaaa', 'bbbbb']);
        expect(body['timestamp'], ts.toIso8601String());
        return jsonResponse({
          'id': 'sw-1',
          'timestamp': ts.toIso8601String(),
          'members': ['aaaaa', 'bbbbb'],
        });
      });

      final sw =
          await h.client.createSwitch(['aaaaa', 'bbbbb'], timestamp: ts);
      expect(sw.id, 'sw-1');
    });

    test('createSwitch omits timestamp when not provided', () async {
      final h = buildClient((req, _) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body.containsKey('timestamp'), isFalse);
        return jsonResponse({
          'id': 'sw-2',
          'timestamp': DateTime.now().toIso8601String(),
          'members': <String>[],
        });
      });

      await h.client.createSwitch([]);
    });

    test('updateSwitch PATCHes timestamp at /switches/{id}', () async {
      final ts = DateTime.utc(2026, 4, 17, 19);
      final h = buildClient((req, _) async {
        expect(req.method, 'PATCH');
        expect(req.url.path, '/v2/systems/@me/switches/sw-1');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['timestamp'], ts.toIso8601String());
        expect(body.containsKey('members'), isFalse,
            reason: 'updateSwitch must not send members — PK rejects it');
        return jsonResponse({
          'id': 'sw-1',
          'timestamp': ts.toIso8601String(),
          'members': <String>[],
        });
      });

      final sw = await h.client.updateSwitch('sw-1', timestamp: ts);
      expect(sw.id, 'sw-1');
    });

    test('updateSwitchMembers PATCHes to /switches/{id}/members', () async {
      final h = buildClient((req, _) async {
        expect(req.method, 'PATCH');
        expect(req.url.path, '/v2/systems/@me/switches/sw-1/members');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['members'], ['aaaaa']);
        return jsonResponse({
          'id': 'sw-1',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'members': ['aaaaa'],
        });
      });

      await h.client.updateSwitchMembers('sw-1', ['aaaaa']);
    });

    test('deleteSwitch sends DELETE to /switches/{id}', () async {
      final h = buildClient((req, _) async {
        expect(req.method, 'DELETE');
        expect(req.url.path, '/v2/systems/@me/switches/sw-1');
        return http.Response('', 204);
      });

      await h.client.deleteSwitch('sw-1');
      expect(h.requests, hasLength(1));
    });

    test('downloadBytes returns response body bytes', () async {
      final bytes = [1, 2, 3, 4, 5];
      final h = buildClient((req, _) async {
        expect(req.url.toString(), 'https://cdn.example/foo.png');
        return http.Response.bytes(bytes, 200);
      });

      final out = await h.client.downloadBytes('https://cdn.example/foo.png');
      expect(out, bytes);
    });
  });

  group('PluralKitClient — error mapping', () {
    test('401 throws PluralKitAuthError', () async {
      final h = buildClient((_, __) async => http.Response('nope', 401));

      await expectLater(
        h.client.getSystem(),
        throwsA(isA<PluralKitAuthError>()),
      );
    });

    test('500 throws PluralKitApiError with status + body', () async {
      final h = buildClient(
        (_, __) async => http.Response('kaboom', 500),
        maxRetries: 0,
      );

      try {
        await h.client.getSystem();
        fail('expected PluralKitApiError');
      } on PluralKitApiError catch (e) {
        expect(e.statusCode, 500);
        expect(e.message, contains('kaboom'));
        expect(e, isNot(isA<PluralKitRateLimitError>()));
        expect(e, isNot(isA<PluralKitAuthError>()));
      }
    });

    test('downloadBytes maps non-200 to PluralKitApiError', () async {
      final h = buildClient(
        (_, __) async => http.Response('missing', 404),
        maxRetries: 0,
      );

      await expectLater(
        h.client.downloadBytes('https://cdn.example/missing.png'),
        throwsA(isA<PluralKitApiError>()
            .having((e) => e.statusCode, 'statusCode', 404)),
      );
    });
  });

  group('PluralKitClient — rate limit handling', () {
    test('retries on 429, honors Retry-After seconds, eventually succeeds',
        () async {
      final h = buildClient((req, call) async {
        if (call == 0) {
          return http.Response(
            'slow down',
            429,
            headers: {'retry-after': '0'},
          );
        }
        return jsonResponse({'id': 'sys'});
      });

      final system = await h.client.getSystem();
      expect(system.id, 'sys');
      expect(h.requests, hasLength(2),
          reason: 'should retry once after the 429');
    });

    test('retries on 429 honoring X-RateLimit-Reset epoch', () async {
      final pastEpoch =
          (DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000) - 1;
      final h = buildClient((req, call) async {
        if (call == 0) {
          return http.Response(
            'slow down',
            429,
            headers: {'x-ratelimit-reset': pastEpoch.toString()},
          );
        }
        return jsonResponse({'id': 'sys'});
      });

      final system = await h.client.getSystem();
      expect(system.id, 'sys');
      expect(h.requests, hasLength(2));
    });

    test('future X-RateLimit-Reset is parsed as a positive delay', () async {
      // Use a future epoch large enough to be unambiguously positive after
      // the parser subtracts "now", but small enough that the test doesn't
      // actually sleep that long — we use maxRetries: 0 so the error is
      // thrown without retrying.
      final futureEpoch =
          (DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000) + 5;
      final h = buildClient(
        (_, __) async => http.Response(
          '',
          429,
          headers: {'x-ratelimit-reset': futureEpoch.toString()},
        ),
        maxRetries: 0,
      );

      try {
        await h.client.getSystem();
        fail('expected PluralKitRateLimitError');
      } on PluralKitRateLimitError catch (e) {
        expect(e.retryAfter, isNotNull,
            reason: 'future X-RateLimit-Reset should parse to a Duration');
        expect(e.retryAfter!.inSeconds, inInclusiveRange(1, 10),
            reason:
                'parsed delay should be the delta from now (~5s), not the raw epoch');
      }
    });

    test('gives up after max retries of persistent 429', () async {
      final h = buildClient(
        (_, __) async => http.Response(
          'nope',
          429,
          headers: {'retry-after': '0'},
        ),
        maxRetries: 2,
      );

      await expectLater(
        h.client.getSystem(),
        throwsA(isA<PluralKitRateLimitError>()),
      );
      // 1 initial attempt + 2 retries = 3 total requests.
      expect(h.requests, hasLength(3));
    });

    test('PluralKitRateLimitError carries parsed Retry-After', () async {
      final h = buildClient(
        (_, __) async => http.Response(
          '',
          429,
          headers: {'retry-after': '7'},
        ),
        maxRetries: 0,
      );

      try {
        await h.client.getSystem();
        fail('expected PluralKitRateLimitError');
      } on PluralKitRateLimitError catch (e) {
        expect(e.retryAfter, const Duration(seconds: 7));
      }
    });

    test('malformed Retry-After falls through to exponential backoff',
        () async {
      final h = buildClient(
        (_, __) async => http.Response(
          '',
          429,
          headers: {'retry-after': 'not-a-number'},
        ),
        maxRetries: 0,
      );

      try {
        await h.client.getSystem();
        fail('expected PluralKitRateLimitError');
      } on PluralKitRateLimitError catch (e) {
        expect(e.retryAfter, isNull);
      }
    });

    test('back-to-back calls are paced by the client-owned queue', () async {
      // Regression guard: if someone unwraps a client method from
      // _queue.enqueue(...), this test catches it. We inject a queue with a
      // short but non-zero minInterval and measure elapsed wall time.
      final requests = <http.Request>[];
      final mock = MockClient((req) async {
        requests.add(req);
        return jsonResponse({'id': 'sys'});
      });

      final client = PluralKitClient(
        token: 't',
        httpClient: mock,
        queue: PkRequestQueue(
          minInterval: const Duration(milliseconds: 100),
          maxRetries: 0,
        ),
      );

      final sw = Stopwatch()..start();
      await client.getSystem();
      await client.getSystem();
      sw.stop();

      expect(requests, hasLength(2));
      // Second call must wait for the pacing window. Lower threshold
      // accounts for timer imprecision; upper bound catches regressions
      // where pacing accidentally stacks (e.g. 2x).
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(80),
          reason: 'second call should be paced ~100ms after the first');
      expect(sw.elapsedMilliseconds, lessThan(500),
          reason:
              'pacing should be ~100ms, not stacked or mis-applied per call');
    });

    test('retries cover write endpoints (createMember)', () async {
      final h = buildClient((req, call) async {
        if (call == 0) {
          return http.Response(
            'slow down',
            429,
            headers: {'retry-after': '0'},
          );
        }
        return jsonResponse({
          'id': 'new01',
          'uuid': 'uuid-new01',
          'name': 'Created',
        });
      });

      final m = await h.client.createMember({'name': 'Created'});
      expect(m.id, 'new01');
      expect(h.requests, hasLength(2));
    });
  });
}
