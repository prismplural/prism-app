import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';

/// Whether the fronting screen shows the timeline or list view.
class TimelineViewNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
  void setActive(bool value) => state = value;
}

final timelineViewActiveProvider =
    NotifierProvider<TimelineViewNotifier, bool>(TimelineViewNotifier.new);

/// Controls the timeline zoom level.
class TimelineState {
  const TimelineState({this.pixelsPerHour = 60.0});

  /// Zoom level: how many pixels represent one hour.
  final double pixelsPerHour;

  static const double minPixelsPerHour = 20.0;
  static const double maxPixelsPerHour = 200.0;

  TimelineState copyWith({double? pixelsPerHour}) {
    return TimelineState(
      pixelsPerHour: pixelsPerHour ?? this.pixelsPerHour,
    );
  }
}

class TimelineStateNotifier extends Notifier<TimelineState> {
  @override
  TimelineState build() => const TimelineState();

  void zoomIn() {
    final current = state.pixelsPerHour;
    final next = (current * 1.5).clamp(
      TimelineState.minPixelsPerHour,
      TimelineState.maxPixelsPerHour,
    );
    state = state.copyWith(pixelsPerHour: next);
  }

  void zoomOut() {
    final current = state.pixelsPerHour;
    final next = (current / 1.5).clamp(
      TimelineState.minPixelsPerHour,
      TimelineState.maxPixelsPerHour,
    );
    state = state.copyWith(pixelsPerHour: next);
  }
}

final timelineStateProvider =
    NotifierProvider<TimelineStateNotifier, TimelineState>(
  TimelineStateNotifier.new,
);

/// How many sessions to load. Increases as the user scrolls back in time.
class TimelineSessionLimitNotifier extends Notifier<int> {
  @override
  int build() => 100;

  void increase(int amount) => state = state + amount;
}

final timelineSessionLimitProvider =
    NotifierProvider<TimelineSessionLimitNotifier, int>(
  TimelineSessionLimitNotifier.new,
);

/// Target date to scroll to (set by controls, consumed by view).
class TimelineJumpTargetNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void jumpTo(DateTime date) => state = date;
  void clear() => state = null;
}

final timelineJumpTargetProvider =
    NotifierProvider<TimelineJumpTargetNotifier, DateTime?>(
  TimelineJumpTargetNotifier.new,
);

/// A row in the timeline: one member with their sessions.
class TimelineMemberRow {
  const TimelineMemberRow({
    required this.member,
    required this.sessions,
  });

  final Member member;
  final List<FrontingSession> sessions;

  /// Resolve the display color for this member's timeline column.
  ///
  /// Uses the member's custom color if set, otherwise generates a distinct
  /// color from [rowIndex] (the member's position in the timeline row list).
  Color resolveColor(int rowIndex, Color accentColor, Brightness brightness) {
    if (member.customColorEnabled && member.customColorHex != null) {
      return AppColors.fromHex(member.customColorHex!);
    }
    return AppColors.generatedColor(rowIndex, accentColor, brightness);
  }
}

class TimelineData {
  const TimelineData({
    required this.memberRows,
    required this.sleepSessions,
  });

  final List<TimelineMemberRow> memberRows;
  final List<FrontingSession> sleepSessions;
}

/// Provides timeline rows: sessions grouped by member for display.
/// Expands co-fronters so each member who participated gets their own row entry.
final timelineRowsProvider =
    Provider.autoDispose<AsyncValue<TimelineData>>((ref) {
  final limit = ref.watch(timelineSessionLimitProvider);
  final sessionsAsync = ref.watch(frontingHistoryProvider(limit));
  final sleepSessionsAsync = ref.watch(recentSleepSessionsProvider);
  final membersAsync = ref.watch(activeMembersProvider);

  return sessionsAsync.when(
    loading: () => const AsyncValue.loading(),
    error: AsyncValue.error,
    data: (sessions) {
      return sleepSessionsAsync.when(
        loading: () => const AsyncValue.loading(),
        error: AsyncValue.error,
        data: (sleepSessions) {
          return membersAsync.when(
            loading: () => const AsyncValue.loading(),
            error: AsyncValue.error,
            data: (members) {
              // Group fronting sessions by member, expanding co-fronters.
              final rowMap = <String, List<FrontingSession>>{};

              for (final session in sessions) {
                final primaryId = session.memberId;
                if (primaryId != null) {
                  rowMap.putIfAbsent(primaryId, () => []).add(session);
                }

                for (final coId in session.coFronterIds) {
                  rowMap.putIfAbsent(coId, () => []).add(session);
                }
              }

              final rows = <TimelineMemberRow>[];
              for (final member in members) {
                final memberSessions = rowMap[member.id];
                if (memberSessions != null && memberSessions.isNotEmpty) {
                  rows.add(TimelineMemberRow(
                    member: member,
                    sessions: memberSessions,
                  ));
                }
              }

              return AsyncValue.data(
                TimelineData(
                  memberRows: rows,
                  sleepSessions: sleepSessions,
                ),
              );
            },
          );
        },
      );
    },
  );
});
