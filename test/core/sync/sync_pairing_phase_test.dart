import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/sync/sync_pairing_phase.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SyncPairingPhaseService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('default state when no SharedPref value is unread', () async {
      final service = SyncPairingPhaseService();
      expect(await service.read(), SyncPairingPhase.unread);
    });

    test('write/read round-trips every phase', () async {
      final service = SyncPairingPhaseService();
      for (final phase in SyncPairingPhase.values) {
        await service.write(phase);
        expect(await service.read(), phase);
      }
    });

    test('unknown saved value falls back to unread', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kSyncPairingPhaseKey: 'bogus_value_v999',
      });
      final service = SyncPairingPhaseService();
      expect(await service.read(), SyncPairingPhase.unread);
    });

    group('allowed transitions', () {
      test('unread → wipeInProgress', () async {
        final service = SyncPairingPhaseService();
        await service.transition(
          from: SyncPairingPhase.unread,
          to: SyncPairingPhase.wipeInProgress,
        );
        expect(await service.read(), SyncPairingPhase.wipeInProgress);
      });

      test('wipeInProgress → pendingPair', () async {
        final service = SyncPairingPhaseService();
        await service.write(SyncPairingPhase.wipeInProgress);
        await service.transition(
          from: SyncPairingPhase.wipeInProgress,
          to: SyncPairingPhase.pendingPair,
        );
        expect(await service.read(), SyncPairingPhase.pendingPair);
      });

      test('pendingPair → paired', () async {
        final service = SyncPairingPhaseService();
        await service.write(SyncPairingPhase.pendingPair);
        await service.transition(
          from: SyncPairingPhase.pendingPair,
          to: SyncPairingPhase.paired,
        );
        expect(await service.read(), SyncPairingPhase.paired);
      });

      test('paired → unread', () async {
        final service = SyncPairingPhaseService();
        await service.write(SyncPairingPhase.paired);
        await service.transition(
          from: SyncPairingPhase.paired,
          to: SyncPairingPhase.unread,
        );
        expect(await service.read(), SyncPairingPhase.unread);
      });

      test('identity transition is a silent no-op', () async {
        final service = SyncPairingPhaseService();
        await service.write(SyncPairingPhase.pendingPair);
        await service.transition(
          from: SyncPairingPhase.pendingPair,
          to: SyncPairingPhase.pendingPair,
        );
        expect(await service.read(), SyncPairingPhase.pendingPair);
      });

      test('reset path: wipeInProgress → unread is allowed (recovery)',
          () async {
        final service = SyncPairingPhaseService();
        await service.write(SyncPairingPhase.wipeInProgress);
        await service.transition(
          from: SyncPairingPhase.wipeInProgress,
          to: SyncPairingPhase.unread,
        );
        expect(await service.read(), SyncPairingPhase.unread);
      });

      test('reset path: pendingPair → unread is allowed (recovery)',
          () async {
        final service = SyncPairingPhaseService();
        await service.write(SyncPairingPhase.pendingPair);
        await service.transition(
          from: SyncPairingPhase.pendingPair,
          to: SyncPairingPhase.unread,
        );
        expect(await service.read(), SyncPairingPhase.unread);
      });
    });

    group('invalid transitions throw StateError', () {
      test('unread → pendingPair', () async {
        final service = SyncPairingPhaseService();
        expect(
          () => service.transition(
            from: SyncPairingPhase.unread,
            to: SyncPairingPhase.pendingPair,
          ),
          throwsA(isA<StateError>()),
        );
      });

      test('unread → paired', () async {
        final service = SyncPairingPhaseService();
        expect(
          () => service.transition(
            from: SyncPairingPhase.unread,
            to: SyncPairingPhase.paired,
          ),
          throwsA(isA<StateError>()),
        );
      });

      test('wipeInProgress → paired (skips pendingPair)', () async {
        final service = SyncPairingPhaseService();
        await service.write(SyncPairingPhase.wipeInProgress);
        expect(
          () => service.transition(
            from: SyncPairingPhase.wipeInProgress,
            to: SyncPairingPhase.paired,
          ),
          throwsA(isA<StateError>()),
        );
      });

      test('paired → wipeInProgress (must go through unread first)',
          () async {
        final service = SyncPairingPhaseService();
        await service.write(SyncPairingPhase.paired);
        expect(
          () => service.transition(
            from: SyncPairingPhase.paired,
            to: SyncPairingPhase.wipeInProgress,
          ),
          throwsA(isA<StateError>()),
        );
      });

      test('precondition mismatch throws (from != saved)', () async {
        final service = SyncPairingPhaseService();
        await service.write(SyncPairingPhase.unread);
        expect(
          () => service.transition(
            from: SyncPairingPhase.pendingPair,
            to: SyncPairingPhase.paired,
          ),
          throwsA(isA<StateError>()),
        );
      });
    });
  });
}
