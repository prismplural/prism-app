import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards boot wiring without opening secure storage and both databases.
void main() {
  test('app startup initializes sync and media codec Rust libraries', () {
    final source = File('lib/main.dart').readAsStringSync();
    final uncommented = source
        .split('\n')
        .map((line) => line.replaceFirst(RegExp(r'\s*//.*$'), ''))
        .join('\n');

    expect(
      uncommented,
      matches(
        RegExp(
          r'Future<void>\s+_initRustLibs\(\)\s+async\s*\{'
          r'\s*await RustLib\.init\(\);'
          r'\s*try\s*\{\s*await media_codec\.initializeMediaCodec\(\);\s*\}'
          r'\s*catch\s*\(error, stackTrace\)\s*\{'
          r'.*?ErrorReportingService\.instance\.report\(',
          dotAll: true,
        ),
      ),
      reason:
          'sync initialization must remain fatal, while media codec '
          'initialization is reported and allowed to degrade gracefully',
    );

    expect(
      RegExp(r'await\s+_initRustLibs\(\)\s*;').allMatches(uncommented),
      hasLength(1),
      reason: 'main() must invoke the Rust library initializer exactly once',
    );
  });
}
