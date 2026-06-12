// Unit tests for PluralKitClient — request shape, error mapping, and
// rate-limit retry behavior.
//
// These tests inject a mock http.Client and a zero-interval PkRequestQueue
// so the suite stays fast while still exercising the real queue wiring.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
({PluralKitClient client, List<http.Request> requests}) buildClient(
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
    queue: PkRequestQueue(minInterval: Duration.zero, maxRetries: maxRetries),
  );

  return (client: client, requests: requests);
}

http.Response jsonResponse(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

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
        expect(req.headers['User-Agent'], startsWith('PrismPlural/'));
        expect(req.headers['User-Agent'], contains('prismplural.com/about'));
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

    test('getMember fetches one member by short ID', () async {
      final h = buildClient((req, _) async {
        expect(req.method, 'GET');
        expect(req.url.path, '/v2/members/abcde');
        return jsonResponse({
          'id': 'abcde',
          'uuid': 'uuid-abcde',
          'name': 'Alice',
          'display_name': 'Alice Display',
        });
      });

      final member = await h.client.getMember(' abcde ');
      expect(member.id, 'abcde');
      expect(member.uuid, 'uuid-abcde');
      expect(member.displayName, 'Alice Display');
      expect(h.requests, hasLength(1));
    });

    test('getSwitches forwards before + limit as query params', () async {
      final before = DateTime.utc(2026, 4, 1, 12);
      final h = buildClient((req, _) async {
        expect(req.url.path, '/v2/systems/@me/switches');
        expect(req.url.queryParameters['limit'], '50');
        expect(req.url.queryParameters['before'], before.toIso8601String());
        return jsonResponse(<Map<String, dynamic>>[]);
      });

      final switches = await h.client.getSwitches(before: before, limit: 50);
      expect(switches, isEmpty);
    });

    test(
      'getSwitch GETs /switches/{ref} and normalizes member objects to '
      'short ids',
      () async {
        // PK inlines full member objects on this endpoint; PKSwitch.fromJson
        // must normalize to short ids. Used by the deletion pusher (2026-06
        // PK audit H2) for the PK-authoritative co-fronter snapshot.
        const switchUuid = 'e6f1b9c2-0000-4000-8000-000000000001';
        final h = buildClient((req, _) async {
          expect(req.method, 'GET');
          expect(req.url.path, '/v2/systems/@me/switches/$switchUuid');
          expect(req.headers['Authorization'], 'test-token');
          return jsonResponse({
            'id': switchUuid,
            'timestamp': '2026-04-01T12:00:00.000Z',
            'members': [
              {'id': 'aaaaa', 'uuid': 'u1', 'name': 'Alice'},
              {'id': 'bbbbb', 'uuid': 'u2', 'name': 'Bob'},
            ],
          });
        });

        final sw = await h.client.getSwitch(' $switchUuid ');
        expect(sw.id, switchUuid);
        expect(sw.members, ['aaaaa', 'bbbbb']);
        expect(h.requests, hasLength(1));
      },
    );

    test('getSwitch is idempotent — retries a transient 5xx', () async {
      // getSwitch routes through _get, inheriting `idempotent: true` on the
      // request queue: a single Fly/Caddy blip must not abort a deletion
      // push pass.
      final h = buildClient((req, call) async {
        if (call == 0) return http.Response('blip', 502);
        return jsonResponse({
          'id': 'sw-1',
          'timestamp': '2026-04-01T12:00:00.000Z',
          'members': <String>[],
        });
      });

      final sw = await h.client.getSwitch('sw-1');
      expect(sw.id, 'sw-1');
      expect(h.requests, hasLength(2), reason: 'one retry after the 502');
    });

    test('getSwitch maps a deleted switch to 404 with code 20007', () async {
      final h = buildClient(
        (_, _) async => http.Response(
          '{"message":"Switch not found.","code":20007}',
          404,
          headers: {'content-type': 'application/json'},
        ),
        maxRetries: 0,
      );

      try {
        await h.client.getSwitch('sw-gone');
        fail('expected PluralKitApiError');
      } on PluralKitApiError catch (e) {
        expect(e.statusCode, 404);
        expect(e.code, 20007);
      }
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

      final sw = await h.client.createSwitch(['aaaaa', 'bbbbb'], timestamp: ts);
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
        expect(
          body.containsKey('members'),
          isFalse,
          reason: 'updateSwitch must not send members — PK rejects it',
        );
        return jsonResponse({
          'id': 'sw-1',
          'timestamp': ts.toIso8601String(),
          'members': <String>[],
        });
      });

      final sw = await h.client.updateSwitch('sw-1', timestamp: ts);
      expect(sw.id, 'sw-1');
    });

    test(
      'updateSwitchMembers PATCHes a bare JSON array to /switches/{id}/members',
      () async {
        // PK requires a bare array body (["id1","id2"]) — NOT {"members":[...]}.
        // The object shape 400s on the live API. This test pins the array
        // contract (regression guard for audit finding C2).
        final h = buildClient((req, _) async {
          expect(req.method, 'PATCH');
          expect(req.url.path, '/v2/systems/@me/switches/sw-1/members');
          final body = jsonDecode(req.body);
          expect(body, isA<List<dynamic>>());
          expect(body, ['aaaaa', 'bbbbb']);
          return jsonResponse({
            'id': 'sw-1',
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'members': ['aaaaa', 'bbbbb'],
          });
        });

        final sw = await h.client.updateSwitchMembers('sw-1', [
          'aaaaa',
          'bbbbb',
        ]);
        expect(sw.id, 'sw-1');
      },
    );

    test('updateSwitchMembers surfaces a 400 40004 as PluralKitApiError', () async {
      // Re-PATCHing the identical member list returns 400 with a JSON body
      // embedding code 40004. The sync service matches `40004` against
      // PluralKitApiError.message, so message must remain the raw body.
      final h = buildClient(
        (_, _) async => http.Response(
          '{"message":"400: Bad Request","code":40004}',
          400,
          headers: {'content-type': 'application/json'},
        ),
        maxRetries: 0,
      );

      try {
        await h.client.updateSwitchMembers('sw-1', ['aaaaa']);
        fail('expected PluralKitApiError');
      } on PluralKitApiError catch (e) {
        expect(e.statusCode, 400);
        expect(e.message, contains('40004'));
        expect(e.code, 40004);
      }
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
      final h = buildClient((_, _) async => http.Response('nope', 401));

      await expectLater(
        h.client.getSystem(),
        throwsA(isA<PluralKitAuthError>()),
      );
    });

    test('500 throws PluralKitApiError with status + body', () async {
      final h = buildClient(
        (_, _) async => http.Response('kaboom', 500),
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

    test('400 with JSON body populates PluralKitApiError.code', () async {
      final h = buildClient(
        (_, _) async => http.Response(
          '{"message":"400: Bad Request","code":40005}',
          400,
          headers: {'content-type': 'application/json'},
        ),
        maxRetries: 0,
      );

      try {
        await h.client.createSwitch(['aaaaa']);
        fail('expected PluralKitApiError');
      } on PluralKitApiError catch (e) {
        expect(e.statusCode, 400);
        expect(e.code, 40005);
        expect(e.message, contains('40005'),
            reason: 'message stays the raw body');
      }
    });

    test('non-JSON 5xx body does not crash parsing; code is null', () async {
      // Fly/Caddy serves HTML on 5xx — _parseErrorCode must not throw.
      // Use a non-idempotent endpoint (createSwitch) so the 5xx isn't retried
      // (idempotent retry is covered by the queue tests).
      final h = buildClient(
        (_, _) async => http.Response(
          '<html><body>502 Bad Gateway</body></html>',
          502,
          headers: {'content-type': 'text/html'},
        ),
        maxRetries: 0,
      );

      try {
        await h.client.createSwitch(['aaaaa']);
        fail('expected PluralKitApiError');
      } on PluralKitApiError catch (e) {
        expect(e.statusCode, 502);
        expect(e.code, isNull);
        expect(e.message, contains('Bad Gateway'));
      }
    });

    test('downloadBytes maps non-200 to PluralKitApiError', () async {
      final h = buildClient(
        (_, _) async => http.Response('missing', 404),
        maxRetries: 0,
      );

      await expectLater(
        h.client.downloadBytes('https://cdn.example/missing.png'),
        throwsA(
          isA<PluralKitApiError>().having(
            (e) => e.statusCode,
            'statusCode',
            404,
          ),
        ),
      );
    });
  });

  // downloadBytes is bounded by
  // PluralKitClient.maxDownloadBytes via a STREAMED read — oversized bodies
  // abort mid-transfer instead of being buffered and checked afterwards.
  group('PluralKitClient — downloadBytes size cap', () {
    test('rejects an oversized declared Content-Length up front', () async {
      final oversized = List<int>.filled(
        PluralKitClient.maxDownloadBytes + 1,
        0,
      );
      final h = buildClient(
        (_, _) async => http.Response.bytes(oversized, 200),
        maxRetries: 0,
      );

      await expectLater(
        h.client.downloadBytes('https://cdn.example/huge.png'),
        throwsA(
          isA<PkDownloadTooLargeException>()
              .having(
                (e) => e.limitBytes,
                'limitBytes',
                PluralKitClient.maxDownloadBytes,
              )
              .having(
                (e) => e.observedBytes,
                'observedBytes',
                PluralKitClient.maxDownloadBytes + 1,
              )
              .having(
                (e) => e.toString(),
                'toString',
                allOf(contains('exceeds'), contains('huge.png')),
              ),
        ),
      );
    });

    test(
      'aborts a chunked body past the cap without draining the stream',
      () async {
        // A server that never sends Content-Length and never stops sending.
        // The cap must trip from received bytes and CANCEL the transfer —
        // chunksServed proves the stream wasn't drained much past the cap.
        const chunkSize = 1024 * 1024; // 1 MiB
        var chunksServed = 0;
        Stream<List<int>> endless() async* {
          while (true) {
            chunksServed++;
            yield List<int>.filled(chunkSize, 0);
          }
        }

        final mock = MockClient.streaming(
          (request, bodyStream) async =>
              http.StreamedResponse(endless(), 200),
        );
        final client = PluralKitClient(
          token: 'test-token',
          httpClient: mock,
          queue: PkRequestQueue(minInterval: Duration.zero, maxRetries: 0),
        );

        await expectLater(
          client.downloadBytes('https://cdn.example/endless.gif'),
          throwsA(isA<PkDownloadTooLargeException>()),
        );

        const capChunks = PluralKitClient.maxDownloadBytes ~/ chunkSize;
        expect(
          chunksServed,
          lessThanOrEqualTo(capChunks + 2),
          reason: 'the read must stop right after crossing the cap',
        );
      },
    );

    test('a body exactly at the cap downloads fully', () async {
      final exact = List<int>.filled(PluralKitClient.maxDownloadBytes, 7);
      final h = buildClient(
        (_, _) async => http.Response.bytes(exact, 200),
        maxRetries: 0,
      );

      final out = await h.client.downloadBytes('https://cdn.example/max.png');
      expect(out.length, PluralKitClient.maxDownloadBytes);
    });
  });

  group('PluralKitClient — rate limit handling', () {
    test(
      'retries on 429, honors Retry-After seconds, eventually succeeds',
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
        expect(
          h.requests,
          hasLength(2),
          reason: 'should retry once after the 429',
        );
      },
    );

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
        (_, _) async => http.Response(
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
        expect(
          e.retryAfter,
          isNotNull,
          reason: 'future X-RateLimit-Reset should parse to a Duration',
        );
        expect(
          e.retryAfter!.inSeconds,
          inInclusiveRange(1, 10),
          reason:
              'parsed delay should be the delta from now (~5s), not the raw epoch',
        );
      }
    });

    test('gives up after max retries of persistent 429', () async {
      final h = buildClient(
        (_, _) async =>
            http.Response('nope', 429, headers: {'retry-after': '0'}),
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
        (_, _) async => http.Response('', 429, headers: {'retry-after': '7'}),
        maxRetries: 0,
      );

      try {
        await h.client.getSystem();
        fail('expected PluralKitRateLimitError');
      } on PluralKitRateLimitError catch (e) {
        expect(e.retryAfter, const Duration(seconds: 7));
      }
    });

    test(
      '429 JSON body retry_after (ms) is the primary source for retryAfter',
      () async {
        // Deployed PK sends no Retry-After header — the only signal is the
        // body's retry_after, in MILLISECONDS.
        final h = buildClient(
          (_, _) async => http.Response(
            '{"message":"429: too many requests","retry_after":250,"code":0}',
            429,
            headers: {'content-type': 'application/json'},
          ),
          maxRetries: 0,
        );

        try {
          await h.client.getSystem();
          fail('expected PluralKitRateLimitError');
        } on PluralKitRateLimitError catch (e) {
          expect(e.retryAfter, const Duration(milliseconds: 250));
        }
      },
    );

    test('429 body retry_after wins over a Retry-After header', () async {
      final h = buildClient(
        (_, _) async => http.Response(
          '{"message":"429","retry_after":500}',
          429,
          // Header says 7s; body says 500ms — body must win.
          headers: {
            'content-type': 'application/json',
            'retry-after': '7',
          },
        ),
        maxRetries: 0,
      );

      try {
        await h.client.getSystem();
        fail('expected PluralKitRateLimitError');
      } on PluralKitRateLimitError catch (e) {
        expect(e.retryAfter, const Duration(milliseconds: 500));
      }
    });

    test('non-JSON 429 body falls back to headers without crashing', () async {
      // Fly/Caddy HTML on 429 — parsing must not throw; header fallback used.
      final h = buildClient(
        (_, _) async => http.Response(
          '<html>too many requests</html>',
          429,
          headers: {
            'content-type': 'text/html',
            'retry-after': '3',
          },
        ),
        maxRetries: 0,
      );

      try {
        await h.client.getSystem();
        fail('expected PluralKitRateLimitError');
      } on PluralKitRateLimitError catch (e) {
        expect(e.retryAfter, const Duration(seconds: 3));
      }
    });

    test('X-RateLimit-Reset > 10^12 is treated as epoch milliseconds', () async {
      // Heuristic: a reset value too large to be epoch-seconds is ms.
      final futureMs =
          DateTime.now().toUtc().millisecondsSinceEpoch + 4000;
      final h = buildClient(
        (_, _) async => http.Response(
          '',
          429,
          headers: {'x-ratelimit-reset': futureMs.toString()},
        ),
        maxRetries: 0,
      );

      try {
        await h.client.getSystem();
        fail('expected PluralKitRateLimitError');
      } on PluralKitRateLimitError catch (e) {
        expect(e.retryAfter, isNotNull);
        expect(e.retryAfter!.inSeconds, inInclusiveRange(1, 6),
            reason: 'ms epoch must yield the ~4s delta, not a huge duration');
      }
    });

    test(
      'malformed Retry-After falls through to exponential backoff',
      () async {
        final h = buildClient(
          (_, _) async =>
              http.Response('', 429, headers: {'retry-after': 'not-a-number'}),
          maxRetries: 0,
        );

        try {
          await h.client.getSystem();
          fail('expected PluralKitRateLimitError');
        } on PluralKitRateLimitError catch (e) {
          expect(e.retryAfter, isNull);
        }
      },
    );

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
      expect(
        sw.elapsedMilliseconds,
        greaterThanOrEqualTo(80),
        reason: 'second call should be paced ~100ms after the first',
      );
      expect(
        sw.elapsedMilliseconds,
        lessThan(500),
        reason: 'pacing should be ~100ms, not stacked or mis-applied per call',
      );
    });

    test('retries cover write endpoints (createMember)', () async {
      final h = buildClient((req, call) async {
        if (call == 0) {
          return http.Response('slow down', 429, headers: {'retry-after': '0'});
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

  group('isPluralKitNetworkException', () {
    test('returns true for SocketException', () {
      expect(
        isPluralKitNetworkException(
          const SocketException('Failed host lookup: api.pluralkit.me'),
        ),
        isTrue,
      );
    });

    test('returns true for HandshakeException', () {
      expect(
        isPluralKitNetworkException(const HandshakeException('TLS bad')),
        isTrue,
      );
    });

    test('returns true for TimeoutException', () {
      expect(
        isPluralKitNetworkException(TimeoutException('stalled')),
        isTrue,
      );
    });

    test('returns true for ClientException with SocketException', () {
      expect(
        isPluralKitNetworkException(
          http.ClientException(
            'SocketException: Failed host lookup',
            Uri.parse('https://api.pluralkit.me/v2/members'),
          ),
        ),
        isTrue,
      );
    });

    test('returns true for ClientException with HandshakeException', () {
      expect(
        isPluralKitNetworkException(
          http.ClientException(
            'HandshakeException: bad cert',
            Uri.parse('https://api.pluralkit.me/v2/members'),
          ),
        ),
        isTrue,
      );
    });

    test('returns true for ClientException with Failed host lookup', () {
      expect(
        isPluralKitNetworkException(
          http.ClientException(
            "Failed host lookup: 'api.pluralkit.me'",
            Uri.parse('https://api.pluralkit.me/v2/members'),
          ),
        ),
        isTrue,
      );
    });

    test('returns true for ClientException with Connection refused', () {
      expect(
        isPluralKitNetworkException(
          http.ClientException(
            'Connection refused',
            Uri.parse('https://api.pluralkit.me/v2/members'),
          ),
        ),
        isTrue,
      );
    });

    test('returns true for ClientException with Connection closed', () {
      expect(
        isPluralKitNetworkException(
          http.ClientException(
            'Connection closed before full header was received',
            Uri.parse('https://api.pluralkit.me/v2/members'),
          ),
        ),
        isTrue,
      );
    });

    test('returns true for ClientException with Connection failed', () {
      expect(
        isPluralKitNetworkException(
          http.ClientException(
            'Connection failed',
            Uri.parse('https://api.pluralkit.me/v2/members'),
          ),
        ),
        isTrue,
      );
    });

    test('returns true for ClientException with Connection terminated', () {
      expect(
        isPluralKitNetworkException(
          http.ClientException(
            'Connection terminated during handshake',
            Uri.parse('https://api.pluralkit.me/v2/members'),
          ),
        ),
        isTrue,
      );
    });

    test('returns true for ClientException with Connection reset by peer', () {
      expect(
        isPluralKitNetworkException(
          http.ClientException(
            'Connection reset by peer',
            Uri.parse('https://api.pluralkit.me/v2/members'),
          ),
        ),
        isTrue,
      );
    });

    test('returns true for ClientException with Network is unreachable', () {
      expect(
        isPluralKitNetworkException(
          http.ClientException(
            'Network is unreachable',
            Uri.parse('https://api.pluralkit.me/v2/members'),
          ),
        ),
        isTrue,
      );
    });

    test('returns true for ClientException with No route to host', () {
      expect(
        isPluralKitNetworkException(
          http.ClientException(
            'No route to host',
            Uri.parse('https://api.pluralkit.me/v2/members'),
          ),
        ),
        isTrue,
      );
    });

    test(
      'returns true for ClientException with Software caused connection abort',
      () {
        expect(
          isPluralKitNetworkException(
            http.ClientException(
              'Software caused connection abort',
              Uri.parse('https://api.pluralkit.me/v2/members'),
            ),
          ),
          isTrue,
        );
      },
    );

    test('returns true for ClientException with Operation timed out', () {
      expect(
        isPluralKitNetworkException(
          http.ClientException(
            'Operation timed out',
            Uri.parse('https://api.pluralkit.me/v2/members'),
          ),
        ),
        isTrue,
      );
    });

    test('returns true for ClientException with Broken pipe', () {
      expect(
        isPluralKitNetworkException(
          http.ClientException(
            'Broken pipe',
            Uri.parse('https://api.pluralkit.me/v2/members'),
          ),
        ),
        isTrue,
      );
    });

    test('returns true for ClientException with XMLHttpRequest error', () {
      expect(
        isPluralKitNetworkException(
          http.ClientException(
            'XMLHttpRequest error.',
            Uri.parse('https://api.pluralkit.me/v2/members'),
          ),
        ),
        isTrue,
      );
    });

    test('returns false for PluralKitApiError', () {
      expect(
        isPluralKitNetworkException(const PluralKitApiError(500, 'boom')),
        isFalse,
      );
    });

    test('returns false for PluralKitAuthError', () {
      expect(
        isPluralKitNetworkException(const PluralKitAuthError()),
        isFalse,
      );
    });

    test('returns false for PluralKitRateLimitError', () {
      expect(
        isPluralKitNetworkException(const PluralKitRateLimitError()),
        isFalse,
      );
    });

    test('returns false for StateError', () {
      expect(
        isPluralKitNetworkException(StateError('bad state')),
        isFalse,
      );
    });

    test('returns false for FormatException', () {
      expect(
        isPluralKitNetworkException(const FormatException('bad json')),
        isFalse,
      );
    });

    test(
      'returns false for ClientException whose toString does not match patterns',
      () {
        expect(
          isPluralKitNetworkException(
            http.ClientException(
              'malformed response body',
              Uri.parse('https://api.pluralkit.me/v2/members'),
            ),
          ),
          isFalse,
        );
      },
    );
  });
}
