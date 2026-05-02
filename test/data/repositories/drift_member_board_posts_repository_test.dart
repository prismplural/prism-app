// test/data/repositories/drift_member_board_posts_repository_test.dart
//
// Tests for DriftMemberBoardPostsRepository:
//   - createPost emits expected _postFields map via debugPostFields
//   - updatePost emits syncRecordUpdate (field contents)
//   - softDeletePost flips is_deleted (NOT a hard delete; emits update)
//   - markInboxOpenedFor writes boardLastReadAt for each member transactionally
//   - Round-trip: create on device A → marshal via _postFields →
//       apply via _memberBoardPostsEntity.applyFields on device B →
//       all fields including null author_id and null title survive
//   - audience forward-compat fallback: unknown audience → applied as 'public'

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/member_board_posts_dao.dart';
import 'package:prism_plurality/core/database/daos/members_dao.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';
import 'package:prism_plurality/data/repositories/drift_member_board_posts_repository.dart';
import 'package:prism_plurality/domain/models/member_board_post.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

MemberBoardPost _post({
  String id = 'p1',
  String audience = 'public',
  String body = 'hello world',
  String? targetMemberId,
  String? authorId,
  String? title,
  DateTime? createdAt,
  DateTime? writtenAt,
  DateTime? editedAt,
  bool isDeleted = false,
}) {
  final now = createdAt ?? DateTime.utc(2026, 1, 1, 12);
  return MemberBoardPost(
    id: id,
    audience: audience,
    body: body,
    targetMemberId: targetMemberId,
    authorId: authorId,
    title: title,
    createdAt: now,
    writtenAt: writtenAt ?? now,
    editedAt: editedAt,
    isDeleted: isDeleted,
  );
}

/// Insert a minimal member row so boardLastReadAt can be written.
Future<void> _insertMember(AppDatabase db, String memberId) async {
  await db.into(db.members).insert(
    MembersCompanion.insert(
      id: memberId,
      name: memberId,
      createdAt: DateTime.utc(2026, 1, 1),
    ),
  );
}

void main() {
  late AppDatabase db;
  late MemberBoardPostsDao dao;
  late MembersDao membersDao;
  late DriftMemberBoardPostsRepository repo;

  setUp(() {
    db = _makeDb();
    dao = db.memberBoardPostsDao;
    membersDao = db.membersDao;
    // null sync handle → syncRecord* calls are no-ops (handle == null short-circuits)
    repo = DriftMemberBoardPostsRepository(dao, membersDao, null);
  });

  tearDown(() => db.close());

  // -------------------------------------------------------------------------
  // debugPostFields — emitted field map
  // -------------------------------------------------------------------------

  group('debugPostFields (sync field map)', () {
    test('emits all required keys', () {
      final post = _post();
      final fields = repo.debugPostFields(post);
      expect(
        fields.keys.toSet(),
        containsAll({
          'target_member_id',
          'author_id',
          'audience',
          'title',
          'body',
          'created_at',
          'written_at',
          'edited_at',
          'is_deleted',
        }),
      );
    });

    test('emits correct values for non-null fields', () {
      final writtenAt = DateTime.utc(2026, 3, 15, 9, 0, 0);
      final createdAt = DateTime.utc(2026, 3, 15, 8, 0, 0);
      final post = _post(
        id: 'p42',
        audience: 'private',
        body: 'test body',
        targetMemberId: 'm_target',
        authorId: 'a_author',
        title: 'My Title',
        createdAt: createdAt,
        writtenAt: writtenAt,
      );
      final fields = repo.debugPostFields(post);
      expect(fields['target_member_id'], 'm_target');
      expect(fields['author_id'], 'a_author');
      expect(fields['audience'], 'private');
      expect(fields['title'], 'My Title');
      expect(fields['body'], 'test body');
      expect(fields['is_deleted'], isFalse);
    });

    test('null author_id emits null (not absent)', () {
      final post = _post(authorId: null);
      final fields = repo.debugPostFields(post);
      expect(fields.containsKey('author_id'), isTrue);
      expect(fields['author_id'], isNull);
    });

    test('null title emits null (not absent)', () {
      final post = _post(title: null);
      final fields = repo.debugPostFields(post);
      expect(fields.containsKey('title'), isTrue);
      expect(fields['title'], isNull);
    });

    test('null edited_at emits null (not absent)', () {
      final post = _post(editedAt: null);
      final fields = repo.debugPostFields(post);
      expect(fields.containsKey('edited_at'), isTrue);
      expect(fields['edited_at'], isNull);
    });

    test('non-null edited_at emits UTC ISO string', () {
      final edited = DateTime.utc(2026, 4, 1, 11, 22, 33);
      final post = _post(editedAt: edited);
      final fields = repo.debugPostFields(post);
      final editedStr = fields['edited_at'] as String;
      expect(editedStr.endsWith('Z'), isTrue, reason: editedStr);
      expect(DateTime.parse(editedStr).isAtSameMomentAs(edited), isTrue);
    });

    test('is_deleted=true emits true', () {
      final post = _post(isDeleted: true);
      final fields = repo.debugPostFields(post);
      expect(fields['is_deleted'], isTrue);
    });

    test('created_at and written_at emit Z-suffixed UTC strings', () {
      final local = DateTime(2026, 5, 1, 10, 0, 0); // local (non-UTC)
      final post = _post(createdAt: local, writtenAt: local);
      final fields = repo.debugPostFields(post);
      final createdStr = fields['created_at'] as String;
      final writtenStr = fields['written_at'] as String;
      expect(createdStr.endsWith('Z'), isTrue, reason: createdStr);
      expect(writtenStr.endsWith('Z'), isTrue, reason: writtenStr);
      expect(
        DateTime.parse(createdStr).isAtSameMomentAs(local.toUtc()),
        isTrue,
      );
    });
  });

  // -------------------------------------------------------------------------
  // createPost
  // -------------------------------------------------------------------------

  group('createPost', () {
    test('persists row to the database', () async {
      final post = _post(id: 'p1');
      await repo.createPost(post);
      final row = await dao.getPostById('p1');
      expect(row, isNotNull);
      expect(row!.body, 'hello world');
    });

    test('persists null author_id', () async {
      await repo.createPost(_post(id: 'p1', authorId: null));
      final row = await dao.getPostById('p1');
      expect(row!.authorId, isNull);
    });

    test('persists null title', () async {
      await repo.createPost(_post(id: 'p1', title: null));
      final row = await dao.getPostById('p1');
      expect(row!.title, isNull);
    });
  });

  // -------------------------------------------------------------------------
  // updatePost
  // -------------------------------------------------------------------------

  group('updatePost', () {
    test('updates the body in the database', () async {
      await repo.createPost(_post(id: 'p1', body: 'original'));
      final edited = _post(
        id: 'p1',
        body: 'updated',
        editedAt: DateTime.utc(2026, 2, 1),
      );
      await repo.updatePost(edited);
      final row = await dao.getPostById('p1');
      expect(row!.body, 'updated');
      expect(row.editedAt, isNotNull);
    });

    test('can update audience and target', () async {
      await repo.createPost(
        _post(id: 'p1', audience: 'public', body: 'original'),
      );
      await repo.updatePost(
        _post(
          id: 'p1',
          audience: 'private',
          body: 'private now',
          targetMemberId: 'm1',
        ),
      );
      final row = await dao.getPostById('p1');
      expect(row!.audience, 'private');
      expect(row.targetMemberId, 'm1');
    });
  });

  // -------------------------------------------------------------------------
  // softDeletePost
  // -------------------------------------------------------------------------

  group('softDeletePost', () {
    test('sets is_deleted to true (soft delete, not hard delete)', () async {
      await repo.createPost(_post(id: 'p1'));
      await repo.softDeletePost('p1');
      final row = await dao.getPostById('p1');
      // Row must still exist (soft delete, not hard delete)
      expect(row, isNotNull);
      expect(row!.isDeleted, isTrue);
    });

    test('row remains in the database after soft delete', () async {
      await repo.createPost(_post(id: 'p1', body: 'body'));
      await repo.softDeletePost('p1');
      final row = await dao.getPostById('p1');
      expect(row, isNotNull);
      // Body is preserved
      expect(row!.body, 'body');
    });
  });

  // -------------------------------------------------------------------------
  // markInboxOpenedFor
  // -------------------------------------------------------------------------

  group('markInboxOpenedFor', () {
    test('no-op for empty list', () async {
      // Should not throw
      await repo.markInboxOpenedFor([]);
    });

    test('writes boardLastReadAt for a single member', () async {
      await _insertMember(db, 'm1');
      await repo.markInboxOpenedFor(['m1']);
      final member = await membersDao.getMemberById('m1');
      expect(member!.boardLastReadAt, isNotNull);
    });

    test('writes boardLastReadAt for multiple members atomically', () async {
      await _insertMember(db, 'm1');
      await _insertMember(db, 'm2');
      await _insertMember(db, 'm3');

      await repo.markInboxOpenedFor(['m1', 'm2', 'm3']);

      final m1 = await membersDao.getMemberById('m1');
      final m2 = await membersDao.getMemberById('m2');
      final m3 = await membersDao.getMemberById('m3');

      expect(m1!.boardLastReadAt, isNotNull);
      expect(m2!.boardLastReadAt, isNotNull);
      expect(m3!.boardLastReadAt, isNotNull);
    });

    test('boardLastReadAt is recent (within 5s of now)', () async {
      await _insertMember(db, 'm1');
      final before = DateTime.now().toUtc().subtract(const Duration(seconds: 1));
      await repo.markInboxOpenedFor(['m1']);
      final after = DateTime.now().toUtc().add(const Duration(seconds: 5));

      final member = await membersDao.getMemberById('m1');
      final ts = member!.boardLastReadAt!.toUtc();
      expect(ts.isAfter(before), isTrue);
      expect(ts.isBefore(after), isTrue);
    });

    test('unknown member id does not throw (member not found is silently skipped)', () async {
      // MembersDao.updateMember only writes if the member exists;
      // no exception expected for missing member.
      await expectLater(
        repo.markInboxOpenedFor(['no-such-member']),
        completes,
      );
    });
  });

  // -------------------------------------------------------------------------
  // Round-trip: device A creates → _postFields → applyFields device B
  // -------------------------------------------------------------------------

  group('round-trip apply via drift_sync_adapter', () {
    test(
      'all fields including null author_id and null title survive the round-trip',
      () async {
        // Device A: create a post with null author_id and null title
        final deviceA = _makeDb();
        addTearDown(deviceA.close);
        final repoA = DriftMemberBoardPostsRepository(
          deviceA.memberBoardPostsDao,
          deviceA.membersDao,
          null,
        );

        final writtenAt = DateTime.utc(2026, 6, 1, 8, 0, 0);
        final createdAt = DateTime.utc(2026, 6, 1, 7, 0, 0);
        final postA = MemberBoardPost(
          id: 'rt-post-1',
          targetMemberId: 'member-target',
          authorId: null, // null author
          audience: 'private',
          title: null, // null title
          body: 'round-trip body',
          createdAt: createdAt,
          writtenAt: writtenAt,
          editedAt: null,
          isDeleted: false,
        );
        await repoA.createPost(postA);

        // Marshal fields via debugPostFields (mirrors what _postFields emits)
        final fields = repoA.debugPostFields(postA);

        // Device B: apply via the sync adapter
        final deviceB = _makeDb();
        addTearDown(deviceB.close);
        final adapterB = buildSyncAdapterWithCompletion(deviceB);
        final entity = adapterB.adapter.entities.firstWhere(
          (e) => e.tableName == 'member_board_posts',
        );
        await entity.applyFields('rt-post-1', fields);

        // Verify all fields on device B
        final rowB = await deviceB.memberBoardPostsDao.getPostById('rt-post-1');
        expect(rowB, isNotNull);
        expect(rowB!.id, 'rt-post-1');
        expect(rowB.targetMemberId, 'member-target');
        expect(rowB.authorId, isNull); // null survived
        expect(rowB.audience, 'private');
        expect(rowB.title, isNull); // null survived
        expect(rowB.body, 'round-trip body');
        expect(rowB.isDeleted, isFalse);
        expect(
          rowB.writtenAt.isAtSameMomentAs(writtenAt),
          isTrue,
          reason: 'writtenAt must survive round-trip',
        );
        expect(
          rowB.createdAt.isAtSameMomentAs(createdAt),
          isTrue,
          reason: 'createdAt must survive round-trip',
        );
        expect(rowB.editedAt, isNull);
      },
    );

    test('is_deleted=true survives round-trip', () async {
      final deviceA = _makeDb();
      addTearDown(deviceA.close);
      final repoA = DriftMemberBoardPostsRepository(
        deviceA.memberBoardPostsDao,
        deviceA.membersDao,
        null,
      );

      final post = _post(id: 'tombstone', isDeleted: true);
      await repoA.createPost(post);
      final fields = repoA.debugPostFields(post);

      final deviceB = _makeDb();
      addTearDown(deviceB.close);
      final adapterB = buildSyncAdapterWithCompletion(deviceB);
      final entity = adapterB.adapter.entities.firstWhere(
        (e) => e.tableName == 'member_board_posts',
      );
      await entity.applyFields('tombstone', fields);

      final rowB = await deviceB.memberBoardPostsDao.getPostById('tombstone');
      expect(rowB, isNotNull);
      expect(rowB!.isDeleted, isTrue);
    });

    test('non-null editedAt survives round-trip', () async {
      final editedAt = DateTime.utc(2026, 7, 4, 15, 30, 0);
      final deviceA = _makeDb();
      addTearDown(deviceA.close);
      final repoA = DriftMemberBoardPostsRepository(
        deviceA.memberBoardPostsDao,
        deviceA.membersDao,
        null,
      );

      final post = _post(id: 'edited', editedAt: editedAt);
      await repoA.createPost(post);
      final fields = repoA.debugPostFields(post);

      final deviceB = _makeDb();
      addTearDown(deviceB.close);
      final adapterB = buildSyncAdapterWithCompletion(deviceB);
      final entity = adapterB.adapter.entities.firstWhere(
        (e) => e.tableName == 'member_board_posts',
      );
      await entity.applyFields('edited', fields);

      final rowB = await deviceB.memberBoardPostsDao.getPostById('edited');
      expect(rowB!.editedAt, isNotNull);
      expect(rowB.editedAt!.isAtSameMomentAs(editedAt), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // audience forward-compat fallback
  // -------------------------------------------------------------------------

  group('audience forward-compat fallback', () {
    test(
      'unknown audience value from peer applies as "public"',
      () async {
        final deviceB = _makeDb();
        addTearDown(deviceB.close);
        final adapterB = buildSyncAdapterWithCompletion(deviceB);
        final entity = adapterB.adapter.entities.firstWhere(
          (e) => e.tableName == 'member_board_posts',
        );

        // Simulate a future-version peer sending an unknown audience
        await entity.applyFields('future-post', {
          'target_member_id': null,
          'author_id': 'a1',
          'audience': 'something_new', // unknown value
          'title': null,
          'body': 'future body',
          'created_at': '2026-01-01T00:00:00.000Z',
          'written_at': '2026-01-01T00:00:00.000Z',
          'edited_at': null,
          'is_deleted': false,
        });

        final row = await deviceB.memberBoardPostsDao.getPostById('future-post');
        expect(row, isNotNull);
        // Unknown audience → treated as 'public' per locked forward-compat rule
        expect(
          row!.audience,
          'public',
          reason:
              'Unknown audience from a future-version peer must be treated as "public"',
        );
      },
    );

    test(
      '"public" audience value passes through unchanged',
      () async {
        final deviceB = _makeDb();
        addTearDown(deviceB.close);
        final adapterB = buildSyncAdapterWithCompletion(deviceB);
        final entity = adapterB.adapter.entities.firstWhere(
          (e) => e.tableName == 'member_board_posts',
        );

        await entity.applyFields('pub-post', {
          'target_member_id': null,
          'author_id': null,
          'audience': 'public',
          'title': null,
          'body': 'a public post',
          'created_at': '2026-01-01T00:00:00.000Z',
          'written_at': '2026-01-01T00:00:00.000Z',
          'edited_at': null,
          'is_deleted': false,
        });

        final row = await deviceB.memberBoardPostsDao.getPostById('pub-post');
        expect(row!.audience, 'public');
      },
    );

    test(
      '"private" audience value passes through unchanged',
      () async {
        final deviceB = _makeDb();
        addTearDown(deviceB.close);
        final adapterB = buildSyncAdapterWithCompletion(deviceB);
        final entity = adapterB.adapter.entities.firstWhere(
          (e) => e.tableName == 'member_board_posts',
        );

        await entity.applyFields('priv-post', {
          'target_member_id': 'm1',
          'author_id': 'a1',
          'audience': 'private',
          'title': null,
          'body': 'a private post',
          'created_at': '2026-01-01T00:00:00.000Z',
          'written_at': '2026-01-01T00:00:00.000Z',
          'edited_at': null,
          'is_deleted': false,
        });

        final row = await deviceB.memberBoardPostsDao.getPostById('priv-post');
        expect(row!.audience, 'private');
      },
    );
  });

  // -------------------------------------------------------------------------
  // watchPublicPaginated / watchInboxPaginated / watchPublicForMemberPaginated
  // through the repo (mapped to domain model)
  // -------------------------------------------------------------------------

  group('read streams via repo', () {
    test('watchPublicPaginated maps rows to domain MemberBoardPost', () async {
      await repo.createPost(_post(id: 'p1', audience: 'public', body: 'hi'));
      final posts = await repo.watchPublicPaginated().first;
      expect(posts.length, 1);
      expect(posts.first, isA<MemberBoardPost>());
      expect(posts.first.id, 'p1');
    });

    test('watchInboxPaginated maps rows to domain MemberBoardPost', () async {
      await repo.createPost(
        _post(id: 'p1', audience: 'private', body: 'inbox', targetMemberId: 'm1'),
      );
      final posts = await repo.watchInboxPaginated(['m1']).first;
      expect(posts.length, 1);
      expect(posts.first, isA<MemberBoardPost>());
      expect(posts.first.id, 'p1');
    });

    test('watchPublicForMemberPaginated maps rows to domain MemberBoardPost', () async {
      await repo.createPost(
        _post(id: 'p1', audience: 'public', body: 'member post', authorId: 'm1'),
      );
      final posts = await repo.watchPublicForMemberPaginated('m1').first;
      expect(posts.length, 1);
      expect(posts.first, isA<MemberBoardPost>());
    });

    test('getPostById returns domain model', () async {
      await repo.createPost(_post(id: 'p1', body: 'fetch me'));
      final post = await repo.getPostById('p1');
      expect(post, isNotNull);
      expect(post!, isA<MemberBoardPost>());
      expect(post.id, 'p1');
    });

    test('getPostById returns null for missing id', () async {
      final post = await repo.getPostById('none');
      expect(post, isNull);
    });
  });
}
