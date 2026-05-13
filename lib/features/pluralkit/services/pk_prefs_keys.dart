/// Shared-preferences key constants for the PluralKit feature.
///
/// All keys are defined here so write sites (controllers) and read sites (UI)
/// reference the same strings without duplication.
abstract class PkPrefsKeys {
  /// Set when the user chose "Decide later" in the Who's fronting? sheet.
  /// Per-system so reconnects to a different PK system get a clean slate.
  static String firstSyncDeferred(String systemId) =>
      'pk_first_sync_deferred_$systemId';
}
