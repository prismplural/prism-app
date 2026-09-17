import 'package:prism_plurality/core/database/app_database.dart'
    hide FrontingSession, Member;
import 'package:prism_plurality/data/mappers/fronting_session_mapper.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';

const memberHistoryCalendarReproMemberId = 'member-history-repro';

final memberHistoryCalendarReproTargetDay = DateTime(2020, 1, 15);

class MemberHistoryCalendarReproFixture {
  const MemberHistoryCalendarReproFixture({
    required this.member,
    required this.targetDay,
    required this.sessionCount,
    required this.longSessionDays,
  });

  final Member member;
  final DateTime targetDay;
  final int sessionCount;
  final int longSessionDays;
}

/// Inserts a target member with a fixed dense historical distribution and one
/// deliberately long open session. IDs and timestamps are stable, allowing
/// comparable runs across macOS and iOS Simulator.
Future<MemberHistoryCalendarReproFixture> seedMemberHistoryCalendarReproFixture(
  AppDatabase db, {
  required bool large,
}) async {
  const fullDenseSessionCount = 1200;
  final longSessionStart = DateTime(2016, 1, 1, 8);
  final member = Member(
    id: memberHistoryCalendarReproMemberId,
    name: 'Calendar Repro Target',
    createdAt: longSessionStart,
  );

  final denseSessionCount = large ? fullDenseSessionCount : 180;
  final sessions = <FrontingSession>[
    FrontingSession(
      id: 'member-history-repro-long',
      memberId: member.id,
      startTime: longSessionStart,
    ),
    for (var i = 0; i < denseSessionCount; i++)
      FrontingSession(
        id: 'member-history-repro-dense-$i',
        memberId: member.id,
        // Six sessions per day force pagination through newer rows.
        startTime: DateTime(
          2020,
          12,
          31,
          8,
        ).subtract(Duration(days: i ~/ 6, hours: (i % 6) * 2)),
        endTime: DateTime(
          2020,
          12,
          31,
          9,
        ).subtract(Duration(days: i ~/ 6, hours: (i % 6) * 2)),
      ),
  ];

  for (final session in sessions) {
    await db.frontingSessionsDao.insertSession(
      FrontingSessionMapper.toCompanion(session),
    );
  }

  return MemberHistoryCalendarReproFixture(
    member: member,
    targetDay: memberHistoryCalendarReproTargetDay,
    sessionCount: sessions.length,
    longSessionDays: DateTime.now().difference(longSessionStart).inDays,
  );
}
