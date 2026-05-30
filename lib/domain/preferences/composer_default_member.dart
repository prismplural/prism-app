/// How the default "acting as" member is chosen when a composer surface (chat,
/// board post) opens.
///
/// Prism has no primary/secondary fronter — every front is an equal, independent
/// timeline — so the composer needs a policy for which fronter to pre-select.
enum ComposerDefaultMember {
  /// Pre-select the member whose front started most recently (legacy behaviour).
  latestFronter('latest_fronter'),

  /// Pre-select whoever the user last acted as, persisted on this device.
  lastUsed('last_used'),

  /// Open the member picker on entry so the user taps a member each time. A
  /// safe fallback is still selected underneath so the chat viewer gate never
  /// sees a null speaking-as member.
  askEachTime('ask_each_time');

  const ComposerDefaultMember(this.storageValue);

  /// Stable string persisted in preferences. Must not change once shipped.
  final String storageValue;

  static const ComposerDefaultMember defaultValue =
      ComposerDefaultMember.latestFronter;

  /// The full set of valid storage strings — used as the preference codec's
  /// allow-list.
  static Set<String> get storageValues =>
      {for (final v in ComposerDefaultMember.values) v.storageValue};

  /// Decodes a stored string back to an enum, falling back to [defaultValue]
  /// for unknown/legacy values so a bad write can never break the composer.
  static ComposerDefaultMember fromStorage(String? value) {
    for (final v in ComposerDefaultMember.values) {
      if (v.storageValue == value) return v;
    }
    return defaultValue;
  }
}
