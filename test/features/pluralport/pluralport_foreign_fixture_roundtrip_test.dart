import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync/generated/frb_generated.dart';

import 'complex_fixture.dart';
import 'pluralport_foreign_fixture_harness.dart';

void main() {
  final environment = Platform.environment;
  final required = environment['PLURALPORT_FOREIGN_REQUIRED'] == '1';
  List<ForeignFixtureCase> cases;
  try {
    cases = foreignFixtureCasesFromEnvironment(environment);
  } on FormatException catch (error) {
    test('foreign fixture configuration is valid', () {
      fail('$error');
    });
    return;
  }

  if (cases.isEmpty) {
    final reason =
        'No foreign fixtures configured. Set PLURALPORT_FOREIGN_BUNDLES to a '
        'JSON object of label to archive path and PLURALPORT_FOREIGN_OUT to '
        'the private fixture root. Fixture archives are not part of this '
        'repository.${required ? ' PLURALPORT_FOREIGN_REQUIRED=1 was set, so '
                  'this run must not skip.' : ''}';
    if (required) {
      test('foreign fixture bundles are configured', () {
        fail(reason);
      });
      return;
    }
    stdout.writeln('SKIPPED: $reason');
    test('foreign fixture bundles are configured', () {}, skip: reason);
    return;
  }

  setUpAll(initializeFixtureCrypto);
  tearDownAll(RustLib.dispose);

  for (final fixture in cases) {
    test(
      '${fixture.label}: foreign PluralPort preview, import, re-export and reimport',
      () async {
        final report = await qualifyForeignFixture(fixture);
        final error = report['error'];
        if (error is Map) {
          fail(
            '${fixture.label} qualification failed: ${error['type']}: '
            '${error['message']}',
          );
        }
        final failed = report['failed_checks'] as List? ?? const [];
        expect(
          failed,
          isEmpty,
          reason:
              '${fixture.label} failed checks: $failed. See '
              '${fixture.outputDirectory}/report.json',
        );
        final checks = report['checks'] as List? ?? const [];
        expect(checks.length, greaterThanOrEqualTo(14));
        stdout.writeln(
          '${fixture.label}: ${checks.length} checks passed; '
          'report: ${fixture.outputDirectory}/report.json',
        );
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  }
}
