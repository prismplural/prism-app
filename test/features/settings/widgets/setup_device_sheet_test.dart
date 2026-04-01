import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/settings/widgets/setup_device_sheet.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

class _FakePrismSyncHandle implements ffi.PrismSyncHandle {
  const _FakePrismSyncHandle();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('opens on the joiner approval flow by default', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prismSyncHandleProvider.overrideWithBuild(
            (ref, notifier) => const _FakePrismSyncHandle(),
          ),
          relayUrlProvider.overrideWithValue(
            const AsyncValue<String?>.data('https://relay.example.com'),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Consumer(
              builder: (context, ref, _) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => SetupDeviceSheet.show(context, ref),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('pairing request QR code'), findsOneWidget);
    expect(find.text('Legacy Invite'), findsNothing);
    expect(find.text('Create Invite'), findsNothing);
  });
}
