import 'dart:async';
import 'dart:convert';

import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/core/database/sync_quarantine_kinds.dart';
import 'package:prism_plurality/core/sync/sync_quarantine.dart';

/// The Dart half of the durable consumer-delivery journal.
///
/// The Rust engine journals one row per winning pulled op inside the SAME
/// storage transaction that advances the pull cursor / applied_ops /
/// field_versions (see `take_undelivered_changes` / `ack_consumer_deliveries`
/// in prism-sync-ffi). This module drains that journal into the consumer Drift
/// DB and acks each chunk ONLY AFTER its Drift transaction commits, so a pulled
/// winner survives process death between the Rust apply-commit and the Dart
/// consumer-DB write. The old `RemoteChanges` event becomes purely advisory: an
/// event is a wake-up to drain, never the data source.

/// One coalesced consumer-delivery, mirroring the shape of a `RemoteChanges`
/// changeset entry (`table` / `entity_id` / `is_delete` / `fields`) so it can
/// flow through the existing [applyRemoteChanges] apply pipeline unchanged.
class ConsumerDelivery {
  const ConsumerDelivery({
    required this.id,
    required this.table,
    required this.entityId,
    required this.isDelete,
    required this.fields,
  });

  /// Highest journal id that contributed to this coalesced entry. Diagnostics
  /// only — acking is by the chunk's [DrainChunk.maxId].
  final int id;
  final String table;
  final String entityId;
  final bool isDelete;
  final Map<String, dynamic> fields;

  /// The change map shape consumed by [applyRemoteChanges].
  Map<String, dynamic> toChange() => {
    'table': table,
    'entity_id': entityId,
    'is_delete': isDelete,
    'fields': fields,
  };
}

/// One decoded `take_undelivered_changes` chunk.
class DrainChunk {
  const DrainChunk({
    required this.deliveries,
    required this.maxId,
    required this.spillUpToId,
    required this.overCap,
  });

  factory DrainChunk.fromJson(Map<String, dynamic> json) {
    final rawDeliveries = (json['deliveries'] as List?) ?? const [];
    final deliveries = rawDeliveries
        .cast<Map<String, dynamic>>()
        .map(
          (d) => ConsumerDelivery(
            id: (d['id'] as num?)?.toInt() ?? 0,
            table: d['table'] as String,
            entityId: d['entity_id'] as String,
            isDelete: d['is_delete'] as bool? ?? false,
            fields: (d['fields'] as Map?)?.cast<String, dynamic>() ?? {},
          ),
        )
        .toList();
    return DrainChunk(
      deliveries: deliveries,
      maxId: (json['max_id'] as num?)?.toInt() ?? 0,
      spillUpToId: (json['spill_up_to_id'] as num?)?.toInt() ?? 0,
      overCap: json['over_cap'] as bool? ?? false,
    );
  }

  final List<ConsumerDelivery> deliveries;
  final int maxId;
  final int spillUpToId;
  final bool overCap;

  bool get isEmpty => deliveries.isEmpty;
}

/// Outcome of a full [drainRemoteDeliveries] run.
class DrainResult {
  const DrainResult({
    required this.rowsApplied,
    required this.rowsSpilled,
    required this.chunksAcked,
    required this.aborted,
    this.touchedTables = const {},
  });

  final int rowsApplied;

  /// Oldest-over-cap rows routed to the payload-bearing quarantine lane rather
  /// than applied. Hard retention cap: never unbounded growth, never silent
  /// loss (the full field payload rides into `sync_quarantine.receivedValue`).
  final int rowsSpilled;
  final int chunksAcked;

  /// True when the loop short-circuited via [shouldAbort] (e.g. revocation,
  /// handle disposed) without draining the journal to empty.
  final bool aborted;

  /// The set of entity tables that the applied deliveries touched. Lets
  /// downstream triggers (e.g. media hydration) re-scan only when a relevant
  /// table actually changed, instead of after every non-empty drain — restores
  /// the narrow `media_attachments` gate that gated the whole-table walk.
  final Set<String> touchedTables;
}

/// How many rows to take per chunk. Matches the engine apply chunk size so a
/// single chunk maps to one Drift transaction in [applyRemoteChanges].
const int kRemoteDeliveryChunkSize = 200;

/// Drain the durable consumer-delivery journal into the consumer Drift DB,
/// acking each chunk only AFTER its Drift transaction commits.
///
/// The loop is: `take(chunkSize)` -> apply (and quarantine over-cap spill) in a
/// Drift transaction -> `ack(maxId)`. Because the ack fires strictly after the
/// commit, a crash mid-loop leaves the un-acked journal rows in Rust to be
/// re-drained on the next invocation — at-least-once delivery with idempotent
/// re-apply (CRDT upsert of winners).
///
/// [take] / [ack] / [applyChanges] / [quarantineSpill] are injected so this
/// core is testable without the FFI or a live engine. [shouldAbort] is checked
/// before each chunk so a revoked / disposed handle stops the loop cleanly.
///
/// [onProgress] is invoked once per drained chunk with the running
/// `(rowsApplied, rowsSpilled)` totals so a long-running drain can keep an
/// idle watchdog alive (the bootstrap path forwards it to the strict-apply
/// coordinator's progress signal — without it a multi-minute large-system
/// snapshot apply would silently hit the pairing idle watchdog).
Future<DrainResult> runRemoteDeliveryDrain({
  required Future<DrainChunk> Function(int limit) take,
  required Future<void> Function(int upToId) ack,
  required Future<int> Function(List<ConsumerDelivery> deliveries) applyChanges,
  required Future<void> Function(List<ConsumerDelivery> spill) quarantineSpill,
  bool Function()? shouldAbort,
  void Function(int rowsApplied, int rowsSpilled)? onProgress,
  int chunkSize = kRemoteDeliveryChunkSize,
}) async {
  var rowsApplied = 0;
  var rowsSpilled = 0;
  var chunksAcked = 0;
  final touchedTables = <String>{};

  // Bound the loop defensively. The journal is drained to empty in practice,
  // but a pathological producer (continuous live pulls) must not let this loop
  // run unbounded inside one invocation — the next trigger re-drains.
  const maxChunksPerRun = 10000;
  for (var i = 0; i < maxChunksPerRun; i++) {
    if (shouldAbort?.call() ?? false) {
      return DrainResult(
        rowsApplied: rowsApplied,
        rowsSpilled: rowsSpilled,
        chunksAcked: chunksAcked,
        aborted: true,
        touchedTables: touchedTables,
      );
    }

    final chunk = await take(chunkSize);
    if (chunk.isEmpty) break;

    // Partition over-cap spill (oldest rows, id <= spillUpToId) from rows to
    // apply normally. Spill is only present when the backlog exceeded the
    // retention cap; the full payload is carried into quarantine so it is held
    // durably rather than dropped.
    final toApply = <ConsumerDelivery>[];
    final toSpill = <ConsumerDelivery>[];
    if (chunk.overCap && chunk.spillUpToId > 0) {
      for (final d in chunk.deliveries) {
        if (d.id <= chunk.spillUpToId) {
          toSpill.add(d);
        } else {
          toApply.add(d);
        }
      }
    } else {
      toApply.addAll(chunk.deliveries);
    }

    // Both the apply and the spill-quarantine must durably commit BEFORE the
    // ack — otherwise an ack-then-crash would delete the journal row without a
    // Drift write or a quarantine row (silent loss). Apply first, then spill.
    if (toApply.isNotEmpty) {
      rowsApplied += await applyChanges(toApply);
      for (final d in toApply) {
        touchedTables.add(d.table);
      }
    }
    if (toSpill.isNotEmpty) {
      await quarantineSpill(toSpill);
      rowsSpilled += toSpill.length;
    }

    // Commits have landed; safe to ack the chunk high-water now.
    await ack(chunk.maxId);
    chunksAcked++;

    // Heartbeat once per drained chunk so a long apply keeps the bootstrap
    // idle watchdog alive between chunks (intra-chunk progress is reported by
    // the apply callback threaded into `applyChanges`).
    onProgress?.call(rowsApplied, rowsSpilled);
  }

  return DrainResult(
    rowsApplied: rowsApplied,
    rowsSpilled: rowsSpilled,
    chunksAcked: chunksAcked,
    aborted: false,
    touchedTables: touchedTables,
  );
}

/// Route over-cap journal spill rows into the payload-bearing quarantine lane.
/// The full field payload is preserved in `sync_quarantine.receivedValue` so a
/// future repair/replay pass can re-materialize them — the hard retention cap
/// bounds engine-DB growth without dropping data.
Future<void> quarantineConsumerDeliverySpill(
  SyncQuarantineService quarantine,
  List<ConsumerDelivery> spill,
) async {
  for (final d in spill) {
    try {
      await quarantine.quarantineField(
        entityType: d.table,
        entityId: d.entityId,
        fieldName: null,
        expectedType: kConsumerDeliverySpillExpectedType,
        receivedType: d.isDelete
            ? kConsumerDeliverySpillDeleteType
            : kConsumerDeliverySpillApplyType,
        receivedValue: jsonEncode(d.fields),
        errorMessage:
            '$kConsumerDeliverySpillErrorPrefix; row spilled to '
            'quarantine to bound engine-DB growth (id=${d.id})',
      );
    } catch (e, st) {
      // A spill quarantine-write failure is reported but does not abort the
      // drain: the row is NOT acked yet (we throw to keep it in the journal),
      // so it is re-tried on the next drain rather than lost.
      ErrorReportingService.instance.report(
        'Failed to quarantine over-cap consumer delivery '
        '${d.table}/${d.entityId}: $e',
        severity: ErrorSeverity.error,
        stackTrace: st,
      );
      rethrow;
    }
  }
}
