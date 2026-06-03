import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/views/fronting_screen.dart';
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
}
