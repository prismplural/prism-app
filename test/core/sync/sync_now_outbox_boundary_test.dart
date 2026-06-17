import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production sync_now calls go through the outbox-drain boundary', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('.g.dart') ||
          entity.path.endsWith('.freezed.dart')) {
        continue;
      }

      final source = entity.readAsStringSync();
      if (!source.contains('ffi.syncNow(')) continue;

      if (entity.path != 'lib/core/sync/prism_sync_providers.dart') {
        offenders.add('${entity.path}: direct ffi.syncNow call');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Local app writes are first committed to sync_op_outbox. Production '
          'sync_now entry points must drain that outbox before asking Rust to '
          'push, so direct ffi.syncNow calls belong only in the shared helpers.',
    );

    final provider = File(
      'lib/core/sync/prism_sync_providers.dart',
    ).readAsStringSync();
    expect(
      RegExp(r'ffi\.syncNow\(').allMatches(provider),
      hasLength(2),
      reason:
          'Keep sync_now centralized in syncNowAfterOutboxDrain and '
          'triggerSync; new production call sites need an explicit outbox '
          'drain first.',
    );
    expect(provider, contains('Future<void> syncNowAfterOutboxDrain({'));
    expect(provider, contains('await triggerOutboxDrain(db, handle);'));
    expect(provider, contains('Future<void> triggerSync('));
    expect(provider, contains('await triggerInstalledOutboxDrain(handle);'));
  });
}
