// Phase 0 parity harness for the SP-import perf work
// (`docs/plans/sp-import-perf-quick-wins.md`).
//
// The harness exists to prove that every later phase produces byte-identical
// observable output to the pre-fix baseline. It is intentionally
// production-shape: real Drift `AppDatabase`, real `DriftXxxRepository`
// instances, real `SpImporter` — no fakes for anything that participates in
// the parity contract.
//
// Five collaborators recorded by this file:
//   * `RecordingSyncHandle` (token + sink semantics — see below): captures
//     every `(table, entityId, opType, fieldsJsonNormalized)` that the
//     `SyncRecordMixin` would have emitted to the FFI.
//   * `RecordingProgressSink`: captures every `(label, current, total)`
//     `onProgress` invocation.
//   * `RecordingErrorReporter`: subscribes to
//     `ErrorReportingService.instance` and captures every `report(...)`.
//   * `snapshotDb`: dumps every SP-relevant Drift table to canonical JSON.
//   * Stream-notification counter: subscribes to `db.tableUpdates()` and
//     counts updates per table.
//
// Implementation note on the "sync handle": the prism_sync FFI handle is an
// opaque Rust type, and the three operations (`recordCreate`, `recordUpdate`,
// `recordDelete`) are *top-level* functions taking the handle as a parameter.
// We therefore cannot subclass `PrismSyncHandle` or replace the FFI calls
// with a polymorphic implementation. The harness instead installs a
// process-wide `@visibleForTesting` capture sink on `SyncRecordMixin`. Every
// repository in the system shares that mixin, so the sink sees the exact
// tuples the FFI would receive. Production wiring never sets the sink.
import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';

/// A recorded sync emission, in a shape that can be compared byte-equal
/// across runs.
///
/// `fields` is the JSON-normalized (`re-parse, re-emit with sorted keys`)
/// representation of the FFI payload. Comparing the normalized form means
/// `{a:1,b:2}` and `{b:2,a:1}` collapse to the same tuple — the FFI doesn't
/// care about key order on the wire, and neither should the parity test.
@immutable
class RecordedEmission {
  const RecordedEmission({
    required this.table,
    required this.entityId,
    required this.opType,
    required this.fieldsJsonNormalized,
  });

  final String table;
  final String entityId;
  final SyncRecordOpType opType;

  /// Normalized JSON: keys sorted ascending at every nesting level.
  final String fieldsJsonNormalized;

  Map<String, dynamic> toJson() => {
    'table': table,
    'entity_id': entityId,
    'op_type': opType.name,
    'fields': fieldsJsonNormalized,
  };

  factory RecordedEmission.fromCapturedOp(CapturedSyncOp op) {
    return RecordedEmission(
      table: op.table,
      entityId: op.entityId,
      opType: op.opType,
      fieldsJsonNormalized: _canonicalJson(op.fields),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecordedEmission &&
          other.table == table &&
          other.entityId == entityId &&
          other.opType == opType &&
          other.fieldsJsonNormalized == fieldsJsonNormalized);

  @override
  int get hashCode =>
      Object.hash(table, entityId, opType, fieldsJsonNormalized);

  @override
  String toString() =>
      'RecordedEmission(table=$table, entityId=$entityId, op=${opType.name}, '
      'fields=$fieldsJsonNormalized)';
}

/// "Recording sync handle" — by API a sink installer, not an FFI handle.
///
/// The name matches the plan's vocabulary. Concretely it owns the sink that
/// `SyncRecordMixin` invokes in tests, and the underlying [recordings] list.
///
/// Lifetime: created per fixture run; [install] inside the run, [remove]
/// on tear-down. Tests assert clean install/remove via
/// `SyncRecordMixin.hasCaptureSink`.
class RecordingSyncHandle {
  RecordingSyncHandle();

  final List<RecordedEmission> recordings = [];

  SyncRecordCaptureSink? _previous;
  bool _installed = false;

  void install() {
    if (_installed) {
      throw StateError('RecordingSyncHandle already installed');
    }
    _previous = SyncRecordMixin.installCaptureSinkForTesting((op) {
      recordings.add(RecordedEmission.fromCapturedOp(op));
    });
    _installed = true;
  }

  void remove() {
    if (!_installed) return;
    SyncRecordMixin.removeCaptureSinkForTesting(_previous);
    _previous = null;
    _installed = false;
  }
}

/// Captures every `onProgress(current, total, label)` invocation.
///
/// The recorded sequence is sequence-equal compared (not multiset) — the
/// plan explicitly calls out that batching can silently collapse progress
/// reporting, and sequence equality catches that.
class RecordingProgressSink {
  final List<ProgressEvent> events = [];

  void onProgress(int current, int total, String label) {
    events.add(ProgressEvent(current: current, total: total, label: label));
  }
}

@immutable
class ProgressEvent {
  const ProgressEvent({
    required this.current,
    required this.total,
    required this.label,
  });

  final int current;
  final int total;
  final String label;

  Map<String, dynamic> toJson() => {
    'current': current,
    'total': total,
    'label': label,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProgressEvent &&
          other.current == current &&
          other.total == total &&
          other.label == label);

  @override
  int get hashCode => Object.hash(current, total, label);

  @override
  String toString() => 'Progress($current/$total, $label)';
}

/// Captures every `ErrorReportingService.report(...)` invocation in scope.
///
/// `ErrorReportingService.instance` exposes `addListener` natively (the
/// service was already test-friendly), so we don't need an injectable
/// interface. The harness uses listener registration scoped to the
/// install/remove lifetime so unrelated test reports aren't pulled in.
class RecordingErrorReporter {
  final List<RecordedError> errors = [];

  ErrorListener? _listener;
  bool _installed = false;

  void install() {
    if (_installed) {
      throw StateError('RecordingErrorReporter already installed');
    }
    void listener(AppError e) {
      errors.add(RecordedError(message: e.message, severity: e.severity));
    }

    _listener = listener;
    ErrorReportingService.instance.addListener(listener);
    _installed = true;
  }

  void remove() {
    if (!_installed) return;
    final l = _listener;
    if (l != null) {
      ErrorReportingService.instance.removeListener(l);
    }
    _listener = null;
    _installed = false;
  }
}

@immutable
class RecordedError {
  const RecordedError({required this.message, required this.severity});
  final String message;
  final ErrorSeverity severity;

  Map<String, dynamic> toJson() => {
    'message': message,
    'severity': severity.name,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecordedError &&
          other.message == message &&
          other.severity == severity);

  @override
  int get hashCode => Object.hash(message, severity);
}

/// Counts `tableUpdates` notifications emitted per table during a run.
///
/// Plan assertion 6: batching may collapse per-row notifications into one
/// per-table notification, but going *below* baseline-floor is a regression
/// — any UI watching mid-import would silently stop ticking.
class StreamUpdateCounter {
  final Map<String, int> _counts = <String, int>{};
  StreamSubscription<Set<TableUpdate>>? _sub;

  Map<String, int> get totalByTable => Map.unmodifiable(_counts);

  void start(AppDatabase db) {
    _sub = db.tableUpdates().listen((updates) {
      for (final u in updates) {
        _counts.update(u.table, (v) => v + 1, ifAbsent: () => 1);
      }
    });
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }
}

/// Build an in-memory `AppDatabase` suitable for parity tests.
///
/// Caller is responsible for closing it via `addTearDown(db.close)`.
AppDatabase makeParityDb() => AppDatabase(NativeDatabase.memory());

/// Dump every SP-relevant Drift table to canonical JSON.
///
/// The shape:
///
/// ```json
/// {
///   "tables": {
///     "members":  [ {<row-sorted-by-pk> ...}, ... ],
///     "polls":    [ ... ],
///     ...
///   }
/// }
/// ```
///
/// Canonicalization rules (so a textual diff is meaningful across runs):
///   * Rows are sorted by primary key (column `id`, or `(group_id, member_id)`
///     for `member_group_entries`, or `id='singleton'` for system settings).
///   * Within each row, columns are emitted in ascending alphabetical order.
///   * Blobs (`Uint8List`) → base64 string.
///   * DateTimes → UTC ISO-8601 with explicit `Z` suffix.
///   * Strings, ints, doubles, bools, nulls pass through as JSON literals.
Future<String> snapshotDb(AppDatabase db) async {
  // Tables relevant to SP import. Ordered so the output is easy to scan.
  const tableNames = <String>[
    'members',
    'fronting_sessions',
    'conversations',
    'conversation_categories',
    'chat_messages',
    'polls',
    'poll_options',
    'poll_votes',
    'notes',
    'front_session_comments',
    'custom_fields',
    'custom_field_values',
    'member_groups',
    'member_group_entries',
    'reminders',
    'member_board_posts',
    'system_settings',
    'sp_id_map',
    'sp_sync_state',
  ];

  final dump = <String, List<Map<String, Object?>>>{};
  for (final t in tableNames) {
    final rows = await db.customSelect('SELECT * FROM $t').get();
    final normalized = rows.map((r) => _canonicalizeRow(r.data)).toList()
      ..sort(_rowComparator);
    dump[t] = normalized;
  }

  return _canonicalJson({'tables': dump});
}

Map<String, Object?> _canonicalizeRow(Map<String, Object?> data) {
  final sortedKeys = data.keys.toList()..sort();
  final out = <String, Object?>{};
  for (final k in sortedKeys) {
    out[k] = _canonicalizeValue(data[k]);
  }
  return out;
}

Object? _canonicalizeValue(Object? v) {
  if (v == null) return null;
  if (v is Uint8List) return base64Encode(v);
  if (v is List<int>) return base64Encode(Uint8List.fromList(v));
  if (v is DateTime) return v.toUtc().toIso8601String();
  if (v is num || v is bool || v is String) return v;
  // Fallback: stringify exotic types so the snapshot doesn't silently change
  // shape when Drift evolves a column type.
  return v.toString();
}

int _rowComparator(Map<String, Object?> a, Map<String, Object?> b) {
  // Primary key candidates in priority order.
  for (final key in const ['id', 'group_id', 'member_id', 'sp_id']) {
    if (a.containsKey(key) && b.containsKey(key)) {
      final av = a[key]?.toString() ?? '';
      final bv = b[key]?.toString() ?? '';
      final cmp = av.compareTo(bv);
      if (cmp != 0) return cmp;
    }
  }
  // Fallback: stringified row.
  return jsonEncode(a).compareTo(jsonEncode(b));
}

/// Canonical JSON encoder: keys are sorted at every nesting level so a
/// textual diff is meaningful.
String _canonicalJson(Object? value) {
  final sb = StringBuffer();
  _writeCanonicalJson(value, sb);
  return sb.toString();
}

void _writeCanonicalJson(Object? value, StringBuffer sb) {
  if (value == null) {
    sb.write('null');
    return;
  }
  if (value is String) {
    sb.write(jsonEncode(value));
    return;
  }
  if (value is num || value is bool) {
    sb.write(jsonEncode(value));
    return;
  }
  if (value is List) {
    sb.write('[');
    for (var i = 0; i < value.length; i++) {
      if (i > 0) sb.write(',');
      _writeCanonicalJson(value[i], sb);
    }
    sb.write(']');
    return;
  }
  if (value is Map) {
    final entries = value.entries.toList()
      ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
    sb.write('{');
    var first = true;
    for (final entry in entries) {
      if (!first) sb.write(',');
      first = false;
      sb.write(jsonEncode(entry.key.toString()));
      sb.write(':');
      _writeCanonicalJson(entry.value, sb);
    }
    sb.write('}');
    return;
  }
  sb.write(jsonEncode(value.toString()));
}

/// Public re-export of [_canonicalJson] for tests that need to normalize
/// non-snapshot maps (e.g. checking a single field shape).
@visibleForTesting
String canonicalJsonForTest(Object? value) => _canonicalJson(value);

/// Seeded UUID generator used by the parity harness's `SpMapper`
/// determinism seam.
///
/// The harness needs a deterministic v4 stream so golden files are stable
/// across runs. The package's `Uuid` accepts a custom `CryptoRNG` but
/// pulling in the full RNG infrastructure for tests is overkill. We instead
/// hand-roll a 122-bit-random / RFC 4122 v4 from a `Random(seed)`.
class SeededUuidGenerator {
  SeededUuidGenerator(int seed) : _rng = _SeededRandom(seed);
  final _SeededRandom _rng;

  String next() {
    final bytes = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      bytes[i] = _rng.nextByte();
    }
    // RFC 4122 §4.4: set the four most significant bits of the
    // time_hi_and_version field to the 4-bit version number (0100).
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    // Set the two most significant bits of the clock_seq_hi_and_reserved
    // field to zero and one, respectively.
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }
}

/// Deterministic per-byte RNG (xorshift32). `dart:math.Random(seed)` is
/// platform-determinism-defined-by-implementation; xorshift32 is identical
/// across SDKs.
class _SeededRandom {
  _SeededRandom(int seed) : _state = seed == 0 ? 1 : (seed & 0xffffffff);
  int _state;
  int nextByte() {
    var x = _state;
    x ^= (x << 13) & 0xffffffff;
    x ^= (x >> 17) & 0xffffffff;
    x ^= (x << 5) & 0xffffffff;
    _state = x & 0xffffffff;
    return _state & 0xff;
  }
}

/// Fixed clock for tests. Returns the same instant each call so any
/// `_now()` site that bakes a timestamp into a row produces a stable value.
class FixedClock {
  FixedClock(this._instant);
  final DateTime _instant;
  DateTime now() => _instant;
}
