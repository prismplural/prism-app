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

    final verifyStart = fastfile.indexOf(
      'def verify_macos_release_entitlements',
    );
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
      fastfile,
      isNot(contains('"keychain-access-groups" => []')),
      reason:
          'Developer ID apps without embedded profiles cannot launch with '
          'Keychain Sharing; secure storage must use its legacy fallback.',
    );
    expect(
      verifyBody,
      contains('"keychain-access-groups"'),
      reason:
          'Keychain Sharing is a restricted entitlement and AMFI rejects the '
          'Developer ID app at launch when no matching profile is embedded.',
    );
    expect(verifyBody, contains('must be absent in Developer ID DMG'));
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

  test('mac sideload verifies exported app and DMG payload before upload', () {
    final fastfile = File('fastlane/Fastfile').readAsStringSync();

    expect(fastfile, contains('def verify_macos_release_app'));
    expect(fastfile, contains('def verify_macos_release_dmg'));
    expect(fastfile, contains('hdiutil verify'));
    expect(fastfile, contains('hdiutil attach -nobrowse -readonly'));
    expect(fastfile, contains('verify_macos_release_app(app_path'));

    final laneStart = fastfile.indexOf(
      'lane :sideload do',
      fastfile.indexOf('platform :mac do'),
    );
    expect(laneStart, isNonNegative);
    final laneEnd = fastfile.indexOf('\n  end\nend', laneStart);
    expect(laneEnd, isNonNegative);
    final lane = fastfile.substring(laneStart, laneEnd);

    final verifyApp = lane.indexOf('verify_macos_release_app(app_path)');
    final createDmg = lane.indexOf('create_macos_dmg(app_path');
    final verifyDmg = lane.indexOf('verify_macos_release_dmg(dmg_path)');
    final checksum = lane.indexOf(
      'checksum_path = write_sha256_file(dmg_path)',
    );
    final upload = lane.indexOf(
      'github_release_upload([dmg_path, checksum_path])',
    );

    expect(verifyApp, isNonNegative);
    expect(createDmg, isNonNegative);
    expect(verifyDmg, isNonNegative);
    expect(checksum, isNonNegative);
    expect(upload, isNonNegative);
    expect(verifyApp, lessThan(createDmg));
    expect(verifyDmg, lessThan(checksum));
    expect(checksum, lessThan(upload));
  });
}
