import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/views/fronting_screen.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';

void main() {
  group('fronting history pagination prefetch', () {
    test('scales the prefetch runway with viewport height', () {
      expect(frontingHistoryPrefetchExtentForViewport(320), 900);
      expect(frontingHistoryPrefetchExtentForViewport(800), 2000);
      expect(frontingHistoryPrefetchExtentForViewport(1200), 2400);
    });

    test('requests two pages when the user is inside one viewport', () {
      expect(
        frontingHistoryPrefetchPagesForRemaining(
          remainingExtent: 700,
          viewportDimension: 800,
        ),
        2,
      );
      expect(
        frontingHistoryPrefetchPagesForRemaining(
          remainingExtent: 1200,
          viewportDimension: 800,
        ),
        1,
      );
    });

    testWidgets('load-more sentinel does not show a spinner', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CustomScrollView(
            slivers: [frontingHistoryLoadMoreSliver(hasMore: true)],
          ),
        ),
      );

      expect(find.byType(PrismLoadingState), findsNothing);
    });

    test('session limit resets after listeners go away', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final firstSub = container.listen(sessionLimitProvider, (_, _) {});
      container.read(sessionLimitProvider.notifier).loadMore();
      expect(container.read(sessionLimitProvider), sessionPageSize * 2);

      firstSub.close();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final secondSub = container.listen(sessionLimitProvider, (_, _) {});
      addTearDown(secondSub.close);
      expect(container.read(sessionLimitProvider), sessionPageSize);
    });
  });

  group('clampSliver responsive centering', () {
    // Pumps a single clampSliver-wrapped box at [width] and returns the box's
    // laid-out rect, after asserting it rendered without a layout exception.
    Future<Rect> pumpClamped(WidgetTester tester, double width) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: CustomScrollView(
            slivers: [
              clampSliver(
                const SliverToBoxAdapter(
                  child: SizedBox(
                    key: Key('clamped'),
                    height: 80,
                    child: Center(child: Text('clamped-content')),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('clamped-content'), findsOneWidget);
      return tester.getRect(find.byKey(const Key('clamped')));
    }

    testWidgets('fills the width below contentMaxWidth (no cross-axis '
        'overflow)', (tester) async {
      final rect = await pumpClamped(tester, 390);
      expect(rect.width, closeTo(390, 0.5));
    });

    testWidgets('fills the width exactly at contentMaxWidth', (tester) async {
      final rect = await pumpClamped(tester, PrismTokens.contentMaxWidth);
      expect(rect.width, closeTo(PrismTokens.contentMaxWidth, 0.5));
    });

    testWidgets('clamps and centers above contentMaxWidth', (tester) async {
      const width = 1200.0;
      final rect = await pumpClamped(tester, width);
      expect(rect.width, closeTo(PrismTokens.contentMaxWidth, 0.5));
      expect(rect.left, closeTo((width - PrismTokens.contentMaxWidth) / 2, 0.5));
    });
  });
}
