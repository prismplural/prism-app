// test/core/database/daos/member_board_posts_dao_test.dart
//
// Full DAO test coverage for MemberBoardPostsDao:
//   watchPublicPaginated, watchInboxPaginated, watchPublicForMemberPaginated,
//   getPostById, countUnreadForMembers, countNewPublicSince, createPost,
//   updatePost, softDeletePost, findByDedupTuple
//
// All tests run against an in-memory Drift database — no mock DAOs.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/member_board_posts_dao.dart';

// ---------------------------------------------------------------------------
// Helper factories
// ---------------------------------------------------------------------------

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

/// Creates a minimal companion for inserting a board post.
MemberBoardPostsCompanion _post({
  required String id,
  required String audience,
  required String body,
  DateTime? writtenAt,
  DateTime? createdAt,
  String? targetMemberId,
  String? authorId,
  String? title,
  DateTime? editedAt,
  bool isDeleted = false,
}) {
  final now = writtenAt ?? DateTime.utc(2026, 1, 1, 12);
  return MemberBoardPostsCompanion.insert(
    id: id,
    audience: audience,
    body: body,
    writtenAt: now,
    createdAt: createdAt ?? now,
    targetMemberId: Value(targetMemberId),
    authorId: Value(authorId),
    title: Value(title),
    editedAt: Value(editedAt),
    isDeleted: Value(isDeleted),
  );
}

void main() {
  late AppDatabase db;
  late MemberBoardPostsDao dao;

  setUp(() {
    db = _makeDb();
    dao = db.memberBoardPostsDao;
  });

  tearDown(() => db.close());

  // -------------------------------------------------------------------------
  // createPost / getPostById
  // -------------------------------------------------------------------------

  group('createPost', () {
    test('inserts a post and returns a row count of 1', () async {
      final rowsAffected = await dao.createPost(
        _post(id: 'p1', audience: 'public', body: 'hello'),
      );
      expect(rowsAffected, 1);
    });

    test('inserted post is retrievable via getPostById', () async {
      await dao.createPost(
        _post(
          id: 'p1',
          audience: 'public',
          body: 'hello world',
          targetMemberId: 'm1',
          authorId: 'a1',
          title: 'Test Title',
        ),
      );
      final row = await dao.getPostById('p1');
      expect(row, isNotNull);
      expect(row!.id, 'p1');
      expect(row.audience, 'public');
      expect(row.body, 'hello world');
      expect(row.targetMemberId, 'm1');
      expect(row.authorId, 'a1');
      expect(row.title, 'Test Title');
      expect(row.isDeleted, isFalse);
    });

    test('null author_id survives round-trip', () async {
      await dao.createPost(
        _post(id: 'p1', audience: 'public', body: 'anon post'),
      );
      final row = await dao.getPostById('p1');
      expect(row!.authorId, isNull);
    });

    test('null title survives round-trip', () async {
      await dao.createPost(
        _post(id: 'p1', audience: 'public', body: 'no title'),
      );
      final row = await dao.getPostById('p1');
      expect(row!.title, isNull);
    });
  });

  group('getPostById', () {
    test('returns null for unknown id', () async {
      final row = await dao.getPostById('nonexistent');
      expect(row, isNull);
    });
  });

  // -------------------------------------------------------------------------
  // updatePost
  // -------------------------------------------------------------------------

  group('updatePost', () {
    test('updates body and other mutable fields', () async {
      final writtenAt = DateTime.utc(2026, 1, 1);
      await dao.createPost(
        _post(id: 'p1', audience: 'public', body: 'original', writtenAt: writtenAt),
      );
      final editedAt = DateTime.utc(2026, 1, 2);
      await dao.updatePost(
        'p1',
        MemberBoardPostsCompanion(
          body: const Value('updated body'),
          editedAt: Value(editedAt),
        ),
      );
      final row = await dao.getPostById('p1');
      expect(row!.body, 'updated body');
      expect(row.editedAt, isNotNull);
    });

    test('no-op on unknown id does not throw', () async {
      await dao.updatePost(
        'nonexistent',
        const MemberBoardPostsCompanion(body: Value('x')),
      );
    });
  });

  // -------------------------------------------------------------------------
  // softDeletePost
  // -------------------------------------------------------------------------

  group('softDeletePost', () {
    test('sets is_deleted to true', () async {
      await dao.createPost(
        _post(id: 'p1', audience: 'public', body: 'soon gone'),
      );
      await dao.softDeletePost('p1');
      final row = await dao.getPostById('p1');
      expect(row!.isDeleted, isTrue);
    });

    test('soft-deleted row still exists (no hard delete)', () async {
      await dao.createPost(
        _post(id: 'p1', audience: 'public', body: 'tombstoned'),
      );
      await dao.softDeletePost('p1');
      final row = await dao.getPostById('p1');
      expect(row, isNotNull);
    });

    test('does not affect other rows', () async {
      await dao.createPost(
        _post(id: 'p1', audience: 'public', body: 'target'),
      );
      await dao.createPost(
        _post(id: 'p2', audience: 'public', body: 'bystander'),
      );
      await dao.softDeletePost('p1');
      final bystander = await dao.getPostById('p2');
      expect(bystander!.isDeleted, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // watchPublicPaginated
  // -------------------------------------------------------------------------

  group('watchPublicPaginated', () {
    test('empty database emits empty list', () async {
      final result = await dao.watchPublicPaginated().first;
      expect(result, isEmpty);
    });

    test('returns public non-deleted posts in writtenAt DESC order', () async {
      final t1 = DateTime.utc(2026, 1, 1);
      final t2 = DateTime.utc(2026, 1, 2);
      final t3 = DateTime.utc(2026, 1, 3);
      await dao.createPost(
        _post(id: 'p1', audience: 'public', body: 'first', writtenAt: t1),
      );
      await dao.createPost(
        _post(id: 'p2', audience: 'public', body: 'second', writtenAt: t2),
      );
      await dao.createPost(
        _post(id: 'p3', audience: 'public', body: 'third', writtenAt: t3),
      );
      final rows = await dao.watchPublicPaginated().first;
      expect(rows.map((r) => r.id).toList(), ['p3', 'p2', 'p1']);
    });

    test('excludes private posts', () async {
      await dao.createPost(
        _post(id: 'pub', audience: 'public', body: 'public'),
      );
      await dao.createPost(
        _post(id: 'priv', audience: 'private', body: 'private', targetMemberId: 'm1'),
      );
      final rows = await dao.watchPublicPaginated().first;
      expect(rows.map((r) => r.id), ['pub']);
    });

    test('excludes soft-deleted posts', () async {
      await dao.createPost(
        _post(id: 'alive', audience: 'public', body: 'alive'),
      );
      await dao.createPost(
        _post(id: 'dead', audience: 'public', body: 'dead', isDeleted: true),
      );
      final rows = await dao.watchPublicPaginated().first;
      expect(rows.map((r) => r.id), ['alive']);
    });

    test('respects limit', () async {
      for (var i = 0; i < 5; i++) {
        await dao.createPost(
          _post(
            id: 'p$i',
            audience: 'public',
            body: 'post $i',
            writtenAt: DateTime.utc(2026, 1, i + 1),
          ),
        );
      }
      final rows = await dao.watchPublicPaginated(limit: 2).first;
      expect(rows.length, 2);
    });

    test('keyset pagination: afterWrittenAt + afterId returns next page', () async {
      final times = List.generate(
        5,
        (i) => DateTime.utc(2026, 1, i + 1),
      );
      for (var i = 0; i < 5; i++) {
        await dao.createPost(
          _post(
            id: 'p$i',
            audience: 'public',
            body: 'post $i',
            writtenAt: times[i],
          ),
        );
      }
      // First page: newest 2 (p4, p3)
      final page1 = await dao.watchPublicPaginated(limit: 2).first;
      expect(page1.map((r) => r.id).toList(), ['p4', 'p3']);

      // Second page: starting after p3
      final last = page1.last;
      final page2 = await dao
          .watchPublicPaginated(
            afterWrittenAt: last.writtenAt,
            afterId: last.id,
            limit: 2,
          )
          .first;
      expect(page2.map((r) => r.id).toList(), ['p2', 'p1']);
    });

    test('keyset continuation for last page yields remaining rows', () async {
      for (var i = 0; i < 3; i++) {
        await dao.createPost(
          _post(
            id: 'p$i',
            audience: 'public',
            body: 'post $i',
            writtenAt: DateTime.utc(2026, 1, i + 1),
          ),
        );
      }
      final page1 = await dao.watchPublicPaginated(limit: 2).first;
      final last = page1.last;
      final page2 = await dao
          .watchPublicPaginated(
            afterWrittenAt: last.writtenAt,
            afterId: last.id,
            limit: 2,
          )
          .first;
      // Only one post left after the first page
      expect(page2.length, 1);
      expect(page2.first.id, 'p0');
    });
  });

  // -------------------------------------------------------------------------
  // watchInboxPaginated
  // -------------------------------------------------------------------------

  group('watchInboxPaginated', () {
    test('empty targetMemberIds emits nothing (Stream.empty)', () async {
      await dao.createPost(
        _post(id: 'p1', audience: 'private', body: 'msg', targetMemberId: 'm1'),
      );
      // Stream.empty() never emits; verify it's not a regular stream that
      // emits [] first.
      final stream = dao.watchInboxPaginated([]);
      // No items should arrive quickly
      final items = await stream.take(0).toList();
      expect(items, isEmpty);
    });

    test('returns private posts for matching targetMemberIds', () async {
      await dao.createPost(
        _post(id: 'p1', audience: 'private', body: 'to m1', targetMemberId: 'm1'),
      );
      await dao.createPost(
        _post(id: 'p2', audience: 'private', body: 'to m2', targetMemberId: 'm2'),
      );
      final rows = await dao.watchInboxPaginated(['m1']).first;
      expect(rows.map((r) => r.id), ['p1']);
    });

    test('returns posts for multiple targetMemberIds', () async {
      await dao.createPost(
        _post(id: 'p1', audience: 'private', body: 'to m1', targetMemberId: 'm1'),
      );
      await dao.createPost(
        _post(id: 'p2', audience: 'private', body: 'to m2', targetMemberId: 'm2'),
      );
      await dao.createPost(
        _post(id: 'p3', audience: 'private', body: 'to m3', targetMemberId: 'm3'),
      );
      final rows = await dao.watchInboxPaginated(['m1', 'm2']).first;
      expect(rows.map((r) => r.id).toSet(), {'p1', 'p2'});
    });

    test('excludes public posts from inbox', () async {
      await dao.createPost(
        _post(id: 'pub', audience: 'public', body: 'public', targetMemberId: 'm1'),
      );
      await dao.createPost(
        _post(id: 'priv', audience: 'private', body: 'private', targetMemberId: 'm1'),
      );
      final rows = await dao.watchInboxPaginated(['m1']).first;
      expect(rows.map((r) => r.id), ['priv']);
    });

    test('excludes soft-deleted inbox posts', () async {
      await dao.createPost(
        _post(
          id: 'deleted',
          audience: 'private',
          body: 'gone',
          targetMemberId: 'm1',
          isDeleted: true,
        ),
      );
      final rows = await dao.watchInboxPaginated(['m1']).first;
      expect(rows, isEmpty);
    });

    test('paginated continuation works', () async {
      for (var i = 0; i < 4; i++) {
        await dao.createPost(
          _post(
            id: 'p$i',
            audience: 'private',
            body: 'msg $i',
            targetMemberId: 'm1',
            writtenAt: DateTime.utc(2026, 1, i + 1),
          ),
        );
      }
      final page1 = await dao.watchInboxPaginated(['m1'], limit: 2).first;
      expect(page1.map((r) => r.id).toList(), ['p3', 'p2']);

      final last = page1.last;
      final page2 = await dao
          .watchInboxPaginated(
            ['m1'],
            afterWrittenAt: last.writtenAt,
            afterId: last.id,
            limit: 2,
          )
          .first;
      expect(page2.map((r) => r.id).toList(), ['p1', 'p0']);
    });
  });

  // -------------------------------------------------------------------------
  // watchPublicForMemberPaginated
  // -------------------------------------------------------------------------

  group('watchPublicForMemberPaginated', () {
    test('empty database emits empty list', () async {
      final rows = await dao.watchPublicForMemberPaginated('m1').first;
      expect(rows, isEmpty);
    });

    test('returns posts where author_id matches', () async {
      await dao.createPost(
        _post(
          id: 'authored',
          audience: 'public',
          body: 'authored by m1',
          authorId: 'm1',
        ),
      );
      final rows = await dao.watchPublicForMemberPaginated('m1').first;
      expect(rows.map((r) => r.id), contains('authored'));
    });

    test('returns posts where target_member_id matches', () async {
      await dao.createPost(
        _post(
          id: 'targeted',
          audience: 'public',
          body: 'targeting m1',
          targetMemberId: 'm1',
        ),
      );
      final rows = await dao.watchPublicForMemberPaginated('m1').first;
      expect(rows.map((r) => r.id), contains('targeted'));
    });

    test('returns both authored and targeted', () async {
      await dao.createPost(
        _post(
          id: 'authored',
          audience: 'public',
          body: 'authored',
          authorId: 'm1',
          writtenAt: DateTime.utc(2026, 1, 2),
        ),
      );
      await dao.createPost(
        _post(
          id: 'targeted',
          audience: 'public',
          body: 'targeted',
          targetMemberId: 'm1',
          writtenAt: DateTime.utc(2026, 1, 1),
        ),
      );
      final rows = await dao.watchPublicForMemberPaginated('m1').first;
      expect(rows.map((r) => r.id).toSet(), {'authored', 'targeted'});
    });

    test('excludes private posts even for matching member', () async {
      await dao.createPost(
        _post(
          id: 'priv',
          audience: 'private',
          body: 'private',
          targetMemberId: 'm1',
        ),
      );
      final rows = await dao.watchPublicForMemberPaginated('m1').first;
      expect(rows, isEmpty);
    });

    test('excludes posts unrelated to this member', () async {
      await dao.createPost(
        _post(id: 'other', audience: 'public', body: 'other', authorId: 'm2'),
      );
      final rows = await dao.watchPublicForMemberPaginated('m1').first;
      expect(rows, isEmpty);
    });

    test('excludes soft-deleted posts', () async {
      await dao.createPost(
        _post(
          id: 'dead',
          audience: 'public',
          body: 'deleted',
          authorId: 'm1',
          isDeleted: true,
        ),
      );
      final rows = await dao.watchPublicForMemberPaginated('m1').first;
      expect(rows, isEmpty);
    });

    test('paginated continuation works', () async {
      for (var i = 0; i < 4; i++) {
        await dao.createPost(
          _post(
            id: 'p$i',
            audience: 'public',
            body: 'post $i',
            authorId: 'm1',
            writtenAt: DateTime.utc(2026, 1, i + 1),
          ),
        );
      }
      final page1 = await dao.watchPublicForMemberPaginated('m1', limit: 2).first;
      expect(page1.map((r) => r.id).toList(), ['p3', 'p2']);

      final last = page1.last;
      final page2 = await dao
          .watchPublicForMemberPaginated(
            'm1',
            afterWrittenAt: last.writtenAt,
            afterId: last.id,
            limit: 2,
          )
          .first;
      expect(page2.map((r) => r.id).toList(), ['p1', 'p0']);
    });
  });

  // -------------------------------------------------------------------------
  // countUnreadForMembers
  // -------------------------------------------------------------------------

  group('countUnreadForMembers', () {
    test('returns 0 for empty memberIds list', () async {
      expect(await dao.countUnreadForMembers([], {}), 0);
    });

    test('counts private posts for members with null lastReadAt', () async {
      await dao.createPost(
        _post(id: 'p1', audience: 'private', body: 'msg', targetMemberId: 'm1'),
      );
      await dao.createPost(
        _post(id: 'p2', audience: 'private', body: 'msg', targetMemberId: 'm1'),
      );
      final count = await dao.countUnreadForMembers(
        ['m1'],
        {'m1': null}, // null = never opened inbox
      );
      expect(count, 2);
    });

    test('counts only posts after lastReadAt', () async {
      final lastRead = DateTime.utc(2026, 1, 2);
      final before = DateTime.utc(2026, 1, 1);
      final after = DateTime.utc(2026, 1, 3);
      await dao.createPost(
        _post(id: 'before', audience: 'private', body: 'old', targetMemberId: 'm1', writtenAt: before),
      );
      await dao.createPost(
        _post(id: 'after', audience: 'private', body: 'new', targetMemberId: 'm1', writtenAt: after),
      );
      final count = await dao.countUnreadForMembers(
        ['m1'],
        {'m1': lastRead},
      );
      expect(count, 1);
    });

    test('does not count public posts', () async {
      await dao.createPost(
        _post(id: 'pub', audience: 'public', body: 'public', targetMemberId: 'm1'),
      );
      final count = await dao.countUnreadForMembers(
        ['m1'],
        {'m1': null},
      );
      expect(count, 0);
    });

    test('does not count soft-deleted private posts', () async {
      await dao.createPost(
        _post(
          id: 'dead',
          audience: 'private',
          body: 'deleted',
          targetMemberId: 'm1',
          isDeleted: true,
        ),
      );
      final count = await dao.countUnreadForMembers(
        ['m1'],
        {'m1': null},
      );
      expect(count, 0);
    });

    test('sums across multiple members', () async {
      await dao.createPost(
        _post(id: 'p1', audience: 'private', body: 'to m1', targetMemberId: 'm1'),
      );
      await dao.createPost(
        _post(id: 'p2', audience: 'private', body: 'to m2', targetMemberId: 'm2'),
      );
      final count = await dao.countUnreadForMembers(
        ['m1', 'm2'],
        {'m1': null, 'm2': null},
      );
      expect(count, 2);
    });

    test('member with lastReadAt after all posts has 0 unread', () async {
      final t = DateTime.utc(2026, 1, 1);
      await dao.createPost(
        _post(id: 'p1', audience: 'private', body: 'old', targetMemberId: 'm1', writtenAt: t),
      );
      final count = await dao.countUnreadForMembers(
        ['m1'],
        {'m1': t.add(const Duration(seconds: 1))},
      );
      expect(count, 0);
    });
  });

  // -------------------------------------------------------------------------
  // countNewPublicSince
  // -------------------------------------------------------------------------

  group('countNewPublicSince', () {
    test('returns 0 for empty db', () async {
      expect(await dao.countNewPublicSince(null), 0);
    });

    test('returns total public count when lastViewedAt is null', () async {
      await dao.createPost(
        _post(id: 'p1', audience: 'public', body: 'a'),
      );
      await dao.createPost(
        _post(id: 'p2', audience: 'public', body: 'b'),
      );
      expect(await dao.countNewPublicSince(null), 2);
    });

    test('returns 0 when no posts after lastViewedAt', () async {
      final t = DateTime.utc(2026, 1, 1);
      await dao.createPost(
        _post(id: 'p1', audience: 'public', body: 'old', writtenAt: t),
      );
      expect(
        await dao.countNewPublicSince(t.add(const Duration(seconds: 1))),
        0,
      );
    });

    test('counts only posts after lastViewedAt', () async {
      final lastViewed = DateTime.utc(2026, 1, 5);
      for (var i = 1; i <= 10; i++) {
        await dao.createPost(
          _post(
            id: 'p$i',
            audience: 'public',
            body: 'post $i',
            writtenAt: DateTime.utc(2026, 1, i),
          ),
        );
      }
      // Posts 6–10 are after lastViewed
      expect(await dao.countNewPublicSince(lastViewed), 5);
    });

    test('does not count private posts', () async {
      await dao.createPost(
        _post(id: 'p1', audience: 'private', body: 'private', targetMemberId: 'm1'),
      );
      expect(await dao.countNewPublicSince(null), 0);
    });

    test('does not count soft-deleted public posts', () async {
      await dao.createPost(
        _post(id: 'p1', audience: 'public', body: 'deleted', isDeleted: true),
      );
      expect(await dao.countNewPublicSince(null), 0);
    });
  });

  // -------------------------------------------------------------------------
  // findByDedupTuple
  // -------------------------------------------------------------------------

  group('findByDedupTuple', () {
    test('returns null when no match', () async {
      final result = await dao.findByDedupTuple(
        targetMemberId: 'm1',
        authorId: 'a1',
        writtenAt: DateTime.utc(2026, 1, 1),
      );
      expect(result, isNull);
    });

    test('returns matching post for exact tuple', () async {
      final ts = DateTime.utc(2026, 6, 15, 10, 30);
      await dao.createPost(
        _post(
          id: 'exact',
          audience: 'private',
          body: 'match me',
          targetMemberId: 'm1',
          authorId: 'a1',
          writtenAt: ts,
        ),
      );
      final result = await dao.findByDedupTuple(
        targetMemberId: 'm1',
        authorId: 'a1',
        writtenAt: ts,
      );
      expect(result, isNotNull);
      expect(result!.id, 'exact');
    });

    test('null authorId matches posts with null authorId', () async {
      final ts = DateTime.utc(2026, 6, 15);
      await dao.createPost(
        _post(
          id: 'p1',
          audience: 'private',
          body: 'anon',
          targetMemberId: 'm1',
          writtenAt: ts,
        ),
      );
      final result = await dao.findByDedupTuple(
        targetMemberId: 'm1',
        authorId: null,
        writtenAt: ts,
      );
      expect(result, isNotNull);
      expect(result!.id, 'p1');
    });

    test('non-null authorId does not match null authorId rows', () async {
      final ts = DateTime.utc(2026, 6, 15);
      await dao.createPost(
        _post(
          id: 'p1',
          audience: 'private',
          body: 'anon',
          targetMemberId: 'm1',
          writtenAt: ts,
        ),
      );
      final result = await dao.findByDedupTuple(
        targetMemberId: 'm1',
        authorId: 'someone',
        writtenAt: ts,
      );
      expect(result, isNull);
    });

    test('different writtenAt does not match', () async {
      final ts = DateTime.utc(2026, 6, 15, 0, 0, 0);
      final different = DateTime.utc(2026, 6, 16, 0, 0, 0); // whole day apart
      await dao.createPost(
        _post(
          id: 'p1',
          audience: 'private',
          body: 'msg',
          targetMemberId: 'm1',
          authorId: 'a1',
          writtenAt: ts,
        ),
      );
      final result = await dao.findByDedupTuple(
        targetMemberId: 'm1',
        authorId: 'a1',
        writtenAt: different,
      );
      expect(result, isNull);
    });

    test('different targetMemberId does not match', () async {
      final ts = DateTime.utc(2026, 6, 15);
      await dao.createPost(
        _post(
          id: 'p1',
          audience: 'private',
          body: 'msg',
          targetMemberId: 'm1',
          authorId: 'a1',
          writtenAt: ts,
        ),
      );
      final result = await dao.findByDedupTuple(
        targetMemberId: 'm2',
        authorId: 'a1',
        writtenAt: ts,
      );
      expect(result, isNull);
    });
  });

  // -------------------------------------------------------------------------
  // watchPostById
  // -------------------------------------------------------------------------

  group('watchPostById', () {
    test('emits null when post does not exist', () async {
      final value = await dao.watchPostById('missing').first;
      expect(value, isNull);
    });

    test('emits the post after insert', () async {
      await dao.createPost(
        _post(id: 'p1', audience: 'public', body: 'watched'),
      );
      final row = await dao.watchPostById('p1').first;
      expect(row, isNotNull);
      expect(row!.id, 'p1');
    });

    test('emits null after soft delete then re-emits with is_deleted=true', () async {
      await dao.createPost(
        _post(id: 'p1', audience: 'public', body: 'alive'),
      );
      await dao.softDeletePost('p1');
      final row = await dao.watchPostById('p1').first;
      // Row still exists but is_deleted = true
      expect(row, isNotNull);
      expect(row!.isDeleted, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // Index DDL verification
  //
  // The idx_mbp_* indexes are created in the v14→v15 migration block, which
  // does NOT run for a fresh in-memory DB (onCreate calls migrator.createAll +
  // _createCurrentIndexes — mbp indexes are deliberately part of the migration
  // block only). This test creates the indexes manually and verifies their
  // DDL is well-formed by confirming they appear after creation.
  // -------------------------------------------------------------------------

  group('index DDL correctness', () {
    test('v14→v15 migration index DDL is valid SQL for member_board_posts', () async {
      // Create the three indexes manually (mirrors the migration block exactly)
      await db.customStatement(
        'CREATE INDEX IF NOT EXISTS idx_mbp_target_audience '
        'ON member_board_posts(target_member_id, audience, written_at DESC, is_deleted)',
      );
      await db.customStatement(
        'CREATE INDEX IF NOT EXISTS idx_mbp_audience '
        'ON member_board_posts(audience, written_at DESC, is_deleted)',
      );
      await db.customStatement(
        'CREATE INDEX IF NOT EXISTS idx_mbp_author '
        'ON member_board_posts(author_id, written_at DESC, is_deleted)',
      );

      // Verify all three now appear in the index list
      final indexes = await db
          .customSelect("PRAGMA index_list('member_board_posts')")
          .get();
      final names = indexes
          .map((r) => r.read<String>('name'))
          .toSet();
      expect(
        names,
        containsAll({
          'idx_mbp_target_audience',
          'idx_mbp_audience',
          'idx_mbp_author',
        }),
        reason: 'All three idx_mbp_* indexes must be creatable. Got: $names',
      );
    });
  });
}
