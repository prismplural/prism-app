import 'package:prism_plurality/core/mutations/app_failure.dart';
import 'package:prism_plurality/core/mutations/mutation_result.dart';
import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/core/services/session_lifecycle_service.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/features/fronting/models/update_fronting_session_patch.dart';
import 'package:uuid/uuid.dart';

class FrontingMutationResult {
  const FrontingMutationResult({
    required this.session,
    this.previousMemberIds = const [],
  });

  final FrontingSession session;
  final List<String?> previousMemberIds;
}

class FrontingMutationService {
  FrontingMutationService({
    required FrontingSessionRepository repository,
    required MutationRunner mutationRunner,
    SessionLifecycleService lifecycle = const SessionLifecycleService(),
    Uuid? uuid,
  }) : _repository = repository,
       _mutationRunner = mutationRunner,
       _lifecycle = lifecycle,
       _uuid = uuid ?? const Uuid();

  final FrontingSessionRepository _repository;
  final MutationRunner _mutationRunner;
  final SessionLifecycleService _lifecycle;
  final Uuid _uuid;

  Future<MutationResult<FrontingMutationResult>> startFronting(
    String memberId, {
    List<String> coFronterIds = const [],
  }) {
    return _mutationRunner.run<FrontingMutationResult>(
      actionLabel: 'Start fronting session',
      action: () async {
        final activeSessions = await _repository
            .getAllActiveSessionsUnfiltered();
        final previousMemberIds = activeSessions
            .map((s) => s.memberId)
            .toList();
        final now = DateTime.now();
        for (final session in activeSessions) {
          await _repository.endSession(session.id, now);
        }

        final created = FrontingSession(
          id: _uuid.v4(),
          startTime: now,
          memberId: memberId,
          coFronterIds: coFronterIds,
        );
        await _repository.createSession(created);
        return FrontingMutationResult(
          session: created,
          previousMemberIds: previousMemberIds,
        );
      },
    );
  }

  Future<MutationResult<FrontingMutationResult>> startFrontingWithDetails({
    required String? memberId,
    List<String> coFronterIds = const [],
    FrontConfidence? confidence,
    String? notes,
    DateTime? startTime,
  }) {
    return _mutationRunner.run<FrontingMutationResult>(
      actionLabel: 'Start detailed fronting session',
      action: () async {
        final activeSessions = await _repository
            .getAllActiveSessionsUnfiltered();
        final previousMemberIds = activeSessions
            .map((s) => s.memberId)
            .toList();
        final now = startTime ?? DateTime.now();
        for (final session in activeSessions) {
          await _repository.endSession(session.id, now);
        }

        final created = FrontingSession(
          id: _uuid.v4(),
          startTime: now,
          memberId: memberId,
          coFronterIds: coFronterIds,
          confidence: confidence,
          notes: notes,
        );
        await _repository.createSession(created);
        return FrontingMutationResult(
          session: created,
          previousMemberIds: previousMemberIds,
        );
      },
    );
  }

  Future<MutationResult<List<String?>>> endFronting() {
    return _mutationRunner.run<List<String?>>(
      actionLabel: 'End fronting session',
      action: () async {
        final activeSessions = await _repository
            .getAllActiveSessionsUnfiltered();
        final previousMemberIds = activeSessions
            .map((s) => s.memberId)
            .toList();
        final now = DateTime.now();
        for (final session in activeSessions) {
          await _repository.endSession(session.id, now);
        }
        return previousMemberIds;
      },
    );
  }

  Future<MutationResult<FrontingMutationResult>> switchFronter(
    String newMemberId, {
    required int thresholdSeconds,
  }) {
    return _mutationRunner.run<FrontingMutationResult>(
      actionLabel: 'Switch fronter',
      action: () async {
        final activeSessions = await _repository
            .getAllActiveSessionsUnfiltered();
        final previousMemberIds = activeSessions
            .map((s) => s.memberId)
            .toList();
        final activeSession = await _repository.getActiveSession();
        final action = _lifecycle.evaluateQuickSwitch(
          activeSession,
          thresholdSeconds: thresholdSeconds,
        );

        switch (action) {
          case QuickSwitchAction.correctExisting:
            if (activeSession == null) {
              throw AppFailure.notFound(
                'No active fronting session to correct.',
              );
            }
            // End any other active sessions (e.g. from sync) to avoid
            // multiple active sessions co-existing after the correction.
            final now = DateTime.now();
            for (final session in activeSessions) {
              if (session.id != activeSession.id) {
                await _repository.endSession(session.id, now);
              }
            }
            final corrected = activeSession.copyWith(memberId: newMemberId);
            await _repository.updateSession(corrected);
            return FrontingMutationResult(
              session: corrected,
              previousMemberIds: previousMemberIds,
            );
          case QuickSwitchAction.createNew:
            final now = DateTime.now();
            for (final session in activeSessions) {
              await _repository.endSession(session.id, now);
            }
            final created = FrontingSession(
              id: _uuid.v4(),
              startTime: now,
              memberId: newMemberId,
            );
            await _repository.createSession(created);
            return FrontingMutationResult(
              session: created,
              previousMemberIds: previousMemberIds,
            );
        }
      },
    );
  }

  Future<MutationResult<FrontingMutationResult>> startSleep({
    String? notes,
    DateTime? startTime,
    SleepQuality? quality,
  }) {
    return _mutationRunner.run<FrontingMutationResult>(
      actionLabel: 'Start sleep session',
      action: () async {
        final activeSessions = await _repository
            .getAllActiveSessionsUnfiltered();
        final previousMemberIds = activeSessions
            .map((s) => s.memberId)
            .toList();
        final now = startTime ?? DateTime.now();
        for (final session in activeSessions) {
          await _repository.endSession(session.id, now);
        }

        final created = FrontingSession(
          id: _uuid.v4(),
          startTime: now,
          memberId: null,
          coFronterIds: const [],
          notes: notes,
          sessionType: SessionType.sleep,
          quality: quality ?? SleepQuality.unknown,
        );
        await _repository.createSession(created);
        return FrontingMutationResult(
          session: created,
          previousMemberIds: previousMemberIds,
        );
      },
    );
  }

  Future<MutationResult<void>> endSleep(String id) {
    return _mutationRunner.run<void>(
      actionLabel: 'End sleep session',
      action: () async {
        final session = await _requireSession(id);
        if (!session.isSleep) {
          throw AppFailure.notFound('Sleep session not found.');
        }
        await _repository.endSession(id, DateTime.now());
      },
    );
  }

  Future<MutationResult<FrontingSession>> updateSleepQuality(
    String id,
    SleepQuality quality,
  ) {
    return _mutationRunner.run<FrontingSession>(
      actionLabel: 'Update sleep quality',
      action: () async {
        final session = await _requireSession(id);
        final updated = session.copyWith(quality: quality);
        await _repository.updateSession(updated);
        return updated;
      },
    );
  }

  Future<MutationResult<void>> deleteSleep(String id) {
    return _mutationRunner.run<void>(
      actionLabel: 'Delete sleep session',
      action: () async {
        final session = await _requireSession(id);
        if (!session.isSleep) {
          throw AppFailure.notFound('Sleep session not found.');
        }
        await _repository.deleteSession(id);
      },
    );
  }

  Future<MutationResult<FrontingSession>> addCoFronter(String memberId) {
    return _mutationRunner.run<FrontingSession>(
      actionLabel: 'Add co-fronter',
      action: () async {
        final session = await _requireActiveSession();
        final coFronterIds = session.coFronterIds.toSet();
        if (!coFronterIds.add(memberId)) {
          return session;
        }

        final updated = session.copyWith(coFronterIds: coFronterIds.toList());
        await _repository.updateSession(updated);
        return updated;
      },
    );
  }

  Future<MutationResult<FrontingSession>> removeCoFronter(String memberId) {
    return _mutationRunner.run<FrontingSession>(
      actionLabel: 'Remove co-fronter',
      action: () async {
        final session = await _requireActiveSession();
        final updated = session.copyWith(
          coFronterIds: session.coFronterIds
              .where((id) => id != memberId)
              .toList(),
        );
        await _repository.updateSession(updated);
        return updated;
      },
    );
  }

  Future<MutationResult<FrontingSession>> updateSession(
    String sessionId,
    UpdateFrontingSessionPatch patch,
  ) {
    return _mutationRunner.run<FrontingSession>(
      actionLabel: 'Update fronting session',
      action: () async {
        final session = await _requireSession(sessionId);
        final updated = patch.applyTo(session);
        await _repository.updateSession(updated);
        return updated;
      },
    );
  }

  Future<MutationResult<FrontingSession>> applyEdit({
    required String sessionId,
    required UpdateFrontingSessionPatch patch,
    List<FrontingSession> overlapsToTrim = const [],
    List<FrontingSession> adjacentMerges = const [],
    List<GapInfo> gapsToFill = const [],
  }) {
    return saveValidatedEdit(
      sessionId: sessionId,
      patch: patch,
      validationResult: EditValidationResult(
        overlaps: overlapsToTrim,
        adjacentMerges: adjacentMerges,
        gapsCreated: gapsToFill,
      ),
      trimOverlaps: overlapsToTrim.isNotEmpty,
    );
  }

  Future<MutationResult<FrontingSession>> saveValidatedEdit({
    required String sessionId,
    required UpdateFrontingSessionPatch patch,
    required EditValidationResult validationResult,
    bool trimOverlaps = false,
  }) {
    return _mutationRunner.run<FrontingSession>(
      actionLabel: 'Save fronting edit',
      action: () async {
        final session = await _requireSession(sessionId);
        var updated = patch.applyTo(session);

        if (trimOverlaps) {
          for (final overlap in validationResult.overlaps) {
            await _lifecycle.trimOverlap(updated, overlap, _repository);
          }
        }

        if (validationResult.hasAdjacentMerges) {
          updated = await _lifecycle.mergeAdjacent(
            updated,
            validationResult.adjacentMerges,
            _repository,
          );
        }

        if (validationResult.gapsCreated.isNotEmpty) {
          await _lifecycle.fillGaps(validationResult.gapsCreated, _repository);
        }

        await _repository.updateSession(updated);
        return updated;
      },
    );
  }

  Future<MutationResult<String?>> deleteSession(
    DeleteOption option,
    DeleteContext context,
  ) {
    return _mutationRunner.run<String?>(
      actionLabel: 'Delete fronting session',
      action: () => _lifecycle.executeDelete(option, context, _repository),
    );
  }

  Future<MutationResult<String?>> executeDeleteOption({
    required String sessionId,
    required DeleteOption option,
    required List<FrontingSession> allSessions,
  }) {
    return _mutationRunner.run<String?>(
      actionLabel: 'Delete fronting session',
      action: () async {
        final session = await _requireSession(sessionId);
        final context = _lifecycle.getDeleteOptions(session, allSessions);
        return _lifecycle.executeDelete(option, context, _repository);
      },
    );
  }

  Future<MutationResult<FrontingSession>> splitSession({
    required String sessionId,
    required DateTime splitTime,
    String? firstMemberId,
    String? secondMemberId,
  }) {
    return _mutationRunner.run<FrontingSession>(
      actionLabel: 'Split fronting session',
      action: () async {
        final session = await _requireSession(sessionId);

        final firstHalf = session.copyWith(
          endTime: splitTime,
          memberId: firstMemberId ?? session.memberId,
        );
        await _repository.updateSession(firstHalf);

        final secondHalf = FrontingSession(
          id: _uuid.v4(),
          startTime: splitTime,
          endTime: session.endTime,
          memberId: secondMemberId ?? session.memberId,
          coFronterIds: session.coFronterIds,
          confidence: session.confidence,
          notes: session.notes,
          pluralkitUuid: session.pluralkitUuid,
          sessionType: session.sessionType,
          quality: session.quality,
          isHealthKitImport: session.isHealthKitImport,
        );
        await _repository.createSession(secondHalf);
        return secondHalf;
      },
    );
  }

  Future<FrontingSession> _requireSession(String sessionId) async {
    final session = await _repository.getSessionById(sessionId);
    if (session == null) {
      throw AppFailure.notFound('Fronting session not found.');
    }
    return session;
  }

  Future<FrontingSession> _requireActiveSession() async {
    final session = await _repository.getActiveSession();
    if (session == null) {
      throw AppFailure.notFound('No active fronting session found.');
    }
    return session;
  }
}
