import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/settings/views/secret_key_setup_screen.dart';

void main() {
  testWidgets('shows a safe fallback when mnemonic is missing', (tester) async {
    var completed = false;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: SecretKeySetupScreen(
            mnemonic: null,
            onComplete: () => completed = true,
          ),
        ),
      ),
    );

    expect(find.text('Secret Key Unavailable'), findsOneWidget);
    expect(find.text('Back to Sync'), findsOneWidget);

    await tester.tap(find.text('Back to Sync'));
    await tester.pump();

    expect(completed, isTrue);
  });
}
