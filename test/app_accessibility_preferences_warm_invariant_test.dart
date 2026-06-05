import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'PrismApp warms sheet accessibility preferences after database init',
    () {
      final appDart = File('lib/app.dart').readAsStringSync();
      final readyStart = appDart.indexOf(
        '_repairPrimaryDatabaseKeySlotOnce();',
      );
      final appBuildStart = appDart.indexOf(
        'return DynamicColorBuilder(',
        readyStart,
      );

      expect(readyStart, isNonNegative);
      expect(appBuildStart, isNonNegative);

      final readyBranch = appDart.substring(readyStart, appBuildStart);
      expect(
        readyBranch,
        contains('ref.watch(dimBackgroundBehindSheetsProvider);'),
        reason: 'Dim-sheet preference must load before the first sheet opens.',
      );
      expect(
        readyBranch,
        contains('ref.watch(forceCenteredSheetsProvider);'),
        reason:
            'Centered-sheet preference must load before the first sheet opens.',
      );
    },
  );
}
