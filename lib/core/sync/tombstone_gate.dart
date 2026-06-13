import 'package:flutter/foundation.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

/// Reads the LWW-winning JSON-encoded value of a single field directly from the
/// Rust engine's local storage (mirrors the FFI `read_field_value`), or `null`
/// when no `field_version` row exists. Injected so the gate is testable without
/// a live engine.
typedef ReadFieldValue =
    Future<String?> Function(String table, String entityId, String field);

/// The CRDT field whose value carries the absorbing tombstone marker.
const String _deletedField = 'is_deleted';

/// A Dart-side view of the Rust engine's absorbing-delete state, plus the
/// "next live incarnation id" minting loop that sits on top of it.
///
/// prism-sync makes `is_deleted` absorbing (a true tombstone is terminal; the
/// sender strips a phantom `is_deleted=false`; the receiver drops every
/// non-`is_deleted` op on a tombstoned entity). The app reuses deterministic
/// entity ids for PK-backed rows, so a local revive of a tombstoned id can
/// never propagate. This gate lets ingress sites ask the engine whether an
/// entity id is already burned and, if so, mint the next *incarnation* id —
/// a fresh id that no peer holds a tombstone for, which deployed peers apply as
/// an ordinary new entity (the sanctioned-revive path).
///
/// `field_versions` are the source of truth: they outlive the Drift consumer
/// row (the TombstonePruner deletes the local consumer row while preserving
/// the `is_deleted` field version), so the gate sees a tombstone even on the
/// reviving device whose Drift row was already hard-deleted.
class TombstoneGate {
  const TombstoneGate(this._readFieldValue);

  /// Builds a gate from a live FFI handle. Returns `null` when no handle is
  /// available (pre-pairing / tests without a real engine) — callers treat a
  /// null gate as "nothing is tombstoned".
  static TombstoneGate? forHandle(ffi.PrismSyncHandle? handle) {
    if (handle == null) return null;
    return TombstoneGate(
      (table, entityId, field) => ffi.readFieldValue(
        handle: handle,
        table: table,
        entityId: entityId,
        field: field,
      ),
    );
  }

  final ReadFieldValue _readFieldValue;

  /// Whether `(table, entityId)` is tombstoned in the engine's merged state.
  ///
  /// Mirrors the Rust strip rule in `client.rs::without_phantom_undelete`: an
  /// `is_deleted` field version whose winning JSON value is anything other than
  /// `"false"` is a tombstone. A missing field version (`null`) is NOT a
  /// tombstone — a fresh incarnation id has no field versions at all, which is
  /// exactly what makes it mintable.
  ///
  /// Fails *open* (returns `false`) on a read error: an ingress site that can't
  /// reach the engine keeps the legacy gen-0 id rather than spuriously bumping
  /// an incarnation. The Rust sender-side strip and the merge.rs receiver
  /// backstop remain the safety net against a phantom undelete.
  Future<bool> isTombstoned(String table, String entityId) async {
    final String? encoded;
    try {
      encoded = await _readFieldValue(table, entityId, _deletedField);
    } catch (_) {
      return false;
    }
    if (encoded == null) return false;
    return encoded.trim() != 'false';
  }

  /// Mint the lowest live incarnation id for a logical entity.
  ///
  /// [deriveForGen] maps a generation `>= 0` to the deterministic entity id for
  /// that incarnation (gen 0 is the legacy id, byte-identical to the historical
  /// derivation). The loop walks gen 0, 1, 2, ... and returns the first id the
  /// gate does not consider tombstoned. Two devices that observed the same
  /// tombstones converge on the same id; a device that has not yet seen a peer's
  /// tombstone may mint a lower generation, but the receiver backstop keeps that
  /// from resurrecting anything and the devices re-converge once the tombstone
  /// propagates.
  ///
  /// [maxGenerations] bounds the loop so a pathological run of tombstones can't
  /// spin forever. Exhausting it throws [TombstoneGateExhausted] rather than
  /// returning a known-burned id: emitting a create into a tombstoned id is a
  /// guaranteed silent no-op fleet-wide (the sender strips is_deleted=false and
  /// every peer drops the op), which is the exact failure this layer exists to
  /// prevent. The caller aborts the revive instead. Unreachable in practice at
  /// 64 generations.
  Future<MintedIncarnation> mintLiveEntityId(
    String table,
    String Function(int gen) deriveForGen, {
    int maxGenerations = 64,
  }) async {
    var gen = 0;
    while (gen < maxGenerations) {
      final candidate = deriveForGen(gen);
      if (!await isTombstoned(table, candidate)) {
        return MintedIncarnation(generation: gen, entityId: candidate);
      }
      gen++;
    }
    throw TombstoneGateExhausted(table, maxGenerations);
  }
}

/// Thrown by [TombstoneGate.mintLiveEntityId] when every generation up to
/// `maxGenerations` is tombstoned. Signals the caller to abort the revive rather
/// than emit a create into a burned id (a silent fleet-wide no-op).
class TombstoneGateExhausted implements Exception {
  const TombstoneGateExhausted(this.table, this.maxGenerations);

  final String table;
  final int maxGenerations;

  @override
  String toString() =>
      'TombstoneGateExhausted($table: all $maxGenerations incarnations '
      'tombstoned)';
}

/// The result of [TombstoneGate.mintLiveEntityId]: the chosen generation and
/// its derived entity id. Both are persisted — the generation onto the row's
/// local-only `sync_generation` column, the id as the emit/delete target.
@immutable
class MintedIncarnation {
  const MintedIncarnation({required this.generation, required this.entityId});

  final int generation;
  final String entityId;

  @override
  bool operator ==(Object other) =>
      other is MintedIncarnation &&
      other.generation == generation &&
      other.entityId == entityId;

  @override
  int get hashCode => Object.hash(generation, entityId);

  @override
  String toString() =>
      'MintedIncarnation(generation: $generation, entityId: $entityId)';
}
