import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_bundle.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_mapper.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_service.dart';

import 'harness.dart';

Json document({bool includeDependents = true}) => {
  'pluralport_version': '0.1',
  'producer': {'app': 'Tombstone fixture', 'app_id': 'tombstone-fixture'},
  'systems': [
    {'id': 'system', 'name': 'Fixture system'},
  ],
  'members': [
    {'id': 'member', 'system_id': 'system', 'name': 'Deleted member'},
  ],
  if (includeDependents) ...{
    'groups': [
      {'id': 'group', 'system_id': 'system', 'name': 'Group'},
    ],
    'group_memberships': [
      {'id': 'membership', 'group_id': 'group', 'member_id': 'member'},
    ],
    'custom_fields': [
      {
        'id': 'field',
        'system_id': 'system',
        'name': 'Field',
        'field_type': 'text',
      },
    ],
    'custom_field_values': [
      {
        'id': 'value',
        'field_id': 'field',
        'subject_type': 'member',
        'subject_id': 'member',
        'value': 'Deleted value',
      },
    ],
    'notes': [
      {
        'id': 'note',
        'system_id': 'system',
        'member_id': 'member',
        'title': 'Deleted note',
        'body': 'Body',
        'created_at': '2026-01-01T00:00:00Z',
      },
    ],
    'front_periods': [
      {
        'id': 'period',
        'system_id': 'system',
        'started_at': '2026-01-01T00:00:00Z',
        'ended_at': '2026-01-01T01:00:00Z',
        'assignments': [
          {'member_id': 'member'},
        ],
      },
    ],
    'front_comments': [
      {
        'id': 'comment',
        'front_period_id': 'period',
        'body': 'Deleted comment',
        'target_time': '2026-01-01T00:30:00Z',
        'created_at': '2026-01-01T00:30:00Z',
      },
    ],
    'chat': {
      'conversations': [
        {'id': 'conversation', 'kind': 'internal_chat', 'title': 'Chat'},
      ],
      'messages': [
        {
          'id': 'message',
          'conversation_id': 'conversation',
          'author_member_id': 'member',
          'body': 'Deleted message',
          'created_at': '2026-01-01T00:00:00Z',
        },
      ],
    },
    'boards': {
      'posts': [
        {
          'id': 'post',
          'target_member_id': 'member',
          'author_member_id': 'member',
          'body': 'Deleted post',
          'created_at': '2026-01-01T00:00:00Z',
        },
      ],
    },
  },
};

PluralPortImportPlan plan(Json source) => PluralPortService.previewBytes(
  Uint8List.fromList(utf8.encode(jsonEncode(source))),
);

PluralPortService service(AppDatabase db, Directory directory) =>
    PluralPortService(
      db: db,
      exporter: makeExport(db),
      importer: makeImport(db, supportDirectory: directory),
      supportDirectory: () async => directory,
    );

void main() {
  test(
    'repeat import honors tombstones for every mapped PluralPort record',
    () async {
      final directory = await Directory.systemTemp.createTemp('pluralport-');
      addTearDown(() => directory.delete(recursive: true));
      final db = makeDb();
      addTearDown(db.close);
      final subject = service(db, directory);
      final source = plan(document());
      await subject.importPlan(source);

      await db
          .update(db.members)
          .write(const MembersCompanion(isDeleted: drift.Value(true)));
      await db
          .update(db.memberGroups)
          .write(const MemberGroupsCompanion(isDeleted: drift.Value(true)));
      await db
          .update(db.memberGroupEntries)
          .write(
            const MemberGroupEntriesCompanion(isDeleted: drift.Value(true)),
          );
      await db
          .update(db.customFields)
          .write(const CustomFieldsCompanion(isDeleted: drift.Value(true)));
      await db
          .update(db.customFieldValues)
          .write(
            const CustomFieldValuesCompanion(isDeleted: drift.Value(true)),
          );
      await db
          .update(db.notes)
          .write(const NotesCompanion(isDeleted: drift.Value(true)));
      await db
          .update(db.frontingSessions)
          .write(const FrontingSessionsCompanion(isDeleted: drift.Value(true)));
      await db
          .update(db.frontSessionComments)
          .write(
            const FrontSessionCommentsCompanion(isDeleted: drift.Value(true)),
          );
      await db
          .update(db.conversations)
          .write(const ConversationsCompanion(isDeleted: drift.Value(true)));
      await db
          .update(db.chatMessages)
          .write(const ChatMessagesCompanion(isDeleted: drift.Value(true)));
      await db
          .update(db.memberBoardPosts)
          .write(const MemberBoardPostsCompanion(isDeleted: drift.Value(true)));

      final repeated = await subject.importPlan(source);
      expect(repeated.totalRecordsCreated, 0);
      for (final rows in await Future.wait([
        db.select(db.members).get(),
        db.select(db.memberGroups).get(),
        db.select(db.memberGroupEntries).get(),
        db.select(db.customFields).get(),
        db.select(db.customFieldValues).get(),
        db.select(db.notes).get(),
        db.select(db.frontingSessions).get(),
        db.select(db.frontSessionComments).get(),
        db.select(db.conversations).get(),
        db.select(db.chatMessages).get(),
        db.select(db.memberBoardPosts).get(),
      ])) {
        expect(rows, hasLength(1));
        expect((rows.single as dynamic).isDeleted, isTrue);
      }

      final exported = await subject.exportBundle();
      expect(
        () => PluralPortMapper.plan(PluralPortBundle.decode(exported.encode())),
        returnsNormally,
      );
    },
  );

  test('a deleted member blocks mapped children on a later import', () async {
    final directory = await Directory.systemTemp.createTemp('pluralport-');
    addTearDown(() => directory.delete(recursive: true));
    final db = makeDb();
    addTearDown(db.close);
    final subject = service(db, directory);
    await subject.importPlan(plan(document(includeDependents: false)));
    await db
        .update(db.members)
        .write(const MembersCompanion(isDeleted: drift.Value(true)));

    await subject.importPlan(plan(document()));
    expect(await db.select(db.memberGroups).get(), hasLength(1));
    expect(await db.select(db.customFields).get(), hasLength(1));
    expect(await db.select(db.memberGroupEntries).get(), isEmpty);
    expect(await db.select(db.customFieldValues).get(), isEmpty);
    expect(await db.select(db.frontingSessions).get(), isEmpty);
    expect(await db.select(db.frontSessionComments).get(), isEmpty);
  });
}
