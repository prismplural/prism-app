import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-level invariant: `clearKeychainIfFreshInstall()` must remain
/// gated on `kReleaseMode` in `lib/main.dart`.
///
/// Why this matters:
/// - Removing the call entirely would re-introduce the security regression
///   the guard exists to prevent (a reinstalled app on a sold/stolen phone
///   silently re-attaching to the previous user's sync group via the
///   surviving keychain entries).
/// - Unwrapping the gate would re-introduce the dev-rebuild misfire where
///   every `flutter run` reinstall wipes sync credentials.
/// - Replacing the gate with a different condition (e.g. `kDebugMode`) would
///   invert the logic and either break dev or break prod.
///
/// See `docs/plans/skip-fresh-install-guard-in-non-release-builds.md`.
void main() {
  test(
    'clearKeychainIfFreshInstall call in main.dart stays gated on '
    'kReleaseMode',
    () {
      final source = File('lib/main.dart').readAsStringSync();

      // Strip line comments so a commented-out call cannot fool the matcher.
      // (No block comments in main.dart today; if that changes, expand this
      // stripper.)
      final uncommented = source
          .split('\n')
          .map((l) => l.replaceFirst(RegExp(r'\s*//.*$'), ''))
          .join('\n');

      // Exactly one real call site must exist.
      final callMatches =
          RegExp(r'\bclearKeychainIfFreshInstall\s*\(\s*\)')
              .allMatches(uncommented)
              .length;
      expect(
        callMatches,
        equals(1),
        reason:
            'main.dart must contain exactly one (uncommented) call to '
            'clearKeychainIfFreshInstall(). Found $callMatches. The guard '
            'is real (do not delete it) but must not be duplicated outside '
            'the kReleaseMode gate. See '
            'docs/plans/skip-fresh-install-guard-in-non-release-builds.md',
      );

      // That single call must be the sole statement inside an
      // `if (kReleaseMode) { await clearKeychainIfFreshInstall(); }` block.
      final guardedPattern = RegExp(
        r'if\s*\(\s*kReleaseMode\s*\)\s*\{\s*'
        r'await\s+clearKeychainIfFreshInstall\(\)\s*;\s*'
        r'\}',
        multiLine: true,
        dotAll: true,
      );
      expect(
        guardedPattern.hasMatch(uncommented),
        isTrue,
        reason:
            'clearKeychainIfFreshInstall() in main.dart must be the sole '
            'statement inside `if (kReleaseMode) { await ...(); }`. '
            'Without this gate, every `flutter run` reinstall wipes sync '
            'credentials. See '
            'docs/plans/skip-fresh-install-guard-in-non-release-builds.md '
            'for the security analysis.',
      );
    },
  );
}
