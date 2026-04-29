import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/fronting/providers/always_present_members_provider.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';

Member _member({
  required String id,
  String? name,
  bool isAlwaysFronting = false,
  int displayOrder = 0,
}) {
  return Member(
    id: id,
    name: name ?? id,
    createdAt: DateTime(2025, 1, 1),
    isAlwaysFronting: isAlwaysFronting,
    displayOrder: displayOrder,
  );
}

FrontingSession _session({
  required String id,
  String? memberId,
  required DateTime start,
  DateTime? end,
  SessionType type = SessionType.normal,
  bool isDeleted = false,
}) {
  return FrontingSession(
    id: id,
    memberId: memberId,
    startTime: start,
    endTime: end,
    sessionType: type,
    isDeleted: isDeleted,
  );
}

ProviderContainer _container({
  required List<FrontingSession> sessions,
  required List<Member> members,
}) {
  return ProviderContainer(overrides: [
    activeSessionsProvider.overrideWith((ref) => Stream.value(sessions)),
    allMembersProvider.overrideWith((ref) => Stream.value(members)),
  ]);
}

Future<List<AlwaysPresentMember>> _drain(ProviderContainer container) async {
  // Hold a subscription so the synchronous Provider recomputes once each
  // upstream stream has emitted.
  container.listen<AsyncValue<List<AlwaysPresentMember>>>(
    alwaysPresentMembersProvider,
    (_, _) {},
    fireImmediately: true,
  );
  await container.read(activeSessionsProvider.future);
  await container.read(allMembersProvider.future);
  await Future<void>.delayed(Duration.zero);
  final value = container.read(alwaysPresentMembersProvider);
  expect(value.hasValue, isTrue,
      reason: 'provider should have a data value after pumping streams');
  return value.value!;
}

void main() {
  group('alwaysPresentMembersProvider', () {
    test('empty when no active sessions', () async {
      final container = _container(
        sessions: const [],
        members: [_member(id: 'a', isAlwaysFronting: true)],
      );
      addTearDown(container.dispose);

      final result = await _drain(container);
      expect(result, isEmpty);
    });

    test(
      'renders for member with isAlwaysFronting == true AND active session',
      () async {
        final start = DateTime.now().subtract(const Duration(minutes: 5));
        final container = _container(
          sessions: [_session(id: 's1', memberId: 'a', start: start)],
          members: [_member(id: 'a', isAlwaysFronting: true)],
        );
        addTearDown(container.dispose);

        final result = await _drain(container);
        expect(result, hasLength(1));
        expect(result.single.member.id, 'a');
        expect(result.single.session.id, 's1');
      },
    );

    test('renders for member with active session running > 7 days', () async {
      final start = DateTime.now().subtract(const Duration(days: 8));
      final container = _container(
        sessions: [_session(id: 's1', memberId: 'a', start: start)],
        members: [_member(id: 'a')], // NOT explicit-always-fronting
      );
      addTearDown(container.dispose);

      final result = await _drain(container);
      expect(result, hasLength(1));
      expect(result.single.member.id, 'a');
    });

    test(
      'does NOT render for explicit always-fronting member with no active session',
      () async {
        final container = _container(
          sessions: const [],
          members: [_member(id: 'a', isAlwaysFronting: true)],
        );
        addTearDown(container.dispose);

        final result = await _drain(container);
        expect(result, isEmpty,
            reason:
                'active-session prerequisite must filter out explicit-only '
                'members with no open session');
      },
    );

    test(
      'does NOT render for member with active session shorter than 7 days '
      'and no explicit flag',
      () async {
        final start = DateTime.now().subtract(const Duration(days: 6));
        final container = _container(
          sessions: [_session(id: 's1', memberId: 'a', start: start)],
          members: [_member(id: 'a')],
        );
        addTearDown(container.dispose);

        final result = await _drain(container);
        expect(result, isEmpty);
      },
    );

    test('boundary: session age slightly past 7d is included', () async {
      // 7d + a small buffer to absorb the time the test takes between
      // capturing `start` and the provider sampling `DateTime.now()`.
      final start = DateTime.now().subtract(
        kAutoPromoteThreshold + const Duration(milliseconds: 50),
      );
      final container = _container(
        sessions: [_session(id: 's1', memberId: 'a', start: start)],
        members: [_member(id: 'a')],
      );
      addTearDown(container.dispose);

      final result = await _drain(container);
      expect(result, hasLength(1));
    });

    test('boundary: session strictly under 7d is excluded', () async {
      // Use a 1-second gap rather than 1ms — the test takes a few
      // microseconds to plumb the start time through the override stream
      // into the provider's `DateTime.now()` sample. A 1ms gap is
      // racy; 1s is well clear of the boundary while still squarely
      // testing the "<7d" exclusion path.
      final start = DateTime.now().subtract(
        kAutoPromoteThreshold - const Duration(seconds: 1),
      );
      final container = _container(
        sessions: [_session(id: 's1', memberId: 'a', start: start)],
        members: [_member(id: 'a')],
      );
      addTearDown(container.dispose);

      final result = await _drain(container);
      expect(result, isEmpty);
    });

    test('skips closed sessions, sleep sessions, and deleted sessions',
        () async {
      final start = DateTime.now().subtract(const Duration(days: 30));
      final container = _container(
        sessions: [
          // Closed → out
          _session(
            id: 's-closed',
            memberId: 'a',
            start: start,
            end: DateTime.now(),
          ),
          // Sleep → out
          _session(
            id: 's-sleep',
            memberId: 'b',
            start: start,
            type: SessionType.sleep,
          ),
          // Deleted → out
          _session(
            id: 's-del',
            memberId: 'c',
            start: start,
            isDeleted: true,
          ),
          // Open + normal + not-deleted → in
          _session(id: 's-keep', memberId: 'd', start: start),
        ],
        members: [
          _member(id: 'a', isAlwaysFronting: true),
          _member(id: 'b', isAlwaysFronting: true),
          _member(id: 'c', isAlwaysFronting: true),
          _member(id: 'd'),
        ],
      );
      addTearDown(container.dispose);

      final result = await _drain(container);
      expect(result.map((q) => q.member.id), ['d']);
    });

    test(
      'multiple qualifying members are ordered by displayOrder, then by '
      'session start, then by id',
      () async {
        final start = DateTime.now().subtract(const Duration(days: 30));
        final container = _container(
          sessions: [
            _session(id: 's1', memberId: 'a', start: start),
            _session(
              id: 's2',
              memberId: 'b',
              // b's session started LATER than a's, but b has lower
              // displayOrder, so b should sort first.
              start: start.add(const Duration(hours: 1)),
            ),
            _session(id: 's3', memberId: 'c', start: start),
          ],
          members: [
            _member(id: 'a', displayOrder: 1),
            _member(id: 'b', displayOrder: 0),
            _member(id: 'c', displayOrder: 2),
          ],
        );
        addTearDown(container.dispose);

        final result = await _drain(container);
        expect(result.map((q) => q.member.id), ['b', 'a', 'c']);
      },
    );

    test('skips sessions with null memberId or unmatched memberId', () async {
      final start = DateTime.now().subtract(const Duration(days: 30));
      final container = _container(
        sessions: [
          _session(id: 's-null', start: start), // memberId null
          _session(id: 's-orphan', memberId: 'ghost', start: start),
          _session(id: 's-real', memberId: 'a', start: start),
        ],
        members: [_member(id: 'a')],
      );
      addTearDown(container.dispose);

      final result = await _drain(container);
      expect(result.map((q) => q.member.id), ['a']);
    });

    test(
      'no rebuild loop: when all qualifying sessions are already promoted, '
      'no Timer is needed and the provider value is stable',
      () async {
        final oldStart = DateTime.now().subtract(const Duration(days: 30));
        final container = _container(
          sessions: [
            _session(id: 's1', memberId: 'a', start: oldStart),
            _session(id: 's2', memberId: 'b', start: DateTime.now()),
          ],
          members: [
            _member(id: 'a'), // qualifies via age
            _member(id: 'b', isAlwaysFronting: true), // qualifies explicitly
          ],
        );
        addTearDown(container.dispose);

        final result = await _drain(container);
        expect(result.map((q) => q.member.id).toSet(), {'a', 'b'});
        // Pump a few extra microtasks; if a runaway timer were
        // scheduled at delay==0 it would invalidate-self into a loop.
        for (var i = 0; i < 5; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        final stable = container.read(alwaysPresentMembersProvider).value;
        expect(stable, isNotNull);
        expect(stable!.map((q) => q.member.id).toSet(), {'a', 'b'});
      },
    );

    test('returned list is immutable', () async {
      final start = DateTime.now().subtract(const Duration(days: 30));
      final container = _container(
        sessions: [_session(id: 's1', memberId: 'a', start: start)],
        members: [_member(id: 'a')],
      );
      addTearDown(container.dispose);

      final result = await _drain(container);
      expect(() => result.add(result.first), throwsUnsupportedError);
    });

    test('disposes scheduled timer cleanly when container is disposed',
        () async {
      // Indirect: schedule a timer (via a not-yet-promoted session) and
      // confirm that disposing the container does not throw or print
      // any pending-timer warnings. The provider's `ref.onDispose`
      // wires `timer.cancel`, so this should always pass.
      final start = DateTime.now().subtract(const Duration(days: 6));
      final container = _container(
        sessions: [_session(id: 's1', memberId: 'a', start: start)],
        members: [_member(id: 'a')],
      );
      await _drain(container);
      // No exceptions on dispose.
      container.dispose();
    });

    test(
      'threshold timer actually fires and surfaces the member after elapse',
      () {
        // Drive the provider with a fake clock + FakeAsync to exercise
        // the real Timer-firing path (not just the delay computation).
        // The session starts 1 hour shy of the auto-promote threshold;
        // before elapsing, the provider must NOT include the member.
        // After elapsing past the threshold, the timer must fire,
        // invalidate the provider, and the member must be present.
        FakeAsync().run((async) {
          var fakeNow = DateTime(2026, 1, 1, 12, 0, 0);
          DateTime now() => fakeNow;
          final start =
              fakeNow.subtract(kAutoPromoteThreshold - const Duration(hours: 1));
          final container = ProviderContainer(overrides: [
            activeSessionsProvider.overrideWith(
              (ref) => Stream.value([
                _session(id: 's1', memberId: 'a', start: start),
              ]),
            ),
            allMembersProvider.overrideWith(
              (ref) => Stream.value([_member(id: 'a')]),
            ),
            alwaysPresentClockProvider.overrideWithValue(now),
          ]);
          addTearDown(container.dispose);

          // Subscribe so the provider stays alive across invalidations.
          container.listen<AsyncValue<List<AlwaysPresentMember>>>(
            alwaysPresentMembersProvider,
            (_, _) {},
            fireImmediately: true,
          );

          // Pump the upstream streams.
          async.elapse(Duration.zero);
          expect(
            container.read(alwaysPresentMembersProvider).value,
            isEmpty,
            reason: 'session under threshold should not qualify yet',
          );

          // Advance the wall-clock past the auto-promote threshold AND
          // past the per-wake cap (6h), so the rescheduled wake fires.
          // After this, the member must be promoted.
          fakeNow = fakeNow.add(const Duration(hours: 2));
          async.elapse(const Duration(hours: 2));

          final after = container.read(alwaysPresentMembersProvider).value;
          expect(after, isNotNull);
          expect(after!.map((q) => q.member.id), ['a'],
              reason: 'timer should have fired and surfaced the member');
        });
      },
    );

    test(
      'wake cap reschedules without invalidating when wall clock has not '
      'crossed yet (e.g., NTP backward jump)',
      () {
        // Schedule a session whose crossing is 8 hours out (longer than
        // the 6h wake cap). The first wake fires at the cap before the
        // crossing and must NOT promote the member — instead, the timer
        // re-checks the (still-pre-crossing) clock and reschedules. The
        // provider value must stay empty across that wake.
        FakeAsync().run((async) {
          var fakeNow = DateTime(2026, 1, 1, 12, 0, 0);
          DateTime now() => fakeNow;
          final start = fakeNow.subtract(
              kAutoPromoteThreshold - const Duration(hours: 8));
          final container = ProviderContainer(overrides: [
            activeSessionsProvider.overrideWith(
              (ref) => Stream.value([
                _session(id: 's1', memberId: 'a', start: start),
              ]),
            ),
            allMembersProvider.overrideWith(
              (ref) => Stream.value([_member(id: 'a')]),
            ),
            alwaysPresentClockProvider.overrideWithValue(now),
          ]);
          addTearDown(container.dispose);

          var emitCount = 0;
          container.listen<AsyncValue<List<AlwaysPresentMember>>>(
            alwaysPresentMembersProvider,
            (_, _) => emitCount++,
            fireImmediately: true,
          );

          async.elapse(Duration.zero);
          final initialEmits = emitCount;
          expect(
            container.read(alwaysPresentMembersProvider).value,
            isEmpty,
          );

          // Advance only past the wake cap (6h) but not past the
          // crossing. FakeAsync's elapsed time advances; the fake wall
          // clock does NOT (simulates backward NTP jump or clock that
          // didn't progress as expected).
          //
          // Note: holding fakeNow constant while async time advances is
          // an extreme version of "wall clock didn't move with monotonic
          // time" — the rescheduling logic must handle it without
          // promoting the member.
          async.elapse(const Duration(hours: 7));

          // The timer fired but rescheduled (no invalidation).
          // Member must still NOT be qualifying.
          expect(
            container.read(alwaysPresentMembersProvider).value,
            isEmpty,
            reason:
                'wake cap should reschedule, not promote, when wall clock '
                'has not crossed yet',
          );
          // No extra emissions from invalidation (the listen path is
          // upstream-driven only).
          expect(emitCount, initialEmits,
              reason: 'rescheduling must not emit a new value');
        });
      },
    );
  });

  group('AlwaysPresentMember value type', () {
    test('equality compares all three fields', () {
      final member = _member(id: 'a');
      final session = _session(
        id: 's',
        memberId: 'a',
        start: DateTime(2026, 1, 1),
      );
      const age = Duration(days: 8);

      final a = AlwaysPresentMember(member: member, session: session, age: age);
      final b = AlwaysPresentMember(member: member, session: session, age: age);
      final c = AlwaysPresentMember(
        member: member,
        session: session,
        age: const Duration(days: 9),
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });
}
