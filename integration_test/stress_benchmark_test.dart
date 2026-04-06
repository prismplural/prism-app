// Manual pre-release benchmark — measures frame timing across screens.
//
// Run on a real device in profile mode:
//   flutter test integration_test/stress_benchmark_test.dart --profile
//
// For stress testing, seed data via the debug screen first, then run this
// benchmark. The traceAction calls produce timeline traces that can be
// analyzed for frame build/rasterize times.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:prism_plurality/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Stress benchmark', () {
    testWidgets('measure frame timing with stress data', (tester) async {
      // Launch the app.
      app.main();
      await tester.pumpAndSettle();

      // Wait for the app to fully initialize (Rust bridge, keychain, etc.).
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // --- Home tab (already active) ---
      await binding.traceAction(
        () async {
          await tester.pump(const Duration(seconds: 1));
          final scrollable = find.byType(Scrollable).first;
          if (scrollable.evaluate().isNotEmpty) {
            await tester.fling(scrollable, const Offset(0, -500), 1000);
            await tester.pumpAndSettle();
          }
        },
        reportKey: 'home_scroll_timeline',
      );

      // --- Chat tab ---
      await binding.traceAction(
        () async {
          final chatTab = find.text('Chat');
          if (chatTab.evaluate().isNotEmpty) {
            await tester.tap(chatTab);
            await tester.pumpAndSettle();
          }
        },
        reportKey: 'chat_list_render',
      );

      // --- Habits tab ---
      await binding.traceAction(
        () async {
          final habitsTab = find.text('Habits');
          if (habitsTab.evaluate().isNotEmpty) {
            await tester.tap(habitsTab);
            await tester.pumpAndSettle();
          }
        },
        reportKey: 'habits_render',
      );

      // --- Polls tab ---
      await binding.traceAction(
        () async {
          final pollsTab = find.text('Polls');
          if (pollsTab.evaluate().isNotEmpty) {
            await tester.tap(pollsTab);
            await tester.pumpAndSettle();
          }
        },
        reportKey: 'polls_render',
      );

      // --- Settings tab ---
      await binding.traceAction(
        () async {
          final settingsTab = find.text('Settings');
          if (settingsTab.evaluate().isNotEmpty) {
            await tester.tap(settingsTab);
            await tester.pumpAndSettle();
          }
        },
        reportKey: 'settings_render',
      );
    });
  });
}
