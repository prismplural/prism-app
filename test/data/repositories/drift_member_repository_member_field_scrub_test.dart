// Regression contract for the member-delete custom-field scrub.
//
// A member-type field stores `{"memberIds":[...]}` in custom_field_values.value.
// Deleting a member must strip its id from every active member-type value on
// other members: the blob is rewritten without the id, and a value that ends up
// empty is tombstoned (clear semantics) rather than left holding a dead id.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/constants/custom_field_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart' as db;
import 'package:prism_plurality/data/repositories/drift_custom_fields_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/domain/custom_fields/definitions/member_field_definition.dart';
import 'package:prism_plurality/domain/models/custom_field.dart' as cf;
import 'package:prism_plurality/domain/models/custom_field_value.dart' as cfv;
import 'package:prism_plurality/domain/models/member.dart' as member_domain;
import 'package:prism_plurality/domain/models/typed_field_value.dart';

void main() {
  late db.AppDatabase database;
  late DriftMemberRepository memberRepo;
  late DriftCustomFieldsRepository fieldsRepo;

  final now = DateTime.utc(2026, 7, 9, 12);
  const fieldId = 'buddies';

  String encode(Set<String> ids) =>
      memberFieldDefinition.valueEncoder(MemberFieldValue(memberIds: ids));

  Set<String> memberIdsOf(String raw) =>
      (memberFieldDefinition.valueParser(raw) as MemberFieldValue).memberIds;

  Future<void> createMember(String id) => memberRepo.createMember(
    member_domain.Member(id: id, name: id, createdAt: now),
  );

  Future<void> setValue(String owner, Set<String> refs) => fieldsRepo.upsertValue(
    cfv.CustomFieldValue(
      id: deriveCustomFieldValueId(customFieldId: fieldId, memberId: owner),
      customFieldId: fieldId,
      memberId: owner,
      value: encode(refs),
    ),
  );

  setUp(() async {
    database = db.AppDatabase(NativeDatabase.memory());
    memberRepo = DriftMemberRepository(
      database.membersDao,
      null,
      customFieldsDao: database.customFieldsDao,
    );
    fieldsRepo = DriftCustomFieldsRepository(database.customFieldsDao, null);
    await fieldsRepo.createField(
      cf.CustomField(
        id: fieldId,
        name: 'Buddies',
        fieldType: cf.CustomFieldType.text,
        fieldTypeId: memberFieldDefinition.id,
        createdAt: now,
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('deleting one referenced member decrements the blob; deleting the last '
      'referenced member tombstones the value row', () async {
    for (final id in ['A', 'B', 'C']) {
      await createMember(id);
    }
    await setValue('A', {'B', 'C'});

    await memberRepo.deleteMember('B');

    final afterB = await fieldsRepo.getValueForField(fieldId, 'A');
    expect(afterB, isNotNull, reason: 'row stays editable while C remains');
    expect(memberIdsOf(afterB!.value), {'C'});

    await memberRepo.deleteMember('C');

    expect(
      await fieldsRepo.getValueForField(fieldId, 'A'),
      isNull,
      reason: 'emptied member value clears',
    );
  });

  test('a value referencing only the deleted member is cleared, and a later '
      'refill of that field is visible again', () async {
    await createMember('D');
    await createMember('X');
    await createMember('live');
    await setValue('X', {'D'});

    await memberRepo.deleteMember('D');

    expect(await fieldsRepo.getValueForField(fieldId, 'X'), isNull);

    // Refill over the burned deterministic id — the DAO mints a fresh row, so
    // it must be visible via getValueForField.
    await setValue('X', {'live'});

    final refilled = await fieldsRepo.getValueForField(fieldId, 'X');
    expect(refilled, isNotNull);
    expect(memberIdsOf(refilled!.value), {'live'});
    expect(
      refilled.id,
      isNot(deriveCustomFieldValueId(customFieldId: fieldId, memberId: 'X')),
      reason: 'refill mints a fresh id over the burned tombstone',
    );
  });

  test('the deleted member is scrubbed only from member-type fields, leaving '
      'other fields untouched', () async {
    await createMember('A');
    await createMember('B');
    // A non-member field whose value happens to contain the deleted id as text.
    await fieldsRepo.createField(
      cf.CustomField(
        id: 'note',
        name: 'Note',
        fieldType: cf.CustomFieldType.text,
        fieldTypeId: 'text',
        createdAt: now,
      ),
    );
    await fieldsRepo.upsertValue(
      cfv.CustomFieldValue(
        id: deriveCustomFieldValueId(customFieldId: 'note', memberId: 'A'),
        customFieldId: 'note',
        memberId: 'A',
        value: 'B is my friend',
      ),
    );
    await setValue('A', {'B'});

    await memberRepo.deleteMember('B');

    // Member-type value cleared, plain-text value preserved verbatim.
    expect(await fieldsRepo.getValueForField(fieldId, 'A'), isNull);
    final note = await fieldsRepo.getValueForField('note', 'A');
    expect(note, isNotNull);
    expect(note!.value, 'B is my friend');
  });
}
