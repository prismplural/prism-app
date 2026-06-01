/// Tag-rename reference rewrite: repoints every `![](oldTag)` /
/// `![](oldTag#frag)` image ref across the surfaces that can contain
/// one — bios, custom-field values, chat messages, notes, group descriptions,
/// and board posts — at a new tag.
///
/// Extracted from `MediaSettingsScreen._rewriteTagReferences` so the core
/// fan-out logic is widget-free and integration-testable against real
/// repositories (the screen just resolves these from `ref` and delegates).
///
/// Behavioral contract (must match the prior in-screen implementation):
///   * Reads are one-shot repo/DAO getters. We never `await` a stream
///     provider's `.future`, which can stall when nothing else is watching it
///     (see git fix 1d3b49ab).
///   * Each surface is guarded independently: a failure on one contributes
///     nothing rather than aborting the whole pass.
///   * A record is only written (and only counted) when the rewrite actually
///     changes its text — `textReferencesTag` guards the scan and the
///     `rewritten == original` check guards the write.
///   * The return value is the number of records actually updated.
library;

import 'package:flutter/foundation.dart';

import 'package:prism_plurality/core/database/daos/chat_messages_dao.dart';
import 'package:prism_plurality/core/database/daos/member_board_posts_dao.dart';
import 'package:prism_plurality/domain/repositories/chat_message_repository.dart';
import 'package:prism_plurality/domain/repositories/custom_fields_repository.dart';
import 'package:prism_plurality/domain/repositories/member_board_posts_repository.dart';
import 'package:prism_plurality/domain/repositories/member_groups_repository.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/domain/repositories/notes_repository.dart';
import 'package:prism_plurality/data/mappers/member_board_post_mapper.dart';
import 'package:prism_plurality/features/settings/utils/tag_usage_scan.dart';

/// Rewrites `![](oldTag…)` image refs to `![](newTag…)` across bios, custom
/// field values, chat messages, notes, group descriptions, and board posts.
/// Returns the number of records actually updated.
Future<int> rewriteTagReferencesAcrossSurfaces({
  required MemberRepository memberRepo,
  required NotesRepository notesRepo,
  required MemberGroupsRepository groupsRepo,
  required CustomFieldsRepository fieldsRepo,
  required ChatMessageRepository chatRepo,
  required ChatMessagesDao chatDao,
  required MemberBoardPostsRepository boardPostsRepo,
  required MemberBoardPostsDao boardPostsDao,
  required String oldTag,
  required String newTag,
}) async {
  var updated = 0;

  // Bios.
  try {
    final members = await memberRepo.getAllMembers();
    for (final m in members) {
      final bio = m.bio;
      if (bio == null || !textReferencesTag(bio, oldTag)) continue;
      final rewritten = rewriteImageTag(bio, oldTag, newTag);
      if (rewritten == bio) continue;
      await memberRepo.updateMember(m.copyWith(bio: rewritten));
      updated++;
    }
  } catch (e) {
    debugPrint('[tagRename] bios rewrite failed: $e');
  }

  // Custom field values.
  try {
    final values = await fieldsRepo.getAllValues();
    for (final v in values) {
      if (!textReferencesTag(v.value, oldTag)) continue;
      final rewritten = rewriteImageTag(v.value, oldTag, newTag);
      if (rewritten == v.value) continue;
      await fieldsRepo.upsertValue(v.copyWith(value: rewritten));
      updated++;
    }
  } catch (e) {
    debugPrint('[tagRename] custom-field values rewrite failed: $e');
  }

  // Chat messages (intra-system only; editing history is fine).
  try {
    final messages = await chatDao.imageMarkdownMessages();
    for (final msg in messages) {
      if (!textReferencesTag(msg.content, oldTag)) continue;
      final rewritten = rewriteImageTag(msg.content, oldTag, newTag);
      if (rewritten == msg.content) continue;
      final full = await chatRepo.getMessageById(msg.id);
      if (full == null) continue;
      await chatRepo.updateMessage(full.copyWith(content: rewritten));
      updated++;
    }
  } catch (e) {
    debugPrint('[tagRename] chat messages rewrite failed: $e');
  }

  // Notes.
  try {
    final notes = await notesRepo.getAllNotes();
    for (final n in notes) {
      if (!textReferencesTag(n.body, oldTag)) continue;
      final rewritten = rewriteImageTag(n.body, oldTag, newTag);
      if (rewritten == n.body) continue;
      await notesRepo.updateNote(n.copyWith(body: rewritten));
      updated++;
    }
  } catch (e) {
    debugPrint('[tagRename] notes rewrite failed: $e');
  }

  // Group descriptions.
  try {
    final groups = await groupsRepo.getAllGroups();
    for (final g in groups) {
      final desc = g.description;
      if (desc == null || !textReferencesTag(desc, oldTag)) continue;
      final rewritten = rewriteImageTag(desc, oldTag, newTag);
      if (rewritten == desc) continue;
      await groupsRepo.updateGroup(g.copyWith(description: rewritten));
      updated++;
    }
  } catch (e) {
    debugPrint('[tagRename] groups rewrite failed: $e');
  }

  // Board posts.
  try {
    final posts = await boardPostsDao.imageMarkdownPosts();
    for (final row in posts) {
      if (!textReferencesTag(row.body, oldTag)) continue;
      final rewritten = rewriteImageTag(row.body, oldTag, newTag);
      if (rewritten == row.body) continue;
      await boardPostsRepo.updatePost(
        MemberBoardPostMapper.toDomain(row).copyWith(body: rewritten),
      );
      updated++;
    }
  } catch (e) {
    debugPrint('[tagRename] board posts rewrite failed: $e');
  }

  return updated;
}
