import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart' as database;
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_event_loop.dart';

/// Repro probe for TestFlight 0.8.4 pairing failure:
///   "Failed to apply your system to this device (system_settings)."
///
/// The user-visible message is built from `StrictApplyFailure.table`, so we
/// know the throw originated inside `_systemSettingsEntity.applyFields` —
/// almost certainly from the Drift INSERT/UPDATE itself.
///
/// This test calls `applyRemoteChanges(strict: true)` on a fresh DB with
/// crafted change payloads representing the on-wire shape the joiner sees
/// during snapshot bootstrap. Any of these passing without throwing rules
/// out that hypothesis. The first one that throws is the repro.

SyncEvent _eventFromChanges(List<Map<String, dynamic>> changes) {
  return SyncEvent.fromJson({'type': 'RemoteChanges', 'changes': changes});
}

Map<String, dynamic> _systemSettingsChange(Map<String, dynamic> fields) {
  return {
    'table': 'system_settings',
    'entity_id': 'singleton',
    'is_delete': false,
    'fields': fields,
  };
}

/// Vanilla payload — what a typical primary device on 0.8.4 would emit
/// from `_systemSettingsEntity.toSyncFields`. Mirrors the table defaults
/// for fields the user never touched.
Map<String, dynamic> _vanillaFields({
  String? avatarBase64,
  Object? wakeSuggestionAfterHours = 8.0,
  String? navBarItems = '',
  String? chatBadgePreferences = '{}',
}) {
  return <String, dynamic>{
    'system_name': 'Repro System',
    'sharing_id': null,
    'show_quick_front': true,
    'accent_color_hex': '#9070A0',
    'per_member_accent_colors': false,
    'terminology': 0,
    'custom_terminology': null,
    'custom_plural_terminology': null,
    'terminology_use_english': false,
    'fronting_reminders_enabled': false,
    'fronting_reminder_interval_minutes': 60,
    'theme_mode': 0,
    'theme_brightness': 0,
    'theme_style': 0,
    'theme_corner_style': 0,
    'chat_enabled': true,
    'polls_enabled': true,
    'habits_enabled': true,
    'sleep_tracking_enabled': true,
    'gif_search_enabled': true,
    'voice_notes_enabled': true,
    'sleep_suggestion_enabled': false,
    'sleep_suggestion_hour': 22,
    'sleep_suggestion_minute': 0,
    'wake_suggestion_enabled': false,
    'wake_suggestion_after_hours': wakeSuggestionAfterHours,
    'locale_override': null,
    'quick_switch_threshold_seconds': 30,
    'identity_generation': 0,
    'chat_logs_front': false,
    'sync_theme_enabled': false,
    'timing_mode': 0,
    'notes_enabled': true,
    'pk_group_sync_v2_enabled': false,
    'system_description': null,
    'system_color': null,
    'system_tag': null,
    'system_avatar_data': avatarBase64,
    'reminders_enabled': true,
    'sync_navigation_enabled': true,
    'nav_bar_items': navBarItems,
    'nav_bar_overflow_items': '',
    'chat_badge_preferences': chatBadgePreferences,
    'habits_badge_enabled': true,
    'fronting_list_view_mode': 0,
    'add_front_default_behavior': 0,
    'quick_front_default_behavior': 0,
    'auto_promote_long_fronting_sessions': true,
    'is_deleted': false,
    'boards_enabled': false,
    'sp_boards_backfilled_at': null,
  };
}

Future<void> _runStrictApply(
  database.AppDatabase db,
  Map<String, dynamic> fields,
) async {
  final wrapped = buildSyncAdapterWithCompletion(db);
  final event = _eventFromChanges([_systemSettingsChange(fields)]);
  await applyRemoteChanges(db, wrapped.adapter, event, strict: true);
}

void main() {
  late database.AppDatabase db;

  setUp(() {
    db = database.AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('system_settings strict apply — repro probes', () {
    test('B0 baseline: vanilla v19 payload applies cleanly', () async {
      await _runStrictApply(db, _vanillaFields());
      // If this throws, the throw is NOT due to a specific field value —
      // there's something structural we're missing.
    });

    test(
      'B1: realistic ~512×512 JPG avatar (~50KB base64 ≈ 67KB) round-trips',
      () async {
        // Synthetic JPG-like bytes; size matches what the real avatar
        // pipeline produces (avatar_normalizer maxDimension=512, q=85).
        final payload = Uint8List.fromList(
          List<int>.generate(50 * 1024, (i) => (i * 31) & 0xff),
        );
        await _runStrictApply(
          db,
          _vanillaFields(avatarBase64: base64Encode(payload)),
        );
      },
    );

    test(
      'B2: avatar at the high end (~800KB blob, ~1.07MB base64) round-trips',
      () async {
        final payload = Uint8List.fromList(
          List<int>.generate(800 * 1024, (i) => (i * 17) & 0xff),
        );
        await _runStrictApply(
          db,
          _vanillaFields(avatarBase64: base64Encode(payload)),
        );
      },
    );

    test('B3: NaN wake_suggestion_after_hours is sanitized away', () async {
      await _runStrictApply(
        db,
        _vanillaFields(wakeSuggestionAfterHours: double.nan),
      );
    });

    test('B4: Infinity wake_suggestion_after_hours is sanitized away', () async {
      await _runStrictApply(
        db,
        _vanillaFields(wakeSuggestionAfterHours: double.infinity),
      );
    });

    test('B5: missing wake_suggestion_after_hours (older peer)', () async {
      final fields = _vanillaFields();
      fields.remove('wake_suggestion_after_hours');
      await _runStrictApply(db, fields);
    });

    test('B6: integer 1 in place of bool field (older peer encoding)',
        () async {
      final fields = _vanillaFields();
      fields['show_quick_front'] = 1;
      fields['chat_enabled'] = 1;
      await _runStrictApply(db, fields);
    });

    test('B7: null in non-nullable string fields (accent_color_hex)',
        () async {
      final fields = _vanillaFields();
      fields['accent_color_hex'] = null;
      fields['nav_bar_items'] = null;
      fields['nav_bar_overflow_items'] = null;
      fields['chat_badge_preferences'] = null;
      await _runStrictApply(db, fields);
    });

    test('B8: empty fields map (Drift update with no columns set)',
        () async {
      // Force the UPDATE path: pre-create the singleton row, then send a
      // change with no fields — Drift's update.write() returns 0 rows on
      // an empty companion, but the validateIntegrity step is still
      // exercised.
      await db
          .into(db.systemSettingsTable)
          .insertOnConflictUpdate(
            const database.SystemSettingsTableCompanion(
              id: Value('singleton'),
            ),
          );
      await _runStrictApply(db, <String, dynamic>{});
    });

    test('B9: emoji + 4-byte unicode in custom_terminology', () async {
      final fields = _vanillaFields();
      fields['custom_terminology'] = '🧠 friend';
      fields['custom_plural_terminology'] = '🧠 friends';
      fields['system_name'] = '🌈 Repro';
      await _runStrictApply(db, fields);
    });

    test('B10: very long nav_bar_items string (64KB)', () async {
      final fields = _vanillaFields(navBarItems: 'x' * (64 * 1024));
      await _runStrictApply(db, fields);
    });

    test(
      'B11: malformed base64 in system_avatar_data is sanitized away',
      () async {
        final fields = _vanillaFields(avatarBase64: 'not!valid!base64!!!');
        await _runStrictApply(db, fields);
      },
    );

    test('B12: ALL fields applied — kitchen sink stress', () async {
      // Make every value present and stress the Drift companion path.
      final payload = Uint8List.fromList(
        List<int>.generate(200 * 1024, (i) => (i * 7) & 0xff),
      );
      final fields = _vanillaFields(avatarBase64: base64Encode(payload));
      fields['system_name'] = 'Repro 🌈';
      fields['sharing_id'] = 'share-' * 20;
      fields['locale_override'] = 'en_US';
      fields['custom_terminology'] = '🧠';
      fields['custom_plural_terminology'] = '🧠s';
      fields['system_description'] = 'desc';
      fields['system_color'] = '#abcdef';
      fields['system_tag'] = '|tag|';
      fields['sp_boards_backfilled_at'] =
          DateTime.utc(2026, 5, 1).toIso8601String();
      await _runStrictApply(db, fields);
    });

    test(
      'B13: payload from a newer peer with bio_markdown_enabled field',
      () async {
        final fields = _vanillaFields();
        fields['bio_markdown_enabled'] = true;
        fields['direction_confirmed'] = true;
        await _runStrictApply(db, fields);
      },
    );

    test('B14: confirm double.tryParse("NaN") yields NaN', () {
      final parsed = double.tryParse('NaN');
      expect(parsed, isNotNull);
      expect(parsed!.isNaN, isTrue);
    });

    test('B15: wire delivers the literal string "NaN"', () async {
      // If any layer round-tripped through a permissive serializer, NaN
      // can land on the wire as the bare string "NaN".  _asDouble parses
      // it with double.tryParse and forwards NaN — same explosion as B3.
      final fields = _vanillaFields(wakeSuggestionAfterHours: 'NaN');
      await _runStrictApply(db, fields);
    });

    test(
      'B16: wire delivers JSON null (the Rust encode_value path for NaN)',
      () async {
        final fields = _vanillaFields(wakeSuggestionAfterHours: null);
        await _runStrictApply(db, fields);
      },
    );

    // ---- Sibling-bug probes (same coercion class, different fields) ----

    test('B17: NaN double in place of an Int field crashes _asInt', () async {
      // _asInt does `value.toInt()` on a double — NaN.toInt() throws
      // UnsupportedError in Dart. Any synced Int field that lands as a
      // NaN/Infinity double on the wire would explode strict apply with
      // the same vague "(system_settings)" / "(members)" / etc. error.
      final fields = _vanillaFields();
      fields['terminology'] = double.nan;
      await _runStrictApply(db, fields);
    });

    test(
      'B18: string "NaN" in place of an Int field passes through tryParse',
      () async {
        // int.tryParse("NaN") returns null — safe. Sanity check.
        final fields = _vanillaFields();
        fields['terminology'] = 'NaN';
        await _runStrictApply(db, fields);
      },
    );

    test(
      'B19: Infinity double in place of an Int field crashes _asInt',
      () async {
        final fields = _vanillaFields();
        fields['fronting_reminder_interval_minutes'] = double.infinity;
        await _runStrictApply(db, fields);
      },
    );
  });
}
