/// Safely decodes a stored enum index without crashing on out-of-range
/// values.
///
/// A peer running a newer build can persist an enum index that hasn't been
/// added to this device's build yet (e.g. a future view-mode value). Using
/// `Enum.values[index]` directly throws `RangeError`; this helper falls
/// back to the supplied default instead so the row still loads.
T enumByIndex<T extends Enum>(int? raw, List<T> values, T fallback) {
  if (raw == null) return fallback;
  if (raw < 0 || raw >= values.length) return fallback;
  return values[raw];
}
