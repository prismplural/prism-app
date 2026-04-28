import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    hide FrontingSession, Member;
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/data/mappers/fronting_session_mapper.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/features/fronting/providers/derived_periods_provider.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/services/derive_periods.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';

FrontingSession _s({
  required String id,
  required String memberId,
  required DateTime start,
  DateTime? end,
}) =>
    FrontingSession(
      id: id,
      memberId: memberId,
      startTime: start,
      endTime: end,
    );

/// Wraps a session list in the [DerivedPeriodsInputBundle] the provider
/// emits, with bounds matching the production lookback/lookahead.
DerivedPeriodsInputBundle _bundle(
  List<FrontingSession> sessions, {
  DateTime? rangeStart,
  DateTime? rangeEnd,
  DateTime? referenceNow,
}) {
  final now = referenceNow ?? DateTime.now();
  return DerivedPeriodsInputBundle(
    sessions: sessions,
    rangeStart: rangeStart ??
        now.subtract(const Duration(days: derivedPeriodsLookbackDays)),
    rangeEnd: rangeEnd ??
        now.add(const Duration(days: derivedPeriodsLookaheadDays)),
  );
}

void main() {
  group('derivedPeriodsProvider', () {
    test('emits derived periods when session stream emits', () async {
      final start = DateTime(2026, 4, 1, 10);
      final end = DateTime(2026, 4, 1, 12);

      final container = ProviderContainer(overrides: [
        unifiedHistoryOverlapProvider.overrideWith((ref) => Stream.value(
              _bundle([
                _s(id: 's1', memberId: 'a', start: start, end: end),
              ]),
            )),
        allMembersProvider.overrideWith((ref) => Stream.value(const <Member>[])),
      ]);
      addTearDown(container.dispose);

      // Subscribe so the autoDispose provider stays alive while the
      // upstream stream pumps its first value.
      container.listen<AsyncValue<List<FrontingPeriod>>>(
        derivedPeriodsProvider,
        (_, _) {},
        fireImmediately: true,
      );
      await container.read(unifiedHistoryOverlapProvider.future);
      // Read the members stream too so its first value is in.
      await container.read(allMembersProvider.future);
      // Microtask flush so the synchronous `Provider` recomputes against
      // the latest upstream values.
      await Future<void>.delayed(Duration.zero);

      final periodsAsync = container.read(derivedPeriodsProvider);
      expect(periodsAsync.hasValue, isTrue);
      final periods = periodsAsync.value!;
      expect(periods, hasLength(1));
      expect(periods[0].activeMembers, ['a']);
    });

    test('recomputes when upstream session list changes', () async {
      final controller = StreamController<DerivedPeriodsInputBundle>();
      addTearDown(controller.close);

      final container = ProviderContainer(overrides: [
        unifiedHistoryOverlapProvider.overrideWith((ref) => controller.stream),
        allMembersProvider.overrideWith((ref) => Stream.value(const <Member>[])),
      ]);
      addTearDown(container.dispose);

      // Subscribe so the provider stays alive.
      container.listen<AsyncValue<List<FrontingPeriod>>>(
        derivedPeriodsProvider,
        (_, _) {},
        fireImmediately: true,
      );

      controller.add(_bundle([
        _s(
          id: 's1',
          memberId: 'a',
          start: DateTime(2026, 4, 1, 10),
          end: DateTime(2026, 4, 1, 11),
        ),
      ]));
      // Pump twice: first to deliver the stream event, second to allow
      // the synchronous Provider to rebuild.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final first = container.read(derivedPeriodsProvider).value!;
      expect(first, hasLength(1));

      controller.add(_bundle([
        _s(
          id: 's1',
          memberId: 'a',
          start: DateTime(2026, 4, 1, 10),
          end: DateTime(2026, 4, 1, 11),
        ),
        _s(
          id: 's2',
          memberId: 'b',
          start: DateTime(2026, 4, 1, 11),
          end: DateTime(2026, 4, 1, 12),
        ),
      ]));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final second = container.read(derivedPeriodsProvider).value!;
      expect(second, hasLength(2));
      expect(second[0].activeMembers, ['a']);
      expect(second[1].activeMembers, ['b']);
    });

    test(
      'reads from same upstream snapshot return identical period list '
      '(memoization within a single emission)',
      () async {
        final container = ProviderContainer(overrides: [
          unifiedHistoryOverlapProvider.overrideWith((ref) => Stream.value(
                _bundle([
                  _s(
                    id: 's1',
                    memberId: 'a',
                    start: DateTime(2026, 4, 1, 10),
                    end: DateTime(2026, 4, 1, 11),
                  ),
                ]),
              )),
          allMembersProvider.overrideWith((ref) => Stream.value(const <Member>[])),
        ]);
        addTearDown(container.dispose);

        container.listen<AsyncValue<List<FrontingPeriod>>>(
          derivedPeriodsProvider,
          (_, _) {},
          fireImmediately: true,
        );
        await container.read(unifiedHistoryOverlapProvider.future);
        await container.read(allMembersProvider.future);
        await Future<void>.delayed(Duration.zero);
        final a = container.read(derivedPeriodsProvider).value!;
        final b = container.read(derivedPeriodsProvider).value!;
        // Same provider snapshot — Riverpod returns the identical cached
        // list instance, not a re-derived one.
        expect(identical(a, b), isTrue);
      },
    );

    test('respects is_always_fronting from members stream', () async {
      final container = ProviderContainer(overrides: [
        unifiedHistoryOverlapProvider.overrideWith((ref) => Stream.value(
              _bundle([
                _s(
                  id: 'host',
                  memberId: 'host',
                  start: DateTime(2025, 1, 1),
                  end: null,
                ),
                _s(
                  id: 'v',
                  memberId: 'v',
                  start: DateTime(2026, 4, 1, 14),
                  end: DateTime(2026, 4, 1, 15),
                ),
              ]),
            )),
        allMembersProvider.overrideWith((ref) => Stream.value([
              Member(
                id: 'host',
                name: 'Host',
                createdAt: DateTime(2025, 1, 1),
                isAlwaysFronting: true,
              ),
              Member(
                id: 'v',
                name: 'V',
                createdAt: DateTime(2026, 1, 1),
              ),
            ])),
      ]);
      addTearDown(container.dispose);

      container.listen<AsyncValue<List<FrontingPeriod>>>(
        derivedPeriodsProvider,
        (_, _) {},
        fireImmediately: true,
      );
      await container.read(unifiedHistoryOverlapProvider.future);
      await container.read(allMembersProvider.future);
      await Future<void>.delayed(Duration.zero);
      final periods = container.read(derivedPeriodsProvider).value!;
      expect(periods, hasLength(1));
      expect(periods[0].activeMembers, ['v']);
      expect(periods[0].alwaysPresentMembers, ['host']);
    });

    test(
      'production overlap-query path catches a long-running host '
      '(real Drift, no provider override)',
      () async {
        // Codex test gap #6: instead of overriding the upstream stream
        // with a hand-built list, plumb a real in-memory Drift DB
        // through the production repository so we exercise the actual
        // overlap query and assert it surfaces a long-running host
        // whose row started >90 days before the lookback window.
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);

        final repo = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        );

        // Long-running host started 120 days ago (well past the
        // 90-day lookback window), still open. The overlap query must
        // surface this via the `end_time IS NULL OR end_time > start`
        // clause even though the session's start_time precedes
        // rangeStart.
        final hostStart = DateTime.now().subtract(const Duration(days: 120));
        await db.frontingSessionsDao.insertSession(
          FrontingSessionMapper.toCompanion(
            FrontingSession(
              id: 'host-row',
              memberId: 'host',
              startTime: hostStart,
              endTime: null,
            ),
          ),
        );

        // Insert MORE THAN sessionPageSize visitor rows AFTER the
        // host's start, so a row-paged "newest N rows" query would
        // page the host out — we'd have caught the LIMIT-page bug if
        // the overlap query weren't there.
        const visitorCount = sessionPageSize + 5;
        for (var i = 0; i < visitorCount; i++) {
          await db.frontingSessionsDao.insertSession(
            FrontingSessionMapper.toCompanion(
              FrontingSession(
                id: 'v$i',
                memberId: 'v$i',
                // Spread visitors over the last few hours so they
                // don't all collapse into the ephemeral threshold.
                startTime: DateTime.now()
                    .subtract(Duration(minutes: (i + 1) * 10)),
                endTime: DateTime.now()
                    .subtract(Duration(minutes: (i + 1) * 10 - 5)),
              ),
            ),
          );
        }

        final container = ProviderContainer(overrides: [
          frontingSessionRepositoryProvider
              .overrideWith((ref) => repo as FrontingSessionRepository),
          allMembersProvider.overrideWith((ref) =>
              Stream.value(const <Member>[])),
        ]);
        addTearDown(container.dispose);

        container.listen<AsyncValue<List<FrontingPeriod>>>(
          derivedPeriodsProvider,
          (_, _) {},
          fireImmediately: true,
        );

        // Wait for the overlap stream's first emission.
        await container.read(unifiedHistoryOverlapProvider.future);
        await container.read(allMembersProvider.future);
        await Future<void>.delayed(Duration.zero);

        final periods = container.read(derivedPeriodsProvider).value!;
        // Assert the host appears in at least one period — the overlap
        // query MUST surface long-running rows that started before the
        // lookback window.
        final allActive = <String>{
          for (final p in periods) ...p.activeMembers,
        };
        expect(allActive, contains('host'),
            reason:
                'production overlap query must surface a long-running host '
                'older than the lookback window');
      },
    );

    test(
      'provider range clamps a 400-day host so the sweep stays inside the '
      'lookback window',
      () async {
        // Codex P2: computeDerivedPeriods used to infer rangeStart from
        // the earliest returned session (a 400-day-old open host),
        // throwing away the provider's 90-day bound and producing
        // hundreds of midnight slices spanning the whole interval.
        // With the fix, the bundle's rangeStart is threaded through.
        final referenceNow = DateTime(2026, 4, 27, 12);
        final hostStart = referenceNow.subtract(const Duration(days: 400));
        final visitorStart = referenceNow.subtract(const Duration(hours: 5));
        final visitorEnd = referenceNow.subtract(const Duration(hours: 4));

        final providerRangeStart =
            referenceNow.subtract(const Duration(days: derivedPeriodsLookbackDays));
        final providerRangeEnd =
            referenceNow.add(const Duration(days: derivedPeriodsLookaheadDays));

        final container = ProviderContainer(overrides: [
          unifiedHistoryOverlapProvider.overrideWith((ref) => Stream.value(
                DerivedPeriodsInputBundle(
                  sessions: [
                    _s(
                      id: 'host-400',
                      memberId: 'host',
                      start: hostStart,
                      end: null,
                    ),
                    _s(
                      id: 'v',
                      memberId: 'v',
                      start: visitorStart,
                      end: visitorEnd,
                    ),
                  ],
                  rangeStart: providerRangeStart,
                  rangeEnd: providerRangeEnd,
                ),
              )),
          allMembersProvider.overrideWith((ref) =>
              Stream.value(const <Member>[])),
        ]);
        addTearDown(container.dispose);

        container.listen<AsyncValue<List<FrontingPeriod>>>(
          derivedPeriodsProvider,
          (_, _) {},
          fireImmediately: true,
        );
        await container.read(unifiedHistoryOverlapProvider.future);
        await container.read(allMembersProvider.future);
        await Future<void>.delayed(Duration.zero);

        final periods = container.read(derivedPeriodsProvider).value!;
        // Earliest period start MUST clamp to the provider's rangeStart,
        // not the host's 400-day-old start time.
        for (final p in periods) {
          expect(p.start.isBefore(providerRangeStart), isFalse,
              reason: 'period $p extends before provider rangeStart');
        }
        // The host should be visible in (at least) the period covering
        // the visitor — i.e. clamp didn't drop it.
        final hostPeriods = periods.where((p) => p.activeMembers.contains('host'));
        expect(hostPeriods, isNotEmpty,
            reason: 'host should still appear in clamped periods');
      },
    );

    test(
      'production provider emits rangeEnd bounded at now (not now + 30d)',
      () async {
        // Codex P1 fix-up #3: the bundle's `rangeEnd` is the visible
        // upper bound, NOT the SQL lookahead. With `rangeEnd = now`,
        // an open current session extends to `now`, not to
        // `now + 30 days`. This test reads the live provider bundle
        // and asserts the bound, then checks the derived open period
        // ends at-or-before `now` (within a small wall-clock tick).
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);

        final repo = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        );

        // Insert one open current session.
        final start = DateTime.now().subtract(const Duration(hours: 1));
        await db.frontingSessionsDao.insertSession(
          FrontingSessionMapper.toCompanion(
            FrontingSession(
              id: 'open',
              memberId: 'a',
              startTime: start,
              endTime: null,
            ),
          ),
        );

        final container = ProviderContainer(overrides: [
          frontingSessionRepositoryProvider
              .overrideWith((ref) => repo as FrontingSessionRepository),
          allMembersProvider
              .overrideWith((ref) => Stream.value(const <Member>[])),
        ]);
        addTearDown(container.dispose);

        container.listen<AsyncValue<DerivedPeriodsInputBundle>>(
          unifiedHistoryOverlapProvider,
          (_, _) {},
          fireImmediately: true,
        );
        container.listen<AsyncValue<List<FrontingPeriod>>>(
          derivedPeriodsProvider,
          (_, _) {},
          fireImmediately: true,
        );

        final bundle =
            await container.read(unifiedHistoryOverlapProvider.future);

        // rangeEnd must be bounded at "now of rebuild" — within a few
        // seconds, NOT 30 days in the future.
        final wallNow = DateTime.now();
        final delta = bundle.rangeEnd.difference(wallNow).abs();
        expect(delta.inSeconds, lessThan(5),
            reason: 'rangeEnd must be ~now, not now + 30 days '
                '(was: ${bundle.rangeEnd}, now: $wallNow)');

        // And the open derived period ends ~now, not ~now + 30d.
        await container.read(allMembersProvider.future);
        await Future<void>.delayed(Duration.zero);
        final periods = container.read(derivedPeriodsProvider).value!;
        expect(periods, hasLength(1));
        final open = periods.single;
        expect(open.isOpenEnded, isTrue);
        // End must be at or before now + a small tolerance — never
        // 30 days in the future.
        final endDelta = open.end.difference(wallNow).abs();
        expect(endDelta.inMinutes, lessThan(1),
            reason: 'open period end must be ~now, not 30 days out '
                '(was: ${open.end})');
      },
    );

    test(
      'future-dated session in DB does not leak into derived periods',
      () async {
        // Codex P2 fix-up #3: even though the DAO's +30d lookahead
        // surfaces a future-dated row, the derivation rejects it.
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);

        final repo = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        );

        // One real recent closed session.
        final realStart = DateTime.now().subtract(const Duration(hours: 2));
        final realEnd = DateTime.now().subtract(const Duration(hours: 1));
        await db.frontingSessionsDao.insertSession(
          FrontingSessionMapper.toCompanion(
            FrontingSession(
              id: 'real',
              memberId: 'a',
              startTime: realStart,
              endTime: realEnd,
            ),
          ),
        );

        // One future-dated typo: starts tomorrow.
        await db.frontingSessionsDao.insertSession(
          FrontingSessionMapper.toCompanion(
            FrontingSession(
              id: 'future',
              memberId: 'b',
              startTime: DateTime.now().add(const Duration(days: 1)),
              endTime: DateTime.now().add(const Duration(days: 1, hours: 1)),
            ),
          ),
        );

        final container = ProviderContainer(overrides: [
          frontingSessionRepositoryProvider
              .overrideWith((ref) => repo as FrontingSessionRepository),
          allMembersProvider
              .overrideWith((ref) => Stream.value(const <Member>[])),
        ]);
        addTearDown(container.dispose);

        container.listen<AsyncValue<List<FrontingPeriod>>>(
          derivedPeriodsProvider,
          (_, _) {},
          fireImmediately: true,
        );

        await container.read(unifiedHistoryOverlapProvider.future);
        await container.read(allMembersProvider.future);
        await Future<void>.delayed(Duration.zero);

        final periods = container.read(derivedPeriodsProvider).value!;
        // Only the real session contributes. Member 'b' must be
        // entirely absent.
        for (final p in periods) {
          expect(p.activeMembers, isNot(contains('b')),
              reason: 'future-dated session must not surface in periods');
          expect(p.briefVisitors.map((v) => v.memberId), isNot(contains('b')));
        }
        final allActive = <String>{
          for (final p in periods) ...p.activeMembers,
        };
        expect(allActive, contains('a'));
      },
    );

    test(
      'provider invalidation propagates a new session to derived periods',
      () async {
        // Codex test gap #5: invalidateFrontingProviders must invalidate
        // unifiedHistoryOverlapProvider + derivedPeriodsProvider so that
        // mutations propagate. Drive this with a controllable stream
        // that we re-emit through the same controller after "mutation".
        final controller = StreamController<DerivedPeriodsInputBundle>.broadcast();
        addTearDown(controller.close);

        final container = ProviderContainer(overrides: [
          unifiedHistoryOverlapProvider
              .overrideWith((ref) => controller.stream),
          allMembersProvider
              .overrideWith((ref) => Stream.value(const <Member>[])),
        ]);
        addTearDown(container.dispose);

        container.listen<AsyncValue<List<FrontingPeriod>>>(
          derivedPeriodsProvider,
          (_, _) {},
          fireImmediately: true,
        );

        controller.add(_bundle([
          _s(
            id: 's1',
            memberId: 'a',
            start: DateTime(2026, 4, 1, 10),
            end: DateTime(2026, 4, 1, 11),
          ),
        ]));
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        final first = container.read(derivedPeriodsProvider).value!;
        expect(first, hasLength(1));
        expect(first[0].activeMembers, ['a']);

        // Simulate a mutation: the upstream stream re-emits with the
        // new row included. The provider must surface it.
        controller.add(_bundle([
          _s(
            id: 's1',
            memberId: 'a',
            start: DateTime(2026, 4, 1, 10),
            end: DateTime(2026, 4, 1, 11),
          ),
          _s(
            id: 's2',
            memberId: 'b',
            start: DateTime(2026, 4, 1, 12),
            end: DateTime(2026, 4, 1, 13),
          ),
        ]));
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        final second = container.read(derivedPeriodsProvider).value!;
        expect(second, hasLength(2),
            reason:
                'new session must appear after upstream re-emission '
                '(invalidation contract)');
        expect(second.last.activeMembers, ['b']);
      },
    );
  });
}
