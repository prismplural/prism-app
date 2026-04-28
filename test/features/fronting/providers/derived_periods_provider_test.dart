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

void main() {
  group('derivedPeriodsProvider', () {
    test('emits derived periods when session stream emits', () async {
      final start = DateTime(2026, 4, 1, 10);
      final end = DateTime(2026, 4, 1, 12);

      final container = ProviderContainer(overrides: [
        unifiedHistoryOverlapProvider.overrideWith((ref) => Stream.value([
              _s(id: 's1', memberId: 'a', start: start, end: end),
            ])),
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
      final controller = StreamController<List<FrontingSession>>();
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

      controller.add([
        _s(
          id: 's1',
          memberId: 'a',
          start: DateTime(2026, 4, 1, 10),
          end: DateTime(2026, 4, 1, 11),
        ),
      ]);
      // Pump twice: first to deliver the stream event, second to allow
      // the synchronous Provider to rebuild.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final first = container.read(derivedPeriodsProvider).value!;
      expect(first, hasLength(1));

      controller.add([
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
      ]);
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
          unifiedHistoryOverlapProvider.overrideWith((ref) => Stream.value([
                _s(
                  id: 's1',
                  memberId: 'a',
                  start: DateTime(2026, 4, 1, 10),
                  end: DateTime(2026, 4, 1, 11),
                ),
              ])),
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
        unifiedHistoryOverlapProvider.overrideWith((ref) => Stream.value([
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
            ])),
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
        // whose row is NOT among the most-recent N.
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);

        final repo = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        );

        // Long-running host started 400 days ago, still open.
        final hostStart = DateTime.now().subtract(const Duration(days: 30));
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

        // A bunch of recent visitor rows AFTER the host's start, to
        // simulate a row-page query missing the host. (We don't need
        // hundreds — the new query is start-time-bound, not paged.)
        for (var i = 0; i < 5; i++) {
          await db.frontingSessionsDao.insertSession(
            FrontingSessionMapper.toCompanion(
              FrontingSession(
                id: 'v$i',
                memberId: 'v$i',
                startTime: DateTime.now()
                    .subtract(Duration(hours: i + 1)),
                endTime:
                    DateTime.now().subtract(Duration(hours: i, minutes: 30)),
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
        // recent-page would catch.
        final allActive = <String>{
          for (final p in periods) ...p.activeMembers,
        };
        expect(allActive, contains('host'),
            reason:
                'production overlap query must surface a long-running host');
      },
    );
  });
}
