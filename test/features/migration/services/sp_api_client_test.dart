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

    test(
      'verifyToken parses content-wrapped /me response (real API format)',
      () async {
        final client = SpApiClient(
          token: 'test-token',
          httpClient: MockClient((request) async {
            return http.Response(
              jsonEncode({
                'exists': true,
                'id': 'sys123',
                'content': {
                  'uid': 'sys123',
                  'username': 'real-user',
                  'isAsystem': true,
                },
              }),
              200,
            );
          }),
        );
        final result = await client.verifyToken();
        expect(result.systemId, 'sys123');
        expect(result.username, 'real-user');
        client.dispose();
      },
    );

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

    test(
      'getMembers unwraps content-wrapped list items (real API format)',
      () async {
        final client = SpApiClient(
          token: 'test-token',
          httpClient: MockClient((request) async {
            if (request.url.path.contains('/members/')) {
              return http.Response(
                jsonEncode([
                  {
                    'exists': true,
                    'id': 'mem1',
                    'content': {'name': 'Kai', 'pronouns': 'he/him'},
                  },
                  {
                    'exists': true,
                    'id': 'mem2',
                    'content': {'name': 'Luna', 'pronouns': 'she/her'},
                  },
                ]),
                200,
              );
            }
            return http.Response('Not found', 404);
          }),
        );
        final members = await client.getMembers('abc123');
        expect(members.length, 2);
        // After unwrapping, top-level fields from content are accessible.
        expect(members.first['name'], 'Kai');
        expect(members.first['pronouns'], 'he/him');
        // The wrapper's id is exposed as _id for fromJson factories.
        expect(members.first['_id'], 'mem1');
        client.dispose();
      },
    );

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
      expect(() => SpApiClient(token: ''), throwsA(isA<ArgumentError>()));
    });

    test('throws ArgumentError on whitespace-only token', () {
      expect(() => SpApiClient(token: '   \n'), throwsA(isA<ArgumentError>()));
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

    test(
      'getChannelMessages uses the live route shape and paginates',
      () async {
        final requestedUris = <Uri>[];
        final firstPage = List.generate(
          100,
          (index) => {
            '_id': 'm${index + 1}',
            'message': 'Message ${index + 1}',
          },
        );
        final client = SpApiClient(
          token: 'test-token',
          httpClient: MockClient((request) async {
            requestedUris.add(request.url);
            if (request.url.path == '/v1/chat/messages/ch1') {
              final skipTo = request.url.queryParameters['skipTo'];
              final limit = request.url.queryParameters['limit'];
              final sortOrder = request.url.queryParameters['sortOrder'];
              expect(limit, '100');
              expect(sortOrder, '1');

              if (skipTo == null) {
                return http.Response(jsonEncode(firstPage), 200);
              }

              expect(skipTo, 'm100');
              return http.Response(
                jsonEncode([
                  {'_id': 'm101', 'message': 'Message 101'},
                ]),
                200,
              );
            }
            return http.Response('Not found', 404);
          }),
        );

        final messages = await client.getChannelMessages('ch1');
        expect(messages.map((m) => m['_id']).toList(), [
          ...List.generate(100, (index) => 'm${index + 1}'),
          'm101',
        ]);
        expect(
          requestedUris.map((uri) => uri.path),
          everyElement(equals('/v1/chat/messages/ch1')),
        );
        expect(
          requestedUris.map((uri) => uri.queryParameters['skipTo']).toList(),
          [null, 'm100'],
        );
        client.dispose();
      },
    );

    test('getChannelMessages unwraps content-wrapped items', () async {
      final client = SpApiClient(
        token: 'test-token',
        httpClient: MockClient((request) async {
          if (request.url.path == '/v1/chat/messages/ch1') {
            return http.Response(
              jsonEncode([
                {
                  'exists': true,
                  'id': 'msg1',
                  'content': {
                    'message': 'hello',
                    'sender': 'mem1',
                    'timestamp': 1768435200000,
                  },
                },
              ]),
              200,
            );
          }
          return http.Response('Not found', 404);
        }),
      );

      final messages = await client.getChannelMessages('ch1');
      expect(messages, hasLength(1));
      expect(messages.first['_id'], 'msg1');
      expect(messages.first['message'], 'hello');
      expect(messages.first['sender'], 'mem1');
      client.dispose();
    });

    test(
      'getChannelMessages stops if the server repeats the terminal page cursor',
      () async {
        final requestedSkipTos = <String?>[];
        final page1 = List.generate(
          100,
          (index) => {
            '_id': 'm${index + 1}',
            'message': 'Message ${index + 1}',
          },
        );
        final page2 = List.generate(
          100,
          (index) => {
            '_id': 'm${index + 101}',
            'message': 'Message ${index + 101}',
          },
        );
        final client = SpApiClient(
          token: 'test-token',
          httpClient: MockClient((request) async {
            if (request.url.path != '/v1/chat/messages/ch1') {
              return http.Response('Not found', 404);
            }

            final skipTo = request.url.queryParameters['skipTo'];
            requestedSkipTos.add(skipTo);
            if (skipTo == null) {
              return http.Response(jsonEncode(page1), 200);
            }
            if (skipTo == 'm100') {
              return http.Response(jsonEncode(page2), 200);
            }
            if (skipTo == 'm200') {
              // Repeat the terminal cursor to exercise the duplicate-page guard.
              return http.Response(
                jsonEncode([
                  ...page2.take(99),
                  {'_id': 'm200', 'message': 'Message 200'},
                ]),
                200,
              );
            }
            return http.Response('Not found', 404);
          }),
        );

        final messages = await client.getChannelMessages('ch1');
        expect(messages, hasLength(200));
        expect(messages.first['_id'], 'm1');
        expect(messages.last['_id'], 'm200');
        expect(requestedSkipTos, [null, 'm100', 'm200']);
        client.dispose();
      },
    );
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
      List<Map<String, dynamic>> channels = const [],
      Map<String, List<Map<String, dynamic>>> messagesByChannel = const {},
      Set<String> failMessageChannels = const {},
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
        if (path == '/v1/chat/channels') {
          return http.Response(jsonEncode(channels), 200);
        }
        if (path.startsWith('/v1/chat/messages/')) {
          final channelId = path.split('/').last;
          if (failMessageChannels.contains(channelId)) {
            return http.Response('Server error', 500);
          }
          final skipTo = request.url.queryParameters['skipTo'];
          final allMessages = messagesByChannel[channelId] ?? const [];
          if (skipTo == null) {
            return http.Response(jsonEncode(allMessages), 200);
          }
          final skipIndex = allMessages.indexWhere(
            (message) => message['_id'] == skipTo,
          );
          if (skipIndex == -1 || skipIndex + 1 >= allMessages.length) {
            return http.Response(jsonEncode(const []), 200);
          }
          return http.Response(
            jsonEncode(allMessages.skip(skipIndex + 1).toList()),
            200,
          );
        }
        if (path.startsWith('/v1/notes/')) {
          final segments = path.split('/');
          final memberId = segments.last;
          if (failNotesForMember && memberId == failNotesId) {
            return http.Response('Not Found', 404);
          }
          return http.Response(jsonEncode(notesByMember[memberId] ?? []), 200);
        }
        if (path.startsWith('/v1/comments/')) {
          final segments = path.split('/');
          final docId = segments.last;
          return http.Response(jsonEncode(commentsByDoc[docId] ?? []), 200);
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
          channels: const [
            {'_id': 'ch1', 'name': 'General'},
          ],
          messagesByChannel: const {
            'ch1': [
              {
                '_id': 'msg1',
                'message': 'hello',
                'sender': 'mem1',
                'timestamp': 1768435200000,
              },
            ],
          },
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
              {
                '_id': 'n1',
                'member': 'mem1',
                'title': 'Note',
                'note': 'Body',
                'date': 1768435200000,
              },
            ],
          },
        ),
      );

      final data = await client.fetchAll();
      expect(data.members.length, 1);
      expect(data.members.first.name, 'Kai');
      expect(data.frontHistory.length, 1);
      expect(data.messages, hasLength(1));
      expect(data.messages.first.content, 'hello');
      expect(data.notes.length, 1);
      expect(data.notes.first.title, 'Note');
      client.dispose();
    });

    test(
      'fetchAll unwraps content-wrapped channels and messages in the same run',
      () async {
        final client = SpApiClient(
          token: 'test-token',
          httpClient: buildMockClient(
            members: const [
              {'_id': 'mem1', 'name': 'Kai', 'pronouns': 'he/him'},
            ],
            channels: const [
              {
                'exists': true,
                'id': 'ch1',
                'content': {
                  'name': 'General',
                  'members': ['mem1'],
                },
              },
            ],
            messagesByChannel: const {
              'ch1': [
                {
                  'exists': true,
                  'id': 'msg1',
                  'content': {
                    'message': 'hello',
                    'sender': 'mem1',
                    'timestamp': 1768435200000,
                  },
                },
              ],
            },
          ),
        );

        final data = await client.fetchAll();
        expect(data.channels, hasLength(1));
        expect(data.channels.first.id, 'ch1');
        expect(data.channels.first.name, 'General');
        expect(data.channels.first.memberIds, ['mem1']);
        expect(data.messages, hasLength(1));
        expect(data.messages.first.id, 'msg1');
        expect(data.messages.first.channelId, 'ch1');
        expect(data.messages.first.senderId, 'mem1');
        expect(data.messages.first.content, 'hello');
        client.dispose();
      },
    );

    test(
      'partial channel message failure continues with other channels',
      () async {
        final client = SpApiClient(
          token: 'test-token',
          httpClient: buildMockClient(
            members: const [
              {'_id': 'mem1', 'name': 'Kai'},
            ],
            channels: const [
              {'_id': 'ch1', 'name': 'General'},
              {'_id': 'ch2', 'name': 'Venting'},
            ],
            messagesByChannel: const {
              'ch1': [
                {
                  '_id': 'msg1',
                  'message': 'hello',
                  'sender': 'mem1',
                  'timestamp': 1768435200000,
                },
              ],
            },
            failMessageChannels: const {'ch2'},
          ),
        );

        final data = await client.fetchAll();
        expect(data.channels, hasLength(2));
        expect(data.messages, hasLength(1));
        expect(data.messages.first.channelId, 'ch1');
        expect(data.messages.first.content, 'hello');
        client.dispose();
      },
    );

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
              {
                '_id': 'n1',
                'member': 'mem2',
                'title': 'Luna note',
                'note': 'Body',
                'date': 1768435200000,
              },
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
