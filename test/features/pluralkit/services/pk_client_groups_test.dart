import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_test;

import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';

void main() {
  group('PluralKitClient.getGroups', () {
    test('appends with_members=true and parses list', () async {
      http.Request? captured;
      final client = http_test.MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode([
            {
              'id': 'aaaaa',
              'uuid': 'u1',
              'name': 'Core',
              'members': [
                {'uuid': 'mem-1'},
                {'uuid': 'mem-2'},
              ],
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final pk = PluralKitClient(token: 't0k', httpClient: client);
      final groups = await pk.getGroups(withMembers: true);

      expect(captured, isNotNull);
      expect(captured!.url.queryParameters['with_members'], 'true');
      expect(captured!.url.path, endsWith('/systems/@me/groups'));
      expect(groups, hasLength(1));
      expect(groups.single.uuid, 'u1');
      expect(groups.single.memberIds, ['mem-1', 'mem-2']);
    });

    test('getGroupMembers falls back to /groups/<ref>/members', () async {
      final client = http_test.MockClient((request) async {
        expect(
          request.url.path,
          endsWith('/groups/u1/members'),
        );
        return http.Response(
          jsonEncode([
            {'uuid': 'mem-1', 'id': 'mm111'},
            {'uuid': 'mem-2', 'id': 'mm222'},
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final pk = PluralKitClient(token: 't0k', httpClient: client);
      final members = await pk.getGroupMembers('u1');
      expect(members, ['mem-1', 'mem-2']);
    });

    test('401 → PluralKitAuthError', () async {
      final client = http_test.MockClient((request) async {
        return http.Response('unauthorized', 401);
      });
      final pk = PluralKitClient(token: 't0k', httpClient: client);
      expect(pk.getGroups(), throwsA(isA<PluralKitAuthError>()));
    });
  });

  // ─── Step 5: bidirectional group membership push ──────────────────────────
  // PluralKit docs: POST /groups/{ref}/members/add and /remove take a raw
  // JSON array of member references and return 204 on success. Tests assert
  // the wire body shape (catches the v1 plan's wrong {"members": [...]}
  // assumption flagged in review) and the rate-limit / error surface.

  group('PluralKitClient.addMembersToGroup', () {
    test('POSTs to /groups/<ref>/members/add with raw JSON array body',
        () async {
      http.Request? captured;
      final client = http_test.MockClient((request) async {
        captured = request;
        return http.Response('', 204);
      });
      final pk = PluralKitClient(token: 't0k', httpClient: client);

      await pk.addMembersToGroup('group-uuid', ['m1', 'm2']);

      expect(captured, isNotNull);
      expect(captured!.method, 'POST');
      expect(captured!.url.path, endsWith('/groups/group-uuid/members/add'));
      // Body must be a raw JSON array — NOT {"members": [...]}.
      expect(jsonDecode(captured!.body), ['m1', 'm2']);
    });

    test('returns without making a request when memberRefs is empty',
        () async {
      var requestCount = 0;
      final client = http_test.MockClient((request) async {
        requestCount++;
        return http.Response('', 204);
      });
      final pk = PluralKitClient(token: 't0k', httpClient: client);

      await pk.addMembersToGroup('group-uuid', const []);

      expect(requestCount, 0);
    });

    test('204 with no body completes normally', () async {
      final client = http_test.MockClient(
        (request) async => http.Response('', 204),
      );
      final pk = PluralKitClient(token: 't0k', httpClient: client);

      await expectLater(
        pk.addMembersToGroup('g', ['m1']),
        completes,
      );
    });

    test('401 → PluralKitAuthError', () async {
      final client = http_test.MockClient(
        (request) async => http.Response('unauthorized', 401),
      );
      final pk = PluralKitClient(token: 't0k', httpClient: client);

      expect(
        pk.addMembersToGroup('g', ['m1']),
        throwsA(isA<PluralKitAuthError>()),
      );
    });

    test('429 → PluralKitRateLimitError surfaces retry-after', () async {
      final client = http_test.MockClient(
        (request) async => http.Response(
          'rate limited',
          429,
          headers: {'retry-after': '5'},
        ),
      );
      final pk = PluralKitClient(token: 't0k', httpClient: client);

      try {
        await pk.addMembersToGroup('g', ['m1']);
        fail('expected PluralKitRateLimitError');
      } on PluralKitRateLimitError catch (e) {
        expect(e.retryAfter, const Duration(seconds: 5));
      }
    });

    test('400 → PluralKitApiError surfaces status + body', () async {
      final client = http_test.MockClient(
        (request) async => http.Response('bad request', 400),
      );
      final pk = PluralKitClient(token: 't0k', httpClient: client);

      try {
        await pk.addMembersToGroup('g', ['m1']);
        fail('expected PluralKitApiError');
      } on PluralKitApiError catch (e) {
        expect(e.statusCode, 400);
        expect(e.message, contains('bad request'));
      }
    });
  });

  group('PluralKitClient.removeMembersFromGroup', () {
    test('POSTs to /groups/<ref>/members/remove with raw JSON array body',
        () async {
      http.Request? captured;
      final client = http_test.MockClient((request) async {
        captured = request;
        return http.Response('', 204);
      });
      final pk = PluralKitClient(token: 't0k', httpClient: client);

      await pk.removeMembersFromGroup('group-uuid', ['m1', 'm2']);

      expect(captured!.method, 'POST');
      expect(captured!.url.path, endsWith('/groups/group-uuid/members/remove'));
      expect(jsonDecode(captured!.body), ['m1', 'm2']);
    });

    test('returns without making a request when memberRefs is empty',
        () async {
      var requestCount = 0;
      final client = http_test.MockClient((request) async {
        requestCount++;
        return http.Response('', 204);
      });
      final pk = PluralKitClient(token: 't0k', httpClient: client);

      await pk.removeMembersFromGroup('group-uuid', const []);

      expect(requestCount, 0);
    });
  });
}
