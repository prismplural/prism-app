// test/core/services/media/bio_media_reconciler_test.dart
//
// Covers the startup bio-media orphan sweep: reconcileBioMediaOrphans.
//
// The sweep used to scan member ids and run two more queries PER member
// (2M+1 statements for M members), sequential tombstones, no yield — the
// startup cost that drove Android ANRs on large systems. These tests pin:
//
//   * the QUERY SHAPE: a bounded, set-based statement count that does NOT grow
//     with the member count (observed through a Drift QueryInterceptor, not via
//     timing),
//   * LARGE-MEMBER correctness: every orphan is tombstoned, matching rows are
//     spared, across several paged sweeps,
//   * IDEMPOTENCE: a second run tombstones nothing and emits no sync ops,
//   * the preserved SEMANTICS: exact `prism-media://` regex extraction, no
//     cross-member reference leakage, and "member row absent/soft-deleted =>
//     all of that member's bio media are orphans",
//   * the bounded sync-emission contract: exactly one `update` op per
//     tombstoned attachment, emitted through the repository seam,
//   * cooperative yielding: the injected yield hook is called during a sweep
//     that tombstones a large batch.

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/media_attachments_dao.dart';
import 'package:prism_plurality/core/services/media/bio_media_reconciler.dart';
import 'package:prism_plurality/data/repositories/drift_media_attachment_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';

void main() {
  late AppDatabase db;
  late MediaAttachmentsDao dao;
  late DriftMediaAttachmentRepository repo;
  late _RecordingSelectInterceptor interceptor;

  setUp(() {
    interceptor = _RecordingSelectInterceptor();
    db = AppDatabase(NativeDatabase.memory().interceptWith(interceptor));
    dao = MediaAttachmentsDao(db);
    // Null sync handle — the SyncRecordMixin capture sink intercepts before any
    // FFI call, so emission is observable without a live engine.
    repo = DriftMediaAttachmentRepository(dao, null);
  });

  tearDown(() async {
    SyncRecordMixin.removeCaptureSinkForTesting();
    await db.close();
  });

  // ---------------------------------------------------------------- helpers

  Future<void> seedMember(String id, {String? bio, bool isDeleted = false}) {
    return db
        .into(db.members)
        .insert(
          MembersCompanion(
            id: Value(id),
            name: Value('Member $id'),
            bio: Value(bio),
            isDeleted: Value(isDeleted),
            createdAt: Value(DateTime(2024)),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  Future<void> seedAttachment({
    required String id,
    required String memberId,
    required String mediaId,
    bool isDeleted = false,
  }) {
    return db
        .into(db.mediaAttachments)
        .insert(
          MediaAttachmentsCompanion(
            id: Value(id),
            memberId: Value(memberId),
            mediaId: Value(mediaId),
            mediaType: const Value('image'),
            isDeleted: Value(isDeleted),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  Future<List<MediaAttachment>> attachmentsFor(String memberId) {
    return (db.select(
      db.mediaAttachments,
    )..where((a) => a.memberId.equals(memberId))).get();
  }

  Future<Set<String>> deletedAttachmentIds() async {
    final rows = await (db.select(
      db.mediaAttachments,
    )..where((a) => a.isDeleted.equals(true))).get();
    return rows.map((r) => r.id).toSet();
  }

  /// Runs the sweep with the sync-emission capture sink installed and returns
  /// the captured ops alongside the deleted count.
  Future<({int deleted, List<CapturedSyncOp> ops})> runWithCapture({
    int memberPageSize = kBioMediaReconcileMemberPageSize,
    int mutationBatchSize = kBioMediaReconcileMutationBatchSize,
    Future<void> Function()? yieldControl,
  }) async {
    final ops = <CapturedSyncOp>[];
    SyncRecordMixin.installCaptureSinkForTesting(ops.add);

    final deleted = await reconcileBioMediaOrphans(
      db: db,
      repository: repo,
      log: (_) {},
      memberPageSize: memberPageSize,
      mutationBatchSize: mutationBatchSize,
      yieldControl: yieldControl,
    );

    SyncRecordMixin.removeCaptureSinkForTesting();
    return (deleted: deleted, ops: ops);
  }

  /// Counts the sweep's SELECT statements. The sweep has no writes of its own
  /// beyond the repository tombstones (which are UPDATEs), so the SELECT count
  /// is the query shape under test.
  int sweepSelects() => interceptor.selects
      .where((sql) => sql.toLowerCase().contains('media_attachments'))
      .length;

  // -------------------------------------------------------- query index

  group('reconcileBioMediaOrphans — query index', () {
    test('fresh schema creates and uses the member/deleted index', () async {
      // Force the lazy database open so the idempotent before-open index
      // backstop has run before inspecting SQLite metadata and its query plan.
      await db.customSelect('SELECT 1').get();

      final indexes = await db
          .customSelect("PRAGMA index_list('media_attachments')")
          .get();
      expect(
        indexes.map((row) => row.read<String>('name')),
        contains('idx_media_attachments_member_deleted'),
      );

      // Keep this predicate and projection aligned with
      // _loadLiveBioAttachmentsForMembers in bio_media_reconciler.dart.
      final plan = await db.customSelect('''
        EXPLAIN QUERY PLAN
        SELECT a.id AS id, a.member_id AS member_id, a.media_id AS media_id
        FROM media_attachments AS a
        WHERE a.member_id != ''
          AND a.is_deleted = 0
          AND a.member_id IN ('member-1', 'member-2')
        ORDER BY a.id
        ''').get();
      final details = plan
          .map((row) => row.read<String>('detail'))
          .join('\n')
          .toLowerCase();

      expect(
        details,
        contains('idx_media_attachments_member_deleted'),
        reason: 'SQLite must use the reconciliation composite index:\n$details',
      );
    });
  });

  // -------------------------------------------------------- basic behavior

  group('reconcileBioMediaOrphans — correctness', () {
    test('tombstones only the unreferenced bio media', () async {
      await seedMember('m1', bio: 'hello ![x](prism-media://keep-1) world');
      await seedAttachment(id: 'a-keep', memberId: 'm1', mediaId: 'keep-1');
      await seedAttachment(id: 'a-orphan', memberId: 'm1', mediaId: 'gone-1');

      final result = await runWithCapture();

      expect(result.deleted, 1);
      expect(await deletedAttachmentIds(), {'a-orphan'});
    });

    test('leaves chat and library media (empty member_id) alone', () async {
      await seedMember('m1', bio: 'no media here');
      await seedAttachment(id: 'a-chat', memberId: '', mediaId: 'chat-1');
      await seedAttachment(id: 'a-lib', memberId: '', mediaId: 'lib-1');

      final result = await runWithCapture();

      expect(result.deleted, 0);
      expect(await deletedAttachmentIds(), isEmpty);
    });

    test('no-ops cleanly when there are no bio-media rows', () async {
      final result = await runWithCapture();
      expect(result.deleted, 0);
    });

    test('spares a row referenced by a bio with no other content', () async {
      await seedMember('m1', bio: '![](prism-media://only-1)');
      await seedAttachment(id: 'a1', memberId: 'm1', mediaId: 'only-1');

      final result = await runWithCapture();
      expect(result.deleted, 0);
    });
  });

  // -------------------------------------------------- preserved semantics

  group('reconcileBioMediaOrphans — preserved reference semantics', () {
    test(
      'treats a prefix-only reference as an orphan (exact id match)',
      () async {
        // `bio` references `media-123`; the row's media_id is `media-12`. A naive
        // substring test would spare it — the exact-regex semantics must not.
        await seedMember('m1', bio: '![](prism-media://media-123)');
        await seedAttachment(
          id: 'a-prefix',
          memberId: 'm1',
          mediaId: 'media-12',
        );

        final result = await runWithCapture();

        expect(result.deleted, 1, reason: 'media-12 is not the referenced id');
        expect(await deletedAttachmentIds(), {'a-prefix'});
      },
    );

    test('does not honor a bare media id mentioned outside a URI', () async {
      // The id appears in the bio as prose, not as a prism-media:// reference.
      await seedMember('m1', bio: 'the string loose-1 is just text');
      await seedAttachment(id: 'a-loose', memberId: 'm1', mediaId: 'loose-1');

      final result = await runWithCapture();

      expect(result.deleted, 1);
      expect(await deletedAttachmentIds(), {'a-loose'});
    });

    test(
      'reference in another member\'s bio does not spare this member\'s orphan',
      () async {
        await seedMember('m1', bio: 'nothing here');
        await seedMember('m2', bio: '![](prism-media://shared-1)');
        await seedAttachment(id: 'a-m1', memberId: 'm1', mediaId: 'shared-1');
        await seedAttachment(id: 'a-m2', memberId: 'm2', mediaId: 'shared-1');

        final result = await runWithCapture();

        expect(result.deleted, 1, reason: 'per-member scoping is preserved');
        expect(await deletedAttachmentIds(), {'a-m1'});
      },
    );

    test(
      'member row absent => all of that member\'s bio media are orphans',
      () async {
        // No `members` row at all for m-ghost (attachment written then member
        // hard-deleted away).
        await seedAttachment(
          id: 'a-ghost',
          memberId: 'm-ghost',
          mediaId: 'g-1',
        );

        final result = await runWithCapture();

        expect(result.deleted, 1);
        expect(await deletedAttachmentIds(), {'a-ghost'});
      },
    );

    test(
      'soft-deleted member => all of that member\'s bio media are orphans',
      () async {
        await seedMember(
          'm1',
          bio: '![](prism-media://keep-1)',
          isDeleted: true,
        );
        await seedAttachment(id: 'a1', memberId: 'm1', mediaId: 'keep-1');

        final result = await runWithCapture();

        expect(
          result.deleted,
          1,
          reason:
              'a tombstoned member is treated as gone (old query filtered it)',
        );
        expect(await deletedAttachmentIds(), {'a1'});
      },
    );

    test('reconciles a NULL-bio member fully', () async {
      await seedMember('m1');
      await seedAttachment(id: 'a1', memberId: 'm1', mediaId: 'n-1');

      final result = await runWithCapture();

      expect(result.deleted, 1);
    });

    test(
      'already soft-deleted attachments are excluded from the scan',
      () async {
        await seedMember('m1', bio: '');
        await seedAttachment(
          id: 'a1',
          memberId: 'm1',
          mediaId: 'g-1',
          isDeleted: true,
        );

        final result = await runWithCapture();

        expect(result.deleted, 0);
        expect(await deletedAttachmentIds(), {'a1'});
      },
    );
  });

  // --------------------------------------------------------- sync emission

  group('reconcileBioMediaOrphans — sync emission contract', () {
    test(
      'emits exactly one is_deleted update per tombstoned attachment',
      () async {
        await seedMember('m1', bio: '');
        await seedMember('m2', bio: '');
        await seedAttachment(id: 'a1', memberId: 'm1', mediaId: 'g-1');
        await seedAttachment(id: 'a2', memberId: 'm1', mediaId: 'g-2');
        await seedAttachment(id: 'a3', memberId: 'm2', mediaId: 'g-3');

        final result = await runWithCapture();

        expect(result.deleted, 3);
        expect(result.ops, hasLength(3));
        expect(result.ops.map((op) => op.table).toSet(), {'media_attachments'});
        expect(result.ops.map((op) => op.opType).toSet(), {
          SyncRecordOpType.update,
        });
        expect(result.ops.map((op) => op.entityId).toSet(), {'a1', 'a2', 'a3'});
        for (final op in result.ops) {
          expect(op.fields, {'is_deleted': true});
        }
      },
    );

    test('emits nothing when there is nothing to tombstone', () async {
      await seedMember('m1', bio: '![](prism-media://keep-1)');
      await seedAttachment(id: 'a1', memberId: 'm1', mediaId: 'keep-1');

      final result = await runWithCapture();

      expect(result.deleted, 0);
      expect(result.ops, isEmpty);
    });
  });

  // ----------------------------------------------------------- idempotence

  group('reconcileBioMediaOrphans — idempotence', () {
    test('a second sweep deletes nothing and emits nothing', () async {
      await seedMember('m1', bio: '![](prism-media://keep-1)');
      await seedAttachment(id: 'a-keep', memberId: 'm1', mediaId: 'keep-1');
      await seedAttachment(id: 'a-orphan', memberId: 'm1', mediaId: 'gone-1');

      final first = await runWithCapture();
      expect(first.deleted, 1);
      expect(first.ops, hasLength(1));

      final second = await runWithCapture();
      expect(second.deleted, 0, reason: 'tombstones are terminal');
      expect(second.ops, isEmpty, reason: 'no duplicate sync ops on re-run');
      expect(await deletedAttachmentIds(), {'a-orphan'});

      final rows = await attachmentsFor('m1');
      expect(rows, hasLength(2), reason: 'no rows are hard-deleted');
    });

    test(
      'a repeat sweep after partial progress converges (crash resume)',
      () async {
        // Simulate a sweep killed after tombstoning only its first page: the
        // second invocation must finish the job without re-tombstoning page 1.
        await seedMember('m1', bio: '');
        await seedMember('m2', bio: '');
        await seedMember('m3', bio: '');
        await seedAttachment(id: 'a1', memberId: 'm1', mediaId: 'g-1');
        await seedAttachment(id: 'a2', memberId: 'm2', mediaId: 'g-2');
        await seedAttachment(id: 'a3', memberId: 'm3', mediaId: 'g-3');

        // Page size 1 => the first page boundary lands after exactly one
        // tombstone; abort there to model a mid-sweep crash.
        final aborted = await runWithCapture(
          memberPageSize: 1,
          yieldControl: () async {
            throw StateError('simulated crash');
          },
        );

        // Best-effort contract: a mid-sweep failure is logged and surfaces as a 0
        // return, but the tombstone it already committed is durable.
        expect(aborted.deleted, 0);
        expect(await deletedAttachmentIds(), {'a1'});

        final resumed = await runWithCapture(memberPageSize: 1);

        expect(resumed.deleted, 2, reason: 'resume must not re-tombstone a1');
        expect(await deletedAttachmentIds(), {'a1', 'a2', 'a3'});
      },
    );
  });

  // ------------------------------------------------------- concurrent edits

  group('reconcileBioMediaOrphans — concurrent bio edits', () {
    test('revalidates each mutation slice before tombstoning', () async {
      await seedMember('m1', bio: '');
      await seedAttachment(id: 'a1', memberId: 'm1', mediaId: 'gone-1');
      await seedAttachment(id: 'a2', memberId: 'm1', mediaId: 'gone-2');
      await seedAttachment(id: 'a3', memberId: 'm1', mediaId: 'restored-3');

      var yields = 0;
      final result = await runWithCapture(
        mutationBatchSize: 2,
        yieldControl: () async {
          yields += 1;
          if (yields == 1) {
            await (db.update(
              db.members,
            )..where((m) => m.id.equals('m1'))).write(
              const MembersCompanion(
                bio: Value('![](prism-media://restored-3)'),
              ),
            );
          }
        },
      );

      expect(result.deleted, 2);
      expect(await deletedAttachmentIds(), {'a1', 'a2'});
      expect(result.ops.map((op) => op.entityId), ['a1', 'a2']);
    });
  });

  // ------------------------------------------------------------ query shape

  group('reconcileBioMediaOrphans — query shape (no N+1)', () {
    test('statement count does not grow with the member count', () async {
      Future<int> selectsFor(int members, int attachmentsPerMember) async {
        await db.customStatement('DELETE FROM media_attachments');
        await db.customStatement('DELETE FROM members');

        for (var m = 0; m < members; m++) {
          await seedMember('m$m', bio: '![](prism-media://keep-$m)');
          for (var a = 0; a < attachmentsPerMember; a++) {
            await seedAttachment(
              id: 'att-$m-$a',
              memberId: 'm$m',
              mediaId: a == 0 ? 'keep-$m' : 'gone-$m-$a',
            );
          }
        }

        interceptor.clear();
        await runWithCapture();
        return sweepSelects();
      }

      // Well under one page, so both runs must issue the SAME bounded number of
      // statements no matter how many members there are.
      final small = await selectsFor(2, 3);
      final large = await selectsFor(40, 3);

      expect(
        large,
        small,
        reason:
            'query count must be independent of member count '
            '(was 2M+1 before batching)',
      );
      expect(
        large,
        lessThanOrEqualTo(3),
        reason:
            'one member-page query + one attachment batch + one empty page; '
            'bounded bio revalidation queries do not scan media_attachments',
      );
    });

    test('paging keeps the statement count bounded for many members', () async {
      const members = 100;
      const pageSize = 10;

      for (var m = 0; m < members; m++) {
        await seedMember('m${m.toString().padLeft(3, '0')}', bio: '');
        await seedAttachment(
          id: 'att-$m',
          memberId: 'm${m.toString().padLeft(3, '0')}',
          mediaId: 'g-$m',
        );
      }

      interceptor.clear();
      final result = await runWithCapture(memberPageSize: pageSize);

      expect(result.deleted, members, reason: 'every orphan still tombstoned');

      final selects = sweepSelects();
      final pages = (members / pageSize).ceil();
      // One media member-page query + one attachment batch per page, plus the
      // final empty-page probe. Bounded bio revalidation reads only `members`,
      // so the expensive media query count remains proportional to pages.
      expect(selects, 2 * pages + 1);
      expect(
        selects,
        lessThan(2 * members / 2),
        reason: 'an N+1 shape would be ~${2 * members} statements',
      );
    });

    test(
      'the batch attachment query binds one member id per paged member',
      () async {
        for (var m = 0; m < 5; m++) {
          await seedMember('m$m', bio: '');
          await seedAttachment(id: 'att-$m', memberId: 'm$m', mediaId: 'g-$m');
        }

        interceptor.clear();
        await runWithCapture(memberPageSize: 50);

        final batch = interceptor.selects.firstWhere(
          (sql) => sql.contains('IN ('),
          orElse: () => '',
        );
        expect(
          batch,
          isNotEmpty,
          reason: 'attachment lookup must be set-based',
        );
        // Five placeholders => all five members resolved in one statement.
        expect(RegExp(r'\?').allMatches(batch).length, 5);
      },
    );

    test(
      'projects narrow columns only (no blob/waveform/key material loaded)',
      () async {
        await seedMember('m1', bio: '');
        await seedAttachment(id: 'a1', memberId: 'm1', mediaId: 'g-1');

        interceptor.clear();
        await runWithCapture();

        final sweepSql = interceptor.selects
            .where((sql) => sql.contains('media_attachments'))
            .join('\n')
            .toLowerCase();
        for (final column in const [
          'waveform_b64',
          'encryption_key_b64',
          'blurhash',
          'thumbnail_content_hash',
          'avatar_image_data',
        ]) {
          expect(
            sweepSql.contains(column),
            isFalse,
            reason: 'sweep must not project $column',
          );
        }
      },
    );
  });

  // ------------------------------------------------------------ large sweep

  group('reconcileBioMediaOrphans — large member sweep', () {
    test('tombstones every orphan across many members and pages', () async {
      const members = 300;
      const orphansPerMember = 2;
      const pageSize = 32;

      for (var m = 0; m < members; m++) {
        final id = 'm${m.toString().padLeft(4, '0')}';
        await seedMember(id, bio: '![](prism-media://keep-$m)');
        await seedAttachment(id: 'k-$m', memberId: id, mediaId: 'keep-$m');
        for (var a = 0; a < orphansPerMember; a++) {
          await seedAttachment(
            id: 'o-$m-$a',
            memberId: id,
            mediaId: 'gone-$m-$a',
          );
        }
      }

      final result = await runWithCapture(memberPageSize: pageSize);

      expect(result.deleted, members * orphansPerMember);
      expect(result.ops, hasLength(members * orphansPerMember));

      final deleted = await deletedAttachmentIds();
      expect(deleted, hasLength(members * orphansPerMember));
      expect(deleted.every((id) => id.startsWith('o-')), isTrue);
    });

    test('yields cooperatively during a large mutation batch', () async {
      const members = 128;

      for (var m = 0; m < members; m++) {
        final id = 'm${m.toString().padLeft(4, '0')}';
        await seedMember(id, bio: '');
        await seedAttachment(id: 'o-$m', memberId: id, mediaId: 'gone-$m');
      }

      var yields = 0;
      final result = await runWithCapture(
        mutationBatchSize: 25,
        yieldControl: () async {
          yields += 1;
        },
      );

      expect(result.deleted, members);
      expect(
        yields,
        greaterThanOrEqualTo(members ~/ 25),
        reason: 'a yield must fire at least once per mutation batch',
      );
    });

    test('yields at every page boundary even with no orphans', () async {
      const pageSize = 10;
      for (var m = 0; m < 25; m++) {
        final id = 'm${m.toString().padLeft(3, '0')}';
        await seedMember(id, bio: '![](prism-media://keep-$m)');
        await seedAttachment(id: 'k-$m', memberId: id, mediaId: 'keep-$m');
      }

      var yields = 0;
      final result = await runWithCapture(
        memberPageSize: pageSize,
        yieldControl: () async {
          yields += 1;
        },
      );

      expect(result.deleted, 0);
      // 3 non-empty pages (10 + 10 + 5 members) => one page-boundary yield
      // each. The 4th (empty) probe terminates the sweep before yielding,
      // because an empty page means the cursor is exhausted.
      expect(yields, 3);
    });
  });
}

/// Records every SELECT statement the sweep issues, so query shape can be
/// asserted structurally instead of being inferred from timing.
class _RecordingSelectInterceptor extends QueryInterceptor {
  final List<String> selects = <String>[];

  void clear() => selects.clear();

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    selects.add(statement);
    return super.runSelect(executor, statement, args);
  }
}
