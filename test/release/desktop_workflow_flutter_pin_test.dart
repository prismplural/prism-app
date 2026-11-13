// CI guard: the desktop release workflow must build against the same Flutter
// pin as the PR workflow, so release artifacts never come from a toolchain the
// normal CI has not exercised.
//
// Run: flutter test test/release/desktop_workflow_flutter_pin_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Version literals only: `${{ env.FLUTTER_VERSION }}` does not start with a
// digit, so env-routed pins are deliberately ignored here.
final _flutterVersionLiteral = RegExp(
  r'''^\s*flutter-version:\s*['"]?(\d[^'"\s#]*)['"]?\s*$''',
  multiLine: true,
);
final _workspacePin = RegExp(
  r'''^\s*FLUTTER_VERSION:\s*['"]?(\d[^'"\s#]*)['"]?\s*$''',
  multiLine: true,
);

Set<String> _versions(RegExp pattern, String yaml) =>
    pattern.allMatches(yaml).map((match) => match.group(1)!).toSet();

void main() {
  test('desktop release workflow pins the same Flutter as normal CI', () {
    final desktop = File('.github/workflows/desktop.yaml').readAsStringSync();
    final ci = File('.github/workflows/test.yml').readAsStringSync();

    final ciPins = _versions(_flutterVersionLiteral, ci);
    expect(ciPins, isNotEmpty, reason: 'Normal CI must pin a Flutter version.');

    expect(
      _versions(_workspacePin, desktop),
      ciPins,
      reason:
          'desktop.yaml FLUTTER_VERSION must match the .github/workflows/'
          'test.yml flutter-version, so release builds use the toolchain CI '
          'tested.',
    );

    expect(
      _versions(_flutterVersionLiteral, desktop),
      isEmpty,
      reason:
          'desktop.yaml steps must use `flutter-version: '
          r'${{ env.FLUTTER_VERSION }}` instead of their own literal pin.',
    );
  });
}
