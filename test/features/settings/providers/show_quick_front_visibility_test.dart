import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';

/// Minimal consumer that mirrors the conditional render in fronting_screen.dart:
/// shows a labelled widget when [showQuickFrontProvider] is true, otherwise
/// renders an empty box.
class _QuickFrontVisibilitySubject extends ConsumerWidget {
  const _QuickFrontVisibilitySubject();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final show = ref.watch(showQuickFrontProvider);
    return show ? const Text('shown') : const SizedBox.shrink();
  }
}

Widget _buildSubject(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      home: Scaffold(body: _QuickFrontVisibilitySubject()),
    ),
  );
}

void main() {
  group('showQuickFrontProvider visibility', () {
    testWidgets(
      'renders content when showQuickFrontProvider is true',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            showQuickFrontProvider.overrideWithValue(true),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(_buildSubject(container));
        await tester.pump();

        expect(find.text('shown'), findsOneWidget);
      },
    );

    testWidgets(
      'renders nothing when showQuickFrontProvider is false',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            showQuickFrontProvider.overrideWithValue(false),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(_buildSubject(container));
        await tester.pump();

        expect(find.text('shown'), findsNothing);
      },
    );
  });
}
