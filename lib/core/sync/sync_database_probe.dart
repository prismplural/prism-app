import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/constants/app_constants.dart';
import 'package:prism_plurality/core/database/database_encryption.dart';
import 'package:prism_plurality/core/sync/sync_schema.dart';

typedef SyncDatabaseOpenProbe =
    Future<bool> Function(String dbPath, String hexKey);

Future<bool> rustSyncDatabaseOpenProbe(String dbPath, String hexKey) async {
  if (!File(dbPath).existsSync()) return false;
  if (!validateHexKey(hexKey)) return false;
  ffi.PrismSyncHandle? handle;
  try {
    handle = await ffi.createPrismSync(
      relayUrl: AppConstants.defaultRelayUrl,
      dbPath: dbPath,
      allowInsecure: false,
      schemaJson: prismSyncSchema,
      databaseKey: await ffi.hexDecode(hexStr: hexKey),
    );
    return true;
  } catch (e) {
    if (e.toString().contains('flutter_rust_bridge has not been initialized')) {
      rethrow;
    }
    debugPrint(
      '[SYNC_PROBE] Rust open failed '
      '(files=${syncDbFileSizes(dbPath)}): $e',
    );
    return false;
  } finally {
    handle?.dispose();
  }
}

String syncDbFileSizes(String dbPath) {
  String size(String suffix) {
    final file = File('$dbPath$suffix');
    if (!file.existsSync()) return 'missing';
    try {
      return file.lengthSync().toString();
    } catch (_) {
      return 'unreadable';
    }
  }

  return 'db=${size('')},wal=${size('-wal')},shm=${size('-shm')},journal=${size('-journal')}';
}
