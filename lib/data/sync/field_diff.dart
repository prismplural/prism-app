import 'dart:convert';

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
/// scalar types and string-encoded JSON. **JSON ordering footgun**: callers
/// passing JSON-encoded list values are responsible for canonicalizing
/// element order — `==` on `'[1,2,3]'` vs `'[3,2,1]'` is order-sensitive.
/// For columns that genuinely encode a *set* (order is not semantically
/// meaningful), pipe values through [jsonSet] before storing/encoding so
/// the diff doesn't false-positive on incidental reordering. For columns
/// where order *is* the data (manualOrder lists, nav-bar items, message
/// reactions, conversation participant lists), keep the existing
/// `jsonEncode(list)` — reordering is a real edit.
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

/// JSON-encode an iterable of [Comparable]s as a sorted list, so the
/// resulting string is stable regardless of input order.
///
/// Use for columns that encode a *set* — element order is incidental, not
/// semantic. Without canonicalization, [diffSyncFields] would false-positive
/// on reordered-but-equivalent inputs because it compares encoded strings.
///
/// Confirmed set-semantic columns at time of writing (2026-05-25 audit):
/// - `friends.offered_scopes`, `friends.granted_scopes`
/// - `reminders.weekly_days`
///
/// Everything else stays as ordered `jsonEncode(list)` — for those columns
/// the user's ordering *is* the data, and reordering is a real edit that
/// must surface in the diff.
String jsonSet<T extends Comparable<T>>(Iterable<T> values) {
  final sorted = values.toList()..sort();
  return jsonEncode(sorted);
}
