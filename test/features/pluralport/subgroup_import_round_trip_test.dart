import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_exporter.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_mapper.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_preservation.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_service.dart';

import 'harness.dart';

void main() {
  for (final portable in [false, true]) {
    for (final pkBacked in [false, true]) {
      test(
        '${portable ? 'PluralPort' : 'native'} clean import preserves '
        '${pkBacked ? 'PK-imported' : 'ordinary'} group hierarchy and membership',
        () async {
          final source = makeDb();
          final target = makeDb();
          addTearDown(source.close);
          addTearDown(target.close);
          String id(int i) => pkBacked ? 'pk-group-uuid-$i' : 'group-$i';
          await source
              .into(source.members)
              .insert(
                MembersCompanion.insert(
                  id: 'member',
                  name: 'Member',
                  createdAt: DateTime.utc(2026),
                ),
              );
          for (var i = 0; i < 4; i++) {
            await source
                .into(source.memberGroups)
                .insert(
                  MemberGroupsCompanion.insert(
                    id: id(i),
                    name: 'Group $i',
                    createdAt: DateTime.utc(2026),
                    parentGroupId: Value(i == 0 ? null : id(i == 1 ? 0 : 1)),
                    displayOrder: Value(i == 3 ? 1 : 0),
                    pluralkitUuid: Value(pkBacked ? 'uuid-$i' : null),
                  ),
                );
          }
          await source
              .into(source.memberGroupEntries)
              .insert(
                MemberGroupEntriesCompanion.insert(
                  id: 'entry',
                  groupId: id(2),
                  memberId: 'member',
                ),
              );
          final native = await makeExport(source).buildExport();
          if (portable) {
            final bundle = PluralPortExporter(
              native.toJson(),
              'fixture',
            ).build(await PluralPortPreservation(source).documents());
            await PluralPortService(
              db: target,
              exporter: makeExport(target),
              importer: makeImport(target),
            ).importPlan(PluralPortMapper.plan(bundle));
          } else {
            await makeImport(target).importData(jsonEncode(native.toJson()));
          }
          final groups = await target.select(target.memberGroups).get();
          final byName = {for (final g in groups) g.name: g};
          expect(groups, hasLength(4));
          expect(byName['Group 0']!.parentGroupId, isNull);
          expect(byName['Group 1']!.parentGroupId, byName['Group 0']!.id);
          expect(byName['Group 2']!.parentGroupId, byName['Group 1']!.id);
          expect(byName['Group 3']!.parentGroupId, byName['Group 1']!.id);
          expect(
            byName['Group 2']!.displayOrder,
            lessThan(byName['Group 3']!.displayOrder),
          );
          final entries = await target.select(target.memberGroupEntries).get();
          expect(entries, hasLength(1));
          expect(entries.single.groupId, byName['Group 2']!.id);
          expect(entries.single.memberId, 'member');
        },
      );
    }
  }
}
