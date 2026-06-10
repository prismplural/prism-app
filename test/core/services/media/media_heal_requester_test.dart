import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/missing_media_dao.dart';
import 'package:prism_plurality/core/services/media/media_heal_requester.dart';

void main() {
  late AppDatabase db;
  late MissingMediaDao dao;

  // Controllable clock + fakes.
  int clock = 1000000000; // ms
  Set<String> present = {};
  Object? batchError;
  final batchCalls = <List<String>>[];
  final requested = <String>[];

  MediaHealRequester build({
    Duration profileCooldown = const Duration(minutes: 2),
    Duration chatCooldown = const Duration(minutes: 5),
    Duration terminalAfter = const Duration(days: 14),
    int batchChunkSize = 1024,
  }) {
    return MediaHealRequester(
      dao: dao,
      clockMs: () => clock,
      profileCooldown: profileCooldown,
      chatCooldown: chatCooldown,
      terminalAfter: terminalAfter,
      batchChunkSize: batchChunkSize,
      batchExists: (ids) async {
        batchCalls.add(List.of(ids));
        if (batchError != null) throw batchError!;
        return ids.where(present.contains).toList();
      },
      sendMediaRequest: (id) async => requested.add(id),
    );
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = db.missingMediaDao;
    clock = 1000000000;
    present = {};
    batchError = null;
    batchCalls.clear();
    requested.clear();
  });
  tearDown(() => db.close());

  group('onReferencedAbsent', () {
    test('relay holds the blob → no record, no request', () async {
      present = {'x'};
      await build().onReferencedAbsent('x', priority: MissingMediaDao.priorityChat);
      expect(await dao.getById('x'), isNull);
      expect(requested, isEmpty);
    });

    test('confirmed absent → records missing + requests once', () async {
      await build().onReferencedAbsent('x', priority: MissingMediaDao.priorityChat);
      final row = await dao.getById('x');
      expect(row, isNotNull);
      expect(row!.attempts, 1);
      expect(row.nextEligibleAt, greaterThan(clock), reason: 'cooldown armed');
      expect(requested, ['x']);
    });

    test('batch-exists failure (old relay/transient) → no-op', () async {
      batchError = Exception('feature absent');
      await build().onReferencedAbsent('x', priority: MissingMediaDao.priorityChat);
      expect(await dao.getById('x'), isNull);
      expect(requested, isEmpty);
    });

    test('repeat while in cooldown does not re-request', () async {
      final r = build();
      await r.onReferencedAbsent('x', priority: MissingMediaDao.priorityChat);
      expect(requested, ['x']);
      // Same blob viewed again before the cooldown elapses.
      clock += const Duration(seconds: 30).inMilliseconds;
      await r.onReferencedAbsent('x', priority: MissingMediaDao.priorityChat);
      expect(requested, ['x'], reason: 'still in cooldown → cadence will handle it');
    });
  });

  group('runCadence', () {
    test('returns healed entries for re-download WITHOUT removing them, and '
        'requests still-absent due ones', () async {
      await dao.markMissing(mediaId: 'healed', priority: MissingMediaDao.priorityChat, nowMs: clock);
      await dao.markMissing(mediaId: 'absent', priority: MissingMediaDao.priorityChat, nowMs: clock);
      present = {'healed'};

      final healed = await build().runCadence();

      expect(healed, ['healed'], reason: 'returned for re-download');
      // Removal is success-driven (on a cache hit), NOT here — so a flapping
      // short-TTL re-supply can't reset the entry's terminal clock/backoff.
      expect(await dao.getById('healed'), isNotNull, reason: 'entry preserved');
      expect(requested, ['absent']);
      final row = await dao.getById('absent');
      expect(row!.attempts, 1);
      expect(row.nextEligibleAt, greaterThan(clock));
    });

    test('returns the healed media ids and requests the still-absent rest',
        () async {
      await dao.markMissing(mediaId: 'h1', priority: MissingMediaDao.priorityChat, nowMs: clock);
      await dao.markMissing(mediaId: 'h2', priority: MissingMediaDao.priorityChat, nowMs: clock);
      await dao.markMissing(mediaId: 'still', priority: MissingMediaDao.priorityChat, nowMs: clock);
      present = {'h1', 'h2'};

      final healed = await build().runCadence();

      expect(healed.toSet(), {'h1', 'h2'});
      expect(requested, ['still'], reason: 'still-absent blob is re-requested');
      // All three remain in the set; healed ones are removed on a cache hit.
      expect((await dao.pendingMediaIds()).toSet(), {'h1', 'h2', 'still'});
    });

    test('a healed-then-failed-redownload preserves the terminal clock', () async {
      // Heal-flap: blob present → returned for re-download (not removed) → the
      // re-download fails (TTL expired) so it is re-confirmed absent. Because the
      // entry was never removed, markMissing updates it in place — firstMissingAt
      // and the backoff are NOT reset.
      await dao.markMissing(mediaId: 'flap', priority: MissingMediaDao.priorityChat, nowMs: 1000);
      await dao.recordRequested(mediaId: 'flap', attempts: 3, nextEligibleAtMs: 999999, nowMs: 1000);
      clock = 2000;
      present = {'flap'};
      final r = build();
      await r.runCadence(); // present → returned, not removed
      // Re-download failed → re-confirmed absent on the next miss (still in
      // cooldown, so no re-request — isolates the clock-preservation check).
      present = {};
      await r.onReferencedAbsent('flap', priority: MissingMediaDao.priorityChat);
      final row = await dao.getById('flap');
      expect(row!.firstMissingAt, 1000, reason: 'terminal clock preserved across the flap');
      expect(row.attempts, 3, reason: 'backoff not reset');
    });

    test('batch-exists failure → no-op (no drop, no request)', () async {
      await dao.markMissing(mediaId: 'a', priority: MissingMediaDao.priorityChat, nowMs: clock);
      batchError = Exception('feature absent');
      await build().runCadence();
      expect(await dao.getById('a'), isNotNull);
      expect(requested, isEmpty);
    });

    test('entries past the terminal window become terminal, not requested', () async {
      await dao.markMissing(mediaId: 'old', priority: MissingMediaDao.priorityChat, nowMs: clock);
      // 15 days later, still absent + due.
      clock += const Duration(days: 15).inMilliseconds;
      await build().runCadence();
      expect(requested, isEmpty);
      expect((await dao.getById('old'))!.state, MissingMediaDao.stateTerminal);
      expect(await dao.terminalCount(), 1);
    });

    test('not-due entries are skipped', () async {
      await dao.markMissing(mediaId: 'a', priority: MissingMediaDao.priorityChat, nowMs: clock);
      await dao.recordRequested(mediaId: 'a', attempts: 1, nextEligibleAtMs: clock + 999999, nowMs: clock);
      await build().runCadence();
      expect(requested, isEmpty, reason: 'still cooling down');
      // batch-exists still ran over the pending set (to detect heals).
      expect(batchCalls, isNotEmpty);
    });

    test('coalesces a large set into chunked batch-exists calls', () async {
      for (var i = 0; i < 3; i++) {
        await dao.markMissing(mediaId: 'm$i', priority: MissingMediaDao.priorityChat, nowMs: clock);
      }
      await build(batchChunkSize: 2).runCadence();
      // 3 ids, chunk size 2 → two batch-exists calls (2 + 1).
      expect(batchCalls.map((c) => c.length).toList(), [2, 1]);
      expect(requested.toSet(), {'m0', 'm1', 'm2'});
    });
  });

  test('profile images get a tighter cooldown than chat images', () async {
    final r = build(
      profileCooldown: const Duration(minutes: 2),
      chatCooldown: const Duration(minutes: 10),
    );
    await dao.markMissing(mediaId: 'p', priority: MissingMediaDao.priorityProfile, nowMs: clock);
    await dao.markMissing(mediaId: 'c', priority: MissingMediaDao.priorityChat, nowMs: clock);
    await r.runCadence();
    final p = (await dao.getById('p'))!.nextEligibleAt - clock;
    final c = (await dao.getById('c'))!.nextEligibleAt - clock;
    expect(p, const Duration(minutes: 2).inMilliseconds);
    expect(c, const Duration(minutes: 10).inMilliseconds);
    expect(p, lessThan(c));
  });
}
