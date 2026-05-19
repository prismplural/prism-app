import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/services/keychain_degraded_state.dart';
import 'package:prism_plurality/core/services/secure_storage_diagnostic.dart';

void main() {
  group('SecureStorageDiagnostic JSON shape', () {
    test('serializes every field with snake_case keys', () {
      final captured = DateTime.utc(2026, 5, 19, 12, 30, 45);
      final degraded = KeychainDegradedState(
        appDbKey: SlotState.unreadable,
        syncKey: SlotState.degraded,
        syncCredentials: SlotState.ok,
        pin: SlotState.ok,
        firstObservedAt: captured,
      );
      final diag = SecureStorageDiagnostic(
        recoveredVia: 'sync',
        capturedAt: captured,
        slotOutcomes: <String, String>{
          DiagnosticSlotIds.appDbPrimary: 'cipher',
          DiagnosticSlotIds.appDbSync: 'ok',
          DiagnosticSlotIds.appDbSyncStaging: 'missing',
        },
        appDbState: DbStartupStateName.ready,
        syncDbState: DbStartupStateName.ready,
        keychainRepairPendingBeforeBoot: true,
        keychainRepairWritebackAttemptedThisBoot: true,
        keychainRepairWritebackResult: KeychainRepairWritebackResult.ok,
        keychainDegradedStateSnapshot: degraded,
        runtimeDekDeviceState: <String, dynamic>{
          'alias_present': true,
          'is_device_locked': false,
        },
        appBuild: const <String, String>{
          'flavor': 'production',
          'mode': 'release',
          'app_version': '0.9.2',
          'app_build_number': '12345',
          'platform_version': 'Test',
        },
      );

      final json = diag.toJson();

      expect(json['recovered_via'], 'sync');
      expect(json['slot_outcomes'], <String, String>{
        DiagnosticSlotIds.appDbPrimary: 'cipher',
        DiagnosticSlotIds.appDbSync: 'ok',
        DiagnosticSlotIds.appDbSyncStaging: 'missing',
      });
      expect(json['app_db_state'], 'ready');
      expect(json['sync_db_state'], 'ready');
      expect(json['keychain_repair_pending_before_boot'], true);
      expect(json['keychain_repair_writeback_attempted_this_boot'], true);
      expect(json['keychain_repair_writeback_result'], 'ok');
      expect(json['keychain_degraded_state_snapshot'], isA<Map<String, dynamic>>());
      expect(json['runtime_dek_device_state'], <String, dynamic>{
        'alias_present': true,
        'is_device_locked': false,
      });
      expect(json['app_build'], <String, String>{
        'flavor': 'production',
        'mode': 'release',
        'app_version': '0.9.2',
        'app_build_number': '12345',
        'platform_version': 'Test',
      });
      expect(json['captured_at'], '2026-05-19T12:30:45.000Z');
    });

    test('null optional fields serialize as explicit null', () {
      final diag = SecureStorageDiagnostic(
        recoveredVia: null,
        slotOutcomes: const <String, String>{},
      );

      final json = diag.toJson();
      expect(json.containsKey('recovered_via'), isTrue);
      expect(json['recovered_via'], isNull);
      expect(json.containsKey('app_db_state'), isTrue);
      expect(json['app_db_state'], isNull);
      expect(json.containsKey('sync_db_state'), isTrue);
      expect(json['sync_db_state'], isNull);
      expect(json.containsKey('keychain_repair_pending_before_boot'), isTrue);
      expect(json['keychain_repair_pending_before_boot'], isNull);
      expect(
        json.containsKey('keychain_repair_writeback_attempted_this_boot'),
        isTrue,
      );
      expect(json['keychain_repair_writeback_attempted_this_boot'], isNull);
      expect(json.containsKey('keychain_repair_writeback_result'), isTrue);
      expect(json['keychain_repair_writeback_result'], isNull);
      expect(json.containsKey('keychain_degraded_state_snapshot'), isTrue);
      expect(json['keychain_degraded_state_snapshot'], isNull);
      expect(json.containsKey('runtime_dek_device_state'), isTrue);
      expect(json['runtime_dek_device_state'], isNull);
      expect(json.containsKey('app_build'), isTrue);
      expect(json['app_build'], isNull);
    });

    test('unrecoverable + null recoveredVia + all-failure slotOutcomes is valid',
        () {
      final diag = SecureStorageDiagnostic(
        recoveredVia: null,
        slotOutcomes: const <String, String>{
          DiagnosticSlotIds.appDbPrimary: 'cipher',
          DiagnosticSlotIds.appDbSync: 'cipher',
          DiagnosticSlotIds.appDbSyncStaging: 'missing',
        },
        appDbState: DbStartupStateName.unrecoverable,
      );

      final json = diag.toJson();
      expect(json['recovered_via'], isNull);
      expect(json['app_db_state'], 'unrecoverable');
      final outcomes = json['slot_outcomes'] as Map<String, dynamic>;
      expect(outcomes.length, 3);
      expect(outcomes[DiagnosticSlotIds.appDbPrimary], 'cipher');
    });

    test('pretty-printed JSON is deterministic across two encodes', () {
      final diag = SecureStorageDiagnostic(
        recoveredVia: 'primary',
        capturedAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
        slotOutcomes: <String, String>{
          DiagnosticSlotIds.appDbPrimary: 'ok',
          DiagnosticSlotIds.appDbSync: 'missing',
        },
        appDbState: DbStartupStateName.ready,
      );

      const encoder = JsonEncoder.withIndent('  ');
      final a = encoder.convert(diag.toJson());
      final b = encoder.convert(diag.toJson());
      expect(a, equals(b));
      // And a few sanity expectations on the rendered form.
      expect(a, contains('"recovered_via": "primary"'));
      expect(a, contains('"app_db_state": "ready"'));
      expect(a, contains('"app_db_primary": "ok"'));
    });
  });

  group('SecureStorageDiagnostic slot-outcome coverage', () {
    test('all known slot ids can appear in slotOutcomes', () {
      final outcomes = <String, String>{
        DiagnosticSlotIds.appDbPrimary: 'ok',
        DiagnosticSlotIds.appDbSync: 'cipher',
        DiagnosticSlotIds.appDbStaging: 'missing',
        DiagnosticSlotIds.appDbSyncStaging: 'transient',
        DiagnosticSlotIds.appDbFresh: 'ok',
        DiagnosticSlotIds.appDbPrimaryStaging: 'invalid_hex',
        DiagnosticSlotIds.syncDbPrimary: 'unknown',
        DiagnosticSlotIds.syncDbSyncStaging: 'cipher',
        DiagnosticSlotIds.syncDbAppPrimaryCandidate: 'ok',
        DiagnosticSlotIds.syncDbAppStagingCandidate: 'missing',
        DiagnosticSlotIds.syncDbFresh: 'ok',
        DiagnosticSlotIds.syncDbStagingPromote: 'ok',
      };

      final diag = SecureStorageDiagnostic(
        recoveredVia: 'primary',
        slotOutcomes: outcomes,
      );

      final json = diag.toJson();
      final readBack = json['slot_outcomes'] as Map<String, dynamic>;
      for (final entry in outcomes.entries) {
        expect(readBack[entry.key], entry.value,
            reason: 'slot ${entry.key} should round-trip');
      }
    });

    test('slotOutcomeName + slotOutcomeThrewString produce expected strings',
        () {
      expect(slotOutcomeName(SlotOutcome.ok), 'ok');
      expect(slotOutcomeName(SlotOutcome.cipher), 'cipher');
      expect(slotOutcomeName(SlotOutcome.transient), 'transient');
      expect(slotOutcomeName(SlotOutcome.unknown), 'unknown');
      expect(slotOutcomeName(SlotOutcome.missing), 'missing');
      expect(slotOutcomeName(SlotOutcome.invalidHex), 'invalid_hex');
      expect(slotOutcomeName(SlotOutcome.threw), 'threw');

      expect(slotOutcomeThrewString(Exception('boom')),
          startsWith('threw: Exception: boom'));

      // Long messages are truncated so the diagnostic JSON stays readable.
      final longMessage = 'x' * 1000;
      final truncated = slotOutcomeThrewString(Exception(longMessage));
      expect(truncated.length, lessThan(longMessage.length));
      expect(truncated, endsWith('…'));
    });
  });

  group('SecureStorageDiagnostic merge + copy', () {
    test('mergeWith unions slotOutcomes and prefers `other` non-null fields',
        () {
      final appDiag = SecureStorageDiagnostic(
        recoveredVia: 'primary',
        slotOutcomes: const <String, String>{
          DiagnosticSlotIds.appDbPrimary: 'ok',
        },
        appDbState: DbStartupStateName.ready,
      );
      final syncDiag = SecureStorageDiagnostic(
        recoveredVia: 'fresh',
        slotOutcomes: const <String, String>{
          DiagnosticSlotIds.syncDbFresh: 'ok',
        },
        syncDbState: DbStartupStateName.ready,
      );

      final merged = appDiag.mergeWith(syncDiag);
      expect(merged.slotOutcomes.length, 2);
      expect(
        merged.slotOutcomes[DiagnosticSlotIds.appDbPrimary],
        'ok',
      );
      expect(
        merged.slotOutcomes[DiagnosticSlotIds.syncDbFresh],
        'ok',
      );
      // `other`'s recoveredVia wins when non-null.
      expect(merged.recoveredVia, 'fresh');
      // Both states are preserved.
      expect(merged.appDbState, DbStartupStateName.ready);
      expect(merged.syncDbState, DbStartupStateName.ready);
    });

    test('mergeWith preserves the base recoveredVia when `other` is null', () {
      final base = SecureStorageDiagnostic(
        recoveredVia: 'sync',
        slotOutcomes: const <String, String>{},
        appDbState: DbStartupStateName.ready,
      );
      final empty = SecureStorageDiagnostic(
        recoveredVia: null,
        slotOutcomes: const <String, String>{},
        syncDbState: DbStartupStateName.unrecoverable,
      );

      final merged = base.mergeWith(empty);
      expect(merged.recoveredVia, 'sync');
      expect(merged.appDbState, DbStartupStateName.ready);
      expect(merged.syncDbState, DbStartupStateName.unrecoverable);
    });

    test('copyWith preserves existing fields when no override is supplied', () {
      final captured = DateTime.utc(2026, 5, 19, 12, 30, 45);
      final diag = SecureStorageDiagnostic(
        recoveredVia: 'primary',
        capturedAt: captured,
        slotOutcomes: const <String, String>{
          DiagnosticSlotIds.appDbPrimary: 'ok',
        },
        appDbState: DbStartupStateName.ready,
      );

      final copied = diag.copyWith(
        keychainRepairPendingBeforeBoot: false,
      );
      expect(copied.recoveredVia, 'primary');
      expect(copied.capturedAt, captured);
      expect(copied.appDbState, DbStartupStateName.ready);
      expect(copied.keychainRepairPendingBeforeBoot, false);
    });
  });
}
