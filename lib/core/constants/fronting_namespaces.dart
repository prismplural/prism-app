/// Namespace UUIDs for deterministic v5 UUID derivation across the fronting
/// refactor (docs/plans/fronting-per-member-sessions.md §2.6, §3.1).
///
/// ⚠️  IMMUTABLE FOREVER.  Once shipped, these values MUST NEVER change.
/// The entire historical id space for PK-imported sessions, SP-imported
/// sessions, migration-expanded rows, and split rows depends on these
/// namespaces.  Changing a namespace would cause every device that re-imports
/// or re-migrates to generate different ids, producing duplicate rows in the
/// CRDT rather than updating existing ones.
///
/// To add a new derivation domain, introduce a NEW namespace constant here;
/// never repurpose an existing one.
library;

/// Namespace for PluralKit-imported fronting session ids.
///
/// Key format: `"${entry_switch_id}:${member_pk_uuid}"`
/// Produces one Prism row per (PK entry-switch UUID × member UUID) pair.
const String pkFrontingNamespace = 'a3c4e6f8-1b2d-4e5f-8a9b-c0d1e2f3a4b5';

/// Namespace for Simply Plural–imported fronting session ids.
///
/// Key format: SP `_id` string from the source export.
/// Used for new SP rows only — existing rows with random v4 ids are looked up
/// via `sp_id_map` and keep their original ids (§2.6).
const String spFrontingNamespace = 'b4d5f7a9-2c3e-4f6a-9b0c-d1e2f3a4b5c6';

/// Namespace for migration-expanded co-fronter rows.
///
/// Key format: `"${legacy_session_id}:${member_id}"`
/// Used when a native Prism session with co-fronters is fanned out into one
/// row per member.  The primary member's row keeps the legacy id; additional
/// co-fronter rows are derived from this namespace.  Paired devices migrating
/// concurrently produce identical ids (§2.6, §4.1 step 4).
const String migrationFrontingNamespace = 'c5e6a8b0-3d4f-4a7b-0c1d-e2f3a4b5c6d7';

/// Namespace for split-operation rows.
///
/// Key format: `"${original_id}:${P_end_isoformat}"`
/// Used when "delete this period" splits a session that spans the period
/// boundary.  The new row (from P_end onwards) gets a deterministic id so
/// concurrent splits on two devices converge on the same result (§3.1).
const String splitNamespace = 'd6f7b9c1-4e5a-4b8c-1d2e-f3a4b5c6d7e8';
