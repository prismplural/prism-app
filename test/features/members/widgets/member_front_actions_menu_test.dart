import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    hide Member, FrontingSession;
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/services/fronting_mutation_service.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/widgets/member_front_actions_menu.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';

/// Instrumentation delegates to the real notifier and mutation service.
class _CountingNotifier extends FrontingNotifier {
  int adds = 0;
  int replaces = 0;
  int ends = 0;
  Completer<void>? gate;
  bool failNextAdd = false;

  @override
  Future<void> startFronting(
    List<String> memberIds, {
    FrontConfidence? confidence,
    String? notes,
    DateTime? startTime,
  }) async {
    adds++;
    if (gate != null) await gate!.future;
    if (failNextAdd) {
      failNextAdd = false;
      throw StateError('Synthetic failure before mutation');
    }
    await super.startFronting(
      memberIds,
      confidence: confidence,
      notes: notes,
      startTime: startTime,
    );
  }

  @override
  Future<void> replaceFronting(
    List<String> memberIds, {
    FrontConfidence? confidence,
    String? notes,
    DateTime? startTime,
  }) async {
    replaces++;
    if (gate != null) await gate!.future;
    await super.replaceFronting(
      memberIds,
      confidence: confidence,
      notes: notes,
      startTime: startTime,
    );
  }

  @override
  Future<void> endFronting(List<String> memberIds) async {
    ends++;
    await super.endFronting(memberIds);
  }
}

class _GatedReadRepository extends DriftFrontingSessionRepository {
  _GatedReadRepository(AppDatabase db) : super(db.frontingSessionsDao, null);
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<List<FrontingSession>> getAllActiveSessionsUnfiltered() async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    return super.getAllActiveSessionsUnfiltered();
  }
}

/// Capture real previous-data states through public refresh/error transitions.
Future<AsyncValue<List<T>>> _previousDataState<T>(
  List<T> data, {
  required bool loading,
}) async {
  final updates = StreamController<List<T>>.broadcast(sync: true);
  final provider = StreamProvider<List<T>>((ref) => updates.stream);
  final container = ProviderContainer();
  try {
    container.listen(provider, (previous, next) {});
    final first = container.read(provider.future);
    updates.add(data);
    printOnFailure('previous-data helper phase: initial data');
    await first.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        throw TimeoutException(
          'previous-data helper initial data timed out',
        );
      },
    );
    late AsyncValue<List<T>> snapshot;
    if (loading) {
      container.invalidate(provider);
      snapshot = container.read(provider);
      expect(snapshot.isLoading, isTrue);
    } else {
      final failed = Completer<AsyncValue<List<T>>>();
      final subscription = container.listen(provider, (previous, next) {
        if (next.hasError && !failed.isCompleted) failed.complete(next);
      });
      updates.addError(
        StateError('Synthetic stream error'),
        StackTrace.current,
      );
      printOnFailure('previous-data helper phase: controlled error');
      snapshot = await failed.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException(
            'previous-data helper controlled error timed out',
          );
        },
      );
      subscription.close();
      expect(snapshot.hasError, isTrue);
    }
    expect(snapshot.hasValue, isTrue, reason: 'control must retain prior data');
    expect(snapshot.value, data);
    return snapshot;
  } finally {
    container.dispose();
    await updates.close();
  }
}

void main() {
  late AppDatabase db;
  late DriftFrontingSessionRepository sessions;
  late DriftMemberRepository members;
  late ProviderContainer container;
  late _CountingNotifier notifier;
  late ProviderSubscription<bool> busyOwner;
  late FrontingSessionRepository selectedRepository;
  var containerDisposed = false;
  late Member alice;
  late Member bob;
  late Member protected;
  late FrontingSession bobSession;
  late StreamController<List<FrontingSession>> activeUpdates;

  Future<T> setupPhase<T>(String name, Future<T> operation) {
    printOnFailure('fixture phase: $name');
    return operation.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        throw TimeoutException('fixture setup phase timed out: $name');
      },
    );
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final ownedDb = db;
    addTearDown(ownedDb.close);
    sessions = DriftFrontingSessionRepository(db.frontingSessionsDao, null);
    members = DriftMemberRepository(db.membersDao, null);
    alice = Member(id: 'alice', name: 'Alice', createdAt: DateTime(2024));
    bob = Member(id: 'bob', name: 'Bob', createdAt: DateTime(2024));
    protected = Member(
      id: 'protected',
      name: 'Protected',
      createdAt: DateTime(2024),
      isAlwaysFronting: true,
    );
    for (final member in [alice, bob, protected]) {
      await setupPhase(
        'create member ${member.id}',
        members.createMember(member),
      );
    }
    bobSession = FrontingSession(
      id: 'bob-session',
      memberId: bob.id,
      startTime: DateTime(2024),
    );
    await setupPhase(
      'create initial Bob session',
      sessions.createSession(bobSession),
    );
    final ownedUpdates = StreamController<List<FrontingSession>>();
    addTearDown(() async {
      await ownedUpdates.close();
    });
    activeUpdates = ownedUpdates;
    notifier = _CountingNotifier();
    selectedRepository = sessions;
    containerDisposed = false;
    final service = FrontingMutationService(
      repository: sessions,
      memberRepository: members,
      mutationRunner: MutationRunner(transactionRunner: db.transaction),
    );
    container = ProviderContainer(
      overrides: [
        memberRepositoryProvider.overrideWithValue(members),
        frontingSessionRepositoryProvider.overrideWith(
          (ref) => selectedRepository,
        ),
        frontingMutationServiceProvider.overrideWithValue(service),
        frontingNotifierProvider.overrideWith(() => notifier),
        frontingRemindersEnabledProvider.overrideWithValue(false),
        quickSwitchThresholdProvider.overrideWithValue(0),
        // Deliberately hold stream acknowledgement behind completed mutations.
        // Actual writes still use the real Drift repositories and service.
        activeSessionsProvider.overrideWith((ref) => activeUpdates.stream),
      ],
    );
    final ownedContainer = container;
    addTearDown(() {
      if (!containerDisposed) ownedContainer.dispose();
    });
    // Own each asynchronous provider before waiting for its first value.
    container.listen(activeSessionsProvider, (previous, next) {});
    container.listen(allMemberListProvider, (previous, next) {});
    container.listen(frontingNotifierProvider, (previous, next) {});
    final initial = container.read(activeSessionsProvider.future);
    activeUpdates.add([bobSession]);
    await setupPhase('initial active session stream', initial);
    await setupPhase(
      'initial lightweight roster stream',
      container.read(allMemberListProvider.future),
    );
    await setupPhase(
      'fronting notifier initialization',
      container.read(frontingNotifierProvider.future),
    );
    busyOwner = container.listen(
      memberFrontActionBusyProvider,
      (previous, next) {},
    );
  });

  Future<void> acknowledge(List<FrontingSession> rows) async {
    final seen = Completer<void>();
    final sub = container.listen(activeSessionsProvider, (previous, next) {
      if (identical(next.value, rows) && !seen.isCompleted) seen.complete();
    });
    activeUpdates.add(rows);
    await seen.future;
    sub.close();
  }

  test(
    'real Drift add rejects in-flight and pre-ack repeat without ending Bob',
    () async {
      final submit = container.read(memberFrontActionBusyProvider.notifier);
      notifier.gate = Completer<void>();
      final first = submit.submit(alice, MemberFrontAction.add);
      expect(await submit.submit(alice, MemberFrontAction.add), isFalse);
      notifier.gate!.complete();
      expect(await first, isTrue);
      expect(await submit.submit(alice, MemberFrontAction.replace), isFalse);
      expect(notifier.adds, 1);
      expect(notifier.replaces, 0);
      final rows = await sessions.getAllActiveSessionsUnfiltered();
      expect(rows.where((row) => row.memberId == alice.id), hasLength(1));
      expect(
        rows.singleWhere((row) => row.id == bobSession.id).isActive,
        isTrue,
      );
      await acknowledge(rows);
      expect(await submit.submit(alice, MemberFrontAction.replace), isFalse);
      expect(notifier.replaces, 0);
    },
  );

  test(
    'real Drift replace preserves protected front and rejects stale replay',
    () async {
      final pinned = FrontingSession(
        id: 'protected-session',
        memberId: protected.id,
        startTime: DateTime(2024),
      );
      await sessions.createSession(pinned);
      await acknowledge([bobSession, pinned]);
      final submit = container.read(memberFrontActionBusyProvider.notifier);
      expect(await submit.submit(alice, MemberFrontAction.replace), isTrue);
      // A co-fronter appears after replace completes but before its UI stream ack.
      final later = FrontingSession(
        id: 'later-bob',
        memberId: bob.id,
        startTime: DateTime.now(),
      );
      await sessions.createSession(later);
      expect(await submit.submit(alice, MemberFrontAction.replace), isFalse);
      expect(notifier.replaces, 1);
      final rows = await sessions.getAllActiveSessionsUnfiltered();
      expect(rows.where((row) => row.memberId == alice.id), hasLength(1));
      expect(rows.any((row) => row.id == later.id), isTrue);
      expect(rows.any((row) => row.id == pinned.id), isTrue);
      expect((await sessions.getSessionById(bobSession.id))!.isActive, isFalse);
    },
  );

  test(
    'real Drift end affects only selected member and protected end never dispatches',
    () async {
      final aliceSession = FrontingSession(
        id: 'alice-session',
        memberId: alice.id,
        startTime: DateTime(2024),
      );
      final pinned = FrontingSession(
        id: 'protected-session',
        memberId: protected.id,
        startTime: DateTime(2024),
      );
      await sessions.createSession(aliceSession);
      await sessions.createSession(pinned);
      await acknowledge([bobSession, aliceSession, pinned]);
      final submit = container.read(memberFrontActionBusyProvider.notifier);
      expect(await submit.submit(protected, MemberFrontAction.end), isFalse);
      expect(await submit.submit(alice, MemberFrontAction.end), isTrue);
      expect(notifier.ends, 1);
      expect(
        (await sessions.getSessionById(aliceSession.id))!.isActive,
        isFalse,
      );
      expect((await sessions.getSessionById(bobSession.id))!.isActive, isTrue);
      expect((await sessions.getSessionById(pinned.id))!.isActive, isTrue);
    },
  );

  test(
    'real Drift failure releases submission guard for retry',
    () async {
      final submit = container.read(memberFrontActionBusyProvider.notifier);
      notifier.failNextAdd = true;
      await expectLater(
        submit.submit(alice, MemberFrontAction.add),
        throwsStateError,
      );
      expect(container.read(memberFrontActionBusyProvider), isFalse);
      expect(await submit.submit(alice, MemberFrontAction.add), isTrue);
      expect(notifier.adds, 2);
      final rows = await sessions.getAllActiveSessionsUnfiltered();
      expect(rows.where((row) => row.memberId == alice.id), hasLength(1));
      expect(rows.any((row) => row.id == bobSession.id), isTrue);
    },
  );

  test(
    'real Drift coalesced A ack allows legitimate A add after B-only',
    () async {
      final submit = container.read(memberFrontActionBusyProvider.notifier);
      expect(await submit.submit(alice, MemberFrontAction.add), isTrue);
      // End A through another fronting surface before A ever appears in this stream.
      await container.read(frontingNotifierProvider.notifier).replaceFronting([
        bob.id,
      ]);
      await acknowledge(await sessions.getAllActiveSessionsUnfiltered());
      expect(await submit.submit(alice, MemberFrontAction.add), isTrue);
      final rows = await sessions.getAllActiveSessionsUnfiltered();
      expect(rows.where((row) => row.memberId == alice.id), hasLength(1));
      expect(rows.where((row) => row.memberId == bob.id), hasLength(1));
      expect(await submit.submit(alice, MemberFrontAction.replace), isFalse);
      expect(
        notifier.replaces,
        1,
        reason: 'only the explicit B replacement dispatched',
      );
      expect(
        (await sessions.getAllActiveSessionsUnfiltered()).any(
          (row) => row.memberId == bob.id,
        ),
        isTrue,
      );
    },
  );

  test('real Drift deleted roster member never dispatches', () async {
    final submit = container.read(memberFrontActionBusyProvider.notifier);
    final deletedSeen = Completer<void>();
    final rosterSubscription = container.listen(allMemberListProvider, (
      previous,
      next,
    ) {
      final roster = next.value;
      if (roster != null &&
          !roster.any((member) => member.id == alice.id && !member.isDeleted) &&
          !deletedSeen.isCompleted) {
        deletedSeen.complete();
      }
    });
    await members.deleteMember(alice.id);
    await deletedSeen.future;
    rosterSubscription.close();
    expect(await submit.submit(alice, MemberFrontAction.add), isFalse);
    expect(notifier.adds, 0);
    expect(await sessions.getSessionById(bobSession.id), isNotNull);
  });

  for (final input in ['sessions', 'roster']) {
    for (final state in ['loading', 'error']) {
      test(
        '$input $state with previous data refuses dispatch',
        () async {
          final previousSessions = AsyncData<List<FrontingSession>>([
            bobSession,
          ]);
          final previousRoster = AsyncData<List<Member>>([
            alice,
            bob,
            protected,
          ]);
          final staleSessions = await _previousDataState(
            previousSessions.requireValue,
            loading: state == 'loading',
          );
          final staleRoster = await _previousDataState(
            previousRoster.requireValue,
            loading: state == 'loading',
          );
          final isolated = ProviderContainer(
            overrides: [
              frontingSessionRepositoryProvider.overrideWithValue(sessions),
              frontingNotifierProvider.overrideWith(_CountingNotifier.new),
              activeSessionsProvider.overrideWithValue(
                input == 'sessions' ? staleSessions : previousSessions,
              ),
              allMemberListProvider.overrideWithValue(
                input == 'roster' ? staleRoster : previousRoster,
              ),
            ],
          );
          try {
            final submit = isolated.read(
              memberFrontActionBusyProvider.notifier,
            );
            expect(await submit.submit(alice, MemberFrontAction.add), isFalse);
            expect(
              (isolated.read(frontingNotifierProvider.notifier)
                      as _CountingNotifier)
                  .adds,
              0,
            );
            expect((await sessions.getAllActiveSessionsUnfiltered()).length, 1);
          } finally {
            isolated.dispose();
          }
        },
      );
    }
  }

  Future<_GatedReadRepository> useGatedRead() async {
    final gated = _GatedReadRepository(db);
    selectedRepository = gated;
    container.invalidate(frontingSessionRepositoryProvider);
    return gated;
  }

  test(
    'repo epoch change during durable read prevents old-scope dispatch',
    () async {
      final gated = await useGatedRead();
      final operation = container
          .read(memberFrontActionBusyProvider.notifier)
          .submit(alice, MemberFrontAction.add);
      await gated.entered.future;
      selectedRepository = sessions;
      container.invalidate(frontingSessionRepositoryProvider);
      gated.release.complete();
      expect(await operation, isFalse);
      expect(notifier.adds, 0);
      expect((await sessions.getAllActiveSessionsUnfiltered()).length, 1);
    },
  );

  test(
    'dispose during durable read returns without dispatch or state-after-dispose',
    () async {
      final gated = await useGatedRead();
      final operation = container
          .read(memberFrontActionBusyProvider.notifier)
          .submit(alice, MemberFrontAction.add);
      await gated.entered.future;
      container.dispose();
      containerDisposed = true;
      gated.release.complete();
      expect(await operation, isFalse);
      expect(notifier.adds, 0);
      expect((await sessions.getAllActiveSessionsUnfiltered()).length, 1);
    },
  );

  test(
    'unmount remount retains in-flight serialization until lease closes',
    () async {
      final gated = await useGatedRead();
      final first = container.read(memberFrontActionBusyProvider.notifier);
      final operation = first.submit(alice, MemberFrontAction.add);
      await gated.entered.future;
      busyOwner.close();
      await container.pump();
      busyOwner = container.listen(
        memberFrontActionBusyProvider,
        (previous, next) {},
      );
      final remounted = container.read(memberFrontActionBusyProvider.notifier);
      expect(identical(first, remounted), isTrue);
      expect(await remounted.submit(alice, MemberFrontAction.add), isFalse);
      gated.release.complete();
      expect(await operation, isTrue);
      expect(notifier.adds, 1);
      busyOwner.close();
      await container.pump();
      busyOwner = container.listen(
        memberFrontActionBusyProvider,
        (previous, next) {},
      );
      expect(
        identical(
          first,
          container.read(memberFrontActionBusyProvider.notifier),
        ),
        isFalse,
      );
      expect(
        (await sessions.getAllActiveSessionsUnfiltered()).where(
          (row) => row.memberId == alice.id,
        ),
        hasLength(1),
      );
    },
  );

  for (final input in ['sessions', 'roster']) {
    for (final state in ['loading', 'error']) {
      test(
        '$input $state arriving during durable read refuses dispatch',
        () async {
          final gated = _GatedReadRepository(db);
          final counter = _CountingNotifier();
          _CountingNotifier counterFactory() => counter;
          final initialSessions = AsyncData<List<FrontingSession>>([
            bobSession,
          ]);
          final initialRoster = AsyncData<List<Member>>([
            alice,
            bob,
            protected,
          ]);
          final isolated = ProviderContainer(
            overrides: [
              frontingSessionRepositoryProvider.overrideWithValue(gated),
              frontingNotifierProvider.overrideWith(counterFactory),
              activeSessionsProvider.overrideWithValue(initialSessions),
              allMemberListProvider.overrideWithValue(initialRoster),
            ],
          );
          final owner = isolated.listen(
            memberFrontActionBusyProvider,
            (previous, next) {},
          );
          try {
            final operation = isolated
                .read(memberFrontActionBusyProvider.notifier)
                .submit(alice, MemberFrontAction.add);
            await gated.entered.future;
            final sessionState = await _previousDataState(
              initialSessions.requireValue,
              loading: state == 'loading',
            );
            final rosterState = await _previousDataState(
              initialRoster.requireValue,
              loading: state == 'loading',
            );
            isolated.updateOverrides([
              frontingSessionRepositoryProvider.overrideWithValue(gated),
              frontingNotifierProvider.overrideWith(counterFactory),
              activeSessionsProvider.overrideWithValue(
                input == 'sessions' ? sessionState : initialSessions,
              ),
              allMemberListProvider.overrideWithValue(
                input == 'roster' ? rosterState : initialRoster,
              ),
            ]);
            gated.release.complete();
            expect(await operation, isFalse);
            expect(counter.adds, 0);
            expect((await sessions.getAllActiveSessionsUnfiltered()).length, 1);
          } finally {
            if (!gated.release.isCompleted) gated.release.complete();
            owner.close();
            isolated.dispose();
          }
        },
      );
    }
  }
}
