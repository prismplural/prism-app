import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/sync/sync_schema.dart';

/// Guards the invariant that every entity declared in [prismSyncSchema] has a
/// matching `_<camelCase>Entity(...)` builder registered in
/// `drift_sync_adapter.dart`, and vice versa.
///
/// CRDT metadata (HLC, dirty flags, pending ops) lives in the Rust sync
/// engine — the Dart side has no schema column to catch drift. If a new
/// synced entity is added to [prismSyncSchema] without registering an
/// adapter builder, remote changes for that entity will never land in the
/// local Drift DB (silent desync). If a builder is registered without a
/// schema entry, the Rust engine will never emit changes for it.
void main() {
  test('every prismSyncSchema entity is registered in drift_sync_adapter', () {
    final schema = jsonDecode(prismSyncSchema) as Map<String, dynamic>;
    final entities = (schema['entities'] as Map<String, dynamic>).keys.toSet();

    final adapter = File(
      'lib/core/sync/drift_sync_adapter.dart',
    ).readAsStringSync();

    // Registered builders always take `(db, quarantine, ...)`. Anchoring on
    // the `(db,` prefix avoids matching prose mentions like `_fooEntity()`
    // in the file's doc comment.
    // Registered builders always take `(db, ...)` as the first arg. Allow
    // whitespace/newlines before `db,` since some call sites wrap arguments.
    // Anchoring on `db,` avoids matching prose mentions like `_fooEntity()`.
    final builderRe = RegExp(r'_([a-zA-Z0-9]+)Entity\(\s*db,');
    final registered = builderRe
        .allMatches(adapter)
        .map((m) => _camelToSnake(m.group(1)!))
        .toSet();

    final schemaMissingBuilder = entities.difference(registered);
    final builderMissingSchema = registered.difference(entities);

    expect(
      schemaMissingBuilder,
      isEmpty,
      reason:
          'Entities in prismSyncSchema have no matching _<name>Entity builder '
          'in drift_sync_adapter.dart — remote changes will be silently dropped: '
          '$schemaMissingBuilder',
    );
    expect(
      builderMissingSchema,
      isEmpty,
      reason:
          '_<name>Entity builders in drift_sync_adapter.dart have no matching '
          'entry in prismSyncSchema — these entities will never sync: '
          '$builderMissingSchema',
    );
  });
}

String _camelToSnake(String camel) {
  final buf = StringBuffer();
  for (var i = 0; i < camel.length; i++) {
    final c = camel[i];
    final isUpper = c == c.toUpperCase() && c != c.toLowerCase();
    if (isUpper && i > 0) buf.write('_');
    buf.write(c.toLowerCase());
  }
  return buf.toString();
}
