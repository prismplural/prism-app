/// Secure-storage audit gate.
///
/// Walks the production `lib/` tree and fails the build if any file outside
/// the small allowlist contains a raw call to `flutter_secure_storage`. The
/// only legal entry points are the wrappers in
/// `lib/core/services/secure_storage.dart` and the intentional
/// biometric-bound instance in `lib/core/services/biometric_service.dart`.
///
/// See `docs/0.9.2-secure-storage-remediation.md` §2 for the policy and the
/// rationale.
///
/// Notes for maintainers:
///
/// * `test/` is intentionally NOT scanned. Test fixtures legitimately seed
///   `secureStorage.write(...)` / `FlutterSecureStorage()` directly to stand
///   up plugin mock state — that's an instrumentation concern, not a
///   production-policy violation.
/// * If you need to add a new file to the allowlist, justify it in the PR
///   description and update `_kAllowlistedRelativePaths` below.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// One banned pattern. `label` is used in the failure message; `pattern` is
/// the regex matched against each source file's full contents.
class _BannedPattern {
  const _BannedPattern(this.label, this.pattern);
  final String label;
  final String pattern;
}

/// Patterns we ban outside the allowlist.
///
/// Patterns are intentionally substring-style (no `\b` word boundaries) so
/// `_secureStorage.read` is caught just as `secureStorage.read` is — every
/// alias of the singleton needs to funnel through the same wrappers.
const _bannedPatterns = <_BannedPattern>[
  // Raw secureStorage.read / .readAll / .write / .delete / .deleteAll
  // / .containsKey. The wrappers (safeSecureRead, etc.) live in the
  // allowlisted file and don't match this pattern.
  _BannedPattern(
    'secureStorage.read/readAll/write/delete/deleteAll/containsKey',
    r'secureStorage\.(read|readAll|write|delete|deleteAll|containsKey)\b',
  ),
  // Same shape for the `_storage` private field convention used by services
  // that took an injected `FlutterSecureStorage`.
  _BannedPattern(
    '_storage.read/readAll/write/delete/deleteAll/containsKey',
    r'_storage\.(read|readAll|write|delete|deleteAll|containsKey)\b',
  ),
  _BannedPattern(
    'FlutterSecureStorage() constructor',
    r'FlutterSecureStorage\(',
  ),
  // PrismSecureStore is allowlisted in its own definition file. Other call
  // sites should go through the safe wrappers instead of constructing one.
  _BannedPattern(
    'PrismSecureStore constructor',
    r'PrismSecureStore\b',
  ),
];

/// Paths relative to the repo root (the worktree) where banned patterns are
/// legitimately expected to appear.
const _kAllowlistedRelativePaths = <String>{
  'lib/core/services/secure_storage.dart',
  'lib/core/services/biometric_service.dart',
  // PrismSecureStore wraps FlutterSecureStorage for the Rust SecureStore
  // interface (a single adapter class). The internals here are intentional;
  // call sites that *use* PrismSecureStore go through its typed API.
  'lib/core/services/prism_secure_store.dart',
};

void main() {
  test(
    'lib/ contains no raw flutter_secure_storage calls outside the allowlist',
    () async {
      final libDir = Directory('lib');
      expect(
        libDir.existsSync(),
        isTrue,
        reason:
            'Audit test must run from the prism-app worktree root. cwd=${Directory.current.path}',
      );

      final compiledPatterns = [
        for (final p in _bannedPatterns)
          (label: p.label, regex: RegExp(p.pattern, caseSensitive: false))
      ];

      final violations = <String>[];
      await for (final entity in libDir.list(recursive: true)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.dart')) continue;

        // Normalise path separators so Windows builds match the allowlist.
        final relative = entity.path.replaceAll('\\', '/');
        if (_kAllowlistedRelativePaths.contains(relative)) continue;

        final content = await entity.readAsString();
        for (final entry in compiledPatterns) {
          for (final match in entry.regex.allMatches(content)) {
            // Compute a 1-based line number for the violation.
            final upTo = content.substring(0, match.start);
            final line = '\n'.allMatches(upTo).length + 1;
            violations.add(
              '$relative:$line — ${entry.label} '
              '(matched "${match.group(0)}")',
            );
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Found raw flutter_secure_storage calls outside the allowlist. '
            'Migrate each call site to the safeSecureRead / safeSecureWrite '
            '/ safeSecureDelete wrappers in lib/core/services/secure_storage.dart. '
            'See docs/0.9.2-secure-storage-remediation.md §2.\n\n'
            'Violations:\n  ${violations.join('\n  ')}',
      );
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );
}
