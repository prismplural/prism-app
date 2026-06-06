import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mac Debug and Profile builds use a separate local app identity', () {
    final project = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();

    final debug = _runnerTargetBuildConfig(project, 'Debug');
    final profile = _runnerTargetBuildConfig(project, 'Profile');

    for (final config in [debug, profile]) {
      expect(
        config,
        contains('PRODUCT_BUNDLE_IDENTIFIER = com.prismplural.prism.dev;'),
      );
      expect(config, contains('PRODUCT_NAME = "Prism Dev";'));
      // Stable signing, not ad-hoc — a per-build signature breaks the keychain
      // ACL. Isolation comes from the .dev bundle id, not from "-".
      expect(config, isNot(contains('CODE_SIGN_IDENTITY = "-";')));
      expect(config, contains('CODE_SIGN_STYLE = Automatic;'));
      expect(config, contains('DEVELOPMENT_TEAM = GF2W9X3Y6L;'));
      expect(
        config,
        contains('CODE_SIGN_ENTITLEMENTS = Runner/DebugProfile.entitlements;'),
      );
    }

    final debugEntitlements = File(
      'macos/Runner/DebugProfile.entitlements',
    ).readAsStringSync();
    // Required for the .dev build's data-protection keychain; the separate
    // bundle id already isolates it from the shipping install.
    expect(debugEntitlements, contains('keychain-access-groups'));
  });

  test('mac Release build keeps the shipping app identity', () {
    final appInfo = File(
      'macos/Runner/Configs/AppInfo.xcconfig',
    ).readAsStringSync();
    final project = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final release = _runnerTargetBuildConfig(project, 'Release');
    final infoPlist = File('macos/Runner/Info.plist').readAsStringSync();

    expect(appInfo, contains('PRODUCT_NAME = Prism'));
    expect(
      appInfo,
      contains('PRODUCT_BUNDLE_IDENTIFIER = com.prismplural.prism'),
    );
    expect(release, isNot(contains('com.prismplural.prism.dev')));
    expect(
      release,
      contains('CODE_SIGN_ENTITLEMENTS = Runner/Release.entitlements;'),
    );
    expect(infoPlist, contains('<key>CFBundleName</key>'));
    expect(infoPlist, contains('<string>\$(PRODUCT_NAME)</string>'));
  });
}

String _runnerTargetBuildConfig(String project, String name) {
  final blockPattern = RegExp(
    r'/\* ' + RegExp.escape(name) + r' \*/ = \{([\s\S]*?)\n\t\t\};',
  );
  final blocks = blockPattern
      .allMatches(project)
      .map((match) => match.group(1)!)
      .where((block) => block.contains('INFOPLIST_FILE = Runner/Info.plist;'))
      .toList();
  expect(blocks, hasLength(1), reason: 'Runner target $name config');
  return blocks.single;
}
