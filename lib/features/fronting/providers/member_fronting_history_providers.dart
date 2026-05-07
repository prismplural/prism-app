import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/data/mappers/fronting_session_mapper.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/providers/derived_periods_provider.dart';
import 'package:prism_plurality/features/fronting/services/derive_periods.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';

const memberFrontingHistoryPageSize = 30;

class MemberFrontingHistoryLimitNotifier extends Notifier<int> {
  @override
  int build() => memberFrontingHistoryPageSize;

  void loadMore() => state = state + memberFrontingHistoryPageSize;
}

final memberFrontingHistoryLimitProvider = NotifierProvider.autoDispose
    .family<MemberFrontingHistoryLimitNotifier, int, String>(
      (_) => MemberFrontingHistoryLimitNotifier(),
    );

class MemberFrontingHistoryData {
  const MemberFrontingHistoryData({
    required this.periods,
    required this.targetSessions,
    required this.hasMore,
  });

  final List<FrontingPeriod> periods;
  final List<FrontingSession> targetSessions;
  final bool hasMore;

  DateTime? get oldestLoadedStart {
    DateTime? oldest;
    for (final session in targetSessions) {
      if (oldest == null || session.startTime.isBefore(oldest)) {
        oldest = session.startTime;
      }
    }
    return oldest;
  }
}

typedef _HistoryRange = ({DateTime start, DateTime end});

final _memberFrontingHistoryTargetSessionsProvider = StreamProvider.autoDispose
    .family<List<FrontingSession>, String>((ref, memberId) {
      final limit = ref.watch(memberFrontingHistoryLimitProvider(memberId));
      final dao = ref.watch(frontingSessionsDaoProvider);
      return dao
          .watchRecentSessionsForMember(memberId, limit: limit)
          .map((rows) => rows.map(FrontingSessionMapper.toDomain).toList());
    });

final _frontingSessionsOverlappingRangeProvider = StreamProvider.autoDispose
    .family<List<FrontingSession>, _HistoryRange>((ref, range) {
      final dao = ref.watch(frontingSessionsDaoProvider);
      return dao
          .watchSessionsOverlappingRange(range.start, range.end)
          .map((rows) => rows.map(FrontingSessionMapper.toDomain).toList());
    });

final memberFrontingHistoryProvider = Provider.autoDispose
    .family<AsyncValue<MemberFrontingHistoryData>, String>((ref, memberId) {
      final limit = ref.watch(memberFrontingHistoryLimitProvider(memberId));
      final targetAsync = ref.watch(
        _memberFrontingHistoryTargetSessionsProvider(memberId),
      );
      final members =
          ref.watch(allMembersProvider).whenOrNull(data: (list) => list) ??
          const <Member>[];

      final targetSessions = targetAsync.value;
      if (targetSessions == null) {
        return targetAsync.when(
          loading: () => const AsyncValue.loading(),
          error: AsyncValue.error,
          data: (_) => const AsyncValue.loading(),
        );
      }

      final hasMore = targetSessions.length >= limit;
      if (targetSessions.isEmpty) {
        return const AsyncValue.data(
          MemberFrontingHistoryData(
            periods: [],
            targetSessions: [],
            hasMore: false,
          ),
        );
      }

      final rangeStart = targetSessions
          .map((session) => session.startTime)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      final allSessionsAsync = ref.watch(
        _frontingSessionsOverlappingRangeProvider((
          start: rangeStart,
          // Keep this value stable across provider rebuilds. Future-dated
          // rows are still filtered by computeDerivedPeriods(now: ...).
          end: DateTime(9999),
        )),
      );
      final allSessions = allSessionsAsync.value;
      if (allSessions == null) {
        return allSessionsAsync.when(
          loading: () => const AsyncValue.loading(),
          error: AsyncValue.error,
          data: (_) => const AsyncValue.loading(),
        );
      }

      final periods = computeDerivedPeriods(
        allSessions,
        members,
        now: DateTime.now(),
        rangeStart: rangeStart,
      ).where((period) => _periodIncludesMember(period, memberId)).toList();

      return AsyncValue.data(
        MemberFrontingHistoryData(
          periods: periods,
          targetSessions: targetSessions,
          hasMore: hasMore,
        ),
      );
    });

bool _periodIncludesMember(FrontingPeriod period, String memberId) {
  return period.activeMembers.contains(memberId) ||
      period.alwaysPresentMembers.contains(memberId) ||
      period.briefVisitors.any((visit) => visit.memberId == memberId);
}
