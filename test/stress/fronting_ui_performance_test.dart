import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    hide FrontingSession, Member;
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/providers/derived_periods_provider.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/providers/timeline_providers.dart';
import 'package:prism_plurality/features/fronting/services/derive_periods.dart';
import 'package:prism_plurality/features/fronting/utils/current_fronters_order.dart';
import 'package:prism_plurality/features/fronting/utils/period_day_grouping.dart';
import 'package:prism_plurality/features/fronting/utils/session_day_grouping.dart';
import 'package:prism_plurality/features/settings/services/stress_data_generator.dart';

const _frontingUiPreset = StressPreset(
  label: 'Fronting UI Performance',
  members: 300,
  sessions: 12000,
  conversations: 20,
  messages: 2000,
  habits: 20,
  completions: 1000,
  notes: 100,
  polls: 20,
  groups: 40,
  customFields: 8,
  years: 3,
  estimatedSizeMb: 80,
  estimatedSeconds: 20,
  realisticProfiles: true,
  groupMembershipsPerMember: 8,
  customFieldValueCoverage: 0.75,
  imageLibraryItems: 40,
  memberAvatarEvery: 2,
  memberHeaderEvery: 4,
  groupAvatarEvery: 4,
  frontingDenseHistory: true,
  frontingMaxMembersPerSession: 5,
  activeFrontingMembers: 5,
);

Future<T> _expectUnder<T>(
  String label,
  FutureOr<T> Function() body, {
  required int budgetMs,
}) async {
  final sw = Stopwatch()..start();
  final result = await body();
  sw.stop();
  // Keep the measured wall-clock visible in expanded test output so local
  // benchmark runs can be compared without intentionally failing the test.
  // ignore: avoid_print
  print('$label: ${sw.elapsedMilliseconds}ms');
  expect(
    sw.elapsedMilliseconds,
    lessThan(budgetMs),
    reason: '$label should stay comfortably below ${budgetMs}ms',
  );
  return result;
}

const _stressTimeout = Timeout(Duration(minutes: 2));

void main() {
  late AppDatabase db;
  late DriftMemberRepository memberRepo;
  late DriftFrontingSessionRepository sessionRepo;

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    final generator = StressDataGenerator(db);
    await for (final _ in generator.generate(_frontingUiPreset)) {}
    await _ensureOpenFronts(db);

    memberRepo = DriftMemberRepository(db.membersDao, null);
    sessionRepo = DriftFrontingSessionRepository(db.frontingSessionsDao, null);
  });

  tearDownAll(() async {
    await db.close();
  });

  test(
    'quick front resolves and orders large member data quickly',
    () async {
      await _expectUnder('quick front data load and ordering', () async {
        final members = await memberRepo
            .watchQuickFrontMembersForList(
              recentLimit: 50,
              suggestionLimit: 12,
              excludedSuggestionMemberId: unknownSentinelMemberId,
            )
            .first;
        final sessions = await sessionRepo.watchActiveSessions().first;

        expect(members.length, lessThanOrEqualTo(17));
        expect(sessions.length, greaterThanOrEqualTo(5));
        expect(
          members.any((member) => member.profileHeaderImageData != null),
          isFalse,
        );
        expect(
          members.any((member) => member.pkBannerImageData != null),
          isFalse,
        );

        final currentFronters = orderCurrentFronters(sessions, members);
        final currentIds = {for (final m in currentFronters) m.id};
        final nonFronters = [
          for (final member in members)
            if (!currentIds.contains(member.id) &&
                member.id != unknownSentinelMemberId)
              member,
        ];
        final suggestions = nonFronters.take(8).toList();

        expect(currentFronters, isNotEmpty);
        expect(suggestions, isNotEmpty);
      }, budgetMs: 500);
    },
    timeout: _stressTimeout,
  );

  test(
    'combined fronting history loads derived list data quickly',
    () async {
      await _expectUnder('combined fronting history data load', () async {
        final members = await memberRepo.watchAllMembersForList().first;
        final recentRows = await sessionRepo
            .watchRecentAllSessions(limit: sessionPageSize)
            .first;
        final rangeStart = _derivedHistoryRangeStart(
          DateTime.now(),
          recentRows,
        );
        final overlapRows = await sessionRepo
            .watchSessionsOverlappingRange(
              rangeStart,
              DateTime.now().add(
                const Duration(days: derivedPeriodsLookaheadDays),
              ),
            )
            .first;
        final periods = computeDerivedPeriods(
          overlapRows,
          members,
          now: DateTime.now(),
          rangeStart: rangeStart,
        );
        final groups = groupHistoryByDay(
          periods: periods,
          sleepSessions: recentRows
              .where((session) => session.isSleep)
              .toList(),
        );
        final memberIds = _memberIdsForPeriods(periods);
        final memberMap = await memberRepo
            .watchMembersByIdsForList(memberIds.toList())
            .first;

        expect(overlapRows.length, greaterThanOrEqualTo(recentRows.length));
        expect(periods, isNotEmpty);
        expect(groups, isNotEmpty);
        expect(memberMap, isNotEmpty);
        expect(
          memberMap.any((member) => member.profileHeaderImageData != null),
          isFalse,
        );
      }, budgetMs: 1800);
    },
    timeout: _stressTimeout,
  );

  test('per-member fronting rows load and group quickly', () async {
    await _expectUnder('per-member fronting rows data load', () async {
      final recentRows = await sessionRepo
          .watchRecentAllSessions(limit: sessionPageSize)
          .first;
      final rangeStart = _derivedHistoryRangeStart(DateTime.now(), recentRows);
      final overlapRows = await sessionRepo
          .watchSessionsOverlappingRange(
            rangeStart,
            DateTime.now().add(
              const Duration(days: derivedPeriodsLookaheadDays),
            ),
          )
          .first;
      final activeSessions = await sessionRepo.watchActiveSessions().first;
      final members = await memberRepo.watchAllMembersForList().first;
      final alwaysPresentAnchors = _alwaysPresentAnchors(
        activeSessions,
        members,
        now: DateTime.now(),
      );

      final visibleRows = <FrontingSession>[];
      for (final session in overlapRows) {
        if (session.isSleep || session.isDeleted || session.memberId == null) {
          continue;
        }
        final anchor = alwaysPresentAnchors[session.memberId];
        if (anchor != null && !session.startTime.isBefore(anchor)) continue;
        visibleRows.add(session);
      }

      final frontGroups = groupSessionsByDay(visibleRows);
      final sleepGroups = groupSessionsByDay(
        recentRows.where((session) => session.isSleep).toList(),
      );
      final memberIds = {
        for (final session in visibleRows)
          if (session.memberId != null) session.memberId!,
      };
      final memberMap = await memberRepo
          .watchMembersByIdsForList(memberIds.toList())
          .first;

      expect(visibleRows, isNotEmpty);
      expect(frontGroups, isNotEmpty);
      expect(sleepGroups, isA<List<DayGroup>>());
      expect(memberMap, isNotEmpty);
    }, budgetMs: 1800);
  }, timeout: _stressTimeout);

  test('timeline fronting rows load quickly', () async {
    await _expectUnder('timeline fronting rows data load', () async {
      final sessions = await sessionRepo
          .watchRecentSessions(limit: timelineSessionPageSize)
          .first;
      final members = await memberRepo.watchAllMembersForList().first;

      final rowMap = <String, List<FrontingSession>>{};
      for (final session in sessions) {
        final memberId = session.memberId;
        if (memberId != null) {
          rowMap.putIfAbsent(memberId, () => []).add(session);
        }
      }

      final rows = <TimelineMemberRow>[];
      for (final member in members) {
        final memberSessions = rowMap[member.id];
        if (memberSessions != null && memberSessions.isNotEmpty) {
          rows.add(TimelineMemberRow(member: member, sessions: memberSessions));
        }
      }

      expect(sessions, isNotEmpty);
      expect(rows, isNotEmpty);
      expect(
        rows.any((row) => row.member.profileHeaderImageData != null),
        isFalse,
      );
    }, budgetMs: 1800);
  }, timeout: _stressTimeout);
}

Future<void> _ensureOpenFronts(AppDatabase db) async {
  final activeRows = await db.frontingSessionsDao.getActiveSessions();
  if (activeRows.length >= 5) return;

  final now = DateTime.now();
  await db.batch((batch) {
    for (var i = activeRows.length; i < 5; i++) {
      batch.insert(
        db.frontingSessions,
        FrontingSessionsCompanion.insert(
          id: 'stress-forced-active-$i',
          startTime: now.subtract(Duration(hours: i + 1)),
          memberId: Value('stress-member-$i'),
        ),
      );
    }
  });
}

DateTime _derivedHistoryRangeStart(
  DateTime now,
  List<FrontingSession> loadedRows,
) {
  final lookbackDays = _derivedHistoryLookbackDaysForLimit(sessionPageSize);
  DateTime? rangeStart;

  for (final session in loadedRows) {
    if (session.isDeleted || session.isSleep) continue;
    if (session.startTime.isAfter(now)) continue;

    final rawAnchor = session.endTime ?? now;
    final displayAnchor = rawAnchor.isAfter(now) ? now : rawAnchor;
    final boundedStart = displayAnchor.subtract(Duration(days: lookbackDays));
    final candidateStart = session.startTime.isAfter(boundedStart)
        ? session.startTime
        : boundedStart;
    if (rangeStart == null || candidateStart.isBefore(rangeStart)) {
      rangeStart = candidateStart;
    }
  }
  return rangeStart ??
      now.subtract(const Duration(days: derivedPeriodsInitialLookbackDays));
}

int _derivedHistoryLookbackDaysForLimit(int limit) {
  final safeLimit = limit <= 0 ? sessionPageSize : limit;
  final pages = (safeLimit + sessionPageSize - 1) ~/ sessionPageSize;
  final days = pages * derivedPeriodsInitialLookbackDays;
  return days > derivedPeriodsLookbackDays ? derivedPeriodsLookbackDays : days;
}

Set<String> _memberIdsForPeriods(List<FrontingPeriod> periods) {
  final ids = <String>{};
  for (final period in periods) {
    ids.addAll(period.activeMembers);
    ids.addAll(period.alwaysPresentMembers);
    for (final visitor in period.briefVisitors) {
      ids.add(visitor.memberId);
    }
  }
  return ids;
}

Map<String, DateTime> _alwaysPresentAnchors(
  List<FrontingSession> activeSessions,
  List<Member> members, {
  required DateTime now,
}) {
  final byId = {for (final member in members) member.id: member};
  final anchors = <String, DateTime>{};
  for (final session in activeSessions) {
    if (session.endTime != null) continue;
    if (session.sessionType != SessionType.normal) continue;
    if (session.isDeleted) continue;
    final memberId = session.memberId;
    if (memberId == null) continue;
    final member = byId[memberId];
    if (member == null) continue;
    final age = now.difference(session.startTime);
    final qualifies = member.isAlwaysFronting || age >= const Duration(days: 7);
    if (!qualifies) continue;
    final existing = anchors[memberId];
    if (existing == null || session.startTime.isBefore(existing)) {
      anchors[memberId] = session.startTime;
    }
  }
  return anchors;
}
