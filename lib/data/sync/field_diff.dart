/// Returns the subset of [next] whose values differ from [previous].
///
/// Strips `is_deleted` unconditionally — that flag is owned by
/// `syncRecordDelete` (tombstone) and `syncRecordCreate` (resurrection on
/// re-create). Emitting `is_deleted: false` via `syncRecordUpdate` would
/// stamp a fresh per-field HLC on the tombstone field and could resurrect
/// a deleted row.
///
/// Pairs with each repo's existing `_<entity>Fields(domain)` helper:
/// ```
/// final prev = _completionFields(previous);
/// final next = _completionFields(updated);
/// final changed = diffSyncFields(prev, next);
/// if (changed.isEmpty) return;
/// await syncRecordUpdate(table, id, changed);
/// ```
///
/// `modified_at` is included naturally when it differs (the notifier
/// always bumps it before persisting), so we don't special-case it.
///
/// Field values in this codebase are scalar (int, String, bool, ISO date
/// string, JSON-encoded string for nested data). `==` is sufficient for the
/// scalar types and string-encoded JSON. **Caveat for future migrations:**
/// callers passing JSON-encoded list values are responsible for canonicalizing
/// key/element order — `==` on `'[1,2,3]'` vs `'[3,2,1]'` is order-sensitive.
/// This is a non-issue for `_completionFields` (no list fields) but a footgun
/// for `_habitFields.weekly_days` if/when that repo migrates to use this helper.
Map<String, dynamic> diffSyncFields(
  Map<String, dynamic> previous,
  Map<String, dynamic> next,
) {
  final out = <String, dynamic>{};
  for (final entry in next.entries) {
    if (entry.key == 'is_deleted') continue;
    if (previous[entry.key] != entry.value) {
      out[entry.key] = entry.value;
    }
  }
  return out;
}
