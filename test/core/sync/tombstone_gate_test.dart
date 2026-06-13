import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/sync/tombstone_gate.dart';

/// A scriptable [ReadFieldValue] keyed by `(table, entityId, field)` to the
/// JSON-encoded winning value the engine would return. Records every read so a
/// test can assert convergence/determinism.
class _FakeFieldVersions {
  _FakeFieldVersions(this._values);

  final Map<String, String?> _values;
  final List<String> reads = [];

  String _key(String table, String entityId, String field) =>
      '$table|$entityId|$field';

  ReadFieldValue get read => (table, entityId, field) async {
    reads.add(_key(table, entityId, field));
    return _values[_key(table, entityId, field)];
  };
}

void main() {
  const table = 'member_group_entries';

  group('isTombstoned', () {
    test('present is_deleted != "false" is a tombstone', () async {
      final fv = _FakeFieldVersions({'$table|e1|is_deleted': 'true'});
      final gate = TombstoneGate(fv.read);
      expect(await gate.isTombstoned(table, 'e1'), isTrue);
    });

    test('missing field version is NOT a tombstone', () async {
      final fv = _FakeFieldVersions({});
      final gate = TombstoneGate(fv.read);
      expect(await gate.isTombstoned(table, 'e1'), isFalse);
    });

    test('explicit "false" is NOT a tombstone', () async {
      final fv = _FakeFieldVersions({'$table|e1|is_deleted': 'false'});
      final gate = TombstoneGate(fv.read);
      expect(await gate.isTombstoned(table, 'e1'), isFalse);
    });

    test('a read error fails open (not tombstoned)', () async {
      final gate = TombstoneGate((table, entityId, field) async {
        throw StateError('engine unavailable');
      });
      expect(await gate.isTombstoned(table, 'e1'), isFalse);
    });
  });

  group('mintLiveEntityId', () {
    String derive(int gen) => gen == 0 ? 'gen0' : 'gen$gen';

    test('returns gen 0 when nothing is tombstoned', () async {
      final fv = _FakeFieldVersions({});
      final gate = TombstoneGate(fv.read);
      final minted = await gate.mintLiveEntityId(table, derive);
      expect(minted.generation, 0);
      expect(minted.entityId, 'gen0');
    });

    test('skips tombstoned generations and returns the first live id', () async {
      final fv = _FakeFieldVersions({
        '$table|gen0|is_deleted': 'true',
        '$table|gen1|is_deleted': 'true',
        // gen2 has no field version -> live.
      });
      final gate = TombstoneGate(fv.read);
      final minted = await gate.mintLiveEntityId(table, derive);
      expect(minted.generation, 2);
      expect(minted.entityId, 'gen2');
    });

    test('identical fv state mints identical ids (cross-device convergence)',
        () async {
      Map<String, String?> state() => {
        '$table|gen0|is_deleted': 'true',
        '$table|gen1|is_deleted': 'false', // explicit live -> NOT a tombstone
      };
      final gateA = TombstoneGate(_FakeFieldVersions(state()).read);
      final gateB = TombstoneGate(_FakeFieldVersions(state()).read);
      final a = await gateA.mintLiveEntityId(table, derive);
      final b = await gateB.mintLiveEntityId(table, derive);
      expect(a, b);
      expect(a.generation, 1);
      expect(a.entityId, 'gen1');
    });

    test('a stale device that has not seen a tombstone mints a lower gen',
        () async {
      // Device A sees gen0 tombstoned; device B has not imported it yet.
      final gateA = TombstoneGate(
        _FakeFieldVersions({'$table|gen0|is_deleted': 'true'}).read,
      );
      final gateB = TombstoneGate(_FakeFieldVersions({}).read);
      final a = await gateA.mintLiveEntityId(table, derive);
      final b = await gateB.mintLiveEntityId(table, derive);
      expect(a.generation, 1);
      expect(b.generation, 0);
      // They re-converge once B imports the tombstone — pinned by the
      // "identical fv state" case above. The receiver backstop keeps B's lower
      // gen0 from resurrecting anything in the meantime (Rust merge.rs).
    });

    test('bounded loop throws rather than minting a known-burned id',
        () async {
      // Every generation is tombstoned; the loop must terminate by THROWING,
      // not by returning a burned id — emitting a create into a tombstoned id
      // is a silent fleet-wide no-op, the exact failure this layer prevents.
      final gate = TombstoneGate(
        (table, entityId, field) async => 'true',
      );
      await expectLater(
        () => gate.mintLiveEntityId(table, derive, maxGenerations: 4),
        throwsA(isA<TombstoneGateExhausted>()),
      );
    });
  });
}
