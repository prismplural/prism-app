import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';

/// Watches all members (active and inactive).
///
/// Includes the Unknown sentinel — analytics, fronting-related selection, and
/// any path that resolves session.memberId back to a member must use this (or
/// `activeMembersProvider`) so the sentinel resolves rather than rendering as
/// "missing." For user-facing member-management lists use
/// [userVisibleMembersProvider] instead.
final allMembersProvider = StreamProvider<List<Member>>((ref) {
  final repo = ref.watch(memberRepositoryProvider);
  return repo.watchAllMembers();
});

/// Watches active members only. Includes the Unknown sentinel — see the note
/// on [allMembersProvider] for which surfaces should filter it.
final activeMembersProvider = StreamProvider<List<Member>>((ref) {
  final repo = ref.watch(memberRepositoryProvider);
  return repo.watchActiveMembers();
});

/// Active members with the Unknown sentinel filtered out.
///
/// Use this on member-management surfaces (members list, system management,
/// system info, settings) where the sentinel would confuse users — it's a
/// system-internal placeholder, not a real headmate. Fronting pickers,
/// chat/poll/reminder selection, and analytics keep using
/// [activeMembersProvider]/[allMembersProvider] so the sentinel resolves
/// normally for sessions attributed to it.
final userVisibleMembersProvider = Provider<AsyncValue<List<Member>>>((ref) {
  final async = ref.watch(activeMembersProvider);
  return async.whenData(
    (members) => members.where((m) => m.id != unknownSentinelMemberId).toList(),
  );
});

/// All members (active + inactive) with the Unknown sentinel filtered out.
///
/// Mirrors [userVisibleMembersProvider] but for management surfaces that show
/// inactive members too (e.g., the "show inactive" toggle on the members
/// list). Same rule: never display the sentinel as a manageable headmate.
final userVisibleAllMembersProvider = Provider<AsyncValue<List<Member>>>((ref) {
  final async = ref.watch(allMembersProvider);
  return async.whenData(
    (members) => members.where((m) => m.id != unknownSentinelMemberId).toList(),
  );
});

/// Single member by ID.
final memberByIdProvider = StreamProvider.autoDispose.family<Member?, String>((
  ref,
  id,
) {
  final link = ref.keepAlive();
  Timer? timer;
  ref.onDispose(() => timer?.cancel());
  ref.onCancel(() {
    timer = Timer(const Duration(seconds: 30), link.close);
  });
  ref.onResume(() => timer?.cancel());
  final repo = ref.watch(memberRepositoryProvider);
  return repo.watchMemberById(id);
});

/// Single non-deleted member by ID.
///
/// UI surfaces should prefer this provider unless they are explicitly rendering
/// tombstone-aware sync, import, or recovery state.
final activeMemberByIdProvider = Provider.autoDispose
    .family<AsyncValue<Member?>, String>((ref, id) {
      return ref.watch(memberByIdProvider(id)).whenData((member) {
        if (member == null || member.isDeleted) return null;
        return member;
      });
    });

/// Cached map of memberId → display name, derived from active members.
/// Computed once and shared across all consumers (e.g., mention previews).
final memberNameMapProvider = Provider<Map<String, String>>((ref) {
  final members = ref.watch(activeMembersProvider).value;
  if (members == null) return const {};
  return {for (final m in members) m.id: m.name};
});

/// Member CRUD notifier.
class MembersNotifier extends AsyncNotifier<void> {
  static const _uuid = Uuid();

  @override
  Future<void> build() async {}

  Future<void> createMember({
    String? id,
    required String name,
    String? pronouns,
    String emoji = '\u2754',
    int? age,
    String? bio,
    Uint8List? avatarImageData,
    bool isAdmin = false,
    String? customColorHex,
    String? displayName,
    String? pluralkitDisplayName,
    String? birthday,
    String? proxyTagsJson,
    bool isAlwaysFronting = false,
    DateTime? createdAt,
    MemberProfileHeaderSource profileHeaderSource =
        MemberProfileHeaderSource.prism,
    MemberProfileHeaderLayout profileHeaderLayout =
        MemberProfileHeaderLayout.compactBackground,
    bool profileHeaderVisible = true,
    MemberNameFont nameStyleFont = MemberNameFont.standard,
    bool nameStyleBold = true,
    bool nameStyleItalic = false,
    MemberNameColorMode nameStyleColorMode = MemberNameColorMode.standard,
    String? nameStyleColorHex,
    Uint8List? profileHeaderImageData,
  }) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(memberRepositoryProvider);
      final member = Member(
        id: id ?? _uuid.v4(),
        name: name,
        pronouns: pronouns,
        emoji: emoji,
        age: age,
        bio: bio,
        avatarImageData: avatarImageData,
        isAdmin: isAdmin,
        customColorEnabled: customColorHex != null,
        customColorHex: customColorHex,
        displayName: displayName,
        pluralkitDisplayName: pluralkitDisplayName,
        birthday: birthday,
        proxyTagsJson: proxyTagsJson,
        isAlwaysFronting: isAlwaysFronting,
        profileHeaderSource: profileHeaderSource,
        profileHeaderLayout: profileHeaderLayout,
        profileHeaderVisible: profileHeaderVisible,
        nameStyleFont: nameStyleFont,
        nameStyleBold: nameStyleBold,
        nameStyleItalic: nameStyleItalic,
        nameStyleColorMode: nameStyleColorMode,
        nameStyleColorHex: nameStyleColorHex,
        profileHeaderImageData: profileHeaderImageData,
        createdAt: createdAt ?? DateTime.now(),
      );
      await repo.createMember(member);
      if (_isActiveAlwaysFronting(member)) {
        await _ensureAlwaysFrontingSession(member.id);
      }
    });
  }

  Future<void> updateMember(
    Member member, {
    bool endPreviousAlwaysFrontingSessions = true,
    Set<String>? previousAlwaysFrontingSessionIdsToEnd,
  }) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(memberRepositoryProvider);
      final previous = await repo.getMemberById(member.id);
      await repo.updateMember(member);
      if (_isActiveAlwaysFronting(member)) {
        await _ensureAlwaysFrontingSession(member.id);
      } else if (endPreviousAlwaysFrontingSessions &&
          previous != null &&
          _isActiveAlwaysFronting(previous)) {
        await _endAlwaysFrontingSessions(
          member.id,
          sessionIdsToEnd: previousAlwaysFrontingSessionIdsToEnd,
        );
      }
    });
  }

  Future<void> deleteMember(String id) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(memberRepositoryProvider);
      await repo.deleteMember(id);
    });
  }

  Future<void> reorderMembers(List<Member> members) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(memberRepositoryProvider);
      if (repo is DriftMemberRepository) {
        await repo.reorderMembers(members);
        return;
      }
      final db = ref.read(databaseProvider);
      await db.transaction(() async {
        for (var i = 0; i < members.length; i++) {
          if (members[i].displayOrder == i) continue;
          await repo.updateMember(members[i].copyWith(displayOrder: i));
        }
      });
    });
  }

  Future<void> _ensureAlwaysFrontingSession(String memberId) async {
    final repo = ref.read(frontingSessionRepositoryProvider);
    final active = await repo.getAllActiveSessionsUnfiltered();
    for (final session in active) {
      if (session.memberId == memberId && !session.isSleep) return;
    }
    await repo.createSession(
      FrontingSession(
        id: _uuid.v4(),
        startTime: DateTime.now(),
        memberId: memberId,
      ),
    );
  }

  Future<void> _endAlwaysFrontingSessions(
    String memberId, {
    Set<String>? sessionIdsToEnd,
  }) async {
    final repo = ref.read(frontingSessionRepositoryProvider);
    final now = DateTime.now();
    final active = await repo.getAllActiveSessionsUnfiltered();
    for (final session in active) {
      final shouldEnd =
          session.memberId == memberId &&
          !session.isSleep &&
          (sessionIdsToEnd == null || sessionIdsToEnd.contains(session.id));
      if (shouldEnd) {
        await repo.endSession(session.id, now);
      }
    }
  }

  bool _isActiveAlwaysFronting(Member member) {
    return member.isActive && !member.isDeleted && member.isAlwaysFronting;
  }
}

final membersNotifierProvider = AsyncNotifierProvider<MembersNotifier, void>(
  MembersNotifier.new,
);
