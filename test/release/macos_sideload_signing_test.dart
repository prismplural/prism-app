import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mac sideload signs Developer ID during export, not archive', () {
    final fastfile = File('fastlane/Fastfile').readAsStringSync();
    final helperStart = fastfile.indexOf('def mac_developer_id_xcargs');
    expect(helperStart, isNonNegative);

    final helperEnd = fastfile.indexOf('\nend', helperStart);
    expect(helperEnd, isNonNegative);

    final archiveArgs = fastfile.substring(helperStart, helperEnd);
    expect(
      archiveArgs,
      isNot(contains('CODE_SIGN_IDENTITY')),
      reason:
          'Forcing Developer ID during automatic archive signing conflicts '
          'with the Runner target development signing settings.',
    );
    expect(
      fastfile,
      isNot(contains('codesigning_identity: developer_id_signing_certificate')),
    );
    expect(
      fastfile,
      contains('"signingCertificate" => developer_id_signing_certificate'),
    );
  });

  test('mac sideload strips provisioning-only launch blockers', () {
    final fastfile = File('fastlane/Fastfile').readAsStringSync();

    expect(fastfile, contains('def developer_id_sign_macos_app'));
    expect(fastfile, contains('embedded.provisionprofile'));
    expect(fastfile, contains('FileUtils.rm_f(profile_path)'));
    expect(fastfile, contains('developer_id_sign_macos_app(app_path)'));

    final verifyStart = fastfile.indexOf('def verify_macos_release_entitlements');
    expect(verifyStart, isNonNegative);
    final verifyEnd = fastfile.indexOf('def create_macos_dmg', verifyStart);
    expect(verifyEnd, isNonNegative);
    final verifyBody = fastfile.substring(verifyStart, verifyEnd);

    expect(
      verifyBody,
      contains('"com.apple.application-identifier"'),
      reason: 'Developer ID DMGs must not ship provisioning entitlements.',
    );
    expect(
      verifyBody,
      contains('"com.apple.developer.team-identifier"'),
      reason: 'Developer ID DMGs must not ship provisioning entitlements.',
    );
    expect(
      verifyBody,
      contains('"keychain-access-groups"'),
      reason: 'Prism does not use a Keychain access group on macOS.',
    );
    expect(
      verifyBody,
      contains('must be absent in Developer ID DMG'),
    );
  });

  test('mac sideload signs the DMG container before notarizing', () {
    final fastfile = File('fastlane/Fastfile').readAsStringSync();
    expect(fastfile, contains('def developer_id_sign_macos_dmg'));

    final laneSign = fastfile.indexOf('developer_id_sign_macos_dmg(dmg_path)');
    final laneNotarize = fastfile.indexOf('notarize_and_staple(dmg_path)');
    expect(laneSign, isNonNegative);
    expect(laneNotarize, isNonNegative);
    expect(
      laneSign,
      lessThan(laneNotarize),
      reason: 'The notarized DMG must already have a Developer ID signature.',
    );
  });
}
