/// Curated palette for scale-friendly glyphs. Each entry is single-codepoint
/// (no ZWJ sequences, no skin-tone variants), renders at a similar visual
/// baseline across iOS/Android, and reads as a "filled" intensity marker.
/// A "Custom" entry alongside this palette lets users pick anything from the
/// system emoji keyboard.
const List<String> kScaleEmojiPalette = [
  '⭐', '❤️', '🔥', '⚡', '🌙', '☀️',
  '💧', '🌱', '🎯', '🍕', '🎵', '✨',
  '🟩', '⬜',
];
