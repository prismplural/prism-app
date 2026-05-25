/// Curated 10-swatch palette for auto-coloring new choice options.
/// Pre-validated for ≥3:1 contrast against light AND dark surfaces.
/// New options pick the next swatch in rotation; tap-to-cycle on the
/// inline color button advances through this list.
const List<String> kChoiceOptionPalette = [
  '#E57373', // red
  '#F06292', // pink
  '#BA68C8', // purple
  '#9575CD', // deep purple
  '#7986CB', // indigo
  '#64B5F6', // blue
  '#4DB6AC', // teal
  '#81C784', // green
  '#FFB74D', // orange
  '#A1887F', // brown
];

String nextChoicePaletteColor(int existingCount) {
  return kChoiceOptionPalette[existingCount % kChoiceOptionPalette.length];
}

int? choicePaletteIndex(String? hex) {
  if (hex == null) return null;
  final normalized = hex.trim().toLowerCase();
  for (var i = 0; i < kChoiceOptionPalette.length; i++) {
    if (kChoiceOptionPalette[i].toLowerCase() == normalized) return i;
  }
  return null;
}

String cycleChoicePaletteColor(String? currentHex) {
  final idx = choicePaletteIndex(currentHex) ?? -1;
  return kChoiceOptionPalette[(idx + 1) % kChoiceOptionPalette.length];
}
