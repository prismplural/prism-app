import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android backup manifest disables backup and references rules', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:allowBackup="false"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
  });

  test('Android full backup rules exclude sensitive app domains', () {
    final rules = File(
      'android/app/src/main/res/xml/backup_rules.xml',
    ).readAsStringSync();

    for (final domain in const ['database', 'sharedpref', 'file', 'external']) {
      expect(
        _hasExclude(rules, domain),
        isTrue,
        reason: 'missing $domain exclude',
      );
    }
  });

  test('Android data extraction rules exclude sensitive transfer domains', () {
    final rules = File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ).readAsStringSync();
    final cloudBackup = _section(rules, 'cloud-backup');
    final deviceTransfer = _section(rules, 'device-transfer');

    for (final domain in const ['database', 'sharedpref', 'file', 'external']) {
      expect(
        _hasExclude(cloudBackup, domain),
        isTrue,
        reason: 'missing cloud-backup $domain exclude',
      );
      expect(
        _hasExclude(deviceTransfer, domain),
        isTrue,
        reason: 'missing device-transfer $domain exclude',
      );
    }
  });
}

String _section(String xml, String tag) {
  final match = RegExp(
    '<$tag>([\\s\\S]*?)</$tag>',
    multiLine: true,
  ).firstMatch(xml);
  expect(match, isNotNull, reason: 'missing <$tag> section');
  return match!.group(1)!;
}

bool _hasExclude(String xml, String domain) {
  return RegExp(
    '<exclude\\s+domain="$domain"\\s+path="\\."\\s*/>',
  ).hasMatch(xml);
}
