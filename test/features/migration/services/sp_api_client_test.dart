import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prism_plurality/features/migration/services/sp_api_client.dart';

void main() {
  group('SpApiClient', () {
    test('verifyToken returns system ID and username', () async {
      final client = SpApiClient(
        token: 'test-token',
        httpClient: MockClient((request) async {
          expect(request.headers['Authorization'], 'test-token');
          return http.Response(
            jsonEncode({
              '_id': 'abc123',
              'uid': 'abc123',
              'username': 'test-user',
            }),
            200,
          );
        }),
      );
      final result = await client.verifyToken();
      expect(result.systemId, 'abc123');
      expect(result.username, 'test-user');
      client.dispose();
    });

    test('verifyToken throws SpAuthError on 401', () async {
      final client = SpApiClient(
        token: 'bad-token',
        httpClient: MockClient((request) async {
          return http.Response('Unauthorized', 401);
        }),
      );
      expect(client.verifyToken, throwsA(isA<SpAuthError>()));
      client.dispose();
    });

    test('verifyToken throws SpAuthError on 403', () async {
      final client = SpApiClient(
        token: 'no-perms',
        httpClient: MockClient((request) async {
          return http.Response('Forbidden', 403);
        }),
      );
      expect(client.verifyToken, throwsA(isA<SpAuthError>()));
      client.dispose();
    });

    test('getMembers returns parsed list', () async {
      final client = SpApiClient(
        token: 'test-token',
        httpClient: MockClient((request) async {
          if (request.url.path.contains('/members/')) {
            return http.Response(
              jsonEncode([
                {'_id': 'mem1', 'name': 'Kai'},
                {'_id': 'mem2', 'name': 'Luna'},
              ]),
              200,
            );
          }
          return http.Response('Not found', 404);
        }),
      );
      final members = await client.getMembers('abc123');
      expect(members.length, 2);
      expect(members.first['name'], 'Kai');
      client.dispose();
    });

    test('trims whitespace from token', () async {
      final client = SpApiClient(
        token: '  test-token  \n',
        httpClient: MockClient((request) async {
          expect(request.headers['Authorization'], 'test-token');
          return http.Response(jsonEncode({'_id': 'x', 'uid': 'x'}), 200);
        }),
      );
      await client.verifyToken();
      client.dispose();
    });

    test('throws SpApiError on non-auth errors', () async {
      final client = SpApiClient(
        token: 'test-token',
        httpClient: MockClient((request) async {
          return http.Response('Internal Server Error', 500);
        }),
      );
      expect(client.verifyToken, throwsA(isA<SpApiError>()));
      client.dispose();
    });

    test('throws ArgumentError on empty token', () {
      expect(
        () => SpApiClient(token: ''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError on whitespace-only token', () {
      expect(
        () => SpApiClient(token: '   \n'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('getList returns empty for non-list response', () async {
      final client = SpApiClient(
        token: 'test-token',
        httpClient: MockClient((request) async {
          return http.Response(jsonEncode({'ok': true}), 200);
        }),
      );
      final result = await client.getMembers('abc123');
      expect(result, isEmpty);
      client.dispose();
    });
  });

  group('SpApiClient.fetchAll', () {
    /// Build a mock client that routes SP API endpoints to fixture data.
    MockClient buildMockClient({
      List<Map<String, dynamic>> members = const [],
      List<Map<String, dynamic>> customFronts = const [],
      List<Map<String, dynamic>> frontHistory = const [],
      List<Map<String, dynamic>> groups = const [],
      List<Map<String, dynamic>> customFields = const [],
      List<Map<String, dynamic>> polls = const [],
      Map<String, List<Map<String, dynamic>>> notesByMember = const {},
      Map<String, List<Map<String, dynamic>>> commentsByDoc = const {},
      bool failNotesForMember = false,
      String? failNotesId,
    }) {
      return MockClient((request) async {
        final path = request.url.path;

        if (path == '/v1/me') {
          return http.Response(
            jsonEncode({'_id': 'sys1', 'uid': 'sys1', 'username': 'test-sys'}),
            200,
          );
        }
        if (path.startsWith('/v1/members/')) {
          return http.Response(jsonEncode(members), 200);
        }
        if (path.startsWith('/v1/customFronts/')) {
          return http.Response(jsonEncode(customFronts), 200);
        }
        if (path == '/v1/frontHistory') {
          return http.Response(jsonEncode(frontHistory), 200);
        }
        if (path.startsWith('/v1/groups/')) {
          return http.Response(jsonEncode(groups), 200);
        }
        if (path.startsWith('/v1/customFields/')) {
          return http.Response(jsonEncode(customFields), 200);
        }
        if (path.startsWith('/v1/polls/')) {
          return http.Response(jsonEncode(polls), 200);
        }
        if (path.startsWith('/v1/notes/')) {
          final segments = path.split('/');
          final memberId = segments.last;
          if (failNotesForMember && memberId == failNotesId) {
            return http.Response('Not Found', 404);
          }
          return http.Response(
            jsonEncode(notesByMember[memberId] ?? []),
            200,
          );
        }
        if (path.startsWith('/v1/comments/')) {
          final segments = path.split('/');
          final docId = segments.last;
          return http.Response(
            jsonEncode(commentsByDoc[docId] ?? []),
            200,
          );
        }
        if (path.startsWith('/v1/board/member/')) {
          return http.Response(jsonEncode([]), 200);
        }

        return http.Response('Not Found', 404);
      });
    }

    test('assembles SpExportData from API responses', () async {
      final client = SpApiClient(
        token: 'test-token',
        httpClient: buildMockClient(
          members: [
            {'_id': 'mem1', 'name': 'Kai', 'pronouns': 'he/him'},
          ],
          frontHistory: [
            {
              '_id': 'fh1',
              'member': 'mem1',
              'startTime': 1767362442459,
              'endTime': 1767394844459,
              'custom': false,
              'live': false,
            },
          ],
          notesByMember: {
            'mem1': [
              {'_id': 'n1', 'member': 'mem1', 'title': 'Note', 'note': 'Body', 'date': 1768435200000},
            ],
          },
        ),
      );

      final data = await client.fetchAll();
      expect(data.members.length, 1);
      expect(data.members.first.name, 'Kai');
      expect(data.frontHistory.length, 1);
      expect(data.notes.length, 1);
      expect(data.notes.first.title, 'Note');
      client.dispose();
    });

    test('reports progress via callback', () async {
      final progressCalls = <String>[];
      final client = SpApiClient(
        token: 'test-token',
        httpClient: buildMockClient(
          members: [
            {'_id': 'mem1', 'name': 'Kai'},
          ],
        ),
      );

      await client.fetchAll(
        onProgress: (collection, count) {
          progressCalls.add(collection);
        },
      );

      expect(progressCalls, contains('Members'));
      expect(progressCalls, contains('Front history'));
      client.dispose();
    });

    test('partial note failure continues with other data', () async {
      final client = SpApiClient(
        token: 'test-token',
        httpClient: buildMockClient(
          members: [
            {'_id': 'mem1', 'name': 'Kai'},
            {'_id': 'mem2', 'name': 'Luna'},
          ],
          notesByMember: {
            'mem2': [
              {'_id': 'n1', 'member': 'mem2', 'title': 'Luna note', 'note': 'Body', 'date': 1768435200000},
            ],
          },
          failNotesForMember: true,
          failNotesId: 'mem1',
        ),
      );

      final data = await client.fetchAll();
      // mem1's notes failed but mem2's notes should still be present
      expect(data.members.length, 2);
      expect(data.notes.length, 1);
      expect(data.notes.first.title, 'Luna note');
      client.dispose();
    });

    test('empty system returns empty SpExportData', () async {
      final client = SpApiClient(
        token: 'test-token',
        httpClient: buildMockClient(),
      );

      final data = await client.fetchAll();
      expect(data.isEmpty, true);
      expect(data.members, isEmpty);
      expect(data.frontHistory, isEmpty);
      client.dispose();
    });
  });
}
