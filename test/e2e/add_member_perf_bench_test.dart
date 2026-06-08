// Benchmark: where does the awaited cost of "adding a member" go on the FFI
// sync-emit path? Drives the REAL compiled prism-sync FFI against a single
// configured device (in-memory db, throwaway relay) — no app, no UI, no
// personal data. Measures the two awaited suspects the static analysis flagged:
//
//   #2  avatar partition: recordCreate cost as a function of inline-avatar size
//       and field count (the O(F x avatar_bytes) re-serialization claim in
//       Client::partition_fields_into_batches).
//   #1  custom-field N+1: a serial loop of one recordCreate per field value,
//       to read the per-op FFI round-trip latency the commit() loop multiplies.
//
// Prereqs (from the prism-sync worktree):
//   cargo build --release -p prism_sync_ffi
//   cargo build --release -p prism-sync-relay --example test_relay
//
// Run: flutter test test/e2e/add_member_perf_bench_test.dart

import 'dart:convert';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_sync/generated/frb_generated.dart';

import 'e2e_fixture.dart';
import 'e2e_support.dart';

/// A base64 avatar of [rawBytes] raw bytes (so the on-wire string is ~1.33x).
String _avatarB64(int rawBytes) {
  final bytes = Uint8List(rawBytes);
  for (var i = 0; i < rawBytes; i++) {
    bytes[i] = i & 0xFF;
  }
  return base64Encode(bytes);
}

/// The real member field shape (mirrors DriftMemberRepository.memberFields):
/// ~36 fields, with the avatar carried inline as base64. [avatarRaw] = 0 means
/// no avatar. [fieldCount] lets us shrink the map to isolate the "x F" factor.
Map<String, dynamic> _memberFields({
  required int avatarRaw,
  int? fieldCount,
}) {
  final full = <String, dynamic>{
    'name': 'Bench Member',
    'pronouns': 'they/them',
    'emoji': '\u{1F60A}',
    'age': '24',
    'bio': 'A reasonably sized bio paragraph for the benchmark member row.',
    'avatar_image_data': avatarRaw > 0 ? _avatarB64(avatarRaw) : null,
    'pk_avatar_cached_url': null,
    'is_active': true,
    'created_at': '2024-01-01T00:00:00.000Z',
    'display_order': 0,
    'is_admin': false,
    'custom_color_enabled': true,
    'custom_color_hex': 'FF6B6B',
    'parent_system_id': null,
    'pluralkit_uuid': null,
    'pluralkit_id': null,
    'pluralkit_display_name': null,
    'markdown_enabled': true,
    'display_name': 'Bench Member / Host',
    'birthday': '1999-04-12',
    'proxy_tags_json': '[{"prefix":"[B]","suffix":null}]',
    'pk_banner_url': null,
    'profile_header_source': 0,
    'profile_header_layout': 0,
    'profile_header_visible': true,
    'name_style_font': 0,
    'name_style_bold': false,
    'name_style_italic': false,
    'name_style_color_mode': 0,
    'name_style_color_hex': null,
    'profile_header_image_data': null,
    'pk_banner_image_data': null,
    'pk_banner_cached_url': null,
    'pluralkit_sync_ignored': false,
    'is_always_fronting': false,
    'is_deleted': false,
  };
  if (fieldCount == null) return full;
  // Keep the avatar field plus the first (fieldCount-1) others.
  final out = <String, dynamic>{
    'avatar_image_data': full['avatar_image_data'],
  };
  for (final e in full.entries) {
    if (out.length >= fieldCount) break;
    out[e.key] = e.value;
  }
  return out;
}

/// Median + p90 of a list of microsecond timings.
({int medianUs, int p90Us, int maxUs}) _stats(List<int> us) {
  final sorted = [...us]..sort();
  int at(double q) => sorted[(q * (sorted.length - 1)).round()];
  return (medianUs: at(0.5), p90Us: at(0.9), maxUs: sorted.last);
}

/// Time one recordCreate, return elapsed microseconds. Distinct [id] each call.
Future<int> _timeCreate(
  E2EDevice d,
  String id,
  Map<String, dynamic> fields,
) async {
  final json = jsonEncode(fields);
  final sw = Stopwatch()..start();
  await ffi.recordCreate(
    handle: d.handle,
    table: 'members',
    entityId: id,
    fieldsJson: json,
  );
  sw.stop();
  return sw.elapsedMicroseconds;
}

void main() {
  setUpAll(() async {
    if (e2eSkip() != null) return;
    await RustLib.init(externalLibrary: ExternalLibrary.open(resolveFfiLib()));
  });
  tearDownAll(() {
    if (e2eSkip() != null) return;
    RustLib.dispose();
  });

  test('add-member FFI emit cost breakdown', skip: e2eSkip(), () async {
    final relay = await spawnRelay();
    E2EDevice? a;
    try {
      a = await createDevice(relay);

      // Warm up (first FFI call pays lazy-init / codec warm costs).
      for (var i = 0; i < 5; i++) {
        await _timeCreate(a, 'warm-$i', _memberFields(avatarRaw: 0));
      }

      const reps = 20;

      // ── #2: avatar size sweep, FULL ~36-field member op ──────────────
      final avatarSweep = <int, ({int medianUs, int p90Us, int maxUs})>{};
      for (final raw in [0, 64 * 1024, 256 * 1024, 512 * 1024, 1024 * 1024]) {
        final times = <int>[];
        for (var i = 0; i < reps; i++) {
          times.add(
            await _timeCreate(a, 'av-$raw-$i', _memberFields(avatarRaw: raw)),
          );
        }
        avatarSweep[raw] = _stats(times);
      }

      // ── #2b: does field COUNT amplify the avatar cost? 512KB avatar,
      //         minimal (2-field) op vs full (~36-field) op. ────────────
      final minTimes = <int>[];
      final fullTimes = <int>[];
      for (var i = 0; i < reps; i++) {
        minTimes.add(
          await _timeCreate(
            a,
            'min-$i',
            _memberFields(avatarRaw: 512 * 1024, fieldCount: 2),
          ),
        );
        fullTimes.add(
          await _timeCreate(
            a,
            'fullbig-$i',
            _memberFields(avatarRaw: 512 * 1024),
          ),
        );
      }
      final minStats = _stats(minTimes);
      final fullStats = _stats(fullTimes);

      // ── #1: serial per-field N+1. The commit() loop does one recordCreate
      //        per custom-field VALUE. Model those as small single-field rows
      //        on a custom_field_values-shaped op and time the serial loop. ─
      final perFieldTimes = <int>[];
      const fieldCounts = [5, 10, 20, 40];
      final serialTotals = <int, int>{};
      for (final n in fieldCounts) {
        final loopSw = Stopwatch()..start();
        for (var f = 0; f < n; f++) {
          final sw = Stopwatch()..start();
          await ffi.recordCreate(
            handle: a.handle,
            table: 'custom_field_values',
            entityId: 'cfv-$n-$f',
            fieldsJson: jsonEncode({
              'custom_field_id': 'field-$f',
              'member_id': 'av-0-0',
              'value': 'A representative custom field value $f',
            }),
          );
          sw.stop();
          perFieldTimes.add(sw.elapsedMicroseconds);
        }
        loopSw.stop();
        serialTotals[n] = loopSw.elapsedMilliseconds;
      }
      final perFieldStats = _stats(perFieldTimes);

      // ── Report ───────────────────────────────────────────────────────
      String ms(int us) => (us / 1000).toStringAsFixed(2);
      final b = StringBuffer()
        ..writeln('\n================ ADD-MEMBER FFI EMIT BENCH ================')
        ..writeln('(median / p90 / max per recordCreate, $reps reps each)\n')
        ..writeln('#2  AVATAR SIZE SWEEP — full ~36-field member op:');
      for (final e in avatarSweep.entries) {
        final kb = e.key ~/ 1024;
        b.writeln(
          '    avatar=${kb.toString().padLeft(4)}KB  '
          'median=${ms(e.value.medianUs).padLeft(7)}ms  '
          'p90=${ms(e.value.p90Us).padLeft(7)}ms  '
          'max=${ms(e.value.maxUs).padLeft(7)}ms',
        );
      }
      b
        ..writeln('')
        ..writeln('#2b FIELD-COUNT AMPLIFICATION @ 512KB avatar:')
        ..writeln(
          '    2-field op : median=${ms(minStats.medianUs)}ms  p90=${ms(minStats.p90Us)}ms',
        )
        ..writeln(
          '    36-field op: median=${ms(fullStats.medianUs)}ms  p90=${ms(fullStats.p90Us)}ms',
        )
        ..writeln(
          '    => amplification x${(fullStats.medianUs / minStats.medianUs).toStringAsFixed(2)} '
          '(if >>1, the avatar bucket is re-serialized per field)',
        )
        ..writeln('')
        ..writeln('#1  SERIAL PER-FIELD N+1 (one recordCreate per cf value):')
        ..writeln(
          '    per-op: median=${ms(perFieldStats.medianUs)}ms  p90=${ms(perFieldStats.p90Us)}ms',
        );
      for (final e in serialTotals.entries) {
        b.writeln(
          '    ${e.key.toString().padLeft(2)} fields serial total = ${e.value}ms',
        );
      }
      b.writeln('==========================================================\n');
      // ignore: avoid_print
      print(b.toString());
    } finally {
      a?.dispose();
    }
  });
}
