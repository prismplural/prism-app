// test/features/pluralkit/services/pk_group_sync_field_maps_utc_test.dart
//
// DateTime UTC normalization for PK group sync field maps (Fix X — UTC tail).
//
// Both `PkGroupsImporter.groupCreateSyncFields` and
// `PkGroupSyncV2CatchupService._groupFields` (exposed via `debugGroupFields`)
// emit `created_at` and `last_seen_from_pk_at`. Routes them through
// .toUtc().toIso8601String() so peers in other timezones don't reparse the
// values as their own local time.

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_group_sync_v2_catchup_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_groups_importer.dart';

void main() {
  late AppDatabase db;
  late MemberGroupRow row;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final localCreated = DateTime(2026, 4, 27, 10, 0);
    final localPkSeen = DateTime(2026, 4, 27, 11, 30);

    await db
        .into(db.memberGroups)
        .insert(
          MemberGroupsCompanion.insert(
            id: 'pk-g',
            name: 'g',
            createdAt: localCreated,
            lastSeenFromPkAt: Value(localPkSeen),
          ),
        );
    row = await (db.select(db.memberGroups)..limit(1)).getSingle();
  });

  tearDown(() => db.close());

  test(
    'PkGroupsImporter.groupCreateSyncFields emits Z-suffixed UTC for '
    'created_at and last_seen_from_pk_at',
    () {
      final fields = PkGroupsImporter.groupCreateSyncFields(row);
      final createdStr = fields['created_at'] as String;
      final pkSeenStr = fields['last_seen_from_pk_at'] as String;
      expect(createdStr.endsWith('Z'), isTrue, reason: createdStr);
      expect(pkSeenStr.endsWith('Z'), isTrue, reason: pkSeenStr);
      expect(
        DateTime.parse(createdStr).isAtSameMomentAs(row.createdAt.toUtc()),
        isTrue,
      );
      expect(
        DateTime.parse(pkSeenStr)
            .isAtSameMomentAs(row.lastSeenFromPkAt!.toUtc()),
        isTrue,
      );
    },
  );

  test(
    'PkGroupSyncV2CatchupService.debugGroupFields emits Z-suffixed UTC for '
    'created_at and last_seen_from_pk_at',
    () {
      final fields = PkGroupSyncV2CatchupService.debugGroupFields(row);
      final createdStr = fields['created_at'] as String;
      final pkSeenStr = fields['last_seen_from_pk_at'] as String;
      expect(createdStr.endsWith('Z'), isTrue, reason: createdStr);
      expect(pkSeenStr.endsWith('Z'), isTrue, reason: pkSeenStr);
      expect(
        DateTime.parse(createdStr).isAtSameMomentAs(row.createdAt.toUtc()),
        isTrue,
      );
      expect(
        DateTime.parse(pkSeenStr)
            .isAtSameMomentAs(row.lastSeenFromPkAt!.toUtc()),
        isTrue,
      );
    },
  );
}
