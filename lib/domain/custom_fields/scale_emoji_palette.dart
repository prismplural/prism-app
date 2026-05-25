/// Curated 12-emoji palette for scale-friendly glyphs.
/// Each emoji is single-codepoint (no ZWJ sequences, no skin-tone variants),
/// renders at similar visual baseline across iOS/Android, and reads as a
/// "filled" intensity marker. An "Advanced: any emoji" escape lets users
/// pick anything from the system emoji keyboard, but defaults from this list.
const List<String> kScaleEmojiPalette = [
  '⭐', '❤️', '🔥', '⚡', '🌙', '☀️',
  '💧', '🌱', '🎯', '🍕', '🎵', '✨',
];
