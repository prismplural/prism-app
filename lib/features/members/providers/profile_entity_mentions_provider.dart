import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_board_post.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/note.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/mentions/entity_mention.dart';
import 'package:prism_plurality/shared/mentions/entity_mention_visibility.dart';

const profileMentionCandidateLimitPerType = 8;

class ProfileEntityMentionResolution {
  const ProfileEntityMentionResolution({
    required this.target,
    required this.visible,
    this.label,
    this.entity,
  });

  final EntityMentionTarget target;
  final bool visible;
  final String? label;
  final Object? entity;

  String displayText(String hiddenLabel) {
    if (!visible) return hiddenLabel;
    final text = label?.trim();
    return text == null || text.isEmpty ? hiddenLabel : '@$text';
  }
}

class ProfileEntityMentionCandidate {
  const ProfileEntityMentionCandidate({
    required this.target,
    required this.title,
    required this.sortText,
  });

  final EntityMentionTarget target;
  final String title;
  final String sortText;

  String get token => target.token;
}

final profileMentionActiveFrontersProvider = Provider<List<Member>>((ref) {
  final sessions = ref.watch(activeSessionsProvider).value ?? const [];
  final activeMembers = ref.watch(activeMembersProvider).value ?? const [];
  return currentActiveFronters(
    activeSessions: sessions,
    activeMembers: activeMembers,
  );
});

final _profileMentionNotesByIdsProvider = StreamProvider.autoDispose
    .family<List<Note>, String>((ref, idsKey) {
      final ids = _idsFromKey(idsKey);
      if (ids.isEmpty) return Stream.value(const <Note>[]);
      final repo = ref.watch(notesRepositoryProvider);
      return repo.watchMentionNotesByIds(ids);
    });

final _profileMentionPostsByIdsProvider = StreamProvider.autoDispose
    .family<List<MemberBoardPost>, String>((ref, idsKey) {
      final ids = _idsFromKey(idsKey);
      if (ids.isEmpty) return Stream.value(const <MemberBoardPost>[]);
      final repo = ref.watch(memberBoardPostsRepositoryProvider);
      return repo.watchMentionPostsByIds(ids);
    });

final _profileMentionConversationsByIdsProvider = StreamProvider.autoDispose
    .family<List<Conversation>, String>((ref, idsKey) {
      final ids = _idsFromKey(idsKey);
      if (ids.isEmpty) return Stream.value(const <Conversation>[]);
      final repo = ref.watch(conversationRepositoryProvider);
      return repo.watchMentionConversationsByIds(ids);
    });

final profileEntityMentionResolutionsProvider = Provider.autoDispose
    .family<Map<EntityMentionTarget, ProfileEntityMentionResolution>, String>((
      ref,
      text,
    ) {
      final targets = extractEntityMentionTargets(text);
      if (targets.isEmpty) {
        return const <EntityMentionTarget, ProfileEntityMentionResolution>{};
      }

      final idsByType = _idsByType(targets);
      final members = ref.watch(userVisibleMembersProvider).value ?? const [];
      final groups = ref.watch(allGroupsProvider).value ?? const [];
      final visibleGroupIds = ref
          .watch(flatGroupListProvider)
          .map((item) => item.group.id)
          .toSet();
      final notesEnabled = ref.watch(notesEnabledProvider);
      final boardsEnabled = ref.watch(boardsEnabledProvider);
      final chatEnabled = ref.watch(chatEnabledProvider);
      final activeFronters = ref.watch(profileMentionActiveFrontersProvider);

      final notes =
          ref
              .watch(
                _profileMentionNotesByIdsProvider(
                  _idsKey(idsByType[EntityMentionType.note] ?? const {}),
                ),
              )
              .value ??
          const <Note>[];
      final posts =
          ref
              .watch(
                _profileMentionPostsByIdsProvider(
                  _idsKey(idsByType[EntityMentionType.board] ?? const {}),
                ),
              )
              .value ??
          const <MemberBoardPost>[];
      final conversations =
          ref
              .watch(
                _profileMentionConversationsByIdsProvider(
                  _idsKey(
                    idsByType[EntityMentionType.conversation] ?? const {},
                  ),
                ),
              )
              .value ??
          const <Conversation>[];

      final memberById = {for (final member in members) member.id: member};
      final groupById = {for (final group in groups) group.id: group};
      final noteById = {for (final note in notes) note.id: note};
      final postById = {for (final post in posts) post.id: post};
      final conversationById = {
        for (final conversation in conversations) conversation.id: conversation,
      };
      final activeMemberById = {
        for (final member
            in ref.watch(activeMembersProvider).value ?? const <Member>[])
          if (canMentionMember(member)) member.id: member,
      };

      return {
        for (final target in targets)
          target: _resolveTarget(
            target,
            memberById: memberById,
            groupById: groupById,
            noteById: noteById,
            postById: postById,
            conversationById: conversationById,
            activeMemberById: activeMemberById,
            visibleGroupIds: visibleGroupIds,
            notesEnabled: notesEnabled,
            boardsEnabled: boardsEnabled,
            chatEnabled: chatEnabled,
            activeFronters: activeFronters,
          ),
      };
    });

final profileEntityMentionCandidatesProvider = FutureProvider.autoDispose
    .family<List<ProfileEntityMentionCandidate>, String>((ref, filter) async {
      final lower = filter.trim().toLowerCase();
      final activeFronters = ref.watch(profileMentionActiveFrontersProvider);
      final activeFronterIds = [
        for (final member in activeFronters)
          if (canMentionMember(member)) member.id,
      ];
      final candidates = <ProfileEntityMentionCandidate>[];

      final members = ref.watch(userVisibleMembersProvider).value ?? const [];
      candidates.addAll(
        members
            .where((member) => _matches(lower, member.name))
            .take(profileMentionCandidateLimitPerType)
            .map(
              (member) => ProfileEntityMentionCandidate(
                target: EntityMentionTarget(
                  type: EntityMentionType.member,
                  id: member.id,
                ),
                title: member.name,
                sortText: member.name.toLowerCase(),
              ),
            ),
      );

      final groups = ref
          .watch(flatGroupListProvider)
          .map((item) => item.group)
          .where((group) => _matches(lower, group.name))
          .take(profileMentionCandidateLimitPerType);
      candidates.addAll(
        groups.map(
          (group) => ProfileEntityMentionCandidate(
            target: EntityMentionTarget(
              type: EntityMentionType.group,
              id: group.id,
            ),
            title: group.name,
            sortText: group.name.toLowerCase(),
          ),
        ),
      );

      if (ref.watch(notesEnabledProvider)) {
        final notes = await ref
            .read(notesRepositoryProvider)
            .searchMentionCandidates(
              filter,
              limit: profileMentionCandidateLimitPerType,
            );
        candidates.addAll(
          notes.map(
            (note) => ProfileEntityMentionCandidate(
              target: EntityMentionTarget(
                type: EntityMentionType.note,
                id: note.id,
              ),
              title: _noteLabel(note),
              sortText: _noteLabel(note).toLowerCase(),
            ),
          ),
        );
      }

      if (ref.watch(boardsEnabledProvider)) {
        final posts = await ref
            .read(memberBoardPostsRepositoryProvider)
            .searchMentionCandidates(
              filter,
              limit: profileMentionCandidateLimitPerType,
              activeFronterIds: activeFronterIds,
            );
        candidates.addAll(
          posts
              .where(
                (post) => canActiveFrontViewBoardPost(
                  post,
                  activeFronters: activeFronters,
                ),
              )
              .take(profileMentionCandidateLimitPerType)
              .map(
                (post) => ProfileEntityMentionCandidate(
                  target: EntityMentionTarget(
                    type: EntityMentionType.board,
                    id: post.id,
                  ),
                  title: _boardPostLabel(post),
                  sortText: _boardPostLabel(post).toLowerCase(),
                ),
              ),
        );
      }

      if (ref.watch(chatEnabledProvider)) {
        final conversations = await ref
            .read(conversationRepositoryProvider)
            .searchMentionCandidates(
              filter,
              limit: profileMentionCandidateLimitPerType * 2,
              activeFronterIds: activeFronterIds,
              includeAdminGroups: activeFronters.any(
                (member) => member.isAdmin,
              ),
            );
        final activeMemberById = {
          for (final member
              in ref.read(activeMembersProvider).value ?? const <Member>[])
            if (canMentionMember(member)) member.id: member,
        };
        candidates.addAll(
          conversations
              .where(
                (conversation) => canActiveFrontViewConversation(
                  conversation,
                  activeFronters: activeFronters,
                ),
              )
              .take(profileMentionCandidateLimitPerType)
              .map((conversation) {
                final title = _conversationLabel(
                  conversation,
                  memberById: activeMemberById,
                );
                return ProfileEntityMentionCandidate(
                  target: EntityMentionTarget(
                    type: EntityMentionType.conversation,
                    id: conversation.id,
                  ),
                  title: title,
                  sortText: title.toLowerCase(),
                );
              }),
        );
      }

      candidates.sort((a, b) {
        final typeCompare = a.target.type.index.compareTo(b.target.type.index);
        if (typeCompare != 0) return typeCompare;
        return a.sortText.compareTo(b.sortText);
      });
      return candidates;
    });

ProfileEntityMentionResolution _resolveTarget(
  EntityMentionTarget target, {
  required Map<String, Member> memberById,
  required Map<String, MemberGroup> groupById,
  required Map<String, Note> noteById,
  required Map<String, MemberBoardPost> postById,
  required Map<String, Conversation> conversationById,
  required Map<String, Member> activeMemberById,
  required Set<String> visibleGroupIds,
  required bool notesEnabled,
  required bool boardsEnabled,
  required bool chatEnabled,
  required List<Member> activeFronters,
}) {
  switch (target.type) {
    case EntityMentionType.member:
      final member = memberById[target.id];
      final visible = canMentionMember(member);
      return ProfileEntityMentionResolution(
        target: target,
        visible: visible,
        label: visible ? member!.name : null,
        entity: visible ? member : null,
      );
    case EntityMentionType.group:
      final group = groupById[target.id];
      final visible = canMentionGroup(group, visibleGroupIds);
      return ProfileEntityMentionResolution(
        target: target,
        visible: visible,
        label: visible ? group!.name : null,
        entity: visible ? group : null,
      );
    case EntityMentionType.note:
      final note = noteById[target.id];
      final visible = canMentionNote(note, notesEnabled: notesEnabled);
      return ProfileEntityMentionResolution(
        target: target,
        visible: visible,
        label: visible ? _noteLabel(note!) : null,
        entity: visible ? note : null,
      );
    case EntityMentionType.board:
      final post = postById[target.id];
      final visible =
          boardsEnabled &&
          canActiveFrontViewBoardPost(post, activeFronters: activeFronters);
      return ProfileEntityMentionResolution(
        target: target,
        visible: visible,
        label: visible ? _boardPostLabel(post!) : null,
        entity: visible ? post : null,
      );
    case EntityMentionType.conversation:
      final conversation = conversationById[target.id];
      final visible =
          chatEnabled &&
          canActiveFrontViewConversation(
            conversation,
            activeFronters: activeFronters,
          );
      return ProfileEntityMentionResolution(
        target: target,
        visible: visible,
        label: visible
            ? _conversationLabel(conversation!, memberById: activeMemberById)
            : null,
        entity: visible ? conversation : null,
      );
  }
}

Map<EntityMentionType, Set<String>> _idsByType(
  Iterable<EntityMentionTarget> targets,
) {
  final idsByType = <EntityMentionType, Set<String>>{};
  for (final target in targets) {
    idsByType.putIfAbsent(target.type, () => <String>{}).add(target.id);
  }
  return idsByType;
}

String _idsKey(Iterable<String> ids) => (ids.toList()..sort()).join('\u001f');

List<String> _idsFromKey(String idsKey) =>
    idsKey.isEmpty ? const <String>[] : idsKey.split('\u001f');

bool _matches(String lowerFilter, String text) {
  if (lowerFilter.isEmpty) return true;
  return text.toLowerCase().contains(lowerFilter);
}

String _noteLabel(Note note) {
  final title = note.title.trim();
  if (title.isNotEmpty) return title;
  return _singleLinePreview(note.body, fallback: 'Untitled note');
}

String _boardPostLabel(MemberBoardPost post) {
  final title = post.title?.trim();
  if (title != null && title.isNotEmpty) return title;
  return _singleLinePreview(post.body, fallback: 'Board message');
}

String _conversationLabel(
  Conversation conversation, {
  required Map<String, Member> memberById,
}) {
  final title = conversation.title?.trim();
  if (title != null && title.isNotEmpty) return title;
  if (conversation.includesAllMembers) return 'Everyone';
  final names = [
    for (final id in conversation.participantIds)
      if (memberById[id] != null) memberById[id]!.name,
  ];
  return names.isEmpty ? 'Conversation' : names.join(', ');
}

String _singleLinePreview(String value, {required String fallback}) {
  final collapsed = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (collapsed.isEmpty) return fallback;
  if (collapsed.length <= 48) return collapsed;
  return '${collapsed.substring(0, 47)}...';
}
