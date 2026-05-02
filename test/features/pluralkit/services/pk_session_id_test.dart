import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_session_id.dart';

void main() {
  group('deriveCanonicalPkSessionId', () {
    const switchId = 'sw-1';
    const localId = 'local-a';
    const pkUuid = 'uuid-a';

    test('with PK uuid mapping: matches derivePkSessionId(switch, pkUuid)', () {
      final id = deriveCanonicalPkSessionId(
        switchId: switchId,
        localMemberId: localId,
        pkUuidByLocalId: const {localId: pkUuid},
      );
      expect(id, derivePkSessionId(switchId, pkUuid));
    });

    test('without PK uuid mapping: falls back to local id', () {
      final id = deriveCanonicalPkSessionId(
        switchId: switchId,
        localMemberId: localId,
        pkUuidByLocalId: const {},
      );
      expect(id, derivePkSessionId(switchId, localId));
    });

    test('idempotent — same inputs produce same id', () {
      final map = {localId: pkUuid};
      final a = deriveCanonicalPkSessionId(
        switchId: switchId,
        localMemberId: localId,
        pkUuidByLocalId: map,
      );
      final b = deriveCanonicalPkSessionId(
        switchId: switchId,
        localMemberId: localId,
        pkUuidByLocalId: map,
      );
      expect(a, b);
    });

    test('different switches produce different ids', () {
      final a = deriveCanonicalPkSessionId(
        switchId: 'sw-1',
        localMemberId: localId,
        pkUuidByLocalId: const {localId: pkUuid},
      );
      final b = deriveCanonicalPkSessionId(
        switchId: 'sw-2',
        localMemberId: localId,
        pkUuidByLocalId: const {localId: pkUuid},
      );
      expect(a, isNot(b));
    });

    test('different local members produce different ids', () {
      final a = deriveCanonicalPkSessionId(
        switchId: switchId,
        localMemberId: 'local-a',
        pkUuidByLocalId: const {'local-a': 'uuid-a', 'local-b': 'uuid-b'},
      );
      final b = deriveCanonicalPkSessionId(
        switchId: switchId,
        localMemberId: 'local-b',
        pkUuidByLocalId: const {'local-a': 'uuid-a', 'local-b': 'uuid-b'},
      );
      expect(a, isNot(b));
    });

    test('with-mapping vs fallback paths can produce different ids '
        '(mapping flips behavior intentionally)', () {
      // With mapping: derive on pkUuid. Without mapping: derive on localId.
      // These must differ when pkUuid != localId, otherwise the helper is
      // collapsing the two paths.
      final withMap = deriveCanonicalPkSessionId(
        switchId: switchId,
        localMemberId: localId,
        pkUuidByLocalId: const {localId: pkUuid},
      );
      final fallback = deriveCanonicalPkSessionId(
        switchId: switchId,
        localMemberId: localId,
        pkUuidByLocalId: const {},
      );
      expect(withMap, isNot(fallback));
    });
  });
}
