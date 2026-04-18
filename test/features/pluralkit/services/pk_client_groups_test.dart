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
}
