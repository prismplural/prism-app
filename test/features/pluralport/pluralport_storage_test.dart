import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_preservation.dart';
import 'harness.dart';

void main() {
  test(
    'v40 upgrade retains existing data and adds preservation storage',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'pluralport-migration-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/db.sqlite');
      final seeded = AppDatabase(NativeDatabase(file));
      await seeded
          .into(seeded.members)
          .insert(
            MembersCompanion.insert(
              id: 'm',
              name: 'Original',
              createdAt: DateTime.utc(2026),
            ),
          );
      await seeded.close();
      final old = raw.sqlite3.open(file.path);
      old.execute('DROP TABLE plural_port_unsupported');
      old.execute('PRAGMA user_version = 40');
      old.close();
      final upgraded = AppDatabase(NativeDatabase(file));
      addTearDown(upgraded.close);
      await PluralPortPreservation(
        upgraded,
      ).retain({'kind': 'test', 'value': 1});
      expect(
        (await upgraded.membersDao.getAllMembersIncludingDeleted()).single.name,
        'Original',
      );
      expect(
        (await PluralPortPreservation(upgraded).documents()).single['value'],
        1,
      );
    },
  );
  test(
    'sync adapter reconstructs complete retained documents on another database',
    () async {
      final source = makeDb(), peer = makeDb();
      addTearDown(source.close);
      addTearDown(peer.close);
      await PluralPortPreservation(
        source,
      ).retain({'kind': 'test', 'value': 'hello' * 15000});
      final sender = buildSyncAdapterWithCompletion(
        source,
      ).adapter.entityForTable('plural_port_unsupported')!;
      final receiver = buildSyncAdapterWithCompletion(
        peer,
      ).adapter.entityForTable('plural_port_unsupported')!;
      final rows = await source.select(source.pluralPortUnsupported).get();
      await receiver.applyFields(
        rows.first.id,
        sender.toSyncFields(rows.first),
      );
      await expectLater(
        PluralPortPreservation(peer).documents(),
        throwsFormatException,
      );
      for (final row in rows.skip(1)) {
        await receiver.applyFields(row.id, sender.toSyncFields(row));
      }
      expect(
        await PluralPortPreservation(peer).documents(),
        await PluralPortPreservation(source).documents(),
      );
    },
  );
  test(
    'failed import transaction rolls back retained data with app rows',
    () async {
      final db = makeDb();
      addTearDown(db.close);
      final exporter = makeExport(db), importer = makeImport(db);
      final data = (await exporter.buildExport()).toJson();
      data['headmates'] = [
        {'id': 'new', 'name': 'New', 'createdAt': '2026-01-01T00:00:00Z'},
      ];
      await expectLater(
        importer.importData(
          jsonEncode(data),
          beforeCommit: () async {
            await PluralPortPreservation(db).retain({'kind': 'test'});
            throw StateError('injected failure');
          },
        ),
        throwsStateError,
      );
      expect(await db.membersDao.getAllMembersIncludingDeleted(), isEmpty);
      expect(await PluralPortPreservation(db).documents(), isEmpty);
    },
  );
}
