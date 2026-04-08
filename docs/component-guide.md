# Prism Component Library

Quick reference for the shared widget library in `lib/shared/widgets/`.

## Component Inventory

| Widget | File | When to use |
|--------|------|-------------|
| `PrismPageScaffold` | `prism_page_scaffold.dart` | Page-level scaffold with consistent padding, top bar slot, and safe area handling |
| `PrismTopBar` | `prism_top_bar.dart` | Standard top bar with title, optional subtitle, and leading/trailing action slots |
| `PrismTopBarAction` | `prism_top_bar_action.dart` | Glass icon button sized for `PrismTopBar` leading/trailing slots |
| `PrismGlassAppBar` | `prism_glass_app_bar.dart` | Convenience wrapper around `PrismTopBar` for glass-styled screens |
| `PrismGlassIconButton` | `prism_glass_icon_button.dart` | Circular icon button with frosted glass background and scale feedback |
| `PrismGlassInputBar` | `prism_glass_input_bar.dart` | Rounded glass container for composer bars, search fields, and inline inputs |
| `PrismButton` | `prism_button.dart` | Styled button with subtle/filled/destructive tones, loading state, and scale feedback |
| `PrismIconButton` | `prism_button.dart` | Circular icon button with tinted background, tooltip, and long-press support |
| `PrismInlineIconButton` | `prism_inline_icon_button.dart` | Lightweight icon action for inline row controls, compact headers, and editor affordances |
| `PrismFieldIconButton` | `prism_field_icon_button.dart` | Compact icon button for text-field suffixes and other tight inline field actions |
| `PrismTextField` | `prism_text_field.dart` | Text input wrapper with standard and borderless styles; use instead of raw `TextField` |
| `PrismSelect` | `prism_select.dart` | Field-styled select/dropdown with frosted popup rows; supports avatars, subtitles, and custom leading widgets |
| `PrismCheckboxRow` | `prism_checkbox_row.dart` | Selectable row with built-in checkbox; use for multi-select lists and confirmation rows |
| `PrismExpandableSection` | `prism_expandable_section.dart` | Surface-backed expandable section for disclosure rows and collapsible record/detail blocks |
| `PrismSurface` | `prism_surface.dart` | Rounded surface container with subtle/strong/accent tones; base for cards and groups |
| `PrismSectionCard` | `prism_section_card.dart` | Grouped content container (wraps `PrismSurface`); use for related rows or controls |
| `PrismSection` | `prism_section.dart` | Section shell with title, optional description, and footer; use for labeled groups |
| `PrismSectionHeader` | `prism_surface.dart` | Compact all-caps section label for lightweight headings |
| `PrismListRow` | `prism_list_row.dart` | Row primitive for navigation items, metadata, and grouped list content |
| `PrismSettingsRow` | `prism_settings_row.dart` | Settings-oriented row with tinted icon badge, subtitle, and optional chevron |
| `PrismPill` | `prism_pill.dart` | Compact metadata pill for counts, tags, and status indicators |
| `PrismSheet` | `prism_sheet.dart` | Styled bottom sheet with drag handle, title/subtitle, and action row |
| `PrismDialog` | `prism_dialog.dart` | Styled dialog with `show()` for custom content and `confirm()` for confirmations |

## When to Use Prism Components vs Raw Material

### Always prefer Prism wrappers

| Instead of | Use |
|------------|-----|
| `Scaffold` + `AppBar` | `PrismPageScaffold` + `PrismTopBar` |
| `ListTile` | `PrismListRow` (general) or `PrismSettingsRow` (settings screens) |
| `Card` | `PrismSurface` or `PrismSectionCard` for grouped content |
| `ElevatedButton` / `TextButton` | `PrismButton` with appropriate `PrismButtonTone` |
| `IconButton` | `PrismInlineIconButton`, `PrismIconButton`, or `PrismGlassIconButton` depending on density and context |
| `TextField` suffix `IconButton` | `PrismFieldIconButton` |
| `TextField` / `TextFormField` | `PrismTextField` |
| Field-style `DropdownButton` / `DropdownButtonFormField` | `PrismSelect` |
| `PrismListRow` + trailing/leading `Checkbox` | `PrismCheckboxRow` |
| `ExpansionTile` | `PrismExpandableSection` |
| `showModalBottomSheet(...)` | `PrismSheet.show(...)` |
| `showDialog(...)` | `PrismDialog.show(...)` or `PrismDialog.confirm(...)` |

### Keep raw Material for

These controls are complex, platform-native, or still intentionally raw:

- `Switch`, `Slider`, standalone `Checkbox`, `Radio`
- `DatePicker`, `TimePicker`
- `SearchDelegate`
- `PopupMenuButton` (when `BlurPopupAnchor` is not suitable)
- `TabBar` / `TabBarView`
- `SnackBar` (via `ScaffoldMessenger`)
- `Tooltip`, `Divider`, `CircularProgressIndicator`

## Design Tokens

All spacing, radius, blur, and animation values live in `lib/shared/theme/prism_tokens.dart`.

### Radius

| Token | Value | Usage |
|-------|-------|-------|
| `radiusSmall` | 12 | Small chips, badges |
| `radiusMedium` | 16 | Cards, surfaces, row ink wells |
| `radiusLarge` | 20 | Sheets, dialogs |
| `radiusXLarge` | 24 | Large containers |
| `radiusPill` | 30 | Pills, fully rounded elements |
| `radiusNav` | 32 | Navigation bar |

### Spacing

| Token | Value | Usage |
|-------|-------|-------|
| `pageHorizontalPadding` | 16 | Horizontal page margins |
| `sectionSpacing` | 24 | Gap between sections |
| `sectionSpacingCompact` | 12 | Tighter section gap |
| `topBarHeight` | 66 | Standard top bar height |
| `topBarActionSize` | 44 | Top bar action button hit area |

### Glass blur

| Token | Value | Usage |
|-------|-------|-------|
| `glassBlurSoft` | 14 | Subtle background blur |
| `glassBlurMedium` | 20 | Standard glass treatment |
| `glassBlurStrong` | 30 | Heavy blur (nav bar, overlays) |

### Animation

| Token | Value | Usage |
|-------|-------|-------|
| `pressDuration` | 100ms | Button press scale feedback |
| `shortAnimationDuration` | 150ms | Quick transitions |
| `mediumAnimationDuration` | 200ms | Standard transitions |

### Preset EdgeInsets

| Token | Usage |
|-------|-------|
| `pagePadding` | Horizontal-only page padding (16px each side) |
| `sectionPadding` | Full section padding (16px horizontal, 24px top, 12px bottom) |
| `topBarPadding` | Top bar horizontal padding (12px each side) |
