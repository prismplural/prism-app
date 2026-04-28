import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
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
        unifiedHistoryProvider.overrideWith((ref) => Stream.value([
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
      await container.read(unifiedHistoryProvider.future);
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
        unifiedHistoryProvider.overrideWith((ref) => controller.stream),
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
          unifiedHistoryProvider.overrideWith((ref) => Stream.value([
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
        await container.read(unifiedHistoryProvider.future);
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
        unifiedHistoryProvider.overrideWith((ref) => Stream.value([
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
      await container.read(unifiedHistoryProvider.future);
      await container.read(allMembersProvider.future);
      await Future<void>.delayed(Duration.zero);
      final periods = container.read(derivedPeriodsProvider).value!;
      expect(periods, hasLength(1));
      expect(periods[0].activeMembers, ['v']);
      expect(periods[0].alwaysPresentMembers, ['host']);
    });
  });
}
