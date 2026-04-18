import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';

String _jsonWithUser(Map<String, dynamic> user) => jsonEncode({
      'users': [user],
    });

void main() {
  group('SpParser.systemAvatarUrl', () {
    test('picks direct avatarUrl when present', () {
      final data = SpParser.parse(_jsonWithUser({
        '_id': 'u1',
        'username': 'Alice',
        'avatarUrl': 'https://example.com/me.png',
      }));
      expect(data.systemAvatarUrl, 'https://example.com/me.png');
    });

    test('constructs apparyllis URL from uid + avatarUuid fallback', () {
      final data = SpParser.parse(_jsonWithUser({
        '_id': 'u1',
        'uid': 'user-123',
        'avatarUuid': 'uuid-abc',
      }));
      expect(
        data.systemAvatarUrl,
        'https://serve.apparyllis.com/avatars/user-123/uuid-abc',
      );
    });

    test('falls back to _id when uid is absent', () {
      final data = SpParser.parse(_jsonWithUser({
        '_id': 'user-xyz',
        'avatarUuid': 'uuid-1',
      }));
      expect(
        data.systemAvatarUrl,
        'https://serve.apparyllis.com/avatars/user-xyz/uuid-1',
      );
    });

    test('prefers direct avatarUrl over uid + avatarUuid', () {
      final data = SpParser.parse(_jsonWithUser({
        '_id': 'u1',
        'uid': 'user-123',
        'avatarUuid': 'uuid-abc',
        'avatarUrl': 'https://example.com/direct.png',
      }));
      expect(data.systemAvatarUrl, 'https://example.com/direct.png');
    });

    test('returns null when neither avatarUrl nor avatarUuid is present', () {
      final data = SpParser.parse(_jsonWithUser({
        '_id': 'u1',
        'username': 'Alice',
      }));
      expect(data.systemAvatarUrl, isNull);
    });

    test('returns null when avatarUuid is empty', () {
      final data = SpParser.parse(_jsonWithUser({
        '_id': 'u1',
        'uid': 'user-123',
        'avatarUuid': '',
      }));
      expect(data.systemAvatarUrl, isNull);
    });

    test('returns null when users array is missing', () {
      final data = SpParser.parse(jsonEncode({'members': []}));
      expect(data.systemAvatarUrl, isNull);
    });
  });
}
