import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';

/// Watches all members (active and inactive).
final allMembersProvider = StreamProvider<List<Member>>((ref) {
  final repo = ref.watch(memberRepositoryProvider);
  return repo.watchAllMembers();
});

/// Watches active members only.
final activeMembersProvider = StreamProvider<List<Member>>((ref) {
  final repo = ref.watch(memberRepositoryProvider);
  return repo.watchActiveMembers();
});

/// Single member by ID.
final memberByIdProvider =
    StreamProvider.family<Member?, String>((ref, id) {
  final repo = ref.watch(memberRepositoryProvider);
  return repo.watchMemberById(id);
});

/// Cached map of memberId → display name, derived from active members.
/// Computed once and shared across all consumers (e.g., mention previews).
final memberNameMapProvider = Provider<Map<String, String>>((ref) {
  final members = ref.watch(activeMembersProvider).value;
  if (members == null) return const {};
  return {for (final m in members) m.id: m.name};
});

/// Member CRUD notifier.
class MembersNotifier extends Notifier<void> {
  static const _uuid = Uuid();

  @override
  void build() {}

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
  }) async {
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
      createdAt: DateTime.now(),
    );
    await repo.createMember(member);
  }

  Future<void> updateMember(Member member) async {
    final repo = ref.read(memberRepositoryProvider);
    await repo.updateMember(member);
  }

  Future<void> deleteMember(String id) async {
    final repo = ref.read(memberRepositoryProvider);
    await repo.deleteMember(id);
  }

  Future<void> reorderMembers(List<Member> members) async {
    final repo = ref.read(memberRepositoryProvider);
    final db = ref.read(databaseProvider);
    await db.transaction(() async {
      for (var i = 0; i < members.length; i++) {
        if (members[i].displayOrder == i) continue;
        await repo.updateMember(members[i].copyWith(displayOrder: i));
      }
    });
  }
}

final membersNotifierProvider =
    NotifierProvider<MembersNotifier, void>(MembersNotifier.new);
