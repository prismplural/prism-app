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
/// All four values are truly random RFC 4122 v4 UUIDs (variant nibble in
/// [89ab]).  The `uuid` package's `UuidParsing.parse()` validates the variant
/// field before accepting a namespace string; passing an invalid UUID throws a
/// `FormatException` at the call site.
///
/// To add a new derivation domain, introduce a NEW namespace constant here;
/// never repurpose an existing one.
library;

/// Namespace for PluralKit-imported fronting session ids.
///
/// Key format: `"${entry_switch_id}:${member_pk_uuid}"`
/// Produces one Prism row per (PK entry-switch UUID × member UUID) pair.
const String pkFrontingNamespace = 'cbf8841f-5ec5-4d77-a356-2aebdeab0e4a';

/// Namespace for Simply Plural–imported fronting session ids.
///
/// Key format: SP `_id` string from the source export.
/// Used for new SP rows only — existing rows with random v4 ids are looked up
/// via `sp_id_map` and keep their original ids (§2.6).
const String spFrontingNamespace = '07fa8466-1914-4510-9f1c-d1223d2b8e60';

/// Namespace for migration-expanded co-fronter rows.
///
/// Key format: `"${legacy_session_id}:${member_id}"`
/// Used when a native Prism session with co-fronters is fanned out into one
/// row per member.  The primary member's row keeps the legacy id; additional
/// co-fronter rows are derived from this namespace.  Paired devices migrating
/// concurrently produce identical ids (§2.6, §4.1 step 4).
const String migrationFrontingNamespace = 'ca045f95-3051-4412-b7b4-2935f96b895a';

/// Namespace for split-operation rows.
///
/// Key format: `"${original_id}:${P_end_isoformat}"`
/// Used when "delete this period" splits a session that spans the period
/// boundary.  The new row (from P_end onwards) gets a deterministic id so
/// concurrent splits on two devices converge on the same result (§3.1).
const String splitNamespace = '2d806d71-c56c-49ef-a185-383489e78a3c';
