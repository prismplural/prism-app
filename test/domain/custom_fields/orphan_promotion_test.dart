import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/custom_fields/orphan_promotion.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';

CustomField _field({
  required String id,
  required String fieldTypeId,
  String? parentFieldId,
}) =>
    CustomField(
      id: id,
      name: 'name-$id',
      fieldType: CustomFieldType.text,
      fieldTypeId: fieldTypeId,
      parentFieldId: parentFieldId,
      createdAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('promoteOrphansForRender', () {
    test('returns input unchanged when nothing to promote', () {
      final group = _field(id: 'g', fieldTypeId: 'group');
      final child = _field(id: 'c', fieldTypeId: 'text', parentFieldId: 'g');
      final out = promoteOrphansForRender([group, child]);
      expect(out[0].parentFieldId, isNull); // group itself
      expect(out[1].parentFieldId, 'g'); // child stays attached
    });

    test('promotes orphan whose parent is missing', () {
      final orphan = _field(
        id: 'orphan',
        fieldTypeId: 'text',
        parentFieldId: 'ghost-id',
      );
      final out = promoteOrphansForRender([orphan]);
      expect(out.single.parentFieldId, isNull);
    });

    test('promotes orphan whose parent is non-group', () {
      final textParent = _field(id: 'p', fieldTypeId: 'text');
      final child = _field(id: 'c', fieldTypeId: 'text', parentFieldId: 'p');
      final out = promoteOrphansForRender([textParent, child]);
      expect(out[1].parentFieldId, isNull);
    });

    test('promotes child whose parent is itself nested (depth-1 enforcement)',
        () {
      // A is a group at top level.
      // B is a child of A but mis-typed as 'group' (createFieldFromImport
      // or sync apply can plant this).
      // C is a child of B → would render 2-deep without this guard.
      final a = _field(id: 'A', fieldTypeId: 'group');
      final b = _field(id: 'B', fieldTypeId: 'group', parentFieldId: 'A');
      final c = _field(id: 'C', fieldTypeId: 'text', parentFieldId: 'B');

      final out = promoteOrphansForRender([a, b, c]);
      // C must be promoted to top level because B is nested.
      final outC = out.firstWhere((f) => f.id == 'C');
      expect(outC.parentFieldId, isNull,
          reason: 'C should promote — its parent B is itself nested');
    });

    test('promotes a field whose parent_field_id is itself (self-cycle)',
        () {
      // Buggy peer or sync apply plants parent_field_id = self_id.
      final selfCycle = _field(
        id: 'self',
        fieldTypeId: 'group',
        parentFieldId: 'self',
      );
      final out = promoteOrphansForRender([selfCycle]);
      expect(out.single.parentFieldId, isNull,
          reason: 'Self-cycle must promote to top level');
    });

    test('does not mutate the input list', () {
      final group = _field(id: 'g', fieldTypeId: 'group');
      final child = _field(id: 'c', fieldTypeId: 'text', parentFieldId: 'g');
      final input = [group, child];
      final inputCopy = List.of(input);
      promoteOrphansForRender(input);
      expect(input, inputCopy);
    });

    test('empty input returns empty', () {
      expect(promoteOrphansForRender(const []), isEmpty);
    });
  });
}
