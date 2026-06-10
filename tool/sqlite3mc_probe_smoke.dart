// Standalone FFI smoke test against the REAL bundled libsqlite3mc.dylib.
//
// Verifies, empirically, which probe distinguishes the live cipher codec:
//   - `PRAGMA cipher_version;`      (the OLD, broken probe — empty on the codec)
//   - `SELECT sqlite3mc_version();` (the FIX — non-empty on the codec)
//
// This exists because `flutter test` loads a STOCK sqlite3 (no codec) and CANNOT
// validate the happy path against the bundled native asset. This script loads
// the actual bundled dylib via dart:ffi and runs the exact probe SQL the
// production assertion uses, so the happy path is verified against the real
// binary the app ships.
//
// Uses ONLY dart:ffi (no package:ffi) — native memory is allocated through the
// loaded sqlite3 library's own sqlite3_malloc/sqlite3_free so there are no extra
// package deps.
//
//   dart run tool/sqlite3mc_probe_smoke.dart <path-to-dylib> [expect=absent]
//
// Default expectation is the codec is PRESENT (the bundled dylib). Pass
// `expect=absent` when pointing at a stock sqlite3 to assert the assertion
// fail-closes.
import 'dart:ffi';
import 'dart:io';

typedef _OpenNative = Int32 Function(Pointer<Uint8>, Pointer<Pointer<Void>>);
typedef _OpenDart = int Function(Pointer<Uint8>, Pointer<Pointer<Void>>);

typedef _PrepareNative =
    Int32 Function(
      Pointer<Void>,
      Pointer<Uint8>,
      Int32,
      Pointer<Pointer<Void>>,
      Pointer<Pointer<Uint8>>,
    );
typedef _PrepareDart =
    int Function(
      Pointer<Void>,
      Pointer<Uint8>,
      int,
      Pointer<Pointer<Void>>,
      Pointer<Pointer<Uint8>>,
    );

typedef _StepNative = Int32 Function(Pointer<Void>);
typedef _StepDart = int Function(Pointer<Void>);

typedef _ColumnTextNative = Pointer<Uint8> Function(Pointer<Void>, Int32);
typedef _ColumnTextDart = Pointer<Uint8> Function(Pointer<Void>, int);

typedef _FinalizeNative = Int32 Function(Pointer<Void>);
typedef _FinalizeDart = int Function(Pointer<Void>);

typedef _ExecNative =
    Int32 Function(
      Pointer<Void>,
      Pointer<Uint8>,
      Pointer<Void>,
      Pointer<Void>,
      Pointer<Pointer<Uint8>>,
    );
typedef _ExecDart =
    int Function(
      Pointer<Void>,
      Pointer<Uint8>,
      Pointer<Void>,
      Pointer<Void>,
      Pointer<Pointer<Uint8>>,
    );

typedef _VersionNative = Pointer<Uint8> Function();
typedef _VersionDart = Pointer<Uint8> Function();

// sqlite3's own allocator (avoids needing package:ffi for native memory).
typedef _MallocNative = Pointer<Void> Function(Int32);
typedef _MallocDart = Pointer<Void> Function(int);
typedef _FreeNative = Void Function(Pointer<Void>);
typedef _FreeDart = void Function(Pointer<Void>);

const _sqliteRow = 100; // SQLITE_ROW
const _sqliteOk = 0; // SQLITE_OK

late _MallocDart _sqliteMalloc;
late _FreeDart _sqliteFree;

Pointer<Uint8> _toCString(String s) {
  final units = s.codeUnits;
  final ptr = _sqliteMalloc(units.length + 1).cast<Uint8>();
  for (var i = 0; i < units.length; i++) {
    ptr[i] = units[i];
  }
  ptr[units.length] = 0;
  return ptr;
}

String _fromCString(Pointer<Uint8> ptr) {
  if (ptr == nullptr) return '';
  final bytes = <int>[];
  var i = 0;
  while (ptr[i] != 0) {
    bytes.add(ptr[i]);
    i++;
  }
  return String.fromCharCodes(bytes);
}

void main(List<String> args) {
  final libPath = args.isNotEmpty
      ? args[0]
      : '.dart_tool/lib/libsqlite3mc.dylib';
  final lib = DynamicLibrary.open(libPath);
  stdout.writeln('Loaded: $libPath');

  _sqliteMalloc = lib.lookupFunction<_MallocNative, _MallocDart>(
    'sqlite3_malloc',
  );
  _sqliteFree = lib.lookupFunction<_FreeNative, _FreeDart>('sqlite3_free');

  final open = lib.lookupFunction<_OpenNative, _OpenDart>('sqlite3_open');
  final prepare = lib.lookupFunction<_PrepareNative, _PrepareDart>(
    'sqlite3_prepare_v2',
  );
  final step = lib.lookupFunction<_StepNative, _StepDart>('sqlite3_step');
  final columnText = lib.lookupFunction<_ColumnTextNative, _ColumnTextDart>(
    'sqlite3_column_text',
  );
  final finalize = lib.lookupFunction<_FinalizeNative, _FinalizeDart>(
    'sqlite3_finalize',
  );
  final exec = lib.lookupFunction<_ExecNative, _ExecDart>('sqlite3_exec');

  // sqlite3mc_version() C symbol — present only on the codec build.
  if (lib.providesSymbol('sqlite3mc_version')) {
    final mcVersion = lib.lookupFunction<_VersionNative, _VersionDart>(
      'sqlite3mc_version',
    );
    stdout.writeln(
      'sqlite3mc_version() C symbol => "${_fromCString(mcVersion())}"',
    );
  } else {
    stdout.writeln('sqlite3mc_version() C symbol => <ABSENT — stock sqlite3>');
  }

  // Open a fresh on-disk DB and run the production sequence: PRAGMA key.
  final dbDir = Directory.systemTemp.createTempSync('mc_probe_');
  final dbPath = '${dbDir.path}/probe.db';
  final dbOut = _sqliteMalloc(8).cast<Pointer<Void>>();
  final pathPtr = _toCString(dbPath);
  final rc = open(pathPtr, dbOut);
  if (rc != _sqliteOk) {
    stderr.writeln('sqlite3_open failed rc=$rc');
    exit(2);
  }
  final db = dbOut.value;
  _sqliteFree(pathPtr.cast());
  _sqliteFree(dbOut.cast());

  const hexKey =
      '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';
  _execStmt(exec, db, 'PRAGMA key = "x\'$hexKey\'";');
  _execStmt(exec, db, 'CREATE TABLE t(id INTEGER PRIMARY KEY);');

  // Mirror the production assertion's decision: a probe yields a usable version
  // string ONLY if prepare+step succeed AND return a non-empty row value.
  // Anything else (prepare error == unknown function/pragma, no row, null) is
  // "codec absent" — the same as `version == null` in
  // _assertSqliteCipherCodecPresent.
  String? probeOne(String sql) {
    final stmtOut = _sqliteMalloc(8).cast<Pointer<Void>>();
    final sqlPtr = _toCString(sql);
    final pr = prepare(db, sqlPtr, -1, stmtOut, nullptr);
    _sqliteFree(sqlPtr.cast());
    if (pr != _sqliteOk) {
      _sqliteFree(stmtOut.cast());
      return null; // prepare failed (e.g. unknown function/pragma) → null
    }
    final stmt = stmtOut.value;
    _sqliteFree(stmtOut.cast());
    String? out;
    if (step(stmt) == _sqliteRow) {
      final s = _fromCString(columnText(stmt, 0)).trim();
      out = s.isEmpty ? null : s;
    } else {
      out = null; // no row → empty result set
    }
    finalize(stmt);
    return out;
  }

  final cipherVersion = probeOne('PRAGMA cipher_version;');
  final mcVersionSql = probeOne('SELECT sqlite3mc_version();');

  stdout.writeln('--- after PRAGMA key (production sequence) ---');
  stdout.writeln(
    'PRAGMA cipher_version;     => '
    '${cipherVersion == null ? '<EMPTY/error>' : '"$cipherVersion"'}',
  );
  stdout.writeln(
    'SELECT sqlite3mc_version();=> '
    '${mcVersionSql == null ? '<EMPTY/error>' : '"$mcVersionSql"'}',
  );

  dbDir.deleteSync(recursive: true);

  // _assertSqliteCipherCodecPresent throws iff `SELECT sqlite3mc_version()` is
  // empty/null. So "would throw" == the probe is empty/null against this binary.
  final assertionWouldThrow = mcVersionSql == null || mcVersionSql.isEmpty;
  final expectPresent = !(args.length > 1 && args[1] == 'expect=absent');

  stdout.writeln('===VERDICT===');
  stdout.writeln(
    'cipher_version_nonempty=${cipherVersion != null && cipherVersion.isNotEmpty}',
  );
  stdout.writeln(
    'sqlite3mc_version_nonempty=${mcVersionSql != null && mcVersionSql.isNotEmpty}',
  );
  stdout.writeln('assertion_would_throw=$assertionWouldThrow');

  if (expectPresent) {
    if (assertionWouldThrow) {
      stderr.writeln(
        'FAIL: codec expected PRESENT but sqlite3mc_version() probe was empty → '
        'assertion WOULD throw (would brick the build).',
      );
      exit(1);
    }
    stdout.writeln(
      'PASS: codec present — _assertSqliteCipherCodecPresent would NOT throw '
      'against this binary.',
    );
  } else {
    if (!assertionWouldThrow) {
      stderr.writeln(
        'FAIL: codec expected ABSENT but sqlite3mc_version() probe returned a '
        'value → assertion would NOT fire (false negative).',
      );
      exit(1);
    }
    stdout.writeln(
      'PASS: codec absent — _assertSqliteCipherCodecPresent WOULD throw against '
      'this stock binary (fail-closed).',
    );
  }
}

void _execStmt(_ExecDart exec, Pointer<Void> db, String sql) {
  final sqlPtr = _toCString(sql);
  final rc = exec(db, sqlPtr, nullptr, nullptr, nullptr);
  _sqliteFree(sqlPtr.cast());
  if (rc != _sqliteOk) {
    stderr.writeln('exec "$sql" rc=$rc');
  }
}
