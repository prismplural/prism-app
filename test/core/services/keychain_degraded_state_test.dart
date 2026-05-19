import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/services/keychain_degraded_state.dart';

const String _kPrefsKey = 'prism.keychain.degraded_state';

void main() {
  // ── KeychainDegradedState: getters ──────────────────────────────────────

  group('KeychainDegradedState getters', () {
    test('healthy() is fully healthy', () {
      const s = KeychainDegradedState.healthy();
      expect(s.isHealthy, isTrue);
      expect(s.hasAnyUnreadable, isFalse);
      expect(s.unreadableSlotNames, isEmpty);
      expect(s.firstObservedAt, isNull);
      expect(s.schemaVersion, currentSchemaVersion);
    });

    test('isHealthy false when any slot is unreadable', () {
      const s = KeychainDegradedState(
        appDbKey: SlotState.ok,
        syncKey: SlotState.unreadable,
        syncCredentials: SlotState.ok,
        pin: SlotState.ok,
        firstObservedAt: null,
      );
      expect(s.isHealthy, isFalse);
      expect(s.hasAnyUnreadable, isTrue);
      expect(s.unreadableSlotNames, {'syncKey'});
    });

    test('isHealthy false when a slot is degraded', () {
      const s = KeychainDegradedState(
        appDbKey: SlotState.ok,
        syncKey: SlotState.ok,
        syncCredentials: SlotState.degraded,
        pin: SlotState.ok,
        firstObservedAt: null,
      );
      expect(s.isHealthy, isFalse);
      expect(s.hasAnyUnreadable, isFalse,
          reason: 'degraded is not the same as unreadable');
      expect(s.unreadableSlotNames, {'syncCredentials'});
    });

    test('unreadableSlotNames includes every non-ok slot', () {
      const s = KeychainDegradedState(
        appDbKey: SlotState.unreadable,
        syncKey: SlotState.unreadable,
        syncCredentials: SlotState.degraded,
        pin: SlotState.unreadable,
        firstObservedAt: null,
      );
      expect(s.unreadableSlotNames,
          {'appDbKey', 'syncKey', 'syncCredentials', 'pin'});
    });
  });

  // ── Equality + hashCode ─────────────────────────────────────────────────

  group('equality + hashCode', () {
    test('two healthy instances are equal', () {
      const a = KeychainDegradedState.healthy();
      const b = KeychainDegradedState.healthy();
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('differing slot states are not equal', () {
      const a = KeychainDegradedState.healthy();
      final b = a.copyWith(pin: SlotState.unreadable);
      expect(a, isNot(equals(b)));
    });

    test('differing firstObservedAt is not equal', () {
      const a = KeychainDegradedState.healthy();
      final b = a.copyWith(firstObservedAt: DateTime.utc(2026, 1, 1));
      expect(a, isNot(equals(b)));
    });

    test('hashCode is stable for equal objects', () {
      final ts = DateTime.utc(2026, 5, 19, 10, 0, 0);
      final a = KeychainDegradedState(
        appDbKey: SlotState.ok,
        syncKey: SlotState.unreadable,
        syncCredentials: SlotState.degraded,
        pin: SlotState.ok,
        firstObservedAt: ts,
      );
      final b = KeychainDegradedState(
        appDbKey: SlotState.ok,
        syncKey: SlotState.unreadable,
        syncCredentials: SlotState.degraded,
        pin: SlotState.ok,
        firstObservedAt: ts,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });

  // ── copyWith ────────────────────────────────────────────────────────────

  group('copyWith', () {
    test('copyWith with no args returns equal value', () {
      const s = KeychainDegradedState.healthy();
      expect(s.copyWith(), equals(s));
    });

    test('copyWith updates only the named field', () {
      const s = KeychainDegradedState.healthy();
      final next = s.copyWith(syncKey: SlotState.unreadable);
      expect(next.syncKey, SlotState.unreadable);
      expect(next.appDbKey, SlotState.ok);
      expect(next.pin, SlotState.ok);
      expect(next.syncCredentials, SlotState.ok);
    });

    test('copyWith with explicit null clears firstObservedAt', () {
      final s = KeychainDegradedState(
        appDbKey: SlotState.ok,
        syncKey: SlotState.unreadable,
        syncCredentials: SlotState.ok,
        pin: SlotState.ok,
        firstObservedAt: DateTime.utc(2026, 1, 1),
      );
      final next = s.copyWith(firstObservedAt: null);
      expect(next.firstObservedAt, isNull);
      expect(next.syncKey, SlotState.unreadable);
    });

    test('copyWith without firstObservedAt preserves it', () {
      final ts = DateTime.utc(2026, 1, 1);
      final s = KeychainDegradedState(
        appDbKey: SlotState.ok,
        syncKey: SlotState.unreadable,
        syncCredentials: SlotState.ok,
        pin: SlotState.ok,
        firstObservedAt: ts,
      );
      final next = s.copyWith(pin: SlotState.unreadable);
      expect(next.firstObservedAt, ts);
    });
  });

  // ── JSON round-trip ─────────────────────────────────────────────────────

  group('JSON round-trip', () {
    test('healthy round-trips', () {
      const s = KeychainDegradedState.healthy();
      final json = s.toJson();
      final back = KeychainDegradedState.fromJson(json);
      expect(back, equals(s));
    });

    test('partially-degraded round-trips', () {
      final s = KeychainDegradedState(
        appDbKey: SlotState.ok,
        syncKey: SlotState.unreadable,
        syncCredentials: SlotState.degraded,
        pin: SlotState.ok,
        firstObservedAt: DateTime.utc(2026, 5, 1, 12, 0, 0),
      );
      final back = KeychainDegradedState.fromJson(s.toJson());
      expect(back, equals(s));
    });

    test('fully-degraded round-trips', () {
      final s = KeychainDegradedState(
        appDbKey: SlotState.unreadable,
        syncKey: SlotState.unreadable,
        syncCredentials: SlotState.unreadable,
        pin: SlotState.unreadable,
        firstObservedAt: DateTime.utc(2026, 5, 19, 9, 0, 0),
      );
      final back = KeychainDegradedState.fromJson(s.toJson());
      expect(back, equals(s));
    });

    test('JSON shape matches the documented schema', () {
      const s = KeychainDegradedState.healthy();
      final json = s.toJson();
      expect(json['schemaVersion'], 1);
      expect(json['appDbKey'], 'ok');
      expect(json['syncKey'], 'ok');
      expect(json['syncCredentials'], 'ok');
      expect(json['pin'], 'ok');
      expect(json.containsKey('firstObservedAt'), isTrue);
      expect(json['firstObservedAt'], isNull);
    });
  });

  // ── Parsing tolerance ───────────────────────────────────────────────────

  group('fromJson parsing tolerance', () {
    test('unknown enum string → degraded (safer default)', () {
      // A future version writes "locked" — current version reads it.
      final json = {
        'schemaVersion': 1,
        'appDbKey': 'ok',
        'syncKey': 'locked', // unknown value
        'syncCredentials': 'ok',
        'pin': 'ok',
        'firstObservedAt': null,
      };
      final state = KeychainDegradedState.fromJson(json);
      expect(state.syncKey, SlotState.degraded);
      expect(state.appDbKey, SlotState.ok);
    });

    test('missing field at saved version → throws FormatException', () {
      // Saved at schemaVersion 1 with appDbKey missing — appDbKey was
      // introduced at v1, so it's required.
      final json = {
        'schemaVersion': 1,
        'syncKey': 'ok',
        'syncCredentials': 'ok',
        'pin': 'ok',
        'firstObservedAt': null,
      };
      expect(
        () => KeychainDegradedState.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('missing field introduced after saved version → defaults to ok', () {
      // Simulate a hypothetical schemaVersion-0 save (older than v1). At
      // v0 none of the current fields existed; all fields were
      // introduced at v1. So loading a v0 save defaults everything to
      // ok. (This is the forward-compat hook: when we bump
      // currentSchemaVersion later and add a field, old saves load
      // cleanly.)
      final json = {
        'schemaVersion': 0,
        'firstObservedAt': null,
      };
      final state = KeychainDegradedState.fromJson(json);
      expect(state.appDbKey, SlotState.ok);
      expect(state.syncKey, SlotState.ok);
      expect(state.syncCredentials, SlotState.ok);
      expect(state.pin, SlotState.ok);
      expect(state.schemaVersion, 0,
          reason: 'schemaVersion is preserved from the save');
    });

    test('schemaVersion higher than current → parses best-effort', () {
      // Future version saves at v99 with an extra unknown field. Older
      // build must NOT throw — user just downgraded.
      final json = {
        'schemaVersion': 99,
        'appDbKey': 'ok',
        'syncKey': 'ok',
        'syncCredentials': 'ok',
        'pin': 'ok',
        'firstObservedAt': null,
        'someFutureField': 'whatever',
      };
      final state = KeychainDegradedState.fromJson(json);
      expect(state.isHealthy, isTrue);
      expect(state.schemaVersion, 99);
    });

    test('missing schemaVersion → throws FormatException', () {
      final json = {
        'appDbKey': 'ok',
        'syncKey': 'ok',
        'syncCredentials': 'ok',
        'pin': 'ok',
        'firstObservedAt': null,
      };
      expect(
        () => KeychainDegradedState.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('null slot value at saved version → throws FormatException', () {
      final json = {
        'schemaVersion': 1,
        'appDbKey': null,
        'syncKey': 'ok',
        'syncCredentials': 'ok',
        'pin': 'ok',
        'firstObservedAt': null,
      };
      expect(
        () => KeychainDegradedState.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('non-string slot value → throws FormatException', () {
      final json = {
        'schemaVersion': 1,
        'appDbKey': 42,
        'syncKey': 'ok',
        'syncCredentials': 'ok',
        'pin': 'ok',
        'firstObservedAt': null,
      };
      expect(
        () => KeychainDegradedState.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('firstObservedAt parses ISO-8601', () {
      final json = {
        'schemaVersion': 1,
        'appDbKey': 'ok',
        'syncKey': 'unreadable',
        'syncCredentials': 'ok',
        'pin': 'ok',
        'firstObservedAt': '2026-05-19T09:00:00.000Z',
      };
      final state = KeychainDegradedState.fromJson(json);
      expect(
        state.firstObservedAt,
        DateTime.utc(2026, 5, 19, 9, 0, 0),
      );
    });
  });

  // ── KeychainDegradedStateService: read / write ──────────────────────────

  group('KeychainDegradedStateService read/write', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('read() returns healthy when no save exists', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = KeychainDegradedStateService(prefs: prefs);
      final state = await service.read();
      expect(state, const KeychainDegradedState.healthy());
    });

    test('write() then read() round-trips', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = KeychainDegradedStateService(prefs: prefs);
      final input = KeychainDegradedState(
        appDbKey: SlotState.ok,
        syncKey: SlotState.unreadable,
        syncCredentials: SlotState.degraded,
        pin: SlotState.ok,
        firstObservedAt: DateTime.utc(2026, 5, 19),
      );
      await service.write(input);
      final back = await service.read();
      expect(back, equals(input));
    });

    test('corrupted JSON → service returns healthy without throwing',
        () async {
      SharedPreferences.setMockInitialValues({
        _kPrefsKey: '{not valid json',
      });
      final prefs = await SharedPreferences.getInstance();
      final service = KeychainDegradedStateService(prefs: prefs);
      final state = await service.read();
      expect(state, const KeychainDegradedState.healthy());
    });

    test('JSON-object-but-corrupt → service returns healthy without throwing',
        () async {
      // Missing required field at schemaVersion 1.
      SharedPreferences.setMockInitialValues({
        _kPrefsKey: jsonEncode({
          'schemaVersion': 1,
          'syncKey': 'ok',
          'syncCredentials': 'ok',
          'pin': 'ok',
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final service = KeychainDegradedStateService(prefs: prefs);
      final state = await service.read();
      expect(state, const KeychainDegradedState.healthy());
    });

    test('non-object JSON → service returns healthy without throwing',
        () async {
      SharedPreferences.setMockInitialValues({
        _kPrefsKey: jsonEncode([1, 2, 3]),
      });
      final prefs = await SharedPreferences.getInstance();
      final service = KeychainDegradedStateService(prefs: prefs);
      final state = await service.read();
      expect(state, const KeychainDegradedState.healthy());
    });
  });

  // ── updateSlot + firstObservedAt management ─────────────────────────────

  group('KeychainDegradedStateService.updateSlot', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('healthy → not-healthy stamps firstObservedAt', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = KeychainDegradedStateService(prefs: prefs);

      final before = DateTime.now();
      await service.updateSlot('syncKey', SlotState.unreadable);
      final after = DateTime.now();

      final state = await service.read();
      expect(state.syncKey, SlotState.unreadable);
      expect(state.isHealthy, isFalse);
      expect(state.firstObservedAt, isNotNull);
      expect(
        state.firstObservedAt!.isBefore(before.subtract(const Duration(seconds: 1))),
        isFalse,
      );
      expect(
        state.firstObservedAt!.isAfter(after.add(const Duration(seconds: 1))),
        isFalse,
      );
    });

    test('not-healthy → fully-healthy clears firstObservedAt', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = KeychainDegradedStateService(prefs: prefs);

      // Set up: degrade syncKey → firstObservedAt stamped.
      await service.updateSlot('syncKey', SlotState.unreadable);
      final degraded = await service.read();
      expect(degraded.firstObservedAt, isNotNull);

      // Recover: syncKey back to ok → fully healthy → cleared.
      await service.updateSlot('syncKey', SlotState.ok);
      final recovered = await service.read();
      expect(recovered.isHealthy, isTrue);
      expect(recovered.firstObservedAt, isNull);
    });

    test(
        'not-healthy → still-not-healthy preserves the original firstObservedAt',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final service = KeychainDegradedStateService(prefs: prefs);

      await service.updateSlot('syncKey', SlotState.unreadable);
      final first = await service.read();
      final firstStamp = first.firstObservedAt;
      expect(firstStamp, isNotNull);

      // Wait long enough that DateTime.now() would differ measurably.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Add another degraded slot — still not fully healthy.
      await service.updateSlot('pin', SlotState.unreadable);
      final second = await service.read();
      expect(second.firstObservedAt, firstStamp,
          reason: 'firstObservedAt should not be re-stamped on subsequent '
              'transitions while remaining non-healthy');
    });

    test('updateSlot with unknown slot name is a no-op (no throw)',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final service = KeychainDegradedStateService(prefs: prefs);

      // Should NOT throw.
      await service.updateSlot('notARealSlot', SlotState.unreadable);
      final state = await service.read();
      expect(state, const KeychainDegradedState.healthy());
    });

    test('updateSlot to same value is a no-op (no firstObservedAt churn)',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final service = KeychainDegradedStateService(prefs: prefs);

      // Starting from healthy, set syncKey to ok — no change.
      await service.updateSlot('syncKey', SlotState.ok);
      final state = await service.read();
      expect(state.firstObservedAt, isNull);
      expect(state.isHealthy, isTrue);
    });

    test('every known slot name routes correctly', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = KeychainDegradedStateService(prefs: prefs);

      await service.updateSlot('appDbKey', SlotState.unreadable);
      expect((await service.read()).appDbKey, SlotState.unreadable);

      await service.updateSlot('syncKey', SlotState.unreadable);
      expect((await service.read()).syncKey, SlotState.unreadable);

      await service.updateSlot('syncCredentials', SlotState.degraded);
      expect((await service.read()).syncCredentials, SlotState.degraded);

      await service.updateSlot('pin', SlotState.unreadable);
      expect((await service.read()).pin, SlotState.unreadable);
    });
  });

  // ── deriveDegradedBannerMessage ─────────────────────────────────────────

  group('deriveDegradedBannerMessage', () {
    test('returns null for healthy', () {
      expect(
        deriveDegradedBannerMessage(const KeychainDegradedState.healthy()),
        isNull,
      );
    });

    test('PIN-only unreadable → PIN message', () {
      const s = KeychainDegradedState(
        appDbKey: SlotState.ok,
        syncKey: SlotState.ok,
        syncCredentials: SlotState.ok,
        pin: SlotState.unreadable,
        firstObservedAt: null,
      );
      expect(
        deriveDegradedBannerMessage(s),
        'PIN lock data lost — set a new PIN in Settings',
      );
    });

    test('syncCredentials degraded → re-pair message', () {
      const s = KeychainDegradedState(
        appDbKey: SlotState.ok,
        syncKey: SlotState.ok,
        syncCredentials: SlotState.degraded,
        pin: SlotState.ok,
        firstObservedAt: null,
      );
      expect(
        deriveDegradedBannerMessage(s),
        'Sync credentials unreadable — re-pair to resume sync',
      );
    });

    test('syncCredentials unreadable → re-pair message', () {
      const s = KeychainDegradedState(
        appDbKey: SlotState.ok,
        syncKey: SlotState.ok,
        syncCredentials: SlotState.unreadable,
        pin: SlotState.ok,
        firstObservedAt: null,
      );
      expect(
        deriveDegradedBannerMessage(s),
        'Sync credentials unreadable — re-pair to resume sync',
      );
    });

    test('syncKey unreadable → sync unlock failed message', () {
      const s = KeychainDegradedState(
        appDbKey: SlotState.ok,
        syncKey: SlotState.unreadable,
        syncCredentials: SlotState.ok,
        pin: SlotState.ok,
        firstObservedAt: null,
      );
      expect(
        deriveDegradedBannerMessage(s),
        'Sync data unlock failed — re-pair to resume sync',
      );
    });

    test('appDbKey unreadable → defense-in-depth message', () {
      const s = KeychainDegradedState(
        appDbKey: SlotState.unreadable,
        syncKey: SlotState.ok,
        syncCredentials: SlotState.ok,
        pin: SlotState.ok,
        firstObservedAt: null,
      );
      expect(
        deriveDegradedBannerMessage(s),
        'Local data unlock failed — see recovery options',
      );
    });

    test('multiple slots unreadable → multi-slot message', () {
      const s = KeychainDegradedState(
        appDbKey: SlotState.ok,
        syncKey: SlotState.unreadable,
        syncCredentials: SlotState.ok,
        pin: SlotState.unreadable,
        firstObservedAt: null,
      );
      expect(
        deriveDegradedBannerMessage(s),
        'Multiple keychain slots unreadable — see Settings for recovery '
        'options',
      );
    });

    test('multi-slot wins over appDbKey single case', () {
      const s = KeychainDegradedState(
        appDbKey: SlotState.unreadable,
        syncKey: SlotState.unreadable,
        syncCredentials: SlotState.ok,
        pin: SlotState.ok,
        firstObservedAt: null,
      );
      expect(
        deriveDegradedBannerMessage(s),
        'Multiple keychain slots unreadable — see Settings for recovery '
        'options',
      );
    });
  });
}
