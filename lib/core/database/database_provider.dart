import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as raw;

import 'app_database.dart';
import 'database_encryption.dart';
import 'package:prism_plurality/core/services/app_data_dir.dart';
import 'package:prism_plurality/core/services/backup_exclusion.dart';
import 'package:prism_plurality/core/services/keychain_degraded_state.dart';
import 'package:prism_plurality/core/services/secure_storage.dart';
import 'package:prism_plurality/core/services/secure_storage_diagnostic.dart';

// Re-export so existing callers that import database_provider.dart for the
// SecureStorageDiagnostic type don't have to change their imports. The
// canonical definition now lives in
// `lib/core/services/secure_storage_diagnostic.dart`.
export 'package:prism_plurality/core/services/secure_storage_diagnostic.dart'
    show
        SecureStorageDiagnostic,
        SlotOutcome,
        DbStartupStateName,
        KeychainRepairWritebackResult,
        DiagnosticSlotIds,
        slotOutcomeName,
        slotOutcomeThrewString,
        bootSecureStorageDiagnosticProvider;

// ---------------------------------------------------------------------------
// Public API — §4 app DB startup probe
// ---------------------------------------------------------------------------
//
// The §4 boot probe is the SINGLE place that touches secure storage on the
// app-DB open path. It:
//
//   1. Runs before any provider hydrates — called from main.dart pre-runApp
//      (§6 wires this up).
//   2. Resolves the verified app DB key, trying primary → sync → sync_staging
//      slots until one of them actually opens the on-disk encrypted DB.
//   3. Returns the key in memory so `verifiedStartupKeyProvider` can be
//      overridden via `ProviderScope.overrides`. Every subsequent DB-key
//      write goes through the guarded writers in `database_encryption.dart`
//      with that verified key in hand.
//
// After the probe returns, `databaseProvider` reads
// `verifiedStartupKeyProvider` directly to construct the LazyDatabase — the
// open path has ZERO secure-storage reads this session.

/// The path to the app's main database file.
///
/// Exposed so that startup and reset flows can access the file before Drift
/// opens the database. The optional [directory] override is used by tests so
/// they don't need to mock the `path_provider` platform channel.
Future<File> getDatabaseFile({Directory? directory}) async {
  final dbFolder = directory ?? await getAppDataDir();
  return File(p.join(dbFolder.path, 'prism.db'));
}

/// Terminal state of the app DB startup probe.
///
/// - [ready]: the probe found (or generated) a key that successfully opens
///   the on-disk DB (or, in the fresh-install case, the new key was
///   persisted and the DB has yet to be created by Drift).
/// - [unrecoverable]: every recovery slot was READ and none opened the DB
///   (keys genuinely missing or cipher-corrupt). The boot path short-circuits
///   to the recovery UI, which may offer a destructive reset.
/// - [keychainUnavailable]: the DB file exists but at least one slot could not
///   be READ this boot (transient / locked / platform error) and no slot
///   produced a working key. The key may be intact and readable on the next
///   boot, so this MUST NOT trigger a destructive reset — the boot path shows
///   a non-destructive "retry" screen instead.
enum DbStartupState { ready, unrecoverable, keychainUnavailable }

/// Result of the §4 app DB startup probe.
@immutable
class DbStartupReport {
  const DbStartupReport({
    required this.state,
    required this.keyInMemory,
    required this.usedRecoverySlot,
    required this.diagnostic,
    this.schemaVersionBeforeOpen,
  });

  /// Terminal state.
  final DbStartupState state;

  /// The 64-character lowercase hex key that opens `prism.db`. Always
  /// non-null when [state] is [DbStartupState.ready]; always null when
  /// [state] is [DbStartupState.unrecoverable].
  final String? keyInMemory;

  /// Which slot the verified key came from. One of:
  ///   * `'fresh'`         — no DB file existed; a new key was generated
  ///   * `'primary'`       — the canonical Drift DB-key slot
  ///   * `'sync'`          — the dedicated sync DB-key slot
  ///   * `'sync_staging'`  — the sync DB staging slot
  ///   * `null`            — unrecoverable
  ///
  /// Set the `keychain_repair_pending` flag iff this is in
  /// {`'sync'`, `'sync_staging'`}. (`'fresh'` and `'primary'` are healthy.)
  final String? usedRecoverySlot;

  /// Diagnostic record. §10 will extend this; for §4 it captures
  /// per-slot outcomes and which slot produced the verified key.
  final SecureStorageDiagnostic? diagnostic;

  /// The on-disk SQLite user_version observed by the boot probe before Drift
  /// opens the app DB. Null means no app DB existed yet, or the version was
  /// not available.
  final int? schemaVersionBeforeOpen;
}

@immutable
class DatabaseReadyReport {
  const DatabaseReadyReport({
    required this.schemaVersionBeforeOpen,
    required this.schemaVersionAfterOpen,
  });

  /// Null means no on-disk app DB existed before Drift opened it.
  final int? schemaVersionBeforeOpen;
  final int schemaVersionAfterOpen;

  bool get createdFresh => schemaVersionBeforeOpen == null;

  bool get migrated =>
      schemaVersionBeforeOpen != null &&
      schemaVersionBeforeOpen! < schemaVersionAfterOpen;
}

/// Reads SQLite user_version before Drift opens the database.
///
/// Production overrides this with the boot probe value.
final databaseSchemaVersionBeforeOpenProvider = FutureProvider<int?>((
  ref,
) async {
  final hexKey = ref.watch(verifiedStartupKeyProvider);
  if (hexKey == null) {
    throw StateError(
      'databaseSchemaVersionBeforeOpenProvider read before '
      'verifiedStartupKeyProvider was overridden.',
    );
  }
  final file = await getDatabaseFile();
  if (!file.existsSync()) return null;
  return _readEncryptedUserVersion(file.path, hexKey);
});

/// Opens Drift before DB-backed routes can render.
final databaseReadyProvider = FutureProvider<DatabaseReadyReport>((ref) async {
  final schemaVersionBeforeOpen = ref.watch(
    databaseSchemaVersionBeforeOpenProvider.future,
  );
  final db = ref.watch(databaseProvider);
  final before = await schemaVersionBeforeOpen.catchError((
    Object error,
    StackTrace stackTrace,
  ) {
    debugPrint(
      '[DB_PROVIDER] Startup schema-version probe failed; continuing without '
      'migration status copy: $error',
    );
    return null;
  });
  await db.customSelect('SELECT 1').getSingle();
  final after = await _readDriftUserVersion(db);
  return DatabaseReadyReport(
    schemaVersionBeforeOpen: before,
    schemaVersionAfterOpen: after,
  );
});

/// Probe the app DB at startup, returning a verified key in memory or
/// signalling unrecoverable so the boot path can short-circuit to the
/// recovery UI.
///
/// Order of operations (the only path through):
///
/// 1. **Fresh-install branch.** If `prism.db` does not exist, generate a
///    fresh 32-byte key, persist it through the guarded writer, and return
///    `ready('fresh')`. No recovery candidates are consulted.
/// 2. **Staging crash recovery.** If a primary-slot staging key exists,
///    verify it against the on-disk DB; promote on match, discard on
///    mismatch. This may update the primary slot before we read it.
/// 3. **Primary slot.** Read via the wrapped, classified reader. If the
///    value opens the on-disk DB, return `ready('primary')`.
/// 4. **Sync primary slot.** Same — return `ready('sync')` on success and
///    set the repair-pending flag.
/// 5. **Sync staging slot.** Same — return `ready('sync_staging')` on
///    success and set the repair-pending flag.
/// 6. **Unrecoverable.** No slot opened the DB. Return
///    `unrecoverable`.
///
/// The optional [directory] override exists so tests don't need to mock the
/// `path_provider` platform channel.
///
/// [degradedStateService] is the §8 service used to record per-slot
/// outcomes. When omitted a default instance is constructed; tests inject
/// a fake.
///
/// [random] feeds the fresh-install key generator — tests inject a
/// deterministic source. Production callers must omit it (or pass
/// `Random.secure()`).
Future<DbStartupReport> probeAppDatabaseStartup({
  Directory? directory,
  KeychainDegradedStateService? degradedStateService,
  Random? random,
}) async {
  final service = degradedStateService ?? KeychainDegradedStateService();
  final slotOutcomes = <String, String>{};
  final file = await getDatabaseFile(directory: directory);
  final dbPath = file.path;

  // A transient/unknown read (keychain locked at boot, macOS errSecParam, …) is
  // "couldn't read", not "key gone" — so it must not contribute to an
  // unrecoverable verdict. See [DbStartupState.keychainUnavailable].
  var sawIndeterminate = false;
  void noteOutcome(SlotOutcome outcome) {
    if (outcome == SlotOutcome.transient || outcome == SlotOutcome.unknown) {
      sawIndeterminate = true;
    }
  }

  int? readSchemaVersionBeforeOpen(String hexKey) {
    try {
      return _readEncryptedUserVersion(dbPath, hexKey);
    } catch (e) {
      debugPrint(
        '[DB_PROVIDER] Failed to read pre-open schema version from app DB: $e',
      );
      return null;
    }
  }

  Future<SecureStorageDiagnostic> buildDiagnostic({
    required String? recoveredVia,
    required DbStartupStateName appDbState,
  }) async {
    KeychainDegradedState? degradedSnapshot;
    try {
      degradedSnapshot = await service.read();
    } catch (e) {
      debugPrint('[DB_PROVIDER] Failed to snapshot degraded state: $e');
    }
    return SecureStorageDiagnostic(
      recoveredVia: recoveredVia,
      slotOutcomes: slotOutcomes,
      appDbState: appDbState,
      keychainDegradedStateSnapshot: degradedSnapshot,
    );
  }

  // ── 1. Fresh-install branch ────────────────────────────────────────────
  if (!file.existsSync()) {
    final rng = random ?? Random.secure();
    final bytes = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      bytes[i] = rng.nextInt(256);
    }
    final newKey = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    // Fresh install: keychain_repair_pending should be false at this point,
    // so the guarded writer passes through. We supply no verifiedStartupKey
    // — if the flag is somehow set (e.g. a partial previous boot left it
    // sticky), the guard will throw, which we catch and surface as
    // unrecoverable.
    SecureWriteResult writeResult;
    try {
      writeResult = await writeDatabaseKeyHex(newKey);
    } on StateError catch (e) {
      slotOutcomes[DiagnosticSlotIds.appDbFresh] = slotOutcomeThrewString(e);
      await service.updateSlot('appDbKey', SlotState.unreadable);
      return DbStartupReport(
        state: DbStartupState.unrecoverable,
        keyInMemory: null,
        usedRecoverySlot: null,
        diagnostic: await buildDiagnostic(
          recoveredVia: null,
          appDbState: DbStartupStateName.unrecoverable,
        ),
      );
    }
    if (!writeResult.ok) {
      slotOutcomes[DiagnosticSlotIds.appDbFresh] =
          'threw: write-failed (${writeResult.failure?.name ?? 'unknown'})';
      await service.updateSlot('appDbKey', SlotState.unreadable);
      return DbStartupReport(
        state: DbStartupState.unrecoverable,
        keyInMemory: null,
        usedRecoverySlot: null,
        diagnostic: await buildDiagnostic(
          recoveredVia: null,
          appDbState: DbStartupStateName.unrecoverable,
        ),
      );
    }

    debugPrint('[DB_PROVIDER] Fresh install — generated new database key');
    slotOutcomes[DiagnosticSlotIds.appDbFresh] = 'ok';
    await service.updateSlot('appDbKey', SlotState.ok);
    return DbStartupReport(
      state: DbStartupState.ready,
      keyInMemory: newKey,
      usedRecoverySlot: 'fresh',
      diagnostic: await buildDiagnostic(
        recoveredVia: 'fresh',
        appDbState: DbStartupStateName.ready,
      ),
    );
  }

  // ── 2. Staging crash recovery (existing logic, wrapped reads) ──────────
  //
  // Best-effort: if a previous boot left `keychain_repair_pending` set, the
  // guarded writer inside `promoteStagingDatabaseKey` may refuse to promote
  // because we don't have a verifiedStartupKey yet. Swallow that and let
  // the subsequent slot reads do their job — the staging key will still be
  // tried as part of the primary-slot read path if it happens to be the
  // active key.
  final stagingRead = await readSlotForDiagnostic(
    '${kDatabaseKeyStorageKey}_staging',
    slotLabel: 'app DB staging key',
  );
  noteOutcome(stagingRead.outcome);
  if (stagingRead.hex != null) {
    try {
      await _recoverFromStagingKey(stagingRead.hex!, dbPath);
      slotOutcomes[DiagnosticSlotIds.appDbPrimaryStaging] = 'ok';
    } catch (e) {
      slotOutcomes[DiagnosticSlotIds.appDbPrimaryStaging] =
          slotOutcomeThrewString(e);
      debugPrint(
        '[DB_PROVIDER] Staging crash recovery skipped (repair-pending?): $e',
      );
    }
  } else {
    slotOutcomes[DiagnosticSlotIds.appDbPrimaryStaging] = slotOutcomeName(
      stagingRead.outcome,
    );
  }

  // ── 3. Primary slot ────────────────────────────────────────────────────
  final primaryRead = await readSlotForDiagnostic(
    kDatabaseKeyStorageKey,
    slotLabel: 'primary DB key',
  );
  noteOutcome(primaryRead.outcome);
  if (primaryRead.hex != null) {
    if (_tryOpenEncrypted(dbPath, primaryRead.hex!)) {
      debugPrint('[DB_PROVIDER] Primary slot opened the DB');
      slotOutcomes[DiagnosticSlotIds.appDbPrimary] = 'ok';
      await service.updateSlot('appDbKey', SlotState.ok);
      return DbStartupReport(
        state: DbStartupState.ready,
        keyInMemory: primaryRead.hex,
        usedRecoverySlot: 'primary',
        diagnostic: await buildDiagnostic(
          recoveredVia: 'primary',
          appDbState: DbStartupStateName.ready,
        ),
        schemaVersionBeforeOpen: readSchemaVersionBeforeOpen(primaryRead.hex!),
      );
    }
    slotOutcomes[DiagnosticSlotIds.appDbPrimary] = 'threw: present-but-stale';
    debugPrint(
      '[DB_PROVIDER] Primary slot returned a key that does not open the DB '
      '— falling through to sync candidates',
    );
  } else {
    slotOutcomes[DiagnosticSlotIds.appDbPrimary] = slotOutcomeName(
      primaryRead.outcome,
    );
  }

  // ── 4. Sync primary slot ───────────────────────────────────────────────
  final syncRead = await readSlotForDiagnostic(
    kSyncDatabaseKeyStorageKey,
    slotLabel: 'sync DB key',
  );
  noteOutcome(syncRead.outcome);
  if (syncRead.hex != null) {
    if (_tryOpenEncrypted(dbPath, syncRead.hex!)) {
      debugPrint('[DB_PROVIDER] Sync slot opened the DB — repair-pending');
      slotOutcomes[DiagnosticSlotIds.appDbSync] = 'ok';
      await setKeychainRepairPending(true);
      await service.updateSlot('appDbKey', SlotState.ok);
      return DbStartupReport(
        state: DbStartupState.ready,
        keyInMemory: syncRead.hex,
        usedRecoverySlot: 'sync',
        diagnostic: await buildDiagnostic(
          recoveredVia: 'sync',
          appDbState: DbStartupStateName.ready,
        ),
        schemaVersionBeforeOpen: readSchemaVersionBeforeOpen(syncRead.hex!),
      );
    }
    slotOutcomes[DiagnosticSlotIds.appDbSync] = 'threw: present-but-stale';
  } else {
    slotOutcomes[DiagnosticSlotIds.appDbSync] = slotOutcomeName(
      syncRead.outcome,
    );
  }

  // ── 5. Sync staging slot ───────────────────────────────────────────────
  final syncStagingRead = await readSlotForDiagnostic(
    '${kSyncDatabaseKeyStorageKey}_staging',
    slotLabel: 'sync DB staging key',
  );
  noteOutcome(syncStagingRead.outcome);
  if (syncStagingRead.hex != null) {
    if (_tryOpenEncrypted(dbPath, syncStagingRead.hex!)) {
      debugPrint(
        '[DB_PROVIDER] Sync staging slot opened the DB — repair-pending',
      );
      slotOutcomes[DiagnosticSlotIds.appDbSyncStaging] = 'ok';
      await setKeychainRepairPending(true);
      await service.updateSlot('appDbKey', SlotState.ok);
      return DbStartupReport(
        state: DbStartupState.ready,
        keyInMemory: syncStagingRead.hex,
        usedRecoverySlot: 'sync_staging',
        diagnostic: await buildDiagnostic(
          recoveredVia: 'sync_staging',
          appDbState: DbStartupStateName.ready,
        ),
        schemaVersionBeforeOpen: readSchemaVersionBeforeOpen(
          syncStagingRead.hex!,
        ),
      );
    }
    slotOutcomes[DiagnosticSlotIds.appDbSyncStaging] =
        'threw: present-but-stale';
  } else {
    slotOutcomes[DiagnosticSlotIds.appDbSyncStaging] = slotOutcomeName(
      syncStagingRead.outcome,
    );
  }

  // ── 6. No slot produced a working key ──────────────────────────────────
  //
  // Split the verdict on WHY. An indeterminate read (we couldn't read, vs. a
  // clean-missing or cipher-corrupt key) is not proof the key is gone, so defer
  // to a non-destructive retry rather than the reset flow, and don't stamp the
  // slot unreadable.
  if (sawIndeterminate) {
    debugPrint(
      '[DB_PROVIDER] Recovery slots could not be read this boot — keychain '
      'unavailable (deferring, NOT unrecoverable). Outcomes: $slotOutcomes',
    );
    return DbStartupReport(
      state: DbStartupState.keychainUnavailable,
      keyInMemory: null,
      usedRecoverySlot: null,
      diagnostic: await buildDiagnostic(
        recoveredVia: null,
        appDbState: DbStartupStateName.keychainUnavailable,
      ),
    );
  }

  debugPrint(
    '[DB_PROVIDER] All recovery slots exhausted — DB unrecoverable. '
    'Outcomes: $slotOutcomes',
  );
  await service.updateSlot('appDbKey', SlotState.unreadable);
  return DbStartupReport(
    state: DbStartupState.unrecoverable,
    keyInMemory: null,
    usedRecoverySlot: null,
    diagnostic: await buildDiagnostic(
      recoveredVia: null,
      appDbState: DbStartupStateName.unrecoverable,
    ),
  );
}

/// Attempt to write the verified startup key back into the primary slot when
/// the §4 boot probe recovered the DB via a non-primary slot.
///
/// Called from `main.dart` (wired in §6) AFTER the probe returns ready and
/// BEFORE `runApp`. Safe to call unconditionally — no-ops when the
/// `keychain_repair_pending` flag is clear.
///
/// On success: clears the flag.
/// On failure: leaves the flag set so the next boot retries. Never throws.
Future<void> attemptKeychainRepairWriteback(String verifiedStartupKey) async {
  final pending = await isKeychainRepairPending();
  if (!pending) return;

  try {
    final result = await writeDatabaseKeyHex(
      verifiedStartupKey,
      verifiedStartupKey: verifiedStartupKey,
    );
    if (result.ok) {
      await setKeychainRepairPending(false);
      debugPrint(
        '[DB_PROVIDER] Keychain repair write-back succeeded — flag cleared',
      );
    } else {
      debugPrint(
        '[DB_PROVIDER] Keychain repair write-back failed '
        '(failure=${result.failure?.name}, code=${result.code}, '
        'message=${result.message}) — flag kept for next boot',
      );
    }
  } catch (e, st) {
    debugPrint(
      '[DB_PROVIDER] Keychain repair write-back threw — flag kept for next '
      'boot: $e\n$st',
    );
  }
}

/// Outcome of [repairPrimaryDatabaseKeyFromVerifiedMemory].
enum PrimaryDatabaseKeyRepairOutcome {
  alreadyHealthy,
  repaired,
  skippedNoVerifiedKey,
  skippedInvalidVerifiedKey,
  skippedNoDatabase,
  skippedVerifiedKeyDoesNotOpenDb,
  writeFailed,
}

final primaryDatabaseKeyRepairProvider =
    Provider<Future<PrimaryDatabaseKeyRepairOutcome> Function(String?)>(
      (ref) => repairPrimaryDatabaseKeyFromVerifiedMemory,
    );

/// Opportunistically repair the primary app-DB key slot from the key that
/// already opened `prism.db` during this process.
///
/// This is intentionally conservative. It never generates a key and never
/// trusts process memory by itself: before writing, it proves
/// [verifiedStartupKey] still opens the on-disk database. That lets a live
/// session heal a missing/stale secure-storage slot before a later cold start,
/// without risking a divergent key write.
Future<PrimaryDatabaseKeyRepairOutcome>
repairPrimaryDatabaseKeyFromVerifiedMemory(
  String? verifiedStartupKey, {
  Directory? directory,
  KeychainDegradedStateService? degradedStateService,
}) async {
  if (verifiedStartupKey == null) {
    return PrimaryDatabaseKeyRepairOutcome.skippedNoVerifiedKey;
  }
  if (!validateHexKey(verifiedStartupKey)) {
    return PrimaryDatabaseKeyRepairOutcome.skippedInvalidVerifiedKey;
  }

  final file = await getDatabaseFile(directory: directory);
  if (!file.existsSync()) {
    return PrimaryDatabaseKeyRepairOutcome.skippedNoDatabase;
  }

  final service = degradedStateService ?? KeychainDegradedStateService();
  final primaryRead = await readSlotForDiagnostic(
    kDatabaseKeyStorageKey,
    slotLabel: 'primary DB key (in-session repair probe)',
  );

  if (primaryRead.hex == verifiedStartupKey &&
      tryOpenEncryptedDb(file.path, primaryRead.hex!)) {
    await service.updateSlot('appDbKey', SlotState.ok);
    return PrimaryDatabaseKeyRepairOutcome.alreadyHealthy;
  }

  if (!tryOpenEncryptedDb(file.path, verifiedStartupKey)) {
    debugPrint(
      '[DB_PROVIDER] In-session DB-key repair skipped — verifiedStartupKey '
      'does not open current prism.db',
    );
    return PrimaryDatabaseKeyRepairOutcome.skippedVerifiedKeyDoesNotOpenDb;
  }

  final write = await writeDatabaseKeyHex(
    verifiedStartupKey,
    verifiedStartupKey: verifiedStartupKey,
  );
  if (!write.ok) {
    debugPrint(
      '[DB_PROVIDER] In-session DB-key repair write failed '
      '(failure=${write.failure?.name}, code=${write.code}, '
      'message=${write.message})',
    );
    await service.updateSlot('appDbKey', SlotState.unreadable);
    return PrimaryDatabaseKeyRepairOutcome.writeFailed;
  }

  await service.updateSlot('appDbKey', SlotState.ok);
  if (await isKeychainRepairPending()) {
    await setKeychainRepairPending(false);
  }
  debugPrint('[DB_PROVIDER] In-session DB-key repair wrote primary slot');
  return PrimaryDatabaseKeyRepairOutcome.repaired;
}

// ---------------------------------------------------------------------------
// databaseProvider — pure injection of the verified startup key
// ---------------------------------------------------------------------------
//
// CONTRACT (see also database_encryption.dart):
//   * `verifiedStartupKeyProvider` MUST be overridden via
//     `ProviderScope.overrides` in main.dart (§6) with the result of
//     `probeAppDatabaseStartup()`.
//   * The override value MUST be a non-null 64-character lowercase hex
//     string. The probe is responsible for ensuring this.
//   * This provider does NO secure-storage reads on the open path. The key
//     is the verified one from the §4 probe; the DB will always open with
//     it (the probe wouldn't have returned `ready` otherwise) or this is a
//     fresh install and Drift is creating a new encrypted file.

final databaseProvider = Provider<AppDatabase>((ref) {
  final hexKey = ref.watch(verifiedStartupKeyProvider);
  // Defensive: §6 boot order guarantees this. In debug we surface the
  // misuse loudly; in release we throw a clear error rather than crashing
  // sqlite3 mid-PRAGMA with a confusing assertion.
  assert(
    hexKey != null,
    'databaseProvider read before verifiedStartupKeyProvider was overridden — '
    'main.dart must run probeAppDatabaseStartup() and supply the result via '
    'ProviderScope.overrides before any code reads databaseProvider.',
  );
  if (hexKey == null) {
    throw StateError(
      'databaseProvider read before verifiedStartupKeyProvider was overridden. '
      'main.dart must run probeAppDatabaseStartup() and override '
      'verifiedStartupKeyProvider with the probe result before runApp.',
    );
  }

  final db = AppDatabase(_openVerifiedConnection(hexKey));
  ref.onDispose(db.close);
  return db;
});

/// Construct a Drift `LazyDatabase` opener bound to a pre-verified
/// encryption key. ZERO secure-storage reads in this path.
LazyDatabase _openVerifiedConnection(String hexKey) {
  return LazyDatabase(() async {
    final file = await getDatabaseFile();
    await excludeFromiCloudBackup(file.path);
    return NativeDatabase.createInBackground(
      file,
      setup: makeCipherSetup(hexKey),
    );
  });
}

// ---------------------------------------------------------------------------
// Internal helpers (kept private; mirror the pre-§4 code as much as possible)
// ---------------------------------------------------------------------------

Future<String?> _verifiedSyncRecoveryKey(String dbPath) async {
  final candidates = <String?>[
    await readSyncDatabaseKeyHex(),
    await readStagingSyncDatabaseKeyHex(),
  ];
  final tried = <String>{};
  for (final candidate in candidates) {
    if (candidate == null || !tried.add(candidate)) continue;
    if (_tryOpenEncrypted(dbPath, candidate)) return candidate;
  }
  return null;
}

@visibleForTesting
Future<String?> verifiedSyncRecoveryKeyForTest(String dbPath) {
  return _verifiedSyncRecoveryKey(dbPath);
}

// ---------------------------------------------------------------------------
// DB state probes — lightweight open/query/close to determine file state.
// ---------------------------------------------------------------------------

/// Try to open the database with the given encryption key and read from it.
/// Returns true if the DB is readable with this key.
bool _tryOpenEncrypted(String path, String hexKey) {
  try {
    final db = raw.sqlite3.open(path);
    try {
      configurePrismSqliteConnection(db, hexKey: hexKey);
      db.select('SELECT count(*) FROM sqlite_master;');
      return true;
    } finally {
      db.close();
    }
  } catch (_) {
    return false;
  }
}

int _readEncryptedUserVersion(String path, String hexKey) {
  final db = raw.sqlite3.open(path);
  try {
    configurePrismSqliteConnection(db, hexKey: hexKey);
    final rows = db.select('PRAGMA user_version;');
    if (rows.isEmpty) return 0;
    final value = rows.first['user_version'];
    return value is int ? value : int.parse(value.toString());
  } finally {
    db.close();
  }
}

Future<int> _readDriftUserVersion(AppDatabase db) async {
  final row = await db.customSelect('PRAGMA user_version;').getSingle();
  final value = row.data['user_version'];
  return value is int ? value : int.parse(value.toString());
}

/// Promote the staging key to the primary slot if — and only if — the DB
/// actually opens with that key.
///
/// Two crash scenarios:
/// 1. Crash AFTER PRAGMA rekey, BEFORE primary-slot write → staging key opens
///    the DB. Safe to promote.
/// 2. Crash BEFORE PRAGMA rekey (during or after staging-slot write) → staging
///    key does NOT open the DB (old key still applies). Discard staging slot;
///    startup proceeds with the existing primary key.
Future<void> _recoverFromStagingKey(String stagingHexKey, String dbPath) async {
  if (!File(dbPath).existsSync()) {
    // No DB file yet — staging slot is stale. Clean it up.
    await discardStagingDatabaseKey();
    return;
  }

  if (_tryOpenEncrypted(dbPath, stagingHexKey)) {
    // PRAGMA rekey completed. Staging key is the real key — promote it.
    debugPrint(
      '[DB_PROVIDER] Crash-recovery: staging key verified — promoting to primary slot',
    );
    await promoteStagingDatabaseKey(stagingHexKey);
  } else {
    // PRAGMA rekey did not complete. DB still has the old key.
    // Discard the staging slot; startup will use the existing primary key.
    await discardStagingDatabaseKey();
  }
}
