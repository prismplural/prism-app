import 'dart:convert';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_sync/generated/frb_generated.dart';

import 'e2e_fixture.dart';
import 'e2e_support.dart';

void main() {
  setUpAll(() async {
    if (e2eSkip() != null) return;
    await RustLib.init(externalLibrary: ExternalLibrary.open(resolveFfiLib()));
  });
  tearDownAll(() {
    if (e2eSkip() != null) return;
    RustLib.dispose();
  });

  test(
    'pairing snapshot preserves scale field stacked layout',
    skip: e2eSkip(),
    () async {
      final relay = await spawnRelay();
      E2EDevice? android;
      E2EDevice? windows;
      try {
        android = await createDevice(relay);

        await ffi.recordCreate(
          handle: android.handle,
          table: 'custom_fields',
          entityId: 'scale-field',
          fieldsJson: jsonEncode({
            'name': 'Energy',
            'field_type': 6,
            'field_type_id': 'scale',
            'parent_field_id': null,
            'type_config_json': _scaleConfigJson('compact'),
            'date_precision': null,
            'display_order': 0,
            'created_at': '2026-06-15T00:00:00.000Z',
            'is_deleted': false,
          }),
        );
        final compactPush = await android.sync();
        expect(
          compactPush['error'],
          isNull,
          reason: 'compact push: $compactPush',
        );

        await ffi.recordUpdate(
          handle: android.handle,
          table: 'custom_fields',
          entityId: 'scale-field',
          changedFieldsJson: jsonEncode({
            'type_config_json': _scaleConfigJson('stacked'),
          }),
        );

        windows = await pairNewDevice(relay, android);

        final raw = await ffi.readFieldValue(
          handle: windows.handle,
          table: 'custom_fields',
          entityId: 'scale-field',
          field: 'type_config_json',
        );
        expect(raw, isNotNull, reason: 'joiner has type_config_json');

        final typeConfigJson = jsonDecode(raw!) as String;
        final typeConfig = jsonDecode(typeConfigJson) as Map<String, dynamic>;
        expect(typeConfig['runtimeType'], 'scale');
        expect(typeConfig['displayLayout'], 'stacked');
      } finally {
        android?.dispose();
        windows?.dispose();
        relay.stop();
      }
    },
  );
}

String _scaleConfigJson(String displayLayout) => jsonEncode({
  'runtimeType': 'scale',
  'emoji': '*',
  'steps': 5,
  'stepLabels': null,
  'displayLayout': displayLayout,
  'headerIcon': null,
  'hideTitleOnProfile': false,
});
