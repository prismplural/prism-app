import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/constants/custom_field_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/drift_chat_message_repository.dart';
import 'package:prism_plurality/data/repositories/drift_conversation_repository.dart';
import 'package:prism_plurality/data/repositories/drift_custom_fields_repository.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/data/repositories/drift_poll_repository.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart'
    as domain;
import 'package:prism_plurality/features/migration/services/sp_importer.dart';

/// SP imports write custom-field values through the reconciled per-row
/// upsert: the deterministic (field, member) id keeps repeat imports and
/// UI edits converging on one live row, and a burned (tombstoned) id gets
/// a freshly minted row instead of a silent write into the tombstone.
void main() {
  late AppDatabase db;
  late SpImporter importer;
  late DriftCustomFieldsRepository fieldsRepo;
  late DriftMemberRepository memberRepo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    importer = SpImporter();
    fieldsRepo = DriftCustomFieldsRepository(db.customFieldsDao, null);
    memberRepo = DriftMemberRepository(db.membersDao, null);
  });

  tearDown(() => db.close());

  Uint8List exportJson({required String colorValue, String fieldName = 'Color'}) {
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'members': [
            {
              '_id': 'sp-mem-1',
              'name': 'Kai',
              'info': {'sp-cf-1': colorValue},
            },
          ],
          'customFields': [
            {'_id': 'sp-cf-1', 'name': fieldName, 'type': 0},
          ],
        }),
      ),
    );
  }

  Future<void> runImport({
    required String colorValue,
    String fieldName = 'Color',
  }) async {
    final data = await importer.parseBytes(
      exportJson(colorValue: colorValue, fieldName: fieldName),
    );
    await importer.executeImport(
      db: db,
      data: data,
      memberRepo: memberRepo,
      sessionRepo: DriftFrontingSessionRepository(db.frontingSessionsDao, null),
      conversationRepo: DriftConversationRepository(db.conversationsDao, null),
      messageRepo: DriftChatMessageRepository(db.chatMessagesDao, null),
      pollRepo: DriftPollRepository(
        db.pollsDao,
        db.pollOptionsDao,
        db.pollVotesDao,
        null,
      ),
      customFieldsRepo: fieldsRepo,
      spImportDao: db.spImportDao,
      downloadAvatars: false,
    );
  }

  Future<({String fieldId, String memberId})> importedPair() async {
    final fields = await fieldsRepo.getAllFields();
    final field = fields.singleWhere((f) => f.name == 'Color');
    final members = await db.select(db.members).get();
    final member = members.singleWhere((m) => m.name == 'Kai');
    return (fieldId: field.id, memberId: member.id);
  }

  Future<List<CustomFieldValueRow>> allValueRows() =>
      db.select(db.customFieldValues).get();

  test('repeat import converges on one live row per (field, member)',
      () async {
    await runImport(colorValue: 'red');
    final pair = await importedPair();
    final deterministicId = deriveCustomFieldValueId(
      customFieldId: pair.fieldId,
      memberId: pair.memberId,
    );

    final first = await fieldsRepo.getValueForField(
      pair.fieldId,
      pair.memberId,
    );
    expect(first?.value, 'red');
    expect(first?.id, deterministicId);

    await runImport(colorValue: 'blue');

    final second = await fieldsRepo.getValueForField(
      pair.fieldId,
      pair.memberId,
    );
    expect(second?.value, 'blue');
    expect(second?.id, deterministicId);
    expect((await allValueRows()).length, 1);
  });

  test('import after a UI edit updates the live row instead of duplicating',
      () async {
    await runImport(colorValue: 'red');
    final pair = await importedPair();

    await fieldsRepo.upsertValue(
      domain.CustomFieldValue(
        id: deriveCustomFieldValueId(
          customFieldId: pair.fieldId,
          memberId: pair.memberId,
        ),
        customFieldId: pair.fieldId,
        memberId: pair.memberId,
        value: 'edited locally',
      ),
    );

    await runImport(colorValue: 'green');

    final value = await fieldsRepo.getValueForField(
      pair.fieldId,
      pair.memberId,
    );
    expect(value?.value, 'green');
    expect((await allValueRows()).length, 1);
  });

  test('import over a burned deterministic id mints a fresh visible row',
      () async {
    await runImport(colorValue: 'red');
    final pair = await importedPair();
    final deterministicId = deriveCustomFieldValueId(
      customFieldId: pair.fieldId,
      memberId: pair.memberId,
    );

    // Clearing tombstones the deterministic id; fleet-wide it is absorbing
    // and can never be revived, so the re-import must not write into it.
    await fieldsRepo.deleteValueFor(pair.fieldId, pair.memberId);

    await runImport(colorValue: 'blue');

    final revived = await fieldsRepo.getValueForField(
      pair.fieldId,
      pair.memberId,
    );
    expect(revived?.value, 'blue');
    expect(revived?.id, isNot(deterministicId));

    final rows = await allValueRows();
    final tombstone = rows.singleWhere((r) => r.id == deterministicId);
    expect(tombstone.isDeleted, isTrue);
    expect(rows.where((r) => !r.isDeleted).length, 1);
  });

  test('repeat import updates an active field definition without duplicating '
      'or touching local layout', () async {
    await runImport(colorValue: 'red');
    final pair = await importedPair();

    // Simulate a local layout tweak the re-import must not clobber.
    await fieldsRepo.setFieldDisplayOrder(pair.fieldId, 7);

    await runImport(colorValue: 'red', fieldName: 'Colour');

    final fields = await fieldsRepo.getAllFields();
    final field = fields.singleWhere((f) => f.id == pair.fieldId);
    expect(field.name, 'Colour');
    expect(field.displayOrder, 7);
    expect(fields.where((f) => f.name == 'Color'), isEmpty);
  });
}
