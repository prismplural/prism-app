import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

void main() {
  group('PluralKitSyncState — truth table', () {
    // Full 8-row truth table for
    // (isConnected × directionConfirmed × mappingAcknowledged)
    // → (needsDirection, needsMapping, canAutoSync)
    //
    // Row 1: disconnected, nothing confirmed
    test('not connected, nothing confirmed → all false', () {
      const state = PluralKitSyncState(
        isConnected: false,
        directionConfirmed: false,
        mappingAcknowledged: false,
      );
      expect(state.needsDirection, false);
      expect(state.needsMapping, false);
      expect(state.canAutoSync, false);
    });

    // Row 2: disconnected, directionConfirmed
    test('not connected, directionConfirmed=true → all false', () {
      const state = PluralKitSyncState(
        isConnected: false,
        directionConfirmed: true,
        mappingAcknowledged: false,
      );
      expect(state.needsDirection, false);
      expect(state.needsMapping, false);
      expect(state.canAutoSync, false);
    });

    // Row 3: disconnected, mappingAcknowledged (hypothetical)
    test('not connected, mappingAcknowledged=true → all false', () {
      const state = PluralKitSyncState(
        isConnected: false,
        directionConfirmed: false,
        mappingAcknowledged: true,
      );
      expect(state.needsDirection, false);
      expect(state.needsMapping, false);
      expect(state.canAutoSync, false);
    });

    // Row 4: disconnected, both confirmed
    test('not connected, both flags=true → all false', () {
      const state = PluralKitSyncState(
        isConnected: false,
        directionConfirmed: true,
        mappingAcknowledged: true,
      );
      expect(state.needsDirection, false);
      expect(state.needsMapping, false);
      expect(state.canAutoSync, false);
    });

    // Row 5: connected, nothing confirmed → needsDirection only
    test('connected, nothing confirmed → needsDirection=true, needsMapping=false, canAutoSync=false', () {
      const state = PluralKitSyncState(
        isConnected: true,
        directionConfirmed: false,
        mappingAcknowledged: false,
      );
      expect(state.needsDirection, true);
      expect(state.needsMapping, false);
      expect(state.canAutoSync, false);
    });

    // Row 6: connected, directionConfirmed, not mappingAcknowledged → needsMapping only
    test('connected, directionConfirmed=true, mappingAcknowledged=false → needsMapping=true', () {
      const state = PluralKitSyncState(
        isConnected: true,
        directionConfirmed: true,
        mappingAcknowledged: false,
      );
      expect(state.needsDirection, false);
      expect(state.needsMapping, true);
      expect(state.canAutoSync, false);
    });

    // Row 7: connected, mappingAcknowledged without directionConfirmed
    // (hypothetical / migration edge case — should land in needsDirection)
    test('connected, mappingAcknowledged=true, directionConfirmed=false → needsDirection=true', () {
      const state = PluralKitSyncState(
        isConnected: true,
        directionConfirmed: false,
        mappingAcknowledged: true,
      );
      expect(state.needsDirection, true);
      expect(state.needsMapping, false);
      expect(state.canAutoSync, false);
    });

    // Row 8: connected, both confirmed → canAutoSync only
    test('connected, both flags=true → canAutoSync=true', () {
      const state = PluralKitSyncState(
        isConnected: true,
        directionConfirmed: true,
        mappingAcknowledged: true,
      );
      expect(state.needsDirection, false);
      expect(state.needsMapping, false);
      expect(state.canAutoSync, true);
    });
  });

  group('PluralKitSyncState — defaults', () {
    test('default constructor produces all-false state', () {
      const state = PluralKitSyncState();
      expect(state.isConnected, false);
      expect(state.directionConfirmed, false);
      expect(state.mappingAcknowledged, false);
      expect(state.needsDirection, false);
      expect(state.needsMapping, false);
      expect(state.canAutoSync, false);
    });
  });

  group('PluralKitSyncState — copyWith round-trips', () {
    test('copyWith preserves directionConfirmed', () {
      const base = PluralKitSyncState(isConnected: true, directionConfirmed: false);
      final updated = base.copyWith(directionConfirmed: true);
      expect(updated.directionConfirmed, true);
      expect(updated.isConnected, true);
    });

    test('copyWith preserves mappingAcknowledged', () {
      const base = PluralKitSyncState(
        isConnected: true,
        directionConfirmed: true,
        mappingAcknowledged: false,
      );
      final updated = base.copyWith(mappingAcknowledged: true);
      expect(updated.mappingAcknowledged, true);
      expect(updated.directionConfirmed, true);
      expect(updated.canAutoSync, true);
    });

    test('copyWith transitions needsDirection → needsMapping', () {
      const afterConnect = PluralKitSyncState(
        isConnected: true,
        directionConfirmed: false,
        mappingAcknowledged: false,
      );
      expect(afterConnect.needsDirection, true);

      final afterDirection = afterConnect.copyWith(directionConfirmed: true);
      expect(afterDirection.needsDirection, false);
      expect(afterDirection.needsMapping, true);
    });

    test('copyWith transitions needsMapping → canAutoSync', () {
      const afterDirection = PluralKitSyncState(
        isConnected: true,
        directionConfirmed: true,
        mappingAcknowledged: false,
      );
      expect(afterDirection.needsMapping, true);

      final afterMapping = afterDirection.copyWith(mappingAcknowledged: true);
      expect(afterMapping.needsMapping, false);
      expect(afterMapping.canAutoSync, true);
    });

    test('copyWith does not mutate source', () {
      const base = PluralKitSyncState(
        isConnected: true,
        directionConfirmed: false,
        mappingAcknowledged: false,
      );
      base.copyWith(directionConfirmed: true, mappingAcknowledged: true);
      expect(base.directionConfirmed, false);
      expect(base.mappingAcknowledged, false);
    });
  });

  group('PluralKitSyncState — equality', () {
    test('identical states are equal', () {
      const a = PluralKitSyncState(
        isConnected: true,
        directionConfirmed: true,
        mappingAcknowledged: true,
      );
      const b = PluralKitSyncState(
        isConnected: true,
        directionConfirmed: true,
        mappingAcknowledged: true,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('states differing in directionConfirmed are not equal', () {
      const a = PluralKitSyncState(isConnected: true, directionConfirmed: false);
      const b = PluralKitSyncState(isConnected: true, directionConfirmed: true);
      expect(a, isNot(equals(b)));
    });

    test('states differing in mappingAcknowledged are not equal', () {
      const a = PluralKitSyncState(
        isConnected: true,
        directionConfirmed: true,
        mappingAcknowledged: false,
      );
      const b = PluralKitSyncState(
        isConnected: true,
        directionConfirmed: true,
        mappingAcknowledged: true,
      );
      expect(a, isNot(equals(b)));
    });
  });
}
