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

  test('mac sideload retains profile-backed keychain access', () {
    final fastfile = File('fastlane/Fastfile').readAsStringSync();
    expect(fastfile, contains('require_relative "macos_signing"'));
    expect(fastfile, contains('validate_macos_profile'));
    expect(
      fastfile,
      contains(
        '"keychain-access-groups" => ["#{apple_team_id}.#{mac_bundle_identifier}"]',
      ),
    );
    expect(fastfile, isNot(contains('FileUtils.rm_f(profile_path)')));
    expect(fastfile, isNot(contains('must be absent in Developer ID DMG')));
    expect(fastfile, contains('certificate_sha1: certificate_sha1'));
    if (Platform.isMacOS) {
      final policy = Process.runSync('ruby', [
        'test/release/macos_signing_test.rb',
      ]);
      expect(policy.exitCode, 0, reason: '${policy.stdout}\n${policy.stderr}');
    }
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
