import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/sync_schema.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:sqlite3/sqlite3.dart' as raw;

import 'e2e_fixture.dart';
import 'e2e_support.dart';

enum PkRestartUnlockMode { runtimeCache, password }

Future<File> seedPkSchema39Fixture(Directory directory) async {
  // Schema 40 changed only this member index and create_push_started_at; this
  // reverses that exact migration delta before reopening through real Drift.
  final file = File('${directory.path}/app.sqlite');
  final db = AppDatabase(NativeDatabase(file));
  await db.customSelect('SELECT 1').get();
  await db
      .into(db.members)
      .insert(
        MembersCompanion.insert(
          id: 'local-winner',
          name: 'Local winner',
          createdAt: DateTime.utc(2026, 1, 1),
          pluralkitUuid: const Value('stable-member-uuid'),
        ),
      );
  await db
      .into(db.frontingSessions)
      .insert(
        FrontingSessionsCompanion.insert(
          id: 'historical-front',
          startTime: DateTime.utc(2026, 2, 1),
          memberId: const Value('remote-member'),
        ),
      );
  await db
      .into(db.frontingSessions)
      .insert(
        FrontingSessionsCompanion.insert(
          id: 'intentional-sleep',
          startTime: DateTime.utc(2026, 2, 2),
          memberId: const Value(null),
          sessionType: const Value(1),
        ),
      );
  await db.close();

  final rawDb = raw.sqlite3.open(file.path);
  try {
    rawDb.execute('DROP INDEX IF EXISTS idx_members_pluralkit_id');
    rawDb.execute(
      'CREATE UNIQUE INDEX idx_members_pluralkit_id '
      'ON members(pluralkit_id) WHERE pluralkit_id IS NOT NULL',
    );
    rawDb.execute('ALTER TABLE members DROP COLUMN create_push_started_at');
    rawDb.execute('PRAGMA user_version = 39');
  } finally {
    rawDb.close();
  }
  return file;
}

Future<E2EDevice> pairPersistentDevice(
  TestRelay relay,
  E2EDevice initiator,
  String engineDbPath,
) async {
  final handle = await ffi.createPrismSync(
    relayUrl: relay.baseUrl,
    dbPath: engineDbPath,
    allowInsecure: true,
    schemaJson: prismSyncSchema,
  );
  try {
    final joiner =
        jsonDecode(await ffi.startJoinerCeremony(handle: handle))
            as Map<String, dynamic>;
    final init =
        jsonDecode(
              await ffi.startInitiatorCeremony(
                handle: initiator.handle,
                tokenBytes: (joiner['token_bytes'] as List).cast<int>(),
              ),
            )
            as Map<String, dynamic>;
    final sas =
        jsonDecode(await ffi.getJoinerSas(handle: handle))
            as Map<String, dynamic>;
    expect(sas['sas_word_list'], init['sas_word_list']);
    await ffi.uploadPairingSnapshot(
      handle: initiator.handle,
      ttlSecs: BigInt.from(86400),
      forDeviceId: init['joiner_device_id'] as String,
    );
    final complete = await Future.wait([
      ffi.completeInitiatorCeremony(
        handle: initiator.handle,
        password: initiator.password,
        mnemonic: Uint8List.fromList(initiator.mnemonic),
      ),
      ffi.completeJoinerCeremony(handle: handle, password: initiator.password),
    ]).timeout(const Duration(seconds: 45));
    expect(
      (jsonDecode(complete[1]) as Map<String, dynamic>)['sync_id'],
      initiator.syncId,
    );
    await ffi.configureEngine(handle: handle);
    await ffi.bootstrapFromSnapshot(handle: handle);
    await ffi.acknowledgeSnapshotApplied(handle: handle);
    await initiator.sync();
    final device = E2EDevice(
      handle: handle,
      syncId: initiator.syncId,
      password: initiator.password,
      mnemonic: initiator.mnemonic,
    );
    await device.sync();
    return device;
  } catch (_) {
    handle.dispose();
    rethrow;
  }
}

Future<E2EDevice> reopenPersistentDevice(
  TestRelay relay,
  E2EDevice device,
  String engineDbPath,
  PkRestartUnlockMode mode,
) async {
  final dek = await ffi.exportDek(handle: device.handle);
  final secureStore = await ffi.drainSecureStore(handle: device.handle);
  final deviceSecret = secureStore['device_secret'];
  if (deviceSecret == null) {
    throw StateError('paired device did not export device_secret');
  }
  device.dispose();
  final handle = await ffi.createPrismSync(
    relayUrl: relay.baseUrl,
    dbPath: engineDbPath,
    allowInsecure: true,
    schemaJson: prismSyncSchema,
  );
  await ffi.seedSecureStore(handle: handle, entries: secureStore);
  switch (mode) {
    case PkRestartUnlockMode.runtimeCache:
      await ffi.restoreRuntimeKeys(
        handle: handle,
        dek: dek,
        deviceSecret: deviceSecret,
      );
    case PkRestartUnlockMode.password:
      final secretKey = await ffi.mnemonicToBytes(
        mnemonic: Uint8List.fromList(device.mnemonic),
      );
      await ffi.unlock(
        handle: handle,
        password: device.password,
        secretKey: secretKey,
      );
  }
  await ffi.configureEngine(handle: handle);
  return E2EDevice(
    handle: handle,
    syncId: device.syncId,
    password: device.password,
    mnemonic: device.mnemonic,
  );
}
