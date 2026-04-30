/// String tags persisted in `fronting_sessions.pk_import_source` to record
/// which PluralKit import path produced a row.
///
/// Tags drive push eligibility and tombstone semantics:
/// - [pkImportSourceFile]: row came from a `pk;export` file with no
///   API match. Never pushed back: PK already had it (it's in the user's
///   own export) or PK doesn't recognize the source switch id at all.
/// - [pkImportSourceFileApi]: row came from a file import that the
///   token-backed reconciliation matched against an API switch. Pushable
///   under the same rules as any other API-sourced row.
///
/// `pk_import_source == null` rows pre-date this column and are gated by
/// a creation-time cutoff inside `pluralkit_sync_service.dart`.
library;

const String pkImportSourceFile = 'file';
const String pkImportSourceFileApi = 'file_api';
