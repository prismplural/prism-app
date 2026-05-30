// test/features/settings/tag_reference_rewriter_test.dart
//
// Integration test for the tag-rename reference rewrite
// (`rewriteTagReferencesAcrossSurfaces`). Proves that renaming a library tag
// repoints `![](oldTag)` / `![](oldTag#frag)` refs across ALL FIVE surfaces
// (bios, custom-field values, chat messages, notes, group descriptions),
// mutates exactly the right records, preserves alt text + sizing fragments,
// and leaves everything else — including prefix collisions like `flagpole`
// and unrelated tags like `other` — byte-for-byte untouched.
//
// Built against a single in-memory Drift AppDatabase with the real Drift*
// repositories (same pattern as drift_notes_repository_test /
// drift_member_groups_repository_test). Null sync handles → the
// SyncRecordMixin capture sink swallows emissions; we assert on the persisted
// rows, not the sync ops.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/chat_messages_dao.dart';
import 'package:prism_plurality/core/database/daos/custom_fields_dao.dart';
import 'package:prism_plurality/core/database/daos/member_groups_dao.dart';
import 'package:prism_plurality/core/database/daos/members_dao.dart';
import 'package:prism_plurality/core/database/daos/notes_dao.dart';
import 'package:prism_plurality/data/repositories/drift_chat_message_repository.dart';
import 'package:prism_plurality/data/repositories/drift_custom_fields_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_groups_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/data/repositories/drift_notes_repository.dart';
import 'package:prism_plurality/features/settings/utils/tag_reference_rewriter.dart';
import 'package:prism_plurality/domain/models/chat_message.dart' as chat_domain;
import 'package:prism_plurality/domain/models/custom_field_value.dart'
    as cf_domain;
import 'package:prism_plurality/domain/models/member.dart' as member_domain;
import 'package:prism_plurality/domain/models/member_group.dart'
    as group_domain;
import 'package:prism_plurality/domain/models/note.dart' as note_domain;

void main() {
  late AppDatabase db;
  late DriftMemberRepository memberRepo;
  late DriftNotesRepository notesRepo;
  late DriftMemberGroupsRepository groupsRepo;
  late DriftCustomFieldsRepository fieldsRepo;
  late DriftChatMessageRepository chatRepo;
  late ChatMessagesDao chatDao;

  final baseTime = DateTime.utc(2026, 5, 1, 12);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    // Null sync handles everywhere — the repos use the capture sink in tests
    // and we assert on persisted rows, not sync emissions.
    memberRepo = DriftMemberRepository(MembersDao(db), null);
    notesRepo = DriftNotesRepository(NotesDao(db), null);
    fieldsRepo = DriftCustomFieldsRepository(CustomFieldsDao(db), null);
    chatDao = ChatMessagesDao(db);
    chatRepo = DriftChatMessageRepository(chatDao, null);
    groupsRepo = DriftMemberGroupsRepository(
      MemberGroupsDao(db),
      null,
      memberRepository: memberRepo,
    );
  });

  tearDown(() => db.close());

  member_domain.Member member({
    required String id,
    required String name,
    String? bio,
  }) =>
      member_domain.Member(
        id: id,
        name: name,
        bio: bio,
        createdAt: baseTime,
      );

  note_domain.Note note({required String id, required String body}) =>
      note_domain.Note(
        id: id,
        title: 'Note $id',
        body: body,
        date: baseTime,
        createdAt: baseTime,
        modifiedAt: baseTime,
      );

  group_domain.MemberGroup group({
    required String id,
    String? description,
  }) =>
      group_domain.MemberGroup(
        id: id,
        name: 'Group $id',
        description: description,
        createdAt: baseTime,
      );

  cf_domain.CustomFieldValue fieldValue({
    required String id,
    required String value,
  }) =>
      cf_domain.CustomFieldValue(
        id: id,
        // Distinct field id per value: custom_field_values has a UNIQUE
        // (custom_field_id, member_id) constraint, so the three seeded values
        // (flag / other / plain) must differ on that pair.
        customFieldId: 'cf-$id',
        memberId: 'seed-member',
        value: value,
      );

  chat_domain.ChatMessage message({
    required String id,
    required String content,
  }) =>
      chat_domain.ChatMessage(
        id: id,
        content: content,
        timestamp: baseTime,
        authorId: 'author-1',
        conversationId: 'conv-1',
      );

  Future<int> runRewrite({String oldTag = 'flag', String newTag = 'banner'}) {
    return rewriteTagReferencesAcrossSurfaces(
      memberRepo: memberRepo,
      notesRepo: notesRepo,
      groupsRepo: groupsRepo,
      fieldsRepo: fieldsRepo,
      chatRepo: chatRepo,
      chatDao: chatDao,
      oldTag: oldTag,
      newTag: newTag,
    );
  }

  test(
    'rewrites every flag ref across all five surfaces, preserves alt + '
    'fragment, leaves decoys byte-for-byte unchanged, and counts exactly the '
    'records changed',
    () async {
      // ── Members (bios) ───────────────────────────────────────────────────
      // Two members that SHOULD change (bare ref + alt/fragment ref).
      await memberRepo.createMember(
        member(id: 'm-bare', name: 'Bare', bio: 'before ![](flag) after'),
      );
      await memberRepo.createMember(
        member(
          id: 'm-alt',
          name: 'Alt',
          bio: 'pic ![alt](flag#200x80) end',
        ),
      );
      // Decoys: a different tag, a prefix-of-flag tag, and a plain-text bio.
      await memberRepo.createMember(
        member(id: 'm-other', name: 'Other', bio: '![](other)'),
      );
      await memberRepo.createMember(
        member(id: 'm-prefix', name: 'Prefix', bio: '![](flagpole)'),
      );
      await memberRepo.createMember(
        member(id: 'm-plain', name: 'Plain', bio: 'no images here'),
      );

      // ── Notes ────────────────────────────────────────────────────────────
      await notesRepo.createNote(
        note(id: 'n-flag', body: 'note ![](flag) body'),
      );
      await notesRepo.createNote(
        note(id: 'n-other', body: 'note ![](other) body'),
      );
      await notesRepo.createNote(note(id: 'n-plain', body: 'plain note'));

      // ── Groups (descriptions) ─────────────────────────────────────────────
      await groupsRepo.createGroup(
        group(id: 'g-flag', description: 'grp ![](flag) desc'),
      );
      await groupsRepo.createGroup(
        group(id: 'g-prefix', description: 'grp ![](flagpole) desc'),
      );
      await groupsRepo.createGroup(group(id: 'g-plain', description: 'plain'));

      // ── Custom field values ───────────────────────────────────────────────
      await fieldsRepo.upsertValue(
        fieldValue(id: 'v-flag', value: 'val ![](flag) val'),
      );
      await fieldsRepo.upsertValue(
        fieldValue(id: 'v-other', value: 'val ![](other) val'),
      );
      await fieldsRepo.upsertValue(
        fieldValue(id: 'v-plain', value: 'plain value'),
      );

      // ── Chat messages ─────────────────────────────────────────────────────
      await chatRepo.createMessage(
        message(id: 'c-flag', content: 'chat ![](flag) msg'),
      );
      await chatRepo.createMessage(
        message(id: 'c-prefix', content: 'chat ![](flagpole) msg'),
      );
      await chatRepo.createMessage(
        message(id: 'c-plain', content: 'just text, no image'),
      );

      // ── Act ───────────────────────────────────────────────────────────────
      final updated = await runRewrite();

      // Exactly 6 records changed: m-bare + m-alt (2 bios) + n-flag (1 note) +
      // g-flag (1 group) + v-flag (1 field value) + c-flag (1 chat) = 6.
      expect(updated, 6);

      // ── Assert: flag refs became banner, alt + fragment preserved ─────────
      final members = await memberRepo.getAllMembers();
      final byId = {for (final m in members) m.id: m};
      expect(byId['m-bare']!.bio, 'before ![](banner) after');
      expect(byId['m-alt']!.bio, 'pic ![alt](banner#200x80) end');

      // Decoys unchanged byte-for-byte.
      expect(byId['m-other']!.bio, '![](other)');
      expect(byId['m-prefix']!.bio, '![](flagpole)');
      expect(byId['m-plain']!.bio, 'no images here');

      final notes = await notesRepo.getAllNotes();
      final notesById = {for (final n in notes) n.id: n};
      expect(notesById['n-flag']!.body, 'note ![](banner) body');
      expect(notesById['n-other']!.body, 'note ![](other) body');
      expect(notesById['n-plain']!.body, 'plain note');

      final groups = await groupsRepo.getAllGroups();
      final groupsById = {for (final g in groups) g.id: g};
      expect(groupsById['g-flag']!.description, 'grp ![](banner) desc');
      expect(groupsById['g-prefix']!.description, 'grp ![](flagpole) desc');
      expect(groupsById['g-plain']!.description, 'plain');

      final values = await fieldsRepo.getAllValues();
      final valuesById = {for (final v in values) v.id: v};
      expect(valuesById['v-flag']!.value, 'val ![](banner) val');
      expect(valuesById['v-other']!.value, 'val ![](other) val');
      expect(valuesById['v-plain']!.value, 'plain value');

      final cFlag = await chatRepo.getMessageById('c-flag');
      final cPrefix = await chatRepo.getMessageById('c-prefix');
      final cPlain = await chatRepo.getMessageById('c-plain');
      expect(cFlag!.content, 'chat ![](banner) msg');
      expect(cPrefix!.content, 'chat ![](flagpole) msg');
      expect(cPlain!.content, 'just text, no image');

      // ── Idempotent-ish: re-running on the now-renamed corpus for the old
      //    tag changes nothing (no record still references `flag`).
      final secondPass = await runRewrite();
      expect(secondPass, 0);
    },
  );
}
