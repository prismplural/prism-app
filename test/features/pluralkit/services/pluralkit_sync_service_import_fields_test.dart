/// Regression tests: PluralKitSyncService._importMembers must persist every
/// PK member field that Prism tracks — proxy tags, birthday, display name,
/// pronouns, bio, color, avatar-absent, PK IDs.
///
/// Prior bug (fixed 2026-04-19): the main auto-sync import path dropped
/// proxy_tags_json and birthday and collapsed display_name into name. Proxy
/// tags never reached the DB, so the member detail UI showed the empty state
/// and the chat proxy-tag matcher short-circuited on `proxyTagsJson == null`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_banner_cache_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_request_queue.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

http.Response _json(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

PluralKitClient _mockClient({
  required Map<String, dynamic> system,
  required List<Map<String, dynamic>> members,
}) {
  final mock = MockClient((req) async {
    final path = req.url.path;
    if (path.endsWith('/systems/@me')) return _json(system);
    if (path.endsWith('/systems/@me/members')) return _json(members);
    return http.Response('not mocked: $path', 404);
  });
  return PluralKitClient(
    token: 't',
    httpClient: mock,
    queue: PkRequestQueue(minInterval: Duration.zero, maxRetries: 1),
  );
}

PkBannerCacheService _testBannerCacheService() => PkBannerCacheService(
  fetcher: (_) async => Uint8List.fromList([1, 2, 3]),
  normalizer: (bytes) async => bytes,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('_importMembers persists every PK field', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test(
      'create: proxy_tags, birthday, display_name, pronouns, bio, color, banner',
      () async {
        final service = PluralKitSyncService(
          memberRepository: DriftMemberRepository(db.membersDao, null),
          frontingSessionRepository: DriftFrontingSessionRepository(
            db.frontingSessionsDao,
            null,
          ),
          syncDao: db.pluralKitSyncDao,
          tokenOverride: 't',
          clientFactory: (_) => _mockClient(
            system: {'id': 'sys1', 'name': 'Test System'},
            members: [
              {
                'id': 'aaaaa',
                'uuid': 'u-alice',
                'name': 'alice',
                'display_name': 'Alice!',
                'pronouns': 'she/her',
                'description': 'A bio',
                'color': 'ff00aa',
                'birthday': '2020-06-15',
                'banner': 'https://example.com/banner.png',
                'proxy_tags': [
                  {'prefix': 'A:', 'suffix': null},
                  {'prefix': null, 'suffix': ' -A'},
                ],
              },
            ],
          ),
          bannerCacheService: _testBannerCacheService(),
        );

        final (sysName, pkMembers) = await service.importMembersOnly();
        expect(sysName, 'Test System');
        expect(pkMembers, hasLength(1));

        final rows = await db.membersDao.getAllMembers();
        expect(rows, hasLength(1));
        final row = rows.single;

        // PK display_name collapsed into local name for display.
        expect(row.name, 'Alice!');
        // PK raw name stored as displayName subtitle (used by push + data export).
        expect(row.displayName, 'alice');
        expect(row.pronouns, 'she/her');
        expect(row.bio, 'A bio');
        expect(row.birthday, '2020-06-15');
        expect(row.customColorHex, 'ff00aa');
        expect(row.customColorEnabled, isTrue);
        expect(row.pluralkitId, 'aaaaa');
        expect(row.pluralkitUuid, 'u-alice');
        expect(row.pkBannerUrl, 'https://example.com/banner.png');
        expect(row.pkBannerImageData, Uint8List.fromList([1, 2, 3]));
        expect(row.pkBannerCachedUrl, 'https://example.com/banner.png');

        // Proxy tags round-trip as valid JSON with both entries.
        expect(row.proxyTagsJson, isNotNull);
        final decoded = jsonDecode(row.proxyTagsJson!) as List;
        expect(decoded, hasLength(2));
        expect(decoded[0], {'prefix': 'A:', 'suffix': null});
        expect(decoded[1], {'prefix': null, 'suffix': ' -A'});
      },
    );

    test(
      'update: re-import writes proxy_tags onto an existing member',
      () async {
        PluralKitSyncService makeService(List<Map<String, dynamic>> members) =>
            PluralKitSyncService(
              memberRepository: DriftMemberRepository(db.membersDao, null),
              frontingSessionRepository: DriftFrontingSessionRepository(
                db.frontingSessionsDao,
                null,
              ),
              syncDao: db.pluralKitSyncDao,
              tokenOverride: 't',
              clientFactory: (_) => _mockClient(
                system: {'id': 'sys1', 'name': 'Test'},
                members: members,
              ),
              bannerCacheService: _testBannerCacheService(),
            );

        // First import — no proxy tags.
        await makeService([
          {'id': 'aaaaa', 'uuid': 'u-alice', 'name': 'Alice'},
        ]).importMembersOnly();

        var row = (await db.membersDao.getAllMembers()).single;
        expect(row.proxyTagsJson, isNull);

        // Second import — PK now has proxy tags for the same UUID.
        await makeService([
          {
            'id': 'aaaaa',
            'uuid': 'u-alice',
            'name': 'Alice',
            'proxy_tags': [
              {'prefix': 'a:', 'suffix': null},
            ],
          },
        ]).importMembersOnly();

        row = (await db.membersDao.getAllMembers()).single;
        expect(row.proxyTagsJson, isNotNull);
        final decoded = jsonDecode(row.proxyTagsJson!) as List;
        expect(decoded, hasLength(1));
        expect((decoded[0] as Map)['prefix'], 'a:');
      },
    );

    test(
      'update: missing proxy_tags on subsequent import preserves local value',
      () async {
        // First import populates proxy tags.
        PluralKitSyncService build(List<Map<String, dynamic>> members) =>
            PluralKitSyncService(
              memberRepository: DriftMemberRepository(db.membersDao, null),
              frontingSessionRepository: DriftFrontingSessionRepository(
                db.frontingSessionsDao,
                null,
              ),
              syncDao: db.pluralKitSyncDao,
              tokenOverride: 't',
              clientFactory: (_) => _mockClient(
                system: {'id': 'sys1', 'name': 'Test'},
                members: members,
              ),
              bannerCacheService: _testBannerCacheService(),
            );

        await build([
          {
            'id': 'aaaaa',
            'uuid': 'u-alice',
            'name': 'Alice',
            'proxy_tags': [
              {'prefix': 'A:', 'suffix': null},
            ],
          },
        ]).importMembersOnly();

        // Second import: PK omits proxy_tags entirely (e.g. privacy scope).
        // We must not wipe the locally-stored tags.
        await build([
          {'id': 'aaaaa', 'uuid': 'u-alice', 'name': 'Alice'},
        ]).importMembersOnly();

        final row = (await db.membersDao.getAllMembers()).single;
        expect(
          row.proxyTagsJson,
          isNotNull,
          reason: 'Must not clobber local proxy tags when PK omits the field',
        );
        final decoded = jsonDecode(row.proxyTagsJson!) as List;
        expect(decoded, hasLength(1));
      },
    );

    test('update: banner URL is written on re-import', () async {
      PluralKitSyncService build(List<Map<String, dynamic>> members) =>
          PluralKitSyncService(
            memberRepository: DriftMemberRepository(db.membersDao, null),
            frontingSessionRepository: DriftFrontingSessionRepository(
              db.frontingSessionsDao,
              null,
            ),
            syncDao: db.pluralKitSyncDao,
            tokenOverride: 't',
            clientFactory: (_) => _mockClient(
              system: {'id': 'sys1', 'name': 'Test'},
              members: members,
            ),
            bannerCacheService: _testBannerCacheService(),
          );

      // First import — no banner.
      await build([
        {'id': 'aaaaa', 'uuid': 'u-alice', 'name': 'Alice'},
      ]).importMembersOnly();
      expect((await db.membersDao.getAllMembers()).single.pkBannerUrl, isNull);

      // Second import — PK now has a banner.
      await build([
        {
          'id': 'aaaaa',
          'uuid': 'u-alice',
          'name': 'Alice',
          'banner': 'https://cdn.example.com/banner.png',
        },
      ]).importMembersOnly();

      expect(
        (await db.membersDao.getAllMembers()).single.pkBannerUrl,
        'https://cdn.example.com/banner.png',
      );
      final row = (await db.membersDao.getAllMembers()).single;
      expect(
        row.profileHeaderSource,
        MemberProfileHeaderSource.pluralKit.index,
      );
      expect(row.pkBannerImageData, Uint8List.fromList([1, 2, 3]));
      expect(row.pkBannerCachedUrl, 'https://cdn.example.com/banner.png');
    });

    test(
      'update: new banner auto-selects PluralKit unless Prism header exists',
      () async {
        PluralKitSyncService build(List<Map<String, dynamic>> members) =>
            PluralKitSyncService(
              memberRepository: DriftMemberRepository(db.membersDao, null),
              frontingSessionRepository: DriftFrontingSessionRepository(
                db.frontingSessionsDao,
                null,
              ),
              syncDao: db.pluralKitSyncDao,
              tokenOverride: 't',
              clientFactory: (_) => _mockClient(
                system: {'id': 'sys1', 'name': 'Test'},
                members: members,
              ),
              bannerCacheService: _testBannerCacheService(),
            );

        await build([
          {'id': 'aaaaa', 'uuid': 'u-alice', 'name': 'Alice'},
        ]).importMembersOnly();

        await build([
          {
            'id': 'aaaaa',
            'uuid': 'u-alice',
            'name': 'Alice',
            'banner': 'https://cdn.example.com/banner.png',
          },
        ]).importMembersOnly();

        var row = (await db.membersDao.getAllMembers()).single;
        expect(
          row.profileHeaderSource,
          MemberProfileHeaderSource.pluralKit.index,
        );

        await (db.update(
          db.members,
        )..where((m) => m.pluralkitUuid.equals('u-alice'))).write(
          MembersCompanion(
            profileHeaderSource: Value(MemberProfileHeaderSource.prism.index),
            profileHeaderVisible: const Value(false),
            profileHeaderImageData: Value(Uint8List.fromList([9, 8, 7])),
          ),
        );

        await build([
          {
            'id': 'aaaaa',
            'uuid': 'u-alice',
            'name': 'Alice',
            'banner': 'https://cdn.example.com/new-banner.png',
          },
        ]).importMembersOnly();

        row = (await db.membersDao.getAllMembers()).single;
        expect(row.profileHeaderSource, MemberProfileHeaderSource.prism.index);
        expect(row.profileHeaderVisible, isFalse);
        expect(row.profileHeaderImageData, Uint8List.fromList([9, 8, 7]));
        expect(row.pkBannerUrl, 'https://cdn.example.com/new-banner.png');
        expect(row.pkBannerCachedUrl, 'https://cdn.example.com/new-banner.png');
      },
    );

    test(
      'update: missing banner on subsequent import preserves existing URL',
      () async {
        PluralKitSyncService build(List<Map<String, dynamic>> members) =>
            PluralKitSyncService(
              memberRepository: DriftMemberRepository(db.membersDao, null),
              frontingSessionRepository: DriftFrontingSessionRepository(
                db.frontingSessionsDao,
                null,
              ),
              syncDao: db.pluralKitSyncDao,
              tokenOverride: 't',
              clientFactory: (_) => _mockClient(
                system: {'id': 'sys1', 'name': 'Test'},
                members: members,
              ),
              bannerCacheService: _testBannerCacheService(),
            );

        // First import sets a banner URL.
        await build([
          {
            'id': 'aaaaa',
            'uuid': 'u-alice',
            'name': 'Alice',
            'banner': 'https://cdn.example.com/banner.png',
          },
        ]).importMembersOnly();

        // Second import: PK omits banner (e.g. privacy scope).
        // The locally-stored URL must not be wiped.
        await build([
          {'id': 'aaaaa', 'uuid': 'u-alice', 'name': 'Alice'},
        ]).importMembersOnly();

        final row = (await db.membersDao.getAllMembers()).single;
        expect(
          row.pkBannerUrl,
          'https://cdn.example.com/banner.png',
          reason: 'Must not clobber pkBannerUrl when PK omits the field',
        );
        expect(
          row.pkBannerImageData,
          Uint8List.fromList([1, 2, 3]),
          reason:
              'Must not clobber cached banner bytes when PK omits the field',
        );
        expect(
          row.pkBannerCachedUrl,
          'https://cdn.example.com/banner.png',
          reason: 'Must not clobber cached banner URL when PK omits the field',
        );
      },
    );
  });
}
