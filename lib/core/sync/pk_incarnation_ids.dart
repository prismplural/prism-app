// Deterministic entity-id derivation for PK-backed CRDT rows, generation-aware.
//
// Generation 0 reproduces the historical ids byte-for-byte so already-synced
// entities keep their identity across the upgrade; generations >= 1 are the
// "incarnation" ids minted after a tombstone burns the previous generation (see
// TombstoneGate). These formats must stay in lock-step with the Rust
// sender/merge contract and with drift_sync_adapter.dart's parse path.

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Canonical group entity-id prefix for generation 0 (legacy, byte-identical to
/// 0.12.x). 0.12.x's bare prefix-strip parses this to recover the pk uuid.
const String pkGroupCanonicalPrefix = 'pk-group:';

/// Group entity id for [generation].
///
/// gen 0 -> `pk-group:<uuid>` (legacy). gen N>=1 -> `pk-group-g<N>:<uuid>`, a
/// NEW prefix that 0.12.x's bare `pk-group:` strip does NOT mis-parse, so a
/// stale peer never pollutes `pluralkit_uuid` with `g<N>:<uuid>`. Incarnation
/// create payloads always carry `pluralkit_uuid` so the receiver resolves the
/// real uuid from the field, not the id.
String deriveGroupIncarnationEntityId(String pkGroupUuid, int generation) {
  if (generation <= 0) return '$pkGroupCanonicalPrefix$pkGroupUuid';
  return 'pk-group-g$generation:$pkGroupUuid';
}

/// Parsed `(pkGroupUuid, generation)` of a group incarnation entity id, or
/// `null` when [entityId] is neither the canonical form nor an incarnation
/// form. Mirrors [deriveGroupIncarnationEntityId].
PkGroupIncarnation? parseGroupIncarnationEntityId(String entityId) {
  if (entityId.startsWith(pkGroupCanonicalPrefix)) {
    return PkGroupIncarnation(
      pkGroupUuid: entityId.substring(pkGroupCanonicalPrefix.length),
      generation: 0,
    );
  }
  // `pk-group-g<N>:<uuid>` with N >= 1.
  final match = _groupIncarnationPattern.firstMatch(entityId);
  if (match == null) return null;
  return PkGroupIncarnation(
    pkGroupUuid: match.group(2)!,
    generation: int.parse(match.group(1)!),
  );
}

final RegExp _groupIncarnationPattern = RegExp(r'^pk-group-g([1-9][0-9]*):(.+)$');

/// Parsed group incarnation: the base pk uuid and its generation.
class PkGroupIncarnation {
  const PkGroupIncarnation({
    required this.pkGroupUuid,
    required this.generation,
  });

  final String pkGroupUuid;
  final int generation;
}

/// Member-group-entry entity id for [generation].
///
/// gen 0 -> `sha256('<g>\u0000<m>')[:16]`, byte-identical to the legacy 0.12.x
/// derivation (NUL-separated), so already-synced entries keep their identity.
/// gen N>=1 -> `sha256('<g> <m> g<N>')[:16]`, a space-separated, generation-
/// salted derivation invisible to old devices (just a different sha). The
/// separators deliberately differ so a gen>=1 id can never collide with the
/// legacy gen-0 id of a different edge. Returns `null` only when a pk uuid is
/// missing (the caller falls back to the row's own id; non-PK entries never
/// collide so they never need an incarnation).
String? deriveEntryIncarnationEntityId(
  String? pkGroupUuid,
  String? pkMemberUuid,
  int generation,
) {
  final g = (pkGroupUuid ?? '').trim();
  final m = (pkMemberUuid ?? '').trim();
  if (g.isEmpty || m.isEmpty) return null;
  // gen 0 separator is a NUL byte (legacy, byte-identical); gen>=1 is space-
  // separated with a ' g<N>' salt.
  final salt = generation <= 0 ? '$g\u0000$m' : '$g $m g$generation';
  return sha256.convert(utf8.encode(salt)).toString().substring(0, 16);
}

/// Parse the generation of an entry [entityId] against the known logical edge
/// `(pkGroupUuid, pkMemberUuid)`. Returns the generation when [entityId]
/// matches a derived incarnation for the edge, else `null` (e.g. a non-PK
/// fallback id). Walks 0..[maxGenerations); entry ids are opaque shas, so the
/// only way to recover the generation is to re-derive and compare.
int? parseEntryIncarnationGeneration(
  String entityId, {
  required String? pkGroupUuid,
  required String? pkMemberUuid,
  int maxGenerations = 64,
}) {
  for (var gen = 0; gen < maxGenerations; gen++) {
    if (deriveEntryIncarnationEntityId(pkGroupUuid, pkMemberUuid, gen) ==
        entityId) {
      return gen;
    }
  }
  return null;
}
