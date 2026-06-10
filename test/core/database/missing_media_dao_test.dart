import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/missing_media_dao.dart';

void main() {
  late AppDatabase db;
  late MissingMediaDao dao;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = db.missingMediaDao;
  });
  tearDown(() => db.close());

  test('markMissing creates a pending, immediately-eligible entry', () async {
    await dao.markMissing(
      mediaId: 'a',
      priority: MissingMediaDao.priorityChat,
      nowMs: 5000,
    );
    final row = await dao.getById('a');
    expect(row, isNotNull);
    expect(row!.state, MissingMediaDao.statePending);
    expect(row.firstMissingAt, 5000);
    expect(row.nextEligibleAt, 0);
    expect(row.attempts, 0);
    expect(row.priority, MissingMediaDao.priorityChat);
    expect(await dao.dueForRequest(5000), hasLength(1));
  });

  test('markMissing is idempotent: preserves the terminal clock + cooldown', () async {
    await dao.markMissing(mediaId: 'a', priority: MissingMediaDao.priorityChat, nowMs: 1000);
    await dao.recordRequested(
      mediaId: 'a',
      attempts: 3,
      nextEligibleAtMs: 99999,
      nowMs: 2000,
    );
    // Re-confirming absence must NOT reset firstMissingAt, attempts, or the
    // cooldown gate.
    await dao.markMissing(mediaId: 'a', priority: MissingMediaDao.priorityChat, nowMs: 8000);
    final row = await dao.getById('a');
    expect(row!.firstMissingAt, 1000, reason: 'terminal clock preserved');
    expect(row.attempts, 3, reason: 'attempts preserved');
    expect(row.nextEligibleAt, 99999, reason: 'cooldown preserved');
  });

  test('markMissing only lowers priority, never raises it', () async {
    await dao.markMissing(mediaId: 'a', priority: MissingMediaDao.priorityChat, nowMs: 1000);
    // A later sighting in a higher-priority (profile) context upgrades it.
    await dao.markMissing(mediaId: 'a', priority: MissingMediaDao.priorityProfile, nowMs: 2000);
    expect((await dao.getById('a'))!.priority, MissingMediaDao.priorityProfile);
    // A subsequent lower-priority sighting must NOT demote it.
    await dao.markMissing(mediaId: 'a', priority: MissingMediaDao.priorityChat, nowMs: 3000);
    expect((await dao.getById('a'))!.priority, MissingMediaDao.priorityProfile);
  });

  test('dueForRequest orders profile images ahead of chat images', () async {
    await dao.markMissing(mediaId: 'chat', priority: MissingMediaDao.priorityChat, nowMs: 1000);
    await dao.markMissing(mediaId: 'profile', priority: MissingMediaDao.priorityProfile, nowMs: 1000);
    final due = await dao.dueForRequest(1000);
    expect(due.map((d) => d.mediaId), ['profile', 'chat']);
  });

  test('recordRequested gates the next attempt out of the due set', () async {
    await dao.markMissing(mediaId: 'a', priority: MissingMediaDao.priorityChat, nowMs: 1000);
    await dao.recordRequested(mediaId: 'a', attempts: 1, nextEligibleAtMs: 5000, nowMs: 1000);
    // Not due before the cooldown elapses, but still a pending member.
    expect(await dao.dueForRequest(4000), isEmpty);
    expect(await dao.pendingMediaIds(), ['a']);
    // Due again once the cooldown passes.
    expect((await dao.dueForRequest(5000)).single.mediaId, 'a');
    expect((await dao.getById('a'))!.lastRequestedAt, 1000);
  });

  test('markTerminal removes the entry from pending/due but retains it', () async {
    await dao.markMissing(mediaId: 'a', priority: MissingMediaDao.priorityChat, nowMs: 1000);
    await dao.markTerminal('a');
    expect(await dao.pendingMediaIds(), isEmpty);
    expect(await dao.dueForRequest(99999), isEmpty);
    expect(await dao.getById('a'), isNotNull);
    expect(await dao.terminalCount(), 1);
    expect(await dao.pendingCount(), 0);
  });

  test('requestAllNow revives terminal + pending entries for an immediate retry', () async {
    await dao.markMissing(mediaId: 'a', priority: MissingMediaDao.priorityChat, nowMs: 1000);
    await dao.markMissing(mediaId: 'b', priority: MissingMediaDao.priorityChat, nowMs: 1000);
    await dao.markTerminal('a');
    await dao.recordRequested(mediaId: 'b', attempts: 1, nextEligibleAtMs: 99999, nowMs: 1000);
    // Before: a terminal, b gated.
    expect(await dao.dueForRequest(2000), isEmpty);

    await dao.requestAllNow(2000);
    final due = (await dao.dueForRequest(2000)).map((d) => d.mediaId).toSet();
    expect(due, {'a', 'b'});
    expect(await dao.terminalCount(), 0);
    expect(await dao.pendingCount(), 2);
  });

  test('remove deletes a healed entry', () async {
    await dao.markMissing(mediaId: 'a', priority: MissingMediaDao.priorityChat, nowMs: 1000);
    await dao.remove('a');
    expect(await dao.getById('a'), isNull);
    expect(await dao.pendingCount(), 0);
  });
}
