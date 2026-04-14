// Guard: flags stock Material widgets that have Prism replacements.
//
// FAILS on components with explicit Prism alternatives (agents must use them).
// WARNS on components without replacements yet (informational only).
//
// Run from app/: flutter test test/shared/widgets/stock_material_guard_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Stock Material component → Prism replacement.
///
/// If a pattern appears in non-excluded source, the test fails.
const _banned = <String, String>{
  // Buttons
  r'\bElevatedButton\b': 'PrismButton',
  r'\bTextButton\b': 'PrismButton',
  r'\bOutlinedButton\b': 'PrismButton',
  r'\bFilledButton\b': 'PrismButton',

  // Dialogs & sheets
  r'\bAlertDialog\b': 'PrismDialog',
  r'\bSimpleDialog\b': 'PrismDialog',
  r'\bshowDialog\b': 'PrismDialog.show / PrismDialog.confirm',
  r'\bshowModalBottomSheet\b': 'PrismSheet.show',

  // Toasts / snackbars
  r'\bSnackBar\b': 'PrismToast',
  r'\bScaffoldMessenger\b': 'PrismToast',

  // Lists & rows
  r'\bListTile\b': 'PrismListRow',

  // Surfaces
  r'\bCard\(': 'PrismSurface / PrismSectionCard',

  // App bars
  r'\bAppBar\b': 'PrismTopBar / PrismGlassAppBar',
  r'\bSliverAppBar\b': 'SliverPinnedTopBar',

  // Spinners
  r'\bCircularProgressIndicator\b': 'PrismSpinner',

  // Dropdowns & menus
  r'\bDropdownButton\b': 'PrismSelect',
  r'\bDropdownMenu\b': 'PrismSelect',
  r'\bPopupMenuButton\b': 'PrismPopupMenu / BlurPopupAnchor',

  // Segmented / chips
  r'\bSegmentedButton\b': 'PrismSegmentedControl',
  r'\bChoiceChip\b': 'PrismChip',
  r'\bFilterChip\b': 'PrismChip',
  r'\bInputChip\b': 'PrismChip',
  r'\bActionChip\b': 'PrismChip',

  // Expandable
  r'\bExpansionTile\b': 'PrismExpandableSection',

  // Pickers
  r'\bshowDatePicker\b': 'showPrismDatePicker',
  r'\bshowTimePicker\b': 'showPrismTimePicker',
};

/// Stock Material components without Prism replacements yet.
/// Matches are printed as warnings but don't fail the test.
const _warnOnly = <String, String>{
  r'\bTooltip\b(?!\w)': 'No Prism replacement yet',
  r'\bBadge\b(?!\w)': 'No Prism replacement yet (consider PrismPill)',
  r'\bTabBar\b': 'No Prism replacement yet',
  r'\bNavigationBar\b': 'No Prism replacement yet (AppShell has custom nav)',
  r'\bNavigationRail\b': 'No Prism replacement yet',
  r'\bDrawer\b(?!\w)': 'No Prism replacement yet',
  r'\bStepper\b(?!\w)': 'No Prism replacement yet',
  r'\bDataTable\b': 'No Prism replacement yet',
  r'\bSlider\b(?!\w)': 'No Prism replacement yet',
  r'\bRangeSlider\b': 'No Prism replacement yet',
  r'\bLinearProgressIndicator\b': 'No Prism replacement yet (determinate progress)',
  r'\bBottomSheet\b(?!\w)': 'No Prism replacement yet (use PrismSheet)',
  r'\bChip\b(?!\w)': 'No Prism replacement yet (consider PrismChip)',
};

/// Paths that may legitimately use stock Material components.
///
/// - shared/widgets/ — Prism widgets wrap stock Material internally
/// - shared/theme/   — theme definitions reference Material classes
/// - app.dart        — MaterialApp itself
/// - l10n/           — generated localization strings, not widget code
final _excludedPaths = <String>[
  'lib/shared/widgets/',
  'lib/shared/theme/',
  'lib/app.dart',
  'lib/l10n/',
];

/// Files with known legitimate exceptions. Each entry maps a file path suffix
/// to the patterns it's allowed to use, with a reason.
///
/// Add entries here when stock Material usage is intentional and justified.
final _allowlist = <String, Set<String>>{
  // ImageViewer is a standalone fullscreen overlay — AppBar is appropriate here
  // because PrismTopBar expects the Prism page scaffold context.
  'features/chat/widgets/media/image_viewer.dart': {r'\bAppBar\b'},
};

/// Strip regex anchors for human-readable output.
String _humanLabel(String pattern) =>
    pattern.replaceAll(r'\b', '').replaceAll(r'(?!\w)', '').replaceAll(r'\(', '(');

bool _isExcluded(String path) =>
    path.endsWith('.g.dart') ||
    path.endsWith('.freezed.dart') ||
    _excludedPaths.any(path.contains);

void main() {
  late List<File> sourceFiles;

  setUpAll(() {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'Run from app/ directory');
    sourceFiles = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !_isExcluded(f.path))
        .toList();
  });

  group('Stock Material guard', () {
    test('no banned stock Material components outside Prism widgets', () {
      final violations = <String>[];

      for (final file in sourceFiles) {
        final content = file.readAsStringSync();
        final relativePath =
            file.path.startsWith('./') ? file.path.substring(2) : file.path;

        for (final entry in _banned.entries) {
          // Check allowlist.
          if (_allowlist.entries.any((a) =>
              relativePath.endsWith(a.key) && a.value.contains(entry.key))) {
            continue;
          }

          final regex = RegExp(entry.key);
          final lines = content.split('\n');
          for (var i = 0; i < lines.length; i++) {
            final line = lines[i].trimLeft();
            // Skip comments and imports.
            if (line.startsWith('//') || line.startsWith('import ')) continue;
            if (regex.hasMatch(lines[i])) {
              violations.add(
                '$relativePath:${i + 1}  '
                '${_humanLabel(entry.key)}  '
                '→  use ${entry.value}',
              );
            }
          }
        }
      }

      if (violations.isNotEmpty) {
        fail(
          'Found ${violations.length} stock Material component(s) that have '
          'Prism replacements:\n\n${violations.join('\n')}\n\n'
          'If usage is intentional, add the file to _allowlist with a reason.',
        );
      }
    });

    test('warn on stock Material components without replacements', () {
      final warnings = <String>[];

      for (final file in sourceFiles) {
        final content = file.readAsStringSync();
        final relativePath =
            file.path.startsWith('./') ? file.path.substring(2) : file.path;

        for (final entry in _warnOnly.entries) {
          final regex = RegExp(entry.key);
          final lines = content.split('\n');
          for (var i = 0; i < lines.length; i++) {
            final line = lines[i].trimLeft();
            if (line.startsWith('//') || line.startsWith('import ')) continue;
            if (regex.hasMatch(lines[i])) {
              warnings.add(
                '$relativePath:${i + 1}  '
                '${_humanLabel(entry.key)}  '
                '— ${entry.value}',
              );
            }
          }
        }
      }

      if (warnings.isNotEmpty) {
        // ignore: avoid_print
        print(
          '⚠ ${warnings.length} stock Material component(s) without Prism '
          'replacements:\n${warnings.join('\n')}',
        );
      }
    });
  });
}
